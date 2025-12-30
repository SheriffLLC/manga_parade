import { setGlobalOptions } from "firebase-functions/v2";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import cors from "cors";
import * as cheerio from "cheerio";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

setGlobalOptions({ region: "us-central1", maxInstances: 10 });

initializeApp();
const db = getFirestore();

const corsMiddleware = cors({ origin: true });

type RailType = "recent" | "popular";
type SourceType = "qiscans" | "mangadex";

interface RailItem {
  id: string;
  title: string;
  coverUrl: string;
  sourceUrl: string;
  source: SourceType;
  updatedAt?: string;
  catalogScore?: number;
}

// -------------------------
// Helpers
// -------------------------
function cleanUrl(raw?: string | null): string {
  if (!raw) return "";
  const u = raw.trim().replace(/^"+|"+$/g, "");

  // unwrap Next.js image proxy if it shows up
  if (u.includes("/_next/image") && u.includes("url=")) {
    try {
      const uri = new URL(u);
      const wrapped = uri.searchParams.get("url");
      if (wrapped) return decodeURIComponent(wrapped);
    } catch (_) {
      void 0;
    }
  }

  return u;
}

function absUrl(base: string, maybe: string): string {
  if (!maybe) return "";
  if (maybe.startsWith("http")) return maybe;
  if (maybe.startsWith("//")) return `https:${maybe}`;
  if (maybe.startsWith("/")) return `${base}${maybe}`;
  return `${base}/${maybe}`;
}

function safeSlugFromUrl(url: string): string {
  const parts = url.split("/").filter(Boolean);
  return parts[parts.length - 1] || "unknown";
}

function isoToTimestamp(iso?: string): Timestamp | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return Timestamp.fromDate(d);
}

// QiScans cover alt looks like:
// "Surviving As A Wandering Knight - MANHWA cover image"
function extractTitleFromAlt(alt: string): string {
  return alt.replace(/\s*-\s*.*?cover image\s*$/i, "").trim();
}

// -------------------------
// QISCANS SCRAPE
// You provided:
// - latest: https://qiscans.org/latest
// - pinned: https://qiscans.org/pinned
// -------------------------
async function fetchQiscans(type: RailType, limit: number): Promise<RailItem[]> {
  const base = "https://qiscans.org";
  const url = type === "recent" ? `${base}/latest` : `${base}/pinned`;

  const res = await fetch(url, {
    headers: {
      "User-Agent": "MangaParadeBot/1.0 (+firebase-functions)",
      "Accept": "text/html",
    },
  });

  if (!res.ok) throw new Error(`Qiscans HTTP ${res.status}`);

  const html = await res.text();
  const $ = cheerio.load(html);

  const items: RailItem[] = [];
  const seen = new Set<string>();

  // ✅ Only series cover images (prevents grabbing chapter "book" icon rows)
  const imgEls = $("img[alt*=\"cover image\"]").toArray();

  for (const imgEl of imgEls) {
    if (items.length >= limit) break;

    const img = $(imgEl);

    const alt = (img.attr("alt") || "").trim();
    const title = extractTitleFromAlt(alt) || "";

    const rawImg = img.attr("src") || img.attr("data-src") || "";
    const coverUrl = cleanUrl(absUrl(base, rawImg));

    // parent anchor usually points at /series/<slug>
    const a = img.closest("a");
    const href = (a.attr("href") || "").trim();
    const sourceUrl = absUrl(base, href);

    // Hard filters to avoid junk
    if (!title) continue;
    if (!coverUrl) continue;
    if (coverUrl.endsWith(".svg")) continue;
    if (!sourceUrl.includes("/series/")) continue; // avoid /chapter-* etc

    const slug = safeSlugFromUrl(sourceUrl);
    const docId = `qiscans_${slug}`;

    if (seen.has(docId)) continue;
    seen.add(docId);

    items.push({
      id: docId,
      title,
      coverUrl,
      sourceUrl,
      source: "qiscans",
      catalogScore: type === "popular" ? 1000 : 0,
    });
  }

  return items;
}

