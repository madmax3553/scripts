#!/usr/bin/env node

const fs = require('fs');
const readline = require('readline');

function loadPlaywright() {
  try {
    // Local project install (npm i playwright)
    return require('playwright');
  } catch (_err) {
    // Arch global package location (pacman -S playwright)
    return require('/usr/lib/node_modules/playwright');
  }
}

const { chromium } = loadPlaywright();

function parseArgs(argv) {
  const args = {
    domain: 'www.audible.com',
    profileDir: '~/.local/share/audible-playwright-profile',
    pageSize: 50,
    maxPages: 200,
    headless: false,
    probeTitles: [],
  };

  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    const next = argv[i + 1];
    if (key === '--domain' && next) {
      args.domain = next;
      i += 1;
    } else if (key === '--profile-dir' && next) {
      args.profileDir = next;
      i += 1;
    } else if (key === '--page-size' && next) {
      args.pageSize = Number(next);
      i += 1;
    } else if (key === '--max-pages' && next) {
      args.maxPages = Number(next);
      i += 1;
    } else if (key === '--headless') {
      args.headless = true;
    } else if (key === '--probe-title' && next) {
      args.probeTitles.push(next);
      i += 1;
    }
  }

  return args;
}

function expandHome(path) {
  if (!path.startsWith('~/')) return path;
  return `${process.env.HOME}/${path.slice(2)}`;
}

function normalizeSuffix(domain) {
  return domain.startsWith('www.') ? domain.slice(4) : domain;
}

function endpointCandidates(domain) {
  const suffix = normalizeSuffix(domain.toLowerCase());
  const endpoints = [`https://api.${suffix}/1.0/library`];
  if (suffix === 'audible.com') endpoints.push('https://api.audible.com/1.0/library');
  return endpoints;
}

function extractItems(payload) {
  if (Array.isArray(payload)) return payload;
  if (!payload || typeof payload !== 'object') return [];
  for (const key of ['items', 'library', 'products']) {
    if (Array.isArray(payload[key])) return payload[key];
  }
  return [];
}

function extractTitle(item) {
  if (!item || typeof item !== 'object') return '';
  return String(item.title || '').trim().replace(/\s+/g, ' ');
}

function extractAuthor(item) {
  if (!item || typeof item !== 'object') return '';
  if (item.author) return String(item.author).trim();
  if (item.author_name) return String(item.author_name).trim();

  if (Array.isArray(item.authors)) {
    const names = item.authors
      .map((author) => (author && typeof author === 'object' ? author.name : author))
      .map((name) => String(name || '').trim())
      .filter(Boolean);
    if (names.length) return [...new Set(names)].join(', ');
  }

  if (Array.isArray(item.contributors)) {
    const names = item.contributors
      .filter((contributor) => contributor && typeof contributor === 'object')
      .filter((contributor) => String(contributor.role || contributor.type || '').toLowerCase().includes('author'))
      .map((contributor) => String(contributor.name || '').trim())
      .filter(Boolean);
    if (names.length) return [...new Set(names)].join(', ');
  }

  return '';
}

function cleanSummary(text) {
  const summary = String(text || '').replace(/\s+/g, ' ').trim();
  if (!summary) return '';
  if (/audible,\s*inc\./i.test(summary)) return '';
  if (/\b1-888-\d{3}-\d{4}\b/.test(summary)) return '';
  if (/^narrated by:/i.test(summary)) return '';
  const maxLen = 360;
  if (summary.length <= maxLen) return summary;
  return `${summary.slice(0, maxLen).replace(/\s+\S*$/, '').trim()}…`;
}

function cleanSeries(text) {
  return String(text || '').replace(/\s+/g, ' ').trim().replace(/^[,;:\-]\s*/, '').trim();
}

function extractSummary(item) {
  if (!item || typeof item !== 'object') return '';
  for (const key of ['summary', 'publisher_summary', 'description', 'product_desc']) {
    const value = item[key];
    if (typeof value === 'string') {
      const summary = cleanSummary(value);
      if (summary) return summary;
    }
    if (value && typeof value === 'object') {
      for (const nestedKey of ['summary', 'text', 'value', 'description']) {
        const summary = cleanSummary(value[nestedKey]);
        if (summary) return summary;
      }
    }
  }
  return '';
}

