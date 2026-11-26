// Telemetry + screenshot probe. Copy into the repo root as .probe.tmp.mjs, run with Windows node, delete after.
// Usage: node .probe.tmp.mjs [seconds=10] [screenshotPrefix] [mockupHtmlPath]
// Env: PROBE_GLOBAL       name of the app's diagnostics object on window (default __DIAGNOSTICS__)
//      PROBE_LOCALSTORAGE JSON object of localStorage keys to preset, e.g. '{"onboarding_done":"true"}'
//      PROBE_CHANNEL      Playwright browser channel (default msedge; "" for bundled Chromium)
import { createServer } from 'vite';
import { chromium } from 'playwright';
import { pathToFileURL } from 'node:url';

const seconds = Number(process.argv[2] ?? 10);
const shotPrefix = process.argv[3];
const mockup = process.argv[4];
const globalName = process.env.PROBE_GLOBAL || '__DIAGNOSTICS__';
const preset = JSON.parse(process.env.PROBE_LOCALSTORAGE || '{}');
const channel = process.env.PROBE_CHANNEL ?? 'msedge';

const server = await createServer({ server: { port: 0, strictPort: false }, logLevel: 'error' });
await server.listen();
const url = server.resolvedUrls.local[0];
const browser = await chromium.launch({ headless: true, ...(channel ? { channel } : {}), args: ['--use-gl=angle', '--use-angle=default', '--ignore-gpu-blocklist'] });
const errors = [];
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  page.on('pageerror', e => errors.push(String(e.message)));
  page.on('console', m => m.type() === 'error' && errors.push(m.text()));
  await page.addInitScript(p => { try { for (const [k, v] of Object.entries(p)) localStorage.setItem(k, v); } catch {} }, preset);
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(name => window[name], globalName, { timeout: 30000 });
  const trace = [];
  for (let i = 0; i < seconds; i++) {
    await page.waitForTimeout(1000);
    trace.push(await page.evaluate(name => ({ ...window[name] }), globalName));
  }
  const keys = [...new Set(trace.flatMap(d => Object.keys(d).filter(k => typeof d[k] === 'number')))];
  const stats = {};
  for (const k of keys) {
    const v = trace.map(d => d[k]).filter(x => typeof x === 'number' && Number.isFinite(x));
    if (v.length) stats[k] = { min: +Math.min(...v).toFixed(3), max: +Math.max(...v).toFixed(3), final: +v.at(-1).toFixed(3) };
  }
  const nonFinite = trace.flatMap((d, i) => Object.entries(d).filter(([, x]) => typeof x === 'number' && !Number.isFinite(x)).map(([k]) => `${i}:${k}`));
  console.log(JSON.stringify({ url, seconds, globalName, stats, nonFinite, errors: errors.slice(0, 10) }, null, 2));
  if (shotPrefix) {
    await page.screenshot({ path: `${shotPrefix}-app-1280.png` });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    await page.screenshot({ path: `${shotPrefix}-app-390.png`, fullPage: true });
    if (mockup) {
      const m = await browser.newPage({ viewport: { width: 1280, height: 800 } });
      await m.goto(pathToFileURL(mockup).href); await m.waitForTimeout(500);
      await m.screenshot({ path: `${shotPrefix}-mock-1280.png` });
      await m.setViewportSize({ width: 390, height: 844 }); await m.waitForTimeout(300);
      await m.screenshot({ path: `${shotPrefix}-mock-390.png`, fullPage: true });
    }
  }
} finally {
  await browser.close();
  await server.close();
}