// -------------------------
// MANGADEX API
// - recent: order[updatedAt]=desc
// - popular: order[followedCount]=desc (good proxy)
// -------------------------
async function fetchMangadex(type: RailType, limit: number): Promise<RailItem[]> {
  const baseApi = "https://api.mangadex.org";
  const order = type === "recent" ? "order[updatedAt]=desc" : "order[followedCount]=desc";

  const url =
    `${baseApi}/manga?limit=${limit}&offset=0&includes[]=cover_art&contentRating[]=safe&${order}`;

  const res = await fetch(url, { headers: { "Accept": "application/json" } });
  if (!res.ok) throw new Error(`MangaDex HTTP ${res.status}`);

  const json: any = await res.json();
  const data: any[] = Array.isArray(json?.data) ? json.data : [];

  const items: RailItem[] = data.map((m) => {
    const mdId = String(m.id);
    const docId = `mangadex_${mdId}`;

    const attrs = m.attributes || {};
    const titleObj = attrs.title || {};
    const title = titleObj.en || Object.values(titleObj)[0] || "Untitled";

    let fileName = "";
    const rels: any[] = Array.isArray(m.relationships) ? m.relationships : [];
    const coverRel = rels.find((r) => r.type === "cover_art");
    if (coverRel?.attributes?.fileName) fileName = coverRel.attributes.fileName;

    const coverUrl = fileName
      ? `https://uploads.mangadex.org/covers/${mdId}/${fileName}.512.jpg`
      : "";

    return {
      id: docId,
      title: String(title),
      coverUrl,
      sourceUrl: `https://mangadex.org/title/${mdId}`,
      source: "mangadex" as const,
      updatedAt: typeof attrs.updatedAt === "string" ? attrs.updatedAt : undefined,
      catalogScore: type === "popular" ? Number(attrs.followedCount || 0) : 0,
    };
  }).filter(i => i.coverUrl);

  return items;
}

// -------------------------
// Firestore upsert
// -------------------------
async function upsertMangaDocs(items: RailItem[], type: RailType) {
  const batch = db.batch();

  for (const item of items) {
    const ref = db.collection("manga").doc(item.id);

    const updatedAtTs =
      type === "recent"
        ? (isoToTimestamp(item.updatedAt) ?? Timestamp.now())
        : undefined;

    const catalogScore =
      type === "popular"
        ? (item.catalogScore ?? 0)
        : undefined;

    const payload: Record<string, any> = {
      title: item.title,
      coverUrl: item.coverUrl,
      sourceUrl: item.sourceUrl,
      source: item.source,
      lastSyncedAt: FieldValue.serverTimestamp(),
    };

    if (updatedAtTs) payload.updatedAt = updatedAtTs;
    if (catalogScore !== undefined) payload.catalogScore = catalogScore;

    batch.set(ref, payload, { merge: true });
  }

  await batch.commit();
}

// -------------------------
// Scheduled sync (main)
// -------------------------
export const syncRailsToFirestore = onSchedule("every 30 minutes", async () => {
  const recentLimit = 30;
  const popularLimit = 30;

  logger.info("syncRailsToFirestore started", { recentLimit, popularLimit });

  const [
    qRecent,
    qPopular,
    mdRecent,
    mdPopular,
  ] = await Promise.all([
    fetchQiscans("recent", recentLimit),
    fetchQiscans("popular", popularLimit),
    fetchMangadex("recent", recentLimit),
    fetchMangadex("popular", popularLimit),
  ]);

  await Promise.all([
    upsertMangaDocs(qRecent, "recent"),
    upsertMangaDocs(mdRecent, "recent"),
    upsertMangaDocs(qPopular, "popular"),
    upsertMangaDocs(mdPopular, "popular"),
  ]);

  logger.info("syncRailsToFirestore complete", {
    qRecent: qRecent.length,
    qPopular: qPopular.length,
    mdRecent: mdRecent.length,
    mdPopular: mdPopular.length,
  });
});

// -------------------------
// Debug endpoint
// /railDebug?source=qiscans&type=recent&limit=10
// -------------------------
export const railDebug = onRequest((req, res) => {
  corsMiddleware(req, res, async () => {
    try {
      const source = (req.query.source as SourceType) || "qiscans";
      const type = (req.query.type as RailType) || "recent";
      const limit = Math.min(parseInt((req.query.limit as string) || "10", 10) || 10, 100);

      let items: RailItem[] = [];
      if (source === "qiscans") items = await fetchQiscans(type, limit);
      else items = await fetchMangadex(type, limit);

      res.json({ source, type, limit, count: items.length, items });
    } catch (e: any) {
      logger.error("railDebug failed", e);
      res.status(500).json({ error: String(e?.message || e) });
    }
  });
});
