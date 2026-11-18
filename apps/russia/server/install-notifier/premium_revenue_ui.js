// Composed into the analytics view; shares its folding, charts and tooltips.
export const PREMIUM_REVENUE_CSS = String.raw`
.an-premium{--an-premium-orange:#FF7A00}.an-premium .an-head{margin-bottom:24px}.an-premium-heading{display:flex;align-items:center;gap:10px}.an-premium [hidden]{display:none!important}
.an-premium-summary{display:grid;grid-template-columns:1.4fr repeat(3,1fr);gap:24px;margin:4px 0 30px}.an-premium-summary>span{display:flex;flex-direction:column;gap:12px;font-size:11px;color:var(--an-muted);min-width:0}.an-premium-summary b{font-size:26px;font-weight:550;letter-spacing:-.8px;color:var(--an-text);line-height:1.15;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}.an-premium-summary>span:first-child b{font-size:40px;letter-spacing:-1.8px;color:var(--an-premium-orange)}
.an-premium-layout{display:grid;grid-template-columns:minmax(0,1fr) 240px;gap:36px;align-items:start}.an-premium .an-chart{min-height:210px}.an-premium-sources{display:flex;flex-direction:column;gap:20px;padding-top:12px}.an-premium-source{display:grid;grid-template-columns:22px minmax(0,1fr) auto;gap:8px;align-items:center;font-size:12px}.an-premium-source>.an-logo{width:22px;height:22px}.an-premium-source>.an-logo svg{width:20px;height:20px}.an-premium-source b{font-weight:550;font-variant-numeric:tabular-nums;white-space:nowrap}.an-premium-source small{grid-column:2 / -1;color:var(--an-muted);font-size:10px;margin-top:-3px}.an-premium .an-empty{padding:48px 12px}
.an-premium .an-chart svg:focus-visible{outline:2px solid var(--an-premium-orange);outline-offset:-2px;border-radius:8px}.an-premium .an-chart rect[data-premium-point]{cursor:crosshair}.an-premium .an-chart svg{overflow:visible}.an-premium .an-premium-point{pointer-events:none}
@media(max-width:1000px){.an-premium-layout{grid-template-columns:minmax(0,1fr) 190px;gap:24px}}
@media(max-width:640px){.an-premium .an-head{margin-bottom:24px}.an-premium-heading{gap:6px}.an-premium .an-title{font-size:15px}.an-premium-summary{grid-template-columns:repeat(2,minmax(0,1fr));gap:22px 16px;margin-bottom:24px}.an-premium-summary>span{font-size:10px;gap:9px}.an-premium-summary>span:first-child b{font-size:32px}.an-premium-summary b{font-size:24px}.an-premium-layout{grid-template-columns:minmax(0,1fr);gap:12px}.an-premium-sources{padding-top:0;gap:16px}.an-premium-source{font-size:11px}.an-premium .an-chart{min-height:190px}}
@media(max-width:359px){.an-premium-summary>span:first-child b{font-size:28px}}
`;

export const PREMIUM_REVENUE_HTML = String.raw`
<section class="an-card an-premium" id="an-premium" aria-label="Покупки Premium">
 <div class="an-head">
  <div class="an-premium-heading"><h3 class="an-title"><button type="button" class="an-fold" aria-expanded="true" aria-controls="an-body-premium">Покупки Premium</button></h3></div>
 </div>
 <div id="an-body-premium">
  <div class="an-premium-summary" id="an-premium-summary"></div>
  <div class="an-premium-layout"><div class="an-chart" id="an-premium-chart" aria-label="Покупки Premium по дням"></div><div class="an-premium-sources" id="an-premium-sources" aria-label="Способы оплаты"></div></div>
 </div>
</section>
`;

