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
type SourceType = "qiscans" | "mangadex" | "comick";

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

function stringifyUpstreamBody(body: any): string {
  if (typeof body === "string") return body;
  try {
    return JSON.stringify(body ?? "");
  } catch {
    return String(body ?? "");
  }
}

function isQiscansBlockedChallenge(status: any, contentTypeRaw: any, body: any): boolean {
  const contentType = String(contentTypeRaw || "").toLowerCase();
  const bodyText = stringifyUpstreamBody(body).toLowerCase();

  return (
    Number(status) === 403 ||
    contentType.includes("text/html") ||
    bodyText.includes("just a moment") ||
    bodyText.includes("cloudflare")
  );
}

async function getQiscansChaptersPage(postId: number, page = 1, perPage = 100) {
  const url = `https://api.qiscans.org/api/v2/posts/${postId}/chapters`;

  return axios.get<ChaptersResponse>(url, {
    params: {
      page,
      perPage,
      sortOrder: "desc",
      q: "",
    },
    headers: {
      "Accept": "application/json, text/plain, */*",
      "Origin": "https://qiscans.org",
      "Referer": "https://qiscans.org/",
      "User-Agent": "Mozilla/5.0",
    },
    timeout: 15000,
  });
}

async function fetchQiscansChaptersViaApi(
  postId: number,
  page = 1,
  perPage = 100
): Promise<ChapterItem[]> {
  const { data } = await getQiscansChaptersPage(postId, page, perPage);

  return (data.data || []).map((ch: any, i: number): ChapterItem => {
    const num = String(ch.number ?? "");
    const slug = String(ch.slug ?? `chapter-${num || i + 1}`);

    const sourceUrl =
      ch?.mangaPost?.redirectUrl
        ? String(ch.mangaPost.redirectUrl)
        : `https://qiscans.org/chapter/${slug}`;

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

function extractQiscansPostIdFromPayload(payload: any): number | null {
  if (!payload) return null;

  // Case 1: full chapter-list response
  if (Array.isArray(payload.data) && payload.data.length > 0) {
    for (const item of payload.data) {
      const id = Number(item?.mangaPost?.id || 0);
      if (Number.isFinite(id) && id > 0) return id;
    }
  }

  // Case 2: single chapter object
  const singleId = Number(payload?.mangaPost?.id || 0);
  if (Number.isFinite(singleId) && singleId > 0) return singleId;

  return null;
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

    const upstream = await getQiscansChaptersPage(postId, page, perPage);

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
    const status = e?.response?.status;
    const body = e?.response?.data;
    const contentType = e?.response?.headers?.["content-type"];
    const blocked = isQiscansBlockedChallenge(status, contentType, body);

    if (blocked) {
      logger.error("GET /manga/:postId/chapters blocked by upstream", {
        message: String(e?.message || e),
        status,
        contentType,
      });

      return res.status(503).json({
        error: "QiScans blocked the chapter request right now. Please try again in a moment.",
        upstreamStatus: status ?? null,
        upstreamBody: null,
      });
    }

    logger.error("GET /manga/:postId/chapters failed", {
      message: String(e?.message || e),
      status,
      body,
    });

    return res.status(500).json({
      error: status
        ? `QiScans upstream returned ${status}`
        : String(e?.message || e),
      upstreamStatus: status ?? null,
      upstreamBody: body ?? null,
    });
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

// POST /manga/:mangaId/discover-qiscans-post-id
// Body can be either:
// 1) the pasted QiScans chapter-list JSON response
// 2) a single chapter object containing mangaPost.id
app.post("/manga/:mangaId/discover-qiscans-post-id", async (req, res) => {
  try {
    const mangaId = String(req.params.mangaId || "").trim();
    const payload = req.body;

    if (!mangaId) {
      return res.status(400).json({ error: "Missing mangaId" });
    }

    const mangaRef = db.collection("manga").doc(mangaId);
    const mangaSnap = await mangaRef.get();

    if (!mangaSnap.exists) {
      return res.status(404).json({ error: "Manga doc not found", mangaId });
    }

    const postId = extractQiscansPostIdFromPayload(payload);

    if (!postId) {
      return res.status(400).json({
        error: "Could not discover qiscansPostId from provided payload",
        hint: "Paste a QiScans chapter API response that contains mangaPost.id",
      });
    }

    await mangaRef.set(
      {
        qiscansPostId: postId,
        qiscansPostIdUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return res.status(200).json({
      ok: true,
      mangaId,
      qiscansPostId: postId,
      saved: true,
    });
  } catch (e: any) {
    logger.error("POST /manga/:mangaId/discover-qiscans-post-id failed", e);
    return res.status(500).json({ error: String(e?.message || e) });
  }
});

async function triggerApifyComickSync(callbackUrl: string, mangaId: string, sourceUrl: string) {
  const token = process.env.APIFY_TOKEN;
  if (!token) {
    throw new Error("APIFY_TOKEN environment variable is not configured.");
  }

  const webhooks = [
    {
      eventTypes: ["ACTOR.RUN.SUCCEEDED"],
      requestUrl: callbackUrl,
      payloadTemplate: JSON.stringify({
        runId: "{{resource.id}}",
        datasetId: "{{resource.defaultDatasetId}}",
        status: "{{resource.status}}",
      }),
    },
  ];

  const webhooksBase64 = Buffer.from(JSON.stringify(webhooks)).toString("base64");

  const response = await axios.post(
    `https://api.apify.com/v2/acts/panjan~comick-io/runs?token=${token}&webhooks=${webhooksBase64}`,
    {
      url: sourceUrl,
      language: "en",
      format: "cbz",
    },
    {
      headers: {
        "Content-Type": "application/json",
      },
      timeout: 20000,
    }
  );

  return {
    runId: response.data?.data?.id as string,
  };
}

// POST /apify-webhook?mangaId=xxx
app.post("/apify-webhook", async (req, res) => {
  try {
    const mangaId = String(req.query.mangaId || "").trim();
    const { datasetId, status } = req.body;

    if (!mangaId) return res.status(400).json({ error: "Missing mangaId" });
    if (status !== "SUCCEEDED") {
      logger.warn("Apify run did not succeed", { mangaId, status });
      return res.status(200).json({ ok: false, message: "Run was not successful" });
    }

    const token = process.env.APIFY_TOKEN;
    if (!token) {
      logger.error("Missing APIFY_TOKEN environment variable in webhook");
      return res.status(500).json({ error: "APIFY_TOKEN not configured" });
    }

    // Fetch dataset items
    const datasetRes = await axios.get(
      `https://api.apify.com/v2/datasets/${datasetId}/items?token=${token}`
    );

    const items = datasetRes.data;
    if (!Array.isArray(items)) {
      logger.warn("Apify dataset items is not an array", { mangaId, datasetId });
      return res.status(200).json({ ok: false, message: "No items array" });
    }

    logger.info("Syncing comick chapters from Apify dataset", { mangaId, count: items.length });

    // Format comick dataset items to ChapterItems
    const chapters: ChapterItem[] = items.map((item: any, i: number): ChapterItem => {
      const num = String(item.chapterNumber ?? "");
      const title = item.title ? String(item.title) : (num ? `Chapter ${num}` : "Chapter");
      const zipFileUrl = String(item.zipFileUrl || "");

      return {
        id: `comick_ch_${num || i + 1}`,
        chapterNumber: num,
        title,
        sourceUrl: zipFileUrl, // Store the CBZ URL in sourceUrl
        index: chapterIndex(num, 0) || (1000000 - i),
      };
    });

    // Save/upsert chapters to Firestore
    await upsertChapters(mangaId, "comick", chapters);

    return res.json({ ok: true, mangaId, count: chapters.length });
  } catch (e: any) {
    logger.error("POST /apify-webhook failed", e);
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
      const ttl = source === "qiscans" ? TTL_HOURS_QISCANS : TTL_HOURS_MANGADEX;
      if (hoursAgo(last, ttl)) {
        skippedFresh++;
        continue;
      }
    }

    try {
      let chapters: ChapterItem[] = [];
      if (source === "qiscans") {
        const postId = Number(data.qiscansPostId || 0);
        if (!postId) {
          logger.info("Skipping qiscans missing postId", { mangaId });
          continue;
        }
        chapters = await fetchQiscansChaptersViaApi(postId, 1, 200);
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

export const syncChaptersToFirestore = onRequest((req, res) => {
  corsMiddleware(req, res, async () => {
    try {
      const mangaId = String(req.query.mangaId || "").trim();
      const force = String(req.query.force || "").toLowerCase() === "true";

      if (!mangaId) return res.status(400).json({ error: "Missing mangaId" });

      const doc = await db.collection("manga").doc(mangaId).get();
      if (!doc.exists) return res.status(404).json({ error: "Manga not found" });

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
          const ttl = source === "qiscans"
            ? TTL_HOURS_QISCANS
            : source === "comick"
              ? 12 // 12 hours cooldown for comick Apify sync
              : TTL_HOURS_MANGADEX;
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
      if (source === "comick") {
        const protocol = req.protocol || "https";
        const host = req.get ? req.get("host") : (req.headers.host || "");
        const callbackUrl = `${protocol}://${host}/apify-webhook?mangaId=${encodeURIComponent(mangaId)}`;
        const runInfo = await triggerApifyComickSync(callbackUrl, mangaId, sourceUrl);
        return res.json({
          ok: true,
          mangaId,
          source,
          cached: false,
          scraped: false,
          status: "pending",
          runId: runInfo.runId,
          message: "Syncing chapters via Apify in the background.",
        });
      }

      let chapters: ChapterItem[] = [];
      if (source === "qiscans") {
        const postId = Number(data.qiscansPostId || 0);
        if (!postId) {
          return res.status(400).json({ error: "Manga doc missing qiscansPostId" });
        }
        chapters = await fetchQiscansChaptersViaApi(postId, 1, 200);
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
      else items = await fetchMangadex(type, limit);

      res.json({ source, type, limit, count: items.length, items });
    } catch (e: any) {
      logger.error("railDebug failed", e);
      res.status(500).json({ error: String(e?.message || e) });
    }
  });
});
