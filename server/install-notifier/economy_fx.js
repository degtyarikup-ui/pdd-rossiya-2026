// Official CBR daily USD/RUB reference rate. No arbitrary/manual fallback.
const KEY = 'economy_fx_usd_v1';
const flights = new WeakMap();
const moscowDay = now => new Date(now + 10800000).toISOString().slice(0,10);
export function parseCbrUsd(xml, requestedDay) {
  const date = xml.match(/<ValCurs\b[^>]*\bDate="(\d{2})\.(\d{2})\.(\d{4})"/);
  const row = (xml.match(/<Valute\b[^>]*>[\s\S]*?<\/Valute>/g) || []).find(value => /<CharCode>USD<\/CharCode>/.test(value));
  const numeric = tag => Number(row?.match(new RegExp('<'+tag+'>([^<]+)</'+tag+'>'))?.[1]?.replace(/\s/g,'').replace(',','.'));
  const rate = numeric('Value') / numeric('Nominal');
  const effectiveDate = date ? `${date[3]}-${date[2]}-${date[1]}` : '';
  if (!effectiveDate || !Number.isFinite(Date.parse(effectiveDate)) || new Date(effectiveDate).toISOString().slice(0,10)!==effectiveDate || effectiveDate > requestedDay || !Number.isFinite(rate) || rate <= 0 || rate > 100000) throw new Error('Invalid CBR rate');
  return { rubPerUsd: rate, effectiveDate, source: 'CBR', sourceUrl: 'https://www.cbr.ru/currency_base/daily/', base: 'USD', quote: 'RUB' };
}
export async function getUsdRate(env, deps = {}) {
  if (deps.fx) return deps.fx; // Explicit deterministic test dependency.
  const now=deps.now??Date.now(), today=moscowDay(now);
  let cached;try { cached=JSON.parse(await env.INSTALLS.get(KEY)); } catch(_) {}
  if (!(cached?.rubPerUsd > 0 && cached.effectiveDate <= today)) cached=null;
  if(cached && !deps.force && cached.requestedDay===today && now-Date.parse(cached.checkedAt)<3600000) return {...cached,stale:false};
  let task=flights.get(env.INSTALLS);
  if(!task){
    task=(async()=>{
      const requestDate=today.split('-').reverse().join('/');
      const response=await (deps.fxFetch||fetch)('https://www.cbr.ru/scripts/XML_daily.asp?date_req='+encodeURIComponent(requestDate),{redirect:'manual',signal:AbortSignal.timeout(7000)});
      if(!response.ok)throw new Error('CBR unavailable');
      const data={...parseCbrUsd(await response.text(),today),requestedDay:today,checkedAt:new Date(now).toISOString()};
      await env.INSTALLS.put(KEY,JSON.stringify(data));return data;
    })();flights.set(env.INSTALLS,task);
  }
  try{return {...await task,stale:false};}
  catch(_){if(cached)return {...cached,stale:true};throw new Error('Не удалось получить курс ЦБ. Повторите обновление.');}
  finally{if(flights.get(env.INSTALLS)===task)flights.delete(env.INSTALLS);}
}