export const PREMIUM_REVENUE_CLIENT_JS = String.raw`
var AN_PREMIUM_ORANGE='#FF7A00';
var AN_PREMIUM_METHODS={web:{label:'СБП',icon:'sbp'},appstore:{label:'App Store',icon:'appstore'},googleplay:{label:'Google Play',icon:'gplay'},rustore:{label:'RuStore',icon:'rustore'},unknown:{label:'Неизвестно',icon:'other'}};
function anPremiumMoney(value){
 if(value>0&&value<1)return '< 0,01 $';
 return new Intl.NumberFormat('ru-RU',{style:'currency',currency:'USD',minimumFractionDigits:2,maximumFractionDigits:2}).format(value/100);
}
function anPremiumValue(row){return row&&Number.isFinite(row.amountCents)?anEsc(anPremiumMoney(row.amountCents)):'—';}
function anPremiumMethod(key){return AN_PREMIUM_METHODS[key]||AN_PREMIUM_METHODS.unknown;}
var anPremiumCharts=new WeakMap();
var anPremiumResize=new ResizeObserver(function(entries){entries.forEach(function(entry){
 var chart=anPremiumCharts.get(entry.target),svg=entry.target.firstElementChild;
 if(chart&&entry.target.clientWidth&&svg&&Number(svg.getAttribute('width'))!==Math.max(120,entry.target.clientWidth))anMetricLine(entry.target,chart.points,chart.height,chart.label,chart.color,chart.secondary);
});});
function anPremiumClearSelection(el){
 delete el.dataset.activePoint;
 var marker=el.querySelector('[data-premium-marker]');if(marker)marker.setAttribute('visibility','hidden');
}
function anMetricLine(el,points,height,label,color,secondary){
 var gradientId=el.id+'-area';
 if(!anPremiumCharts.has(el))anPremiumResize.observe(el);
 anPremiumCharts.set(el,{points:points,height:height,label:label,color:color,secondary:secondary});
 var W=Math.max(120,el.clientWidth),H=height,padL=el.clientWidth<350?40:54,padR=12,padT=16,padB=30,plotW=W-padL-padR,plotH=H-padT-padB;
 var max=Math.max.apply(null,points.map(function(point){return Math.max(point.value||0,secondary?point[secondary.key]||0:0);}).concat([1]));
 var x=function(i){return points.length===1?padL+plotW/2:padL+i*plotW/(points.length-1);};
 var y=function(value){return padT+plotH-value/max*plotH;},bottom=y(0);
 var svg='<svg width="'+W+'" height="'+H+'" role="img" tabindex="0" aria-label="'+anEsc(label)+'"><desc>Стрелки влево и вправо выбирают день и значение. Home — первый день, End — последний.</desc><defs><linearGradient id="'+gradientId+'" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="'+(color||AN_PREMIUM_ORANGE)+'" stop-opacity=".22"/><stop offset="100%" stop-color="'+(color||AN_PREMIUM_ORANGE)+'" stop-opacity=".015"/></linearGradient></defs>';
 [0,max].forEach(function(value){svg+='<line x1="'+padL+'" x2="'+(W-padR)+'" y1="'+y(value)+'" y2="'+y(value)+'" stroke="#EFF0F4"/><text x="'+(padL-10)+'" y="'+(y(value)+4)+'" text-anchor="end" font-size="11" font-weight="500" fill="#747B88">'+anNum(value)+'</text>';});
 function drawSeries(key,stroke,fillId){
  var runs=[],run=[];
  points.forEach(function(point,i){if(point[key]==null){if(run.length)runs.push(run);run=[];}else run.push({x:x(i),y:y(point[key])});});if(run.length)runs.push(run);
  runs.forEach(function(items){
   if(items.length<2)return;
   var line=items.map(function(point,i){return(i?'L':'M')+point.x+','+point.y;}).join('');
   svg+='<path class="an-premium-area" d="'+line+'L'+items[items.length-1].x+','+bottom+'L'+items[0].x+','+bottom+'Z" fill="url(#'+fillId+')"/><path class="an-premium-line" d="'+line+'" fill="none" stroke="'+stroke+'" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>';
  });
  points.forEach(function(point,i){
   if(point[key]!=null)svg+='<circle class="an-premium-point" data-premium-dot="'+i+'" cx="'+x(i)+'" cy="'+y(point[key])+'" r="'+(points.length>31?2:3.5)+'" fill="white" stroke="'+stroke+'" stroke-width="2"/>';
  });
 }
 drawSeries('value',color||AN_PREMIUM_ORANGE,gradientId);
 if(secondary){
  var secondId=gradientId+'-second';
  svg+='<defs><linearGradient id="'+secondId+'" href="#'+gradientId+'"><stop offset="0%" stop-color="'+secondary.color+'" stop-opacity=".18"/><stop offset="100%" stop-color="'+secondary.color+'" stop-opacity=".015"/></linearGradient></defs>';
  drawSeries(secondary.key,secondary.color,secondId);
 }
 var every=Math.max(1,Math.ceil((points.length-1)/Math.max(1,Math.floor(plotW/70))));
 points.forEach(function(point,i){
  if(i===points.length-1||(points.length-1-i)%every===0)svg+='<text x="'+x(i)+'" y="'+(H-6)+'" text-anchor="middle" font-size="11" font-weight="500" fill="#747B88">'+point.label+'</text>';
 });
 svg+='<g data-premium-marker visibility="hidden" pointer-events="none"><line data-premium-guide y1="'+padT+'" y2="'+bottom+'" stroke="'+(color||AN_PREMIUM_ORANGE)+'" stroke-opacity=".45"/><circle data-premium-halo r="12" fill="'+(color||AN_PREMIUM_ORANGE)+'" fill-opacity=".13"/><circle data-premium-selected r="5" fill="'+(color||AN_PREMIUM_ORANGE)+'" stroke="white" stroke-width="2"/></g>';
 points.forEach(function(point,i){var left=i? (x(i-1)+x(i))/2:padL,right=i<points.length-1?(x(i)+x(i+1))/2:W-padR;svg+='<rect data-i="'+i+'" data-premium-point="'+i+'" x="'+left+'" y="0" width="'+Math.max(1,right-left)+'" height="'+bottom+'" fill="transparent"/>';});
 el.innerHTML=svg+'</svg>';delete el.dataset.activePoint;
 var root=el.querySelector('svg'),active=points.length-1;
 var show=function(index,event){
  active=index;el.dataset.activePoint=String(index);
  var point=points[index],marker=el.querySelector('[data-premium-marker]'),guide=el.querySelector('[data-premium-guide]');
  root.setAttribute('aria-label',label+'. '+point.label+': '+(color?anNum(point.value):point.amountCents==null?'нет суммы':anPremiumMoney(point.amountCents))+(secondary?' · '+secondary.label+': '+anNum(point[secondary.key]):''));
  marker.setAttribute('visibility','visible');guide.setAttribute('x1',x(index));guide.setAttribute('x2',x(index));
  ['halo','selected'].forEach(function(part){var dot=el.querySelector('[data-premium-'+part+']');dot.setAttribute('visibility',point.value==null?'hidden':'visible');dot.setAttribute('cx',x(index));dot.setAttribute('cy',point.value==null?bottom:y(point.value));});
  if(!event){var bounds=root.getBoundingClientRect();event={clientX:bounds.left+x(index),clientY:bounds.top+(point.value==null?bottom:y(point.value))};}
  anTipShow(point.tip,event);
 };
 el.querySelectorAll('[data-premium-point]').forEach(function(hit){
  var display=function(event){show(Number(hit.dataset.premiumPoint),event);};
  hit.addEventListener('mousemove',display);hit.addEventListener('pointerdown',display);
 });
 root.addEventListener('mouseleave',function(){if(document.activeElement!==root){anTipHide();anPremiumClearSelection(el);}});
 root.addEventListener('focus',function(){show(active);});root.addEventListener('blur',function(){anTipHide();anPremiumClearSelection(el);});
 root.addEventListener('keydown',function(event){
  if(event.key==='Escape'){anTipHide();anPremiumClearSelection(el);return;}
  var next=event.key==='ArrowLeft'?Math.max(0,active-1):event.key==='ArrowRight'?Math.min(points.length-1,active+1):event.key==='Home'?0:event.key==='End'?points.length-1:null;
  if(next!=null){event.preventDefault();show(next);}
 });
}
function anRenderPremium(data){
 var revenue=data&&data.premiumPurchases,available=!!(revenue&&revenue.available),usd=available&&revenue.usd,finance=!!(usd&&usd.available),totals=available?(usd&&usd.totals||revenue.totals):null;
 var unverified=revenue&&revenue.coverage&&revenue.coverage.unverifiedPurchases||0,missingDates=revenue&&revenue.coverage&&revenue.coverage.missingDates||0,incomplete=unverified||missingDates;
 var known=totals&&(totals.purchases||!incomplete),priced=finance&&totals.pricedPurchases;
 document.getElementById('an-premium-summary').innerHTML=[['Выручка за период',finance&&known?anPremiumValue(totals):'—'],['Покупки',known?anNum(totals.purchases):'—'],['Средний чек',priced?anEsc(anPremiumMoney(totals.averageCheckCents)):'—'],['В среднем за день',finance&&known&&totals.averageDailyCents!=null?anEsc(anPremiumMoney(totals.averageDailyCents)):'—']].map(function(metric){return '<span>'+metric[0]+'<b>'+metric[1]+'</b></span>';}).join('');
 var methods=available?(usd&&usd.methods||revenue.methods||[]):[],timeline=available?(usd&&usd.timeline||revenue.timeline||[]):[],chart=document.getElementById('an-premium-chart');
 var hasMoney=priced>0,hasPurchases=totals&&totals.purchases>0;
 var sources=document.getElementById('an-premium-sources');
 sources.innerHTML=methods.filter(function(row){return row.purchases>0;}).map(function(row){var method=anPremiumMethod(row.key),count=row.purchases;return '<div class="an-premium-source">'+anLogo({icon:method.icon})+'<span>'+anEsc(method.label)+'</span><b>'+anPremiumValue(row)+'</b><small>'+anNum(count)+' '+anPremiumPurchaseWord(count)+'</small></div>';}).join('');
 sources.hidden=!sources.innerHTML;
 chart.parentElement.style.gridTemplateColumns=sources.hidden?'minmax(0,1fr)':'';
 if(!available||!finance||!timeline.length||!hasPurchases||!hasMoney){
  anPremiumCharts.delete(chart);anPremiumResize.unobserve(chart);
  chart.innerHTML='<div class="an-empty">'+(!available?'Данные о покупках недоступны':!finance?'Не удалось получить курс валют':!hasPurchases?(incomplete?'Нет подтверждённых сумм за период':'За этот период покупок нет'):!hasMoney?'Суммы покупок не сохранены':'Нет данных по дням')+'</div>';
 }else{
  var points=timeline.map(function(day){
   var value=day.amountCents==null?null:day.amountCents/100;
   var tip='<b>'+anDayLabel(day.date,true)+'</b><div class="an-tip-row"><span>Выручка</span><b>'+anPremiumValue(day)+'</b></div><div class="an-tip-row"><span>Покупки</span><b>'+anNum(day.purchases)+'</b></div>';
   (day.methods||[]).filter(function(row){return row.purchases>0;}).forEach(function(row){tip+='<div class="an-tip-row"><span>'+anEsc(anPremiumMethod(row.key).label)+'</span><b>'+anPremiumValue(row)+'</b></div>';});
   if(day.missingAmounts)tip+='<div class="an-tip-note">Без суммы: '+anNum(day.missingAmounts)+'</div>';
   return {label:anDayLabel(day.date),value:value,amountCents:day.amountCents,tip:tip};
  });
  anMetricLine(chart,points,window.innerWidth<640?190:210,'Выручка, USD по дням');
 }
}
function anPremiumPurchaseWord(count){var n=count%100;return n>=11&&n<=14?'покупок':count%10===1?'покупка':count%10>=2&&count%10<=4?'покупки':'покупок';}
`;
