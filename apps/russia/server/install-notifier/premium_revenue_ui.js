// Composed into the analytics view; shares its folding, charts and tooltips.
export const PREMIUM_REVENUE_CSS = String.raw`
.an-premium .an-head{margin-bottom:24px;flex-wrap:wrap}.an-premium-heading,.an-premium-controls{display:flex;align-items:center;gap:10px}.an-premium-controls{margin-left:auto}.an-premium [hidden]{display:none!important}
.an-premium-summary{display:grid;grid-template-columns:1.5fr 1fr 1fr;gap:24px;margin:4px 0 30px}.an-premium-summary>span{display:flex;flex-direction:column;gap:12px;font-size:11px;color:var(--an-muted);min-width:0}.an-premium-summary b{font-size:26px;font-weight:550;letter-spacing:-.8px;color:var(--an-text);line-height:1.15;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}.an-premium-summary>span:first-child b{font-size:40px;letter-spacing:-1.8px;color:var(--an-green)}
.an-premium-layout{display:grid;grid-template-columns:minmax(0,1fr) 240px;gap:36px;align-items:start}.an-premium .an-chart{min-height:210px}.an-premium-sources{display:flex;flex-direction:column;gap:20px;padding-top:12px}.an-premium-source{display:grid;grid-template-columns:8px minmax(0,1fr) auto;gap:8px;align-items:center;font-size:12px}.an-premium-source .an-dot{width:6px;height:6px}.an-premium-source b{font-weight:550;font-variant-numeric:tabular-nums;white-space:nowrap}.an-premium-source small{grid-column:2 / -1;color:var(--an-muted);font-size:10px;margin-top:-3px}.an-premium .an-caption{margin-top:12px}.an-premium .an-search{flex:none;cursor:pointer;min-height:34px;width:76px;padding:7px 8px;font-size:11px}.an-premium .an-day-details{margin-top:20px}.an-premium .an-table th:first-child{width:40%}.an-premium .an-table .an-premium-missing{color:var(--an-muted);font-weight:450}.an-premium .an-empty{padding:48px 12px}
.an-premium.an-folded .an-premium-controls{display:none}
@media(max-width:1000px){.an-premium-layout{grid-template-columns:minmax(0,1fr) 190px;gap:24px}}
@media(max-width:640px){.an-premium .an-head{gap:14px;margin-bottom:24px}.an-premium-heading{gap:6px}.an-premium .an-title{font-size:15px}.an-premium-controls{margin-left:0;justify-content:space-between;width:100%;gap:8px}.an-premium .an-tabs button{padding:6px 12px}.an-premium-summary{grid-template-columns:repeat(2,minmax(0,1fr));gap:22px 16px;margin-bottom:24px}.an-premium-summary>span{font-size:10px;gap:9px}.an-premium-summary>span:first-child{grid-column:1 / -1}.an-premium-summary>span:first-child b{font-size:36px}.an-premium-summary b{font-size:24px}.an-premium-layout{grid-template-columns:minmax(0,1fr);gap:12px}.an-premium-sources{padding-top:0;gap:16px}.an-premium-source{font-size:11px}.an-premium .an-chart{min-height:190px}.an-premium .an-table th:first-child{width:auto}.an-premium .an-table th{white-space:normal}}
`;

export const PREMIUM_REVENUE_HTML = String.raw`
<section class="an-card an-premium" id="an-premium" aria-label="Покупки Premium">
 <div class="an-head">
  <div class="an-premium-heading"><h3 class="an-title"><button type="button" class="an-fold" aria-expanded="true" aria-controls="an-body-premium">Покупки Premium</button></h3><details class="an-help"><summary aria-label="О выручке Premium">i</summary><div>Суммы покупок до комиссий, по дате подтверждения сервером. Дни — по МСК, сегодня ещё не завершён. Валюты считаются отдельно. Средний чек — по покупкам с сохранённой суммой в выбранной валюте. Тестовые оплаты исключены. Возвраты СБП учтены; последующие возвраты магазинов не пересчитываются. Старые покупки без суммы отмечены отдельно.</div></details></div>
  <div class="an-premium-controls"><div class="an-tabs" id="an-premium-modes" role="group" aria-label="Показатель покупок"><button type="button" data-premium-mode="revenue" class="active" aria-pressed="true">Выручка</button><button type="button" data-premium-mode="purchases" aria-pressed="false">Покупки</button></div><select class="an-search" id="an-premium-currencies" aria-label="Валюта выручки" hidden></select></div>
 </div>
 <div id="an-body-premium">
  <div class="an-premium-summary" id="an-premium-summary"></div>
  <div class="an-premium-layout"><div class="an-chart" id="an-premium-chart" aria-label="Покупки Premium по дням"></div><div class="an-premium-sources" id="an-premium-sources" aria-label="Способы оплаты"></div></div>
  <div class="an-caption" id="an-premium-coverage"></div>
  <details class="an-day-details" id="an-details-premium-values"><summary>По дням</summary><div class="an-table-wrap" id="an-premium-days"></div></details>
 </div>
</section>
`;