function extractSeries(item) {
  if (!item || typeof item !== 'object') return '';
  if (typeof item.series === 'string') {
    const direct = cleanSeries(item.series);
    if (direct) return direct;
  }
  if (typeof item.series_name === 'string') {
    const direct = cleanSeries(item.series_name);
    if (direct) return direct;
  }
  if (Array.isArray(item.series)) {
    const names = item.series
      .map((entry) => (entry && typeof entry === 'object' ? (entry.title || entry.name) : entry))
      .map((name) => cleanSeries(name))
      .filter(Boolean);
    if (names.length) return [...new Set(names)].join(', ');
  }
  return '';
}

function cleanTitle(text) {
  let cleaned = String(text || '')
    .replace(/\s+/g, ' ')
    .replace(/^\s*[-–—]\s*/, '')
    .replace(/\s*\(unabridged\)\s*$/i, '')
    .trim();
  cleaned = cleaned.replace(/atLarge/g, 'at Large');
  cleaned = cleaned.replace(/:\s*([^:]+,\s*Book\s*\d+)\s*:\s*\1\s*$/i, ': $1');
  return cleaned;
}

async function extractItemsFromLibraryPage(page) {
  const items = await page.evaluate(() => {
    function cleanLine(text) {
      return String(text || '').replace(/\s+/g, ' ').trim();
    }

    function parseCardText(text) {
      const lines = String(text || '')
        .split('\n')
        .map(cleanLine)
        .filter(Boolean);

      let author = '';
      let series = '';
      for (const line of lines) {
        const by = line.match(/^Written by:\s*(.+)$/i);
        if (by) {
          author = by[1].trim();
          continue;
        }
        const s = line.match(/^Series:\s*(.+)$/i);
        if (s) {
          series = s[1].replace(/\s*,\s*Book\s*\d+\s*$/i, '').trim();
        }
      }

      if (!author) {
        for (const line of lines) {
          const byInline = line.match(/^(.*?)\s+By\s+(.+)$/i);
          if (
            byInline
            && byInline[2]
            && !line.includes('(')
            && !/^narrated by:/i.test(line)
            && !/^written by:/i.test(line)
          ) {
            author = byInline[2].trim();
            break;
          }
        }
      }

      const skipPrefixes = [
        /^written by:/i,
        /^narrated by:/i,
        /^series:/i,
        /^interactive rating/i,
        /^write a review/i,
        /^listen now$/i,
        /^remove$/i,
        /^add to favourites$/i,
        /^add to\.\.\.$/i,
        /^add to$/i,
        /^mark as finished$/i,
        /^download$/i,
      ];
      const durationPattern = /^\d+h(?:\s+\d+m)?(?:\s+left)?$/i;

      let summary = '';
      for (const line of lines) {
        if (line.length < 55) continue;
        if (durationPattern.test(line)) continue;
        if (skipPrefixes.some((rx) => rx.test(line))) continue;
        if (/^.+\s+by\s+.+$/i.test(line) && line.length < 120) continue;
        if (!/[.!?…]/.test(line)) continue;
        summary = line;
        break;
      }

      return {
        author: author || '',
        series: series || '',
        summary: summary || '',
      };
    }

    function pickCardContainer(node, titleText) {
      let current = node;
      for (let depth = 0; current && depth < 8; depth += 1) {
        const text = String(current.innerText || '');
        const lineCount = text.split('\n').length;
        const hasMetadata = /written by:|narrated by:|series:/i.test(text);
        const hasTitle = titleText && text.toLowerCase().includes(String(titleText).toLowerCase());
        if (hasMetadata && hasTitle && lineCount >= 4 && lineCount <= 80) {
          return current;
        }
        current = current.parentElement;
      }
      return node.closest('li, article, [data-asin], [data-testid*="library"]');
    }

    function buildFallbackMetaMap() {
      const lines = String(document.body.innerText || '')
        .split('\n')
        .map(cleanLine)
        .filter(Boolean);
      const map = {};
      const durationPattern = /^\d+h(?:\s+\d+m)?(?:\s+left)?$/i;
      for (let i = 0; i < lines.length; i += 1) {
        const by = lines[i].match(/^Written by:\s*(.+)$/i);
        if (!by) continue;
        let title = '';
        for (let j = i - 1; j >= Math.max(0, i - 4); j -= 1) {
          const candidate = lines[j];
          if (!candidate) continue;
          if (/^.+\s+By\s+.+$/i.test(candidate)) continue;
          if (/^Narrated by:/i.test(candidate)) continue;
          if (/^Series:/i.test(candidate)) continue;
          title = candidate;
          break;
        }
        if (!title) continue;

        let series = '';
        let summary = '';
        for (let j = i + 1; j < Math.min(lines.length, i + 14); j += 1) {
          const line = lines[j];
          const s = line.match(/^Series:\s*(.+)$/i);
          if (s && !series) {
            series = s[1].replace(/\s*,\s*Book\s*\d+\s*$/i, '').trim();
            continue;
          }
          if (durationPattern.test(line)) break;
          if (line.length < 55) continue;
          if (!/[.!?…]/.test(line)) continue;
          if (/^interactive rating/i.test(line)) continue;
          if (/^write a review/i.test(line)) continue;
          summary = line;
          break;
        }
        map[title.toLowerCase()] = {
          author: by[1].trim(),
          series: series || '',
          summary: summary || '',
        };
      }
      return map;
    }

    const links = Array.from(document.querySelectorAll('a[href*="/pd/"]'));
    const fallbackMeta = buildFallbackMetaMap();
    const out = [];
    for (const node of links) {
      const candidates = [
        node.textContent || '',
        node.getAttribute('aria-label') || '',
        node.getAttribute('title') || '',
      ];
      const titleNode = node.querySelector('[title]');
      if (titleNode) candidates.push(titleNode.getAttribute('title') || '');
      const bestTitle = candidates.find((value) => String(value || '').trim().length > 2) || '';
      const container = pickCardContainer(node, bestTitle);
      const parsed = parseCardText(container ? container.innerText || '' : '');
      for (const value of candidates) {
        const text = String(value || '').trim();
        if (text) {
          const fallback = fallbackMeta[text.toLowerCase()] || {};
          out.push({
            title: text,
            author: parsed.author || fallback.author || '',
            series: parsed.series || fallback.series || '',
            summary: parsed.summary || fallback.summary || '',
          });
        }
      }
    }
    return out;
  });

  const deduped = [];
  const byKey = new Map();
  for (const raw of items) {
    const title = cleanTitle(raw.title || '');
    if (title.length <= 1) continue;
    const key = title.toLowerCase();
    const candidate = {
      title,
      author: String(raw.author || '').trim() || null,
      series: cleanSeries(raw.series || '') || null,
      summary: cleanSummary(raw.summary || '') || null,
    };
    if (!byKey.has(key)) {
      byKey.set(key, candidate);
      deduped.push(candidate);
      continue;
    }
    const existing = byKey.get(key);
    if (!existing.author && candidate.author) existing.author = candidate.author;
    if (!existing.series && candidate.series) existing.series = candidate.series;
    if (!existing.summary && candidate.summary) existing.summary = candidate.summary;
  }
  return deduped;
}

