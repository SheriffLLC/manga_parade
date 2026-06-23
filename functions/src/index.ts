import express from "express";
import axios from "axios";
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

// ✅ NEW: Express app for clean routes
const app = express();
app.use(express.json());

// (Optional) reuse your existing corsMiddleware for this app too:
app.use((req, res, next) => {
  corsMiddleware(req as any, res as any, next as any);
});

type RailType = "recent" | "popular";
type SourceType = "qiscans" | "mangadex" | "asurascans";

const SIX_HOURS_MS = 6 * 60 * 60 * 1000;

type ChaptersResponse = {
  data: any[];
  currentPage: number;
  perPage: number;
  totalItems: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPrevPage: boolean;
};

type Cached<T> = { fetchedAt: number; value: T };

function chaptersCacheDocId(postId: number, page: number, perPage: number) {
  return `chapters_${postId}_${page}_${perPage}`;
}

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

function isoToTimestamp(iso?: string): Timestamp | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return Timestamp.fromDate(d);
}

interface ChapterItem {
  id: string;
  chapterNumber: string;
  title: string;
  sourceUrl: string;
  publishedAt?: string;
  index: number;
}

function chapterIndex(num: string, fallback: number): number {
  const n = Number(num);
  return Number.isFinite(n) ? Math.round(n * 1000) : fallback;
}

const TTL_HOURS_QISCANS = 12;
const TTL_HOURS_MANGADEX = 24;

// How many manga to refresh per scheduled run
const SCHEDULE_BATCH_SIZE = 20;

// Safety: don't try to write too many chapter docs in one Firestore batch (limit is 500 ops)
const MAX_BATCH_OPS = 450;

// tiny sleep helper (throttle)
function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

function hoursAgo(ts: Timestamp, hours: number) {
  const ms = hours * 60 * 60 * 1000;
  return ts.toMillis() >= Date.now() - ms;
}

export async function fetchQiscansChaptersViaApi(postId: number, page = 1, perPage = 100) {
  const url = `https://api.qiscans.org/api/v2/posts/${postId}/chapters`;
  const params = { page, perPage, sortOrder: "desc", q: "" };

  const { data } = await axios.get<ChaptersResponse>(url, { params });

  // Convert API response → your ChapterItem[]
  return (data.data || []).map((ch: any, i: number): ChapterItem => {
    const num = String(ch.number ?? "");
    const slug = String(ch.slug ?? `chapter-${num || i + 1}`);

    // If QiScans provides a redirectUrl or readable URL, use it; otherwise store a constructed reference.
    const sourceUrl =
      ch?.mangaPost?.redirectUrl
        ? String(ch.mangaPost.redirectUrl)
        : `https://qiscans.org/chapter/${slug}`; // may not be perfect; adjust if you find the real pattern

    return {
      id: `qiscans_api_${ch.id}`,
      chapterNumber: num,
      title: ch.title ? String(ch.title) : (num ? `Chapter ${num}` : "Chapter"),
      sourceUrl,
      publishedAt: ch.createdAt ? String(ch.createdAt) : undefined,
      index: chapterIndex(num, 0) || (1000000 - i),
    };
  });
}

