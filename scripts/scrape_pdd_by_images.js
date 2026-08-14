#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'exports', 'pdd-by');
const IMG_DIR = path.join(OUT_DIR, 'images', 'tickets');
const META_PATH = path.join(OUT_DIR, 'pdd-by-image-scrape.json');
const BASE_URL = 'https://pdd.by';
const USER_AGENT = 'pdd-by-image-scraper/1.0';

const DEFAULT_EXTYPES = [0, 1, 2, 3, 4, 5, 6, 7];

function parseArgs() {
  const args = process.argv.slice(2);
  const config = {
    sessions: 40,
    staleLimit: 20,
    delayMs: 180,
    extypes: DEFAULT_EXTYPES,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    const next = args[i + 1];
    if (arg === '--sessions') {
      config.sessions = Number(next);
      i += 1;
    } else if (arg === '--stale-limit') {
      config.staleLimit = Number(next);
      i += 1;
    } else if (arg === '--delay-ms') {
      config.delayMs = Number(next);
      i += 1;
    } else if (arg === '--extypes') {
      config.extypes = next.split(',').map((value) => Number(value.trim())).filter(Number.isFinite);
      i += 1;
    }
  }

  return config;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function readPreviousMeta() {
  if (!fs.existsSync(META_PATH)) {
    return {
      source: BASE_URL,
      images: {},
      questions: [],
      runs: [],
    };
  }

  return JSON.parse(fs.readFileSync(META_PATH, 'utf8'));
}

function updateCookieJar(cookieJar, headers) {
  const cookies = headers.getSetCookie ? headers.getSetCookie() : [];
  for (const cookie of cookies) {
    const [pair] = cookie.split(';');
    const [name, value] = pair.split('=');
    if (name && value) cookieJar[name] = value;
  }
}

function cookieHeader(cookieJar) {
  return Object.entries(cookieJar).map(([name, value]) => `${name}=${value}`).join('; ');
}

async function requestJson(url, cookieJar) {
  const response = await fetch(url, {
    headers: {
      'User-Agent': USER_AGENT,
      Cookie: cookieHeader(cookieJar),
      Referer: `${BASE_URL}/tasks/online/`,
    },
  });
  updateCookieJar(cookieJar, response.headers);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} for ${url}`);
  }
  return response.json();
}

function htmlText(value) {
  return String(value || '')
    .replace(/<br\s*\/?>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&quot;/g, '"')
    .replace(/&laquo;/g, '«')
    .replace(/&raquo;/g, '»')
    .replace(/&nbsp;/g, ' ')
    .replace(/&mdash;/g, '—')
    .replace(/&ndash;/g, '–')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractQuestion(ticketHtml) {
  const match = String(ticketHtml || '').match(/<li class="b-question">([\s\S]*?)<\/li>/);
  return match ? htmlText(match[1]) : '';
}

function extractAnswers(ticketHtml) {
  const answers = [];
  const html = String(ticketHtml || '');
  const variants = html.match(/<ul id="variants">([\s\S]*?)<\/ul>/);
  if (!variants) return answers;
  const regex = /<li>\s*(\d+)\.\s*<span>([\s\S]*?)<\/span>\s*<\/li>/g;
  let match;
  while ((match = regex.exec(variants[1]))) {
    answers.push({
      index: Number(match[1]),
      text: htmlText(match[2]),
    });
  }
  return answers;
}

function extractImagePath(ticketHtml) {
  const html = String(ticketHtml || '');
  const match = html.match(/\/img\/tickets\/[^'")\\\s]+/);
  return match ? match[0] : null;
}

function extractHint(payload) {
  return htmlText(payload.hint || '');
}

async function downloadImage(imagePath, imagesMeta) {
  const filename = path.basename(imagePath);
  const dest = path.join(IMG_DIR, filename);
  if (fs.existsSync(dest)) return false;

  const response = await fetch(`${BASE_URL}${imagePath}`, {
    headers: {
      'User-Agent': USER_AGENT,
      Referer: `${BASE_URL}/tasks/online/`,
    },
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} for image ${imagePath}`);
  }

  const bytes = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(dest, bytes);
  imagesMeta[filename] = {
    sourceUrl: `${BASE_URL}${imagePath}`,
    localPath: path.relative(ROOT, dest),
    bytes: bytes.length,
  };
  return true;
}

function upsertQuestion(meta, record) {
  const key = `${record.extype}:${record.question}:${record.image || ''}`;
  if (meta.questions.some((item) => item.key === key)) return;
  meta.questions.push({ key, ...record });
}

async function scrapeSession(extype, sessionIndex, meta) {
  const cookieJar = {};
  const seenImagesBefore = Object.keys(meta.images).length;
  const start = await requestJson(`${BASE_URL}/tasks/o/?meth=start&extype=${extype}`, cookieJar);
  const payloads = [start];

  for (let n = 2; n <= 10; n += 1) {
    const selected = await requestJson(`${BASE_URL}/tasks/o/?meth=select&n=${n}`, cookieJar);
    payloads.push(selected);
    await sleep(25);
  }

  let newImages = 0;
  let questionsWithImages = 0;

  for (const payload of payloads) {
    const ticketHtml = payload.ticket || '';
    const imagePath = extractImagePath(ticketHtml);
    const question = extractQuestion(ticketHtml);
    const answers = extractAnswers(ticketHtml);

    if (imagePath) {
      questionsWithImages += 1;
      const downloaded = await downloadImage(imagePath, meta.images);
      if (downloaded) newImages += 1;
    }

    if (question) {
      upsertQuestion(meta, {
        extype,
        sessionIndex,
        current: Number(payload.current ?? 0),
        hint: extractHint(payload),
        question,
        answers,
        image: imagePath ? path.basename(imagePath) : null,
        imageUrl: imagePath ? `${BASE_URL}${imagePath}` : null,
      });
    }
  }

  return {
    newImages,
    questionsWithImages,
    totalImagesBefore: seenImagesBefore,
    totalImagesAfter: Object.keys(meta.images).length,
  };
}

async function main() {
  const config = parseArgs();
  ensureDir(IMG_DIR);

  const meta = readPreviousMeta();
  meta.source = BASE_URL;
  meta.updatedAt = new Date().toISOString();
  meta.images ||= {};
  meta.questions ||= [];
  meta.runs ||= [];

  const run = {
    startedAt: new Date().toISOString(),
    config,
    progress: [],
  };
  meta.runs.push(run);

  for (const extype of config.extypes) {
    let stale = 0;
    for (let sessionIndex = 1; sessionIndex <= config.sessions; sessionIndex += 1) {
      const result = await scrapeSession(extype, sessionIndex, meta);
      stale = result.newImages === 0 ? stale + 1 : 0;
      run.progress.push({ extype, sessionIndex, ...result });

      fs.writeFileSync(META_PATH, JSON.stringify(meta, null, 2) + '\n', 'utf8');
      console.log(
        `extype=${extype} session=${sessionIndex} new=${result.newImages} total=${result.totalImagesAfter} stale=${stale}`,
      );

      if (stale >= config.staleLimit) break;
      await sleep(config.delayMs);
    }
  }

  run.finishedAt = new Date().toISOString();
  meta.updatedAt = run.finishedAt;
  fs.writeFileSync(META_PATH, JSON.stringify(meta, null, 2) + '\n', 'utf8');
  console.log(JSON.stringify({
    images: Object.keys(meta.images).length,
    questions: meta.questions.length,
    imageDir: IMG_DIR,
    metaPath: META_PATH,
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
