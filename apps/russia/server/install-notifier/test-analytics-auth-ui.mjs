import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { ANALYTICS_VIEW_HTML, ANALYTICS_CLIENT_JS } from './analytics_ui.js';
import { usersSnapshot } from './analytics_data.js';

test('auth shares render all providers, zero counts, missing data and narrow screens', async () => {
 const { chromium } = createRequire(import.meta.url)('playwright');
 const browser = await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 try {
  const page = await browser.newPage({viewport:{width:1200,height:900}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.setContent('<body style="background:#F4F5F7;font-family:Arial;padding:20px">'+ANALYTICS_VIEW_HTML+'</body>');
  await page.addScriptTag({content:ANALYTICS_CLIENT_JS});
  const providers=['yandex','google','google','apple','telegram'];
  const users=usersSnapshot(providers.map(provider=>({provider})),1,'ru',d=>d.toISOString().slice(0,10));
  await page.evaluate(users=>anRenderAuth({users}),users);
  const rows=page.locator('#an-auth-table tbody tr');
  assert.equal(await rows.count(),4);
  assert.deepEqual(await rows.allTextContents(),['Яндекс120%','Google240%','Apple120%','Telegram120%']);
  assert.match(await page.locator('#an-auth').innerText(),/Всё время/);
  for(const width of [1200,375]) {
   await page.setViewportSize({width,height:900});
   const bounds=await page.locator('#an-auth').evaluate(el=>({width:el.clientWidth,scroll:el.scrollWidth}));
   assert.ok(bounds.scroll<=bounds.width,`card overflows at ${width}`);
   if(process.env.ANALYTICS_UI_SCREENSHOTS){
    await mkdir(new URL('../../output/analytics-auth/',import.meta.url),{recursive:true});
    await page.locator('#an-auth').screenshot({path:fileURLToPath(new URL(`../../output/analytics-auth/${width}.png`,import.meta.url))});
   }
  }
  await page.evaluate(()=>anRenderAuth({users:{registered:2,authProviders:{yandex:1,unknown:1}}}));
  assert.equal(await rows.count(),5);
  assert.match(await rows.nth(1).innerText(),/0%/);
  assert.match(await rows.nth(4).innerText(),/Неизвестный способ.*1.*50%/s);
  await page.evaluate(()=>anRenderAuth({users:{registered:0,authProviders:{}}}));
  assert.match(await page.locator('#an-auth-table').innerText(),/Пока нет зарегистрированных аккаунтов/);
  await page.evaluate(()=>anRenderAuth({}));
  assert.match(await page.locator('#an-auth-table').innerText(),/недоступны/);
  assert.deepEqual(errors,[]);
 } finally {await browser.close();}
});