async function fetchMangadexChapters(mangaUrl: string, limit = 500): Promise<ChapterItem[]> {
  const mdId = mangaUrl.split("/title/")[1]?.split(/[/?#]/)[0];
  if (!mdId) throw new Error("Could not parse MangaDex id from sourceUrl");

  const api =
    `https://api.mangadex.org/manga/${mdId}/feed?limit=${Math.min(limit, 500)}` +
    "&order[chapter]=desc&translatedLanguage[]=en";
  const res = await fetch(api, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`MangaDex feed HTTP ${res.status}`);

  const json: any = await res.json();
  const data: any[] = Array.isArray(json?.data) ? json.data : [];

  const items: ChapterItem[] = data.map((ch) => {
    const id = `mangadex_ch_${String(ch.id)}`;
    const attrs = ch.attributes || {};
    const num = String(attrs.chapter || "");
    const title = String(attrs.title || (num ? `Chapter ${num}` : "Chapter"));
    const sourceUrl = `https://mangadex.org/chapter/${String(ch.id)}`;
    const idx = chapterIndex(num, 0);

    return {
      id,
      chapterNumber: num,
      title,
      sourceUrl,
      publishedAt: typeof attrs.publishAt === "string" ? attrs.publishAt : undefined,
      index: idx || 0,
    };
  });

  items.sort((a, b) => b.index - a.index);

  let fallback = items.length * 10;
  for (const it of items) {
    if (!it.index) it.index = fallback--;
  }

  return items;
}

async function upsertChapters(mangaId: string, source: SourceType, chapters: ChapterItem[]) {
  // Write chapters in chunks so we never exceed Firestore batch op limit
  for (let i = 0; i < chapters.length; i += MAX_BATCH_OPS) {
    const chunk = chapters.slice(i, i + MAX_BATCH_OPS);
    const batch = db.batch();

    for (const ch of chunk) {
      const ref = db.collection("manga").doc(mangaId).collection("chapters").doc(ch.id);

      batch.set(
        ref,
        {
          source,
          chapterNumber: ch.chapterNumber,
          title: ch.title,
          sourceUrl: ch.sourceUrl,
          publishedAt: ch.publishedAt ? Timestamp.fromDate(new Date(ch.publishedAt)) : null,
          index: ch.index,
          lastSyncedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    await batch.commit();
  }

  // Update parent AFTER all chunks
  await db.collection("manga").doc(mangaId).set(
    {
      chaptersCount: chapters.length,
      lastChaptersSyncedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

// ✅ Health check
app.get("/healthz", (req, res) => {
  res.status(200).json({ ok: true, ts: new Date().toISOString() });
});

// GET /manga/:postId/chapters?page=1&perPage=10&refresh=0
app.get("/manga/:postId/chapters", async (req, res) => {
  try {
    const postId = Number(req.params.postId);
    const page = Number(req.query.page ?? 1);
    const perPage = Number(req.query.perPage ?? 10);
    const forceRefresh = String(req.query.refresh ?? "0") === "1";

    if (!Number.isFinite(postId) || postId <= 0) {
      return res.status(400).json({ error: "Invalid postId" });
    }

    // Firestore cache doc
    const docId = chaptersCacheDocId(postId, page, perPage);
    const ref = db.collection("qiscans_cache").doc(docId);

    const snap = await ref.get();
    const cached = snap.exists ? (snap.data() as Cached<ChaptersResponse>) : null;

    const isFresh = !!cached && (Date.now() - cached.fetchedAt) < SIX_HOURS_MS;

    // ✅ Only call upstream if stale/missing OR user requested refresh
    if (!forceRefresh && isFresh && cached) {
      return res.status(200).json({
        ...cached.value,
        _cache: { hit: true, fetchedAt: new Date(cached.fetchedAt).toISOString() },
      });
    }

    const url = `https://api.qiscans.org/api/v2/posts/${postId}/chapters`;
    const params = { page, perPage, sortOrder: "desc", q: "" };

    const upstream = await axios.get<ChaptersResponse>(url, { params });

    const payload: Cached<ChaptersResponse> = {
      fetchedAt: Date.now(),
      value: upstream.data,
    };

    await ref.set(payload, { merge: true });

    return res.status(200).json({
      ...upstream.data,
      _cache: { hit: false, fetchedAt: new Date(payload.fetchedAt).toISOString() },
    });
  } catch (e: any) {
    logger.error("GET /manga/:postId/chapters failed", e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
});

// POST /manga/:mangaId/qiscansPostId  { postId: 991 }
app.post("/manga/:mangaId/qiscansPostId", async (req, res) => {
  try {
    const mangaId = String(req.params.mangaId || "").trim();
    const postId = Number(req.body?.postId);

    if (!mangaId) return res.status(400).json({ error: "Missing mangaId" });
    if (!Number.isFinite(postId) || postId <= 0) {
      return res.status(400).json({ error: "Invalid postId" });
    }

    await db.collection("manga").doc(mangaId).set(
      {
        qiscansPostId: postId,
        qiscansPostIdUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return res.json({ ok: true, mangaId, postId });
  } catch (e: any) {
    logger.error("POST /manga/:mangaId/qiscansPostId failed", e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
});

// -------------------------
// QISCANS SCRAPE
// You provided:
// - latest: https://qiscans.org/latest
// - pinned: https://qiscans.org/pinned
// -------------------------
async function fetchQiscans(type: RailType, limit: number): Promise<RailItem[]> {
  const base = "https://qimanga.com";

  const res = await fetch(base, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      "Accept": "text/html",
    },
  });

  if (!res.ok) throw new Error(`Qimanga HTTP ${res.status}`);

  const html = await res.text();
  const $ = cheerio.load(html);

  const items: RailItem[] = [];
  const seen = new Set<string>();

  $('a').each((i, el) => {
    const href = $(el).attr('href') || '';
    if (href.startsWith('/series/') && !href.includes('/chapter-')) {
      const slug = href.replace('/series/', '').split('/')[0];
      if (!slug) return;

      const docId = `qiscans_${slug}`;
      if (seen.has(docId)) return;
      seen.add(docId);

      // Find the image in this anchor or the parent/siblings
      let img = $(el).find('img');
      if (img.length === 0) {
        img = $(el).siblings().find('img');
      }
      if (img.length === 0) {
        img = $(el).closest('div').find('img');
      }

      const title = img.attr('alt') || $(el).text().trim() || '';
      const src = img.attr('src') || img.attr('data-src') || '';
      const coverUrl = cleanUrl(src.startsWith('http') ? src : `${base}${src}`);

      if (!title || !coverUrl || coverUrl.endsWith('.svg')) return;

      items.push({
        id: docId,
        title,
        coverUrl,
        sourceUrl: `${base}/series/${slug}`,
        source: "qiscans",
        catalogScore: type === "popular" ? 1000 : 0,
      });
    }
  });

  if (type === "popular") {
    return items.slice(0, limit);
  } else {
    // Recent items appear after the top carousel/trending items
    return items.slice(15, 15 + limit);
  }
}

// -------------------------
// ASURASCANS SCRAPE (Redirect-only source)
// -------------------------
async function fetchAsurascans(type: RailType, limit: number): Promise<RailItem[]> {
  const base = "https://asurascans.com";
  try {
    const res = await fetch(base, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html",
      },
    });

    if (!res.ok) {
      logger.warn(`Asura Scans fetch failed with status: ${res.status}. Bypassing.`);
      return [];
    }

    const html = await res.text();
    const $ = cheerio.load(html);
    const items: RailItem[] = [];
    const seen = new Set<string>();

    $('a[href^="/comics/"]').each((i, el) => {
      if (items.length >= limit) return;

      const href = $(el).attr('href') || '';
      const slug = href.replace('/comics/', '').split('/')[0];
      if (!slug) return;
      
      const docId = `asurascans_${slug}`;
      if (seen.has(docId)) return;
      seen.add(docId);

      const img = $(el).find('img');
      const title = img.attr('alt') || $(el).text().trim().replace(/^[0-9.]+\s*/, '') || '';
      const src = img.attr('src') || img.attr('data-src') || '';
      if (!title || !src || src.endsWith('.svg')) return;

      const coverUrl = cleanUrl(src.startsWith('http') ? src : `${base}${src}`);
      const sourceUrl = `${base}/comics/${slug}`;

      items.push({
        id: docId,
        title,
        coverUrl,
        sourceUrl,
        source: "asurascans",
        catalogScore: type === "popular" ? 900 : 0,
      });
    });

    return items;
  } catch (err) {
    logger.warn("fetchAsurascans failed due to network or Cloudflare blocking", err);
    return [];
  }
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

function normalizeTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "")
    .trim();
}

// -------------------------
// Firestore upsert
// -------------------------
async function upsertMangaDocs(items: RailItem[], type: RailType) {
  // Query existing documents with the same normalizedTitle in parallel first
  const queries = items.map(async (item) => {
    const norm = normalizeTitle(item.title);
    const snap = await db.collection("manga").where("normalizedTitle", "==", norm).limit(1).get();
    return { item, norm, snap };
  });

  const results = await Promise.all(queries);
  const batch = db.batch();

  for (const { item, norm, snap } of results) {
    let ref;
    let existingData: Record<string, any> = {};

    if (!snap.empty) {
      // Document with the same normalized title already exists
      const doc = snap.docs[0];
      ref = db.collection("manga").doc(doc.id);
      existingData = doc.data() || {};
    } else {
      // No document found; create a new one with item's default ID
      ref = db.collection("manga").doc(item.id);
    }

    const updatedAtTs =
      type === "recent"
        ? (isoToTimestamp(item.updatedAt) ?? Timestamp.now())
        : undefined;

    const catalogScore =
      type === "popular"
        ? (item.catalogScore ?? 0)
        : undefined;

    // Prefer MangaDex as the primary source if either is MangaDex
    const isMangaDex = item.source === "mangadex" || existingData.source === "mangadex";
    const isAsuraScans = item.source === "asurascans" || existingData.source === "asurascans";
    const primarySource = isMangaDex ? "mangadex" : (isAsuraScans ? "asurascans" : "qiscans");

    let sourceUrl = item.sourceUrl;
    let qiscansSourceUrl = existingData.qiscansSourceUrl || undefined;
    let asurascansSourceUrl = existingData.asurascansSourceUrl || undefined;

    if (item.source === "mangadex") {
      sourceUrl = item.sourceUrl;
      if (existingData.source === "qiscans") {
        qiscansSourceUrl = existingData.sourceUrl;
      }
      if (existingData.source === "asurascans") {
        asurascansSourceUrl = existingData.sourceUrl;
      }
    } else if (item.source === "qiscans") {
      qiscansSourceUrl = item.sourceUrl;
      if (existingData.source === "mangadex") {
        sourceUrl = existingData.sourceUrl;
      }
      if (existingData.source === "asurascans") {
        asurascansSourceUrl = existingData.sourceUrl;
      }
    } else if (item.source === "asurascans") {
      asurascansSourceUrl = item.sourceUrl;
      if (existingData.source === "mangadex") {
        sourceUrl = existingData.sourceUrl;
      }
      if (existingData.source === "qiscans") {
        qiscansSourceUrl = existingData.sourceUrl;
      }
    }

    const qiscansPostId = existingData.qiscansPostId || undefined;

    const useMangadexMeta = (item.source === "mangadex") || (existingData.source === "mangadex");
    const useAsuraScansMeta = !useMangadexMeta && ((item.source === "asurascans") || (existingData.source === "asurascans"));

    let displayTitle = item.title;
    let displayCover = item.coverUrl;

    if (useMangadexMeta) {
      displayTitle = item.source === "mangadex" ? item.title : existingData.title;
      displayCover = item.source === "mangadex" ? item.coverUrl : existingData.coverUrl;
    } else if (useAsuraScansMeta) {
      displayTitle = item.source === "asurascans" ? item.title : existingData.title;
      displayCover = item.source === "asurascans" ? item.coverUrl : existingData.coverUrl;
    }

    const payload: Record<string, any> = {
      title: displayTitle || item.title || "Untitled",
      coverUrl: displayCover || item.coverUrl || "",
      sourceUrl: sourceUrl,
      source: primarySource,
      normalizedTitle: norm,
      lastSyncedAt: FieldValue.serverTimestamp(),
    };

    if (qiscansSourceUrl) payload.qiscansSourceUrl = qiscansSourceUrl;
    if (asurascansSourceUrl) payload.asurascansSourceUrl = asurascansSourceUrl;
    if (qiscansPostId) payload.qiscansPostId = qiscansPostId;

    if (updatedAtTs) {
      const existingUpdatedAt = existingData.updatedAt as Timestamp | undefined;
      if (!existingUpdatedAt || updatedAtTs.toMillis() > existingUpdatedAt.toMillis()) {
        payload.updatedAt = updatedAtTs;
      }
    }
    if (catalogScore !== undefined) {
      const existingScore = Number(existingData.catalogScore || 0);
      if (catalogScore > existingScore) {
        payload.catalogScore = catalogScore;
      }
    }

    batch.set(ref, payload, { merge: true });
  }

  await batch.commit();
}

// -------------------------
// Database Clean-up & Sync Helpers
// -------------------------
async function cleanupDuplicates(): Promise<number> {
  const snap = await db.collection("manga").get();
  const groups = new Map<string, any[]>();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const norm = data.normalizedTitle || normalizeTitle(data.title || "");
    if (!norm) continue;

    if (!groups.has(norm)) {
      groups.set(norm, []);
    }
    groups.get(norm)!.push({ id: doc.id, ref: doc.ref, data });
  }

  let mergedCount = 0;

  for (const [norm, docs] of groups.entries()) {
    if (docs.length <= 1) continue;

    logger.info(`Found ${docs.length} duplicates for normalized title: ${norm}`);

    // Sort documents to choose the primary one
    // Priority: mangadex > asurascans > qiscans
    docs.sort((a, b) => {
      const aId = a.id;
      const bId = b.id;
      if (aId.startsWith("mangadex_") && !bId.startsWith("mangadex_")) return -1;
      if (bId.startsWith("mangadex_") && !aId.startsWith("mangadex_")) return 1;
      if (aId.startsWith("asurascans_") && !bId.startsWith("asurascans_")) return -1;
      if (bId.startsWith("asurascans_") && !aId.startsWith("asurascans_")) return 1;
      return aId.localeCompare(bId);
    });

    const primary = docs[0];
    const secondaries = docs.slice(1);

    const mergedPayload = { ...primary.data };

    for (const sec of secondaries) {
      // Merge source URLs
      if (sec.data.qiscansSourceUrl) mergedPayload.qiscansSourceUrl = sec.data.qiscansSourceUrl;
      if (sec.data.asurascansSourceUrl) mergedPayload.asurascansSourceUrl = sec.data.asurascansSourceUrl;
      if (sec.data.qiscansPostId) mergedPayload.qiscansPostId = sec.data.qiscansPostId;

      if (sec.data.source === "qiscans" && !mergedPayload.qiscansSourceUrl) {
        mergedPayload.qiscansSourceUrl = sec.data.sourceUrl;
      }
      if (sec.data.source === "asurascans" && !mergedPayload.asurascansSourceUrl) {
        mergedPayload.asurascansSourceUrl = sec.data.sourceUrl;
      }

      // If primary is not mangadex and secondary is mangadex/asurascans, escalate source
      if (mergedPayload.source !== "mangadex") {
        if (sec.data.source === "mangadex") {
          mergedPayload.source = "mangadex";
          mergedPayload.sourceUrl = sec.data.sourceUrl;
        } else if (mergedPayload.source !== "asurascans" && sec.data.source === "asurascans") {
          mergedPayload.source = "asurascans";
          mergedPayload.sourceUrl = sec.data.sourceUrl;
        }
      }

      // Merge scores
      if (sec.data.catalogScore && (!mergedPayload.catalogScore || sec.data.catalogScore > mergedPayload.catalogScore)) {
        mergedPayload.catalogScore = sec.data.catalogScore;
      }

      // Merge description/genres if primary is missing them
      if (!mergedPayload.description && sec.data.description) mergedPayload.description = sec.data.description;
      if ((!mergedPayload.genres || mergedPayload.genres.length === 0) && sec.data.genres) mergedPayload.genres = sec.data.genres;

      // Delete secondary doc and its chapters
      try {
        const oldChapters = await db.collection("manga").doc(sec.id).collection("chapters").get();
        const deleteBatch = db.batch();
        for (const chDoc of oldChapters.docs) {
          deleteBatch.delete(chDoc.ref);
        }
        deleteBatch.delete(sec.ref);
        await deleteBatch.commit();
        logger.info(`Deleted secondary duplicate doc: ${sec.id}`);
      } catch (err) {
        logger.error(`Error deleting secondary duplicate doc: ${sec.id}`, err);
      }
    }

    // Update primary doc with merged payload
    await db.collection("manga").doc(primary.id).set(mergedPayload, { merge: true });
    logger.info(`Updated primary doc with merged data: ${primary.id}`);
    mergedCount++;
  }

  return mergedCount;
}

async function doSyncRails() {
  const recentLimit = 30;
  const popularLimit = 30;

  logger.info("doSyncRails started", { recentLimit, popularLimit });

  const [
    qRecent,
    qPopular,
    mdRecent,
    mdPopular,
    asRecent,
    asPopular,
  ] = await Promise.all([
    fetchQiscans("recent", recentLimit),
    fetchQiscans("popular", popularLimit),
    fetchMangadex("recent", recentLimit),
    fetchMangadex("popular", popularLimit),
    fetchAsurascans("recent", recentLimit),
    fetchAsurascans("popular", popularLimit),
  ]);

  await Promise.all([
    upsertMangaDocs(qRecent, "recent"),
    upsertMangaDocs(mdRecent, "recent"),
    upsertMangaDocs(asRecent, "recent"),
    upsertMangaDocs(qPopular, "popular"),
    upsertMangaDocs(mdPopular, "popular"),
    upsertMangaDocs(asPopular, "popular"),
  ]);

  logger.info("doSyncRails complete");

  return {
    qRecent: qRecent.length,
    qPopular: qPopular.length,
    mdRecent: mdRecent.length,
    mdPopular: mdPopular.length,
    asRecent: asRecent.length,
    asPopular: asPopular.length,
  };
}

// ✅ Manual sync endpoint
app.post("/sync-rails", async (req, res) => {
  try {
    const results = await doSyncRails();
    res.json({ ok: true, results });
  } catch (e: any) {
    logger.error("POST /sync-rails failed", e);
    res.status(500).json({ error: String(e?.message || e) });
  }
});

// ✅ Manual duplicate cleanup endpoint
app.post("/cleanup-duplicates", async (req, res) => {
  try {
    const mergedCount = await cleanupDuplicates();
    res.json({ ok: true, mergedCount });
  } catch (e: any) {
    logger.error("POST /cleanup-duplicates failed", e);
    res.status(500).json({ error: String(e?.message || e) });
  }
});

// -------------------------
// Scheduled sync (main)
// -------------------------
export const syncRailsToFirestore = onSchedule("every 30 minutes", async () => {
  try {
    const results = await doSyncRails();
    logger.info("syncRailsToFirestore success", results);
  } catch (err) {
    logger.error("syncRailsToFirestore failed", err);
  }
});

export const api = onRequest(app);

export const syncTopChaptersBatch = onSchedule("every 2 hours", async () => {
  logger.info("syncTopChaptersBatch started", { batchSize: SCHEDULE_BATCH_SIZE });

  // Pull “hot” manga: popular + recent
  const popularSnap = await db.collection("manga").orderBy("catalogScore", "desc").limit(50).get();
  const recentSnap = await db.collection("manga").orderBy("updatedAt", "desc").limit(50).get();

  const ids: string[] = [];
  const seen = new Set<string>();

  for (const d of [...popularSnap.docs, ...recentSnap.docs]) {
    if (!seen.has(d.id)) {
      seen.add(d.id);
      ids.push(d.id);
    }
  }

  // Process only a smaller batch each run
  const batchIds = ids.slice(0, SCHEDULE_BATCH_SIZE);

  let scraped = 0;
  let skippedFresh = 0;

  for (const mangaId of batchIds) {
    const doc = await db.collection("manga").doc(mangaId).get();
    if (!doc.exists) continue;

    const data = doc.data() || {};
    const source = String(data.source || "") as SourceType;
    const sourceUrl = String(data.sourceUrl || "");
    if (!source || !sourceUrl) continue;

    // Respect TTL
    const last = data.lastChaptersSyncedAt as Timestamp | undefined;
    if (last) {
      const ttl = (source === "qiscans" || source === "asurascans") ? TTL_HOURS_QISCANS : TTL_HOURS_MANGADEX;
      if (hoursAgo(last, ttl)) {
        skippedFresh++;
        continue;
      }
    }

    try {
      let chapters: ChapterItem[] = [];
      if (source === "qiscans" || source === "asurascans") {
        logger.info(`Skipping scheduled chapter sync for ${source} due to Cloudflare block`, { mangaId });
        continue;
      } else {
        chapters = await fetchMangadexChapters(sourceUrl);
      }

      await upsertChapters(mangaId, source, chapters);
      scraped++;

      // throttle a bit between sites
      await sleep(500);
    } catch (e: any) {
      logger.warn("syncTopChaptersBatch failed for manga", { mangaId, err: String(e?.message || e) });
    }
  }

  logger.info("syncTopChaptersBatch complete", { processed: batchIds.length, scraped, skippedFresh });
});

async function fetchAndCreateMangadexMangaDoc(mangaId: string): Promise<{ source: SourceType; sourceUrl: string } | null> {
  const mdId = mangaId.replace("mangadex_", "");
  if (!mdId) return null;

  const url = `https://api.mangadex.org/manga/${mdId}?includes[]=cover_art`;
  const res = await fetch(url, { headers: { "Accept": "application/json" } });
  if (!res.ok) {
    logger.warn(`Failed to fetch manga details from MangaDex for ${mdId}: HTTP ${res.status}`);
    return null;
  }

  const json: any = await res.json();
  const m = json?.data;
  if (!m) return null;

  const attrs = m.attributes || {};
  const titleObj = attrs.title || {};
  const title = titleObj.en || Object.values(titleObj)[0] || "Untitled";

  let fileName = "";
  const rels: any[] = Array.isArray(m.relationships) ? m.relationships : [];
  const coverRel = rels.find((r) => r.type === "cover_art");
  if (coverRel?.attributes?.fileName) {
    fileName = coverRel.attributes.fileName;
  }

  const coverUrl = fileName
    ? `https://uploads.mangadex.org/covers/${mdId}/${fileName}.512.jpg`
    : "";

  const norm = normalizeTitle(title);

  // Check if a document with the same normalizedTitle already exists
  const snap = await db.collection("manga").where("normalizedTitle", "==", norm).limit(1).get();
  
  const primarySource = "mangadex";
  const sourceUrl = `https://mangadex.org/title/${mdId}`;

  if (!snap.empty) {
    const doc = snap.docs[0];
    const oldId = doc.id;
    
    // If it's a different document ID, migrate/merge!
    if (oldId !== mangaId) {
      logger.info(`Migrating/Merging duplicate manga: ${oldId} -> ${mangaId}`, { title });
      const existingData = doc.data() || {};
      let qiscansSourceUrl = existingData.qiscansSourceUrl || undefined;
      if (existingData.source === "qiscans") {
        qiscansSourceUrl = existingData.sourceUrl;
      }
      let asurascansSourceUrl = existingData.asurascansSourceUrl || undefined;
      if (existingData.source === "asurascans") {
        asurascansSourceUrl = existingData.sourceUrl;
      }
      const qiscansPostId = existingData.qiscansPostId || undefined;

      const payload: Record<string, any> = {
        title,
        coverUrl,
        sourceUrl,
        source: primarySource,
        normalizedTitle: norm,
        lastSyncedAt: FieldValue.serverTimestamp(),
      };

      if (qiscansSourceUrl) payload.qiscansSourceUrl = qiscansSourceUrl;
      if (asurascansSourceUrl) payload.asurascansSourceUrl = asurascansSourceUrl;
      if (qiscansPostId) payload.qiscansPostId = qiscansPostId;

      const updatedAtTs = isoToTimestamp(attrs.updatedAt) ?? Timestamp.now();
      const existingUpdatedAt = existingData.updatedAt as Timestamp | undefined;
      if (!existingUpdatedAt || updatedAtTs.toMillis() > existingUpdatedAt.toMillis()) {
        payload.updatedAt = updatedAtTs;
      }

      // 1. Write the new document with mangaId
      await db.collection("manga").doc(mangaId).set(payload, { merge: true });

      // 2. Delete the old document and its chapters subcollection
      try {
        const oldChapters = await db.collection("manga").doc(oldId).collection("chapters").get();
        const deleteBatch = db.batch();
        for (const chDoc of oldChapters.docs) {
          deleteBatch.delete(chDoc.ref);
        }
        deleteBatch.delete(db.collection("manga").doc(oldId));
        await deleteBatch.commit();
        logger.info(`Successfully deleted old duplicate manga document: ${oldId}`);
      } catch (err) {
        logger.error(`Error deleting old duplicate manga document: ${oldId}`, err);
      }
    } else {
      // It's the same ID, just merge
      const existingData = doc.data() || {};
      const payload: Record<string, any> = {
        title,
        coverUrl,
        sourceUrl,
        source: primarySource,
        normalizedTitle: norm,
        lastSyncedAt: FieldValue.serverTimestamp(),
      };
      if (existingData.qiscansSourceUrl) payload.qiscansSourceUrl = existingData.qiscansSourceUrl;
      if (existingData.asurascansSourceUrl) payload.asurascansSourceUrl = existingData.asurascansSourceUrl;
      if (existingData.qiscansPostId) payload.qiscansPostId = existingData.qiscansPostId;
      await db.collection("manga").doc(mangaId).set(payload, { merge: true });
    }
  } else {
    // No document found; create a new one with mangaId
    const payload: Record<string, any> = {
      title,
      coverUrl,
      sourceUrl,
      source: primarySource,
      normalizedTitle: norm,
      lastSyncedAt: FieldValue.serverTimestamp(),
    };
    const updatedAtTs = isoToTimestamp(attrs.updatedAt) ?? Timestamp.now();
    payload.updatedAt = updatedAtTs;

    await db.collection("manga").doc(mangaId).set(payload, { merge: true });
  }

  return {
    source: primarySource,
    sourceUrl: sourceUrl,
  };
}

export const syncChaptersToFirestore = onRequest((req, res) => {
  corsMiddleware(req, res, async () => {
    try {
      const mangaId = String(req.query.mangaId || "").trim();
      const force = String(req.query.force || "").toLowerCase() === "true";

      if (!mangaId) return res.status(400).json({ error: "Missing mangaId" });

      let doc = await db.collection("manga").doc(mangaId).get();
      
      if (!doc.exists) {
        if (mangaId.startsWith("mangadex_")) {
          const created = await fetchAndCreateMangadexMangaDoc(mangaId);
          if (!created) {
            return res.status(404).json({ error: "Manga not found on MangaDex" });
          }
          // Reload doc reference
          doc = await db.collection("manga").doc(mangaId).get();
        } else {
          return res.status(404).json({ error: "Manga not found" });
        }
      }

      const data = doc.data() || {};
      const source = String(data.source || "") as SourceType;
      const sourceUrl = String(data.sourceUrl || "");

      if (!source || !sourceUrl) {
        return res.status(400).json({ error: "Manga doc missing source/sourceUrl" });
      }

      // TTL cache check
      if (!force) {
        const last = data.lastChaptersSyncedAt as Timestamp | undefined;
        if (last) {
          const ttl = (source === "qiscans" || source === "asurascans") ? TTL_HOURS_QISCANS : TTL_HOURS_MANGADEX;
          const fresh = hoursAgo(last, ttl);

          if (fresh) {
            const cachedResponse = {
              ok: true,
              mangaId,
              source,
              cached: true,
              ttlHours: ttl,
              lastChaptersSyncedAt: last.toDate().toISOString(),
              count: Number(data.chaptersCount || 0),
            };

            const chSnap = await db
              .collection("manga").doc(mangaId)
              .collection("chapters")
              .limit(1)
              .get();

            if (chSnap.empty) {
              // cached metadata exists but chapter docs are missing; fall through to scrape
            } else {
              return res.json({ ...cachedResponse });
            }
          }
        }
      }

      // Scrape
      let chapters: ChapterItem[] = [];
      if (source === "qiscans" || source === "asurascans") {
        return res.status(403).json({ error: `${source === "qiscans" ? "QiScans" : "Asura Scans"} chapter sync is temporarily disabled due to Cloudflare blocks. Please read on their website.` });
      } else {
        chapters = await fetchMangadexChapters(sourceUrl);
      }

      await upsertChapters(mangaId, source, chapters);

      return res.json({ ok: true, mangaId, source, cached: false, scraped: true, count: chapters.length });
    } catch (e: any) {
      logger.error("syncChaptersToFirestore failed", e);
      return res.status(500).json({ error: String(e?.message || e) });
    }
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
      else if (source === "asurascans") items = await fetchAsurascans(type, limit);
      else items = await fetchMangadex(type, limit);

      res.json({ source, type, limit, count: items.length, items });
    } catch (e: any) {
      logger.error("railDebug failed", e);
      res.status(500).json({ error: String(e?.message || e) });
    }
  });
});