async function nextLibraryPageUrl(page, currentPageNum) {
  return page.evaluate((currentPageNumInPage) => {
    const selectors = [
      'a[rel="next"]',
      'li.bc-pagination-next a',
      'a[aria-label*="Next"]',
      'a[data-testid*="next"]',
      'a.bc-pagination-item-next',
    ];
    for (const selector of selectors) {
      const link = document.querySelector(selector);
      if (!link) continue;
      const ariaDisabled = (link.getAttribute('aria-disabled') || '').toLowerCase();
      const disabledClass = (link.className || '').toLowerCase().includes('disabled');
      if (ariaDisabled === 'true' || disabledClass) continue;
      const href = link.getAttribute('href');
      if (href) return href;
    }

    // Fallback: infer next page from any pagination links with page query params.
    const pageLinks = Array.from(document.querySelectorAll('a[href]'))
      .map((a) => a.getAttribute('href') || '')
      .filter((href) => href.includes('/library/titles') && href.includes('page='));

    let bestHref = null;
    let bestPage = Number.POSITIVE_INFINITY;
    for (const href of pageLinks) {
      try {
        const u = new URL(href, window.location.href);
        const pageValue = Number(u.searchParams.get('page'));
        if (!Number.isFinite(pageValue)) continue;
        if (pageValue > currentPageNumInPage && pageValue < bestPage) {
          bestPage = pageValue;
          bestHref = href;
        }
      } catch (_err) {
        // ignore invalid URLs
      }
    }
    if (bestHref) return bestHref;
    return null;
  }, currentPageNum);
}