export const PREMIUM_REVENUE_CLIENT_JS = String.raw`
var anPremiumMode='revenue',anPremiumCurrency='RUB';
var AN_PREMIUM_METHODS={web:{label:'СБП',color:'#22a875'},appstore:{label:'App Store',color:'#17191E'},googleplay:{label:'Google Play',color:'#0574F8'},rustore:{label:'RuStore',color:'#8B65D9'},unknown:{label:'Неизвестно',color:'#B5BBC6'}};
function anPremiumMoney(value,currency){
 try{return new Intl.NumberFormat('ru-RU',{style:'currency',currency:currency,minimumFractionDigits:0,maximumFractionDigits:2}).format(value/1000);}
 catch(_){return anNum(value/1000)+' '+currency;}
}
function anPremiumCount(row,currency){return row&&row.pricedPurchases&&row.pricedPurchases[currency]||0;}
function anPremiumAmount(row,currency){return row&&row.amounts&&row.amounts[currency]||0;}
function anPremiumValue(row,currency){return row&&row.missingAmounts&&!anPremiumCount(row,currency)?'—':anEsc(anPremiumMoney(anPremiumAmount(row,currency),currency));}
function anPremiumMethod(key){return AN_PREMIUM_METHODS[key]||AN_PREMIUM_METHODS.unknown;}
function anRenderPremium(data){
 var revenue=data&&data.premiumPurchases,available=!!(revenue&&revenue.available),totals=available?revenue.totals:null;
 var currencies=available&&revenue.currencies&&revenue.currencies.length?revenue.currencies:['RUB'];
 if(currencies.indexOf(anPremiumCurrency)===-1)anPremiumCurrency=currencies[0];
 var currency=anPremiumCurrency,selector=document.getElementById('an-premium-currencies');
 selector.innerHTML=currencies.map(function(code){return '<option value="'+anEsc(code)+'">'+anEsc(code)+'</option>';}).join('');selector.value=currency;selector.hidden=currencies.length<2||anPremiumMode==='purchases';
 document.querySelectorAll('[data-premium-mode]').forEach(function(button){var active=button.dataset.premiumMode===anPremiumMode;button.classList.toggle('active',active);button.setAttribute('aria-pressed',String(active));});
 var unverified=revenue&&revenue.coverage&&revenue.coverage.unverifiedPurchases||0,missingDates=revenue&&revenue.coverage&&revenue.coverage.missingDates||0,incomplete=unverified||missingDates;
 var priced=anPremiumCount(totals,currency),amount=anPremiumAmount(totals,currency),known=totals&&(totals.purchases||!incomplete);
 document.getElementById('an-premium-summary').innerHTML=[['Выручка за период',known?anPremiumValue(totals,currency):'—'],['Покупки',known?anNum(totals.purchases):'—'],['Средний чек',priced?anEsc(anPremiumMoney(Math.round(amount/priced),currency)):'—']].map(function(metric){return '<span>'+metric[0]+'<b>'+metric[1]+'</b></span>';}).join('');
 var missing=totals&&totals.missingAmounts||0,coverage=document.getElementById('an-premium-coverage');
 coverage.textContent=(missing?'Без суммы: '+anNum(missing):'')+(missing&&incomplete?' · ':'')+(incomplete?'Неполная история':'');
 coverage.title=(missing?'У этих покупок нет сохранённой суммы. Выручка и средний чек учитывают только известные суммы. ':'')+(unverified?'Старые записи без подтверждённого статуса: '+anNum(unverified)+'. Они не включены в итог. ':'')+(missingDates?'Без даты подтверждения: '+anNum(missingDates)+'. Они не включены в итог.':'');
 var methods=available?revenue.methods||[]:[],timeline=available?revenue.timeline||[]:[],chart=document.getElementById('an-premium-chart');
 var hasMoney=priced>0,hasPurchases=totals&&totals.purchases>0;
 var sources=document.getElementById('an-premium-sources');
 sources.innerHTML=methods.filter(function(row){return row.purchases>0;}).map(function(row){var method=anPremiumMethod(row.key),count=row.purchases;return '<div class="an-premium-source"><i class="an-dot" style="background:'+method.color+'" aria-hidden="true"></i><span>'+anEsc(method.label)+'</span><b>'+(anPremiumMode==='revenue'?anPremiumValue(row,currency):anNum(count))+'</b>'+(anPremiumMode==='revenue'?'<small>'+anNum(count)+' '+anPremiumPurchaseWord(count)+'</small>':'')+'</div>';}).join('');
 sources.hidden=!sources.innerHTML;
 chart.parentElement.style.gridTemplateColumns=sources.hidden?'minmax(0,1fr)':'';
 if(!available||!timeline.length||!hasPurchases||(anPremiumMode==='revenue'&&!hasMoney)){
  anBarCharts.delete(chart);anBarResize.unobserve(chart);
  chart.innerHTML='<div class="an-empty">'+(!available?'Данные о покупках недоступны':!hasPurchases?(incomplete?'История покупок неполная':'За этот период покупок нет'):anPremiumMode==='revenue'&&!hasMoney?'Суммы покупок не сохранены':'Нет данных по дням')+'</div>';
 }else{
  var bars=timeline.map(function(day){
   var dayMethods=day.methods||[],segments;
   if(anPremiumMode==='revenue'){
    segments=dayMethods.length?dayMethods.map(function(row){return {value:anPremiumAmount(row,currency)/1000,color:anPremiumMethod(row.key).color};}):[{value:anPremiumAmount(day,currency)/1000,color:AN_C.green}];
   }else{
    segments=dayMethods.length?dayMethods.map(function(row){return {value:row.purchases||0,color:anPremiumMethod(row.key).color};}):[{value:day.purchases||0,color:AN_C.green}];
   }
   var tip='<b>'+anDayLabel(day.date,true)+'</b><div class="an-tip-row"><span>Выручка</span><b>'+anPremiumValue(day,currency)+'</b></div><div class="an-tip-row"><span>Покупки</span><b>'+anNum(day.purchases)+'</b></div>';
   if(day.missingAmounts)tip+='<div class="an-tip-note">Без суммы: '+anNum(day.missingAmounts)+'</div>';
   return {label:anDayLabel(day.date),segments:segments,tip:tip};
  });
  anBars(chart,bars,window.innerWidth<640?190:210,true);
  var svg=chart.querySelector('svg');if(svg)svg.setAttribute('aria-label',(anPremiumMode==='revenue'?'Выручка, '+currency:'Количество покупок')+' по дням');
 }
 var details=document.getElementById('an-details-premium-values');details.hidden=!available||!timeline.length;
 document.getElementById('an-premium-days').innerHTML=available?anTable(['День','Покупки','Сумма, '+anEsc(currency)],timeline.slice().reverse().map(function(day){return '<tr><td>'+anDayLabel(day.date)+'</td><td>'+anNum(day.purchases)+'</td><td>'+anPremiumValue(day,currency)+(day.missingAmounts?'<span class="an-premium-missing" title="Покупки без сохранённой суммы"> · '+anNum(day.missingAmounts)+' без суммы</span>':'')+'</td></tr>';})):'';
}
function anPremiumPurchaseWord(count){var n=count%100;return n>=11&&n<=14?'покупок':count%10===1?'покупка':count%10>=2&&count%10<=4?'покупки':'покупок';}
document.getElementById('an-premium-modes').addEventListener('click',function(event){var button=event.target.closest('[data-premium-mode]');if(button){anPremiumMode=button.dataset.premiumMode;anTipHide();if(window.__anData)anRenderPremium(window.__anData);}});
document.getElementById('an-premium-currencies').addEventListener('change',function(event){anPremiumCurrency=event.target.value;anTipHide();if(window.__anData)anRenderPremium(window.__anData);});
`;
