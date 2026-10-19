#!/usr/bin/env node
// Development test: an isolated Chromium profile with synthetic data only.
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const flags = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => index % 2 ? pairs : [...pairs, [value, all[index + 1]]], []));
const base = new URL(flags['--base-url']);
assert(base.protocol === 'https:' && (base.hostname === 'pdd-drive.app' || /^pdd-domain-migration-preview\.[a-z0-9-]+\.workers\.dev$/.test(base.hostname)), 'Only the isolated preview is allowed');
const fixture = JSON.parse(await readFile(flags['--fixture'], 'utf8'));
assert(Object.keys(fixture).every(key => key.startsWith('flutter.') && !/auth|token|premium|pending_sbp|session_store/i.test(key)), 'Only synthetic progress fixtures are allowed');
const output = resolve(flags['--output-dir']);
await mkdir(output, { recursive: true, mode: 0o700 });
const browser = await chromium.launch({ channel: 'chrome', headless: true, env: {...process.env, TMPDIR: output} });
const context = await browser.newContext({ viewport: {width: 430, height: 932}, serviceWorkers: 'block' });
const blocked = [], failures = [], errors = [];
await context.route('**/*', async route => {
  const request = route.request(), url = new URL(request.url());
  if (url.origin !== base.origin || /\/(api|__staging_disabled__)(\/|$)/i.test(decodeURIComponent(url.pathname)) || !['GET', 'HEAD'].includes(request.method())) {
    blocked.push({origin: url.origin, path: url.pathname, method: request.method()});
    await route.abort('blockedbyclient');
  } else await route.continue();
});
const page = await context.newPage();
page.on('pageerror', error => errors.push(error.message.slice(0, 300)));
page.on('requestfailed', request => failures.push({path: new URL(request.url()).pathname, error: request.failure()?.errorText}));
const read = () => page.evaluate(keys => Object.fromEntries(keys.map(key => [key, localStorage.getItem(key)])), Object.keys(fixture));
const differences = (before, after) => Object.keys(before).filter(key => before[key] !== after[key]);
let report;
try {
  const landing = await page.goto(new URL('/', base).href, {waitUntil: 'domcontentloaded'});
  assert.equal(landing.status(), 200);
  assert.match(landing.headers()['content-security-policy'], /connect-src 'self'/);
  assert.match(landing.headers()['x-robots-tag'], /noindex/);
  // Seed once, on the landing page before the Flutter app starts. Never reseed
  // during reloads: doing so would hide actual data loss.
  await page.evaluate(values => { for (const [key, value] of Object.entries(values)) localStorage.setItem(key, value); }, fixture);
  const seeded = await read(); assert.deepEqual(seeded, fixture);
  await page.goto(new URL('/app/', base).href, {waitUntil: 'domcontentloaded'});
  await page.locator('flutter-view, flt-glass-pane').first().waitFor({state: 'attached', timeout: 45000});
  await page.waitForTimeout(1000);
  const first = await read();
  await page.screenshot({path: join(output, 'app-synthetic-progress.png'), fullPage: false});
  await page.reload({waitUntil: 'domcontentloaded'});
  await page.locator('flutter-view, flt-glass-pane').first().waitFor({state: 'attached', timeout: 45000});
  await page.waitForTimeout(750);
  const second = await read();
  await page.reload({waitUntil: 'domcontentloaded'});
  await page.locator('flutter-view, flt-glass-pane').first().waitFor({state: 'attached', timeout: 45000});
  await page.waitForTimeout(750);
  const third = await read();
  await page.screenshot({path: join(output, 'preview-home.png'), fullPage: false});
  const critical = Object.keys(fixture).filter(key => /question_progress_|ticket_progress_|favorites_|favorite_states_|exam_results_|unfinished_session|traffic_controller_progress|sign_swiper_progress|crossroads_priority_progress|game_garage_|game_best_score|game_vehicle|godot_city_question_history/.test(key));
  const initialChanges = differences(fixture, first);
  const firstReloadChanges = differences(first, second);
  const secondReloadChanges = differences(second, third);
  const consumedUiFlags = new Set(['flutter.streak_celebration_pending', 'flutter.home_exam_concept_index']);
  assert(initialChanges.every(key => consumedUiFlags.has(key)), 'App load changed data outside documented UI flags');
  assert(firstReloadChanges.every(key => key === 'flutter.home_exam_concept_index'), 'Reload changed stored progress');
  assert(secondReloadChanges.every(key => key === 'flutter.home_exam_concept_index'), 'Second reload changed stored progress');
  for (const key of critical) {
    assert.equal(first[key], fixture[key], `Initial app load changed critical progress: ${key}`);
    assert.equal(second[key], first[key], `First reload changed critical progress: ${key}`);
    assert.equal(third[key], second[key], `Second reload changed critical progress: ${key}`);
  }
  assert.equal(blocked.filter(row => row.origin !== base.origin).length, 0, 'Unexpected external request attempt');
  assert.equal(errors.length, 0, 'Browser application errors');
  report = {passed: true, base_url: base.href, fixture_keys: Object.keys(fixture).length,
    critical_keys_verified: critical.length, reloads: 2, production_requests_forwarded: 0,
    stable_keys_verified: Object.keys(fixture).length - consumedUiFlags.size,
    seed_to_first_changed: initialChanges, first_to_second_changed: firstReloadChanges,
    second_to_third_changed: secondReloadChanges, blocked, failures, errors,
    limitations: ['Synthetic browser data only', 'Not a cross-origin migration test', 'No real accounts, payment or cloud synchronization tested']};
} catch (error) {
  report = {passed: false, base_url: base.href, error: error.message, blocked, failures, errors};
  await page.screenshot({path: join(output, 'failure.png')}).catch(() => {});
  process.exitCode = 1;
} finally {
  await writeFile(join(output, 'browser-smoke.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  await browser.close();
}
console.log(JSON.stringify({passed: report.passed, critical_keys_verified: report.critical_keys_verified, error: report.error, output}));