function buildPagedLibraryUrl(baseLibraryUrl, pageNum, pageSize) {
  const url = new URL(baseLibraryUrl);
  url.searchParams.set('page', String(pageNum));
  url.searchParams.set('pageSize', String(pageSize));
  return url.toString();
}

function waitForEnter(prompt) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stderr,
    });
    rl.question(prompt, () => {
      rl.close();
      resolve();
    });
  });
}

async function ensureSignedIn(page, libraryUrl, headless) {
  await page.goto(libraryUrl, { waitUntil: 'domcontentloaded', timeout: 120000 });
  if (!page.url().toLowerCase().includes('/ap/signin')) return;
  if (headless) {
    throw new Error('Browser session is not logged in. Re-run without --headless once and sign in.');
  }
  await waitForEnter('Sign in to Audible in the opened browser, then press Enter here.\n');
  await page.goto(libraryUrl, { waitUntil: 'domcontentloaded', timeout: 120000 });
  if (page.url().toLowerCase().includes('/ap/signin')) {
    throw new Error('Still not authenticated after login attempt.');
  }
}

async function fetchTitles(args) {
  const profileDir = expandHome(args.profileDir);
  fs.mkdirSync(profileDir, { recursive: true });
  const libraryUrl = `https://${args.domain}/library/titles`;
  const context = await chromium.launchPersistentContext(profileDir, {
    headless: !!args.headless,
  });

  try {
    const page = await context.newPage();
    await ensureSignedIn(page, libraryUrl, !!args.headless);

    const fetchedItems = [];
    const seen = new Set();
    const endpoints = endpointCandidates(args.domain);
    const endpointErrors = [];

    for (const baseUrl of endpoints) {
      let offset = 0;
      let pageNum = 1;
      let foundAny = false;

      while (pageNum <= args.maxPages) {
        const response = await context.request.get(baseUrl, {
          params: {
            num_results: args.pageSize,
            offset,
            content_type: 'Audiobook',
            response_groups: 'contributors,media,product_attrs,product_desc',
          },
          timeout: 30000,
        });

        const status = response.status();
        if (status === 404) {
          endpointErrors.push(`${baseUrl}: endpoint not found`);
          break;
        }
        if (status === 401 || status === 403) {
          endpointErrors.push(`${baseUrl}: auth failed (${status})`);
          break;
        }
        if (status >= 400) {
          endpointErrors.push(`${baseUrl}: HTTP ${status}`);
          break;
        }

        const payload = await response.json();
        const apiItems = extractItems(payload);
        if (!apiItems.length) break;
        foundAny = true;

        for (const item of apiItems) {
          const title = extractTitle(item);
          const author = extractAuthor(item);
          const series = extractSeries(item);
          const summary = extractSummary(item);
          if (!title) continue;
          const key = title.toLowerCase();
          if (seen.has(key)) continue;
          seen.add(key);
          fetchedItems.push({
            title,
            author: author || null,
            series: series || null,
            summary: summary || null,
          });
        }

        console.error(`Fetched page ${pageNum} from ${baseUrl}: ${apiItems.length} item(s).`);
        if (apiItems.length < args.pageSize) break;
        offset += args.pageSize;
        pageNum += 1;
      }

      if (foundAny) return fetchedItems;
    }

    console.error('API endpoint fetch failed; falling back to HTML pagination scrape.');
    if (endpointErrors.length) {
      console.error(endpointErrors.join(' | '));
    }

    let pageNum = 1;
    let stalePages = 0;
    let currentUrl = libraryUrl;
    while (pageNum <= args.maxPages) {
      const prevUrl = currentUrl;
      await page.goto(currentUrl, { waitUntil: 'domcontentloaded', timeout: 120000 });

      if (page.url().toLowerCase().includes('/ap/signin')) {
        throw new Error('Session became unauthenticated while paginating library pages.');
      }

      const pageItems = await extractItemsFromLibraryPage(page);
      if (!pageItems.length) break;

      let newOnPage = 0;
      for (const item of pageItems) {
        const title = cleanTitle(item.title || '');
        if (!title) continue;
        const key = title.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        fetchedItems.push({
          title,
          author: item.author || null,
          series: item.series || null,
          summary: item.summary || null,
        });
        newOnPage += 1;
      }

      console.error(`Scraped page ${pageNum}: ${pageItems.length} candidate(s), ${newOnPage} new.`);
      if (newOnPage === 0) {
        stalePages += 1;
      } else {
        stalePages = 0;
      }
      if (stalePages >= 2) break;

      const nextUrl = await nextLibraryPageUrl(page, pageNum);
      if (nextUrl) {
        currentUrl = new URL(nextUrl, page.url()).toString();
      } else {
        // Some Audible layouts do not expose a detectable next-link; force page traversal.
        currentUrl = buildPagedLibraryUrl(libraryUrl, pageNum + 1, args.pageSize);
      }
      if (currentUrl === prevUrl) break;
      pageNum += 1;
    }

    if (fetchedItems.length && args.probeTitles.length === 0) return fetchedItems;
    if (!fetchedItems.length && args.probeTitles.length === 0) {
      throw new Error('No titles returned from Audible API or HTML pagination.');
    }

    // Backfill: probe explicit titles through library search (helps with items not surfaced in pagination).
    if (args.probeTitles.length > 0) {
      for (const probeTitle of args.probeTitles) {
        const searchUrl = new URL(libraryUrl);
        searchUrl.searchParams.set('searchTerm', probeTitle);
        searchUrl.searchParams.set('k', probeTitle);
        await page.goto(searchUrl.toString(), { waitUntil: 'networkidle', timeout: 120000 });
        if (page.url().toLowerCase().includes('/ap/signin')) {
          throw new Error('Session became unauthenticated during search-probe.');
        }
        const found = await page.evaluate((needle) => {
          const n = needle.toLowerCase();
          const body = (document.body.innerText || '').toLowerCase();
          if (body.includes(n)) return true;
          const links = Array.from(document.querySelectorAll('a[href*=\"/pd/\"]'))
            .map((a) => (a.textContent || '').trim().toLowerCase())
            .filter(Boolean);
          return links.some((t) => t.includes(n) || n.includes(t));
        }, probeTitle);
        if (!found) continue;
        const normalized = cleanTitle(probeTitle);
        const key = normalized.toLowerCase();
        if (!seen.has(key)) {
          seen.add(key);
          fetchedItems.push({ title: normalized, author: null, series: null, summary: null });
          console.error(`Search-backfill found owned title: ${normalized}`);
        }
      }
    }

    if (fetchedItems.length) return fetchedItems;
    throw new Error('No titles returned from Audible API or HTML pagination.');
  } finally {
    await context.close();
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const titles = await fetchTitles(args);
  process.stdout.write(`${JSON.stringify(titles)}\n`);
}

main().catch((err) => {
  console.error(`Node Audible fetch failed: ${err.message}`);
  process.exit(1);
});
