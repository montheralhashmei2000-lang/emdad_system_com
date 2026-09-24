/* IMDAD Platform UX v1 — كشف المنصة + واجهة متكيفة: شريط سفلي للجوال/APK، اختصارات وشارة لسطح المكتب/EXE */
(function(){
'use strict';
var doc=document,root=doc.documentElement,body=doc.body,ua=navigator.userAgent;
function hasElectron(){try{return typeof process!=='undefined'&&!!process.versions&&!!process.versions.electron}catch(e){return false}}
var isAndroid=/Android/i.test(ua), isIOS=/iPhone|iPad|iPod/i.test(ua);
var isWin=/Windows|Win64|Win32/i.test(ua)||(/Win/i.test(navigator.platform||''));
var isElectron=hasElectron();
var isDex=(isAndroid||isIOS)&&/wv|WebView|Capacitor|Cordova/i.test(ua);
var plat=isElectron?'desktop-app':isAndroid?'android':isIOS?'ios':isWin?'windows':'web';
root.dataset.platform=plat; root.dataset.appContainer=isDex?'apk':isElectron?'exe':'web';
body.classList.add('plat-'+plat);
if(isDex)body.classList.add('in-apk');
if(isElectron)body.classList.add('in-exe');

/* ---- جمع عناصر التنقل من الواجهة الموجودة (بدون افتراض بنية) ---- */
var ICONS={dashboard:'🏠',home:'🏠',units:'🏕️',issues:'📤',receipts:'📥',stores:'🏬',warehouses:'🏬',entitlements:'📋',ratios:'📋',transfers:'🔁',returns:'↩️',reports:'📊',users:'👥',settings:'⚙️',branding:'🎨',kitchens:'🍽️',stocktake:'🔢',opening:'💰',audit:'🛡️',profile:'👤'};
function collect(shortOnly){
  var out=[],seen={};
  var els=doc.querySelectorAll('[onclick],[data-nav]');
  for(var i=0;i<els.length;i++){var el=els[i];
    var oc=el.getAttribute&&(el.getAttribute('onclick')||'');
    var m=oc.match(/nav\(\s*['"]([^'"]+)['"]\s*\)/);
    var key=m&&m[1]||(el.getAttribute&&el.getAttribute('data-nav'))||'';
    if(!key||seen[key])continue; seen[key]=1;
    var txt=(el.textContent||'').trim().replace(/\s+/g,' ');
    if(shortOnly&&txt.length>9)continue;
    out.push({key:key,label:txt||key});
  }
  return out;
}
var short=collect(true), all=collect(false);
var items=short.length>=4?short.slice(0,6):all.slice(0,6).map(function(it){it.label=it.label.slice(0,9);return it});
function fireNav(key){
  var el=null;
  var els=doc.querySelectorAll('[onclick],[data-nav]');
  for(var i=0;i<els.length;i++){var x=els[i];
    var oc=x.getAttribute&&(x.getAttribute('onclick')||'');
    var m=oc.match(/nav\(\s*['"]([^'"]+)['"]\s*\)/);
    if((m&&m[1]===key)||(x.getAttribute&&x.getAttribute('data-nav')===key)){el=x;break}
  }
  if(el){try{el.click()}catch(e){}}
  else if(typeof nav==='function'){try{nav(key)}catch(e){}}
  try{var q=doc.querySelector('.ovl,.scrim,.side-scrim,.nav-scrim,.drawer-scrim');if(q)q.click()}catch(e){}
  markActive(key);
}
function markActive(key){
  var bs=doc.querySelectorAll('#imdadBottomNav .ibn-btn');
  for(var i=0;i<bs.length;i++)bs[i].classList.toggle('on',bs[i].getAttribute('data-ibn')===key);
}
/* ---- شريط تنقل سفلي حقيقي (جوال / APK) ---- */
if(items.length>=4 && !doc.getElementById('imdadBottomNav')){
  var bar=doc.createElement('div');bar.id='imdadBottomNav';
  items.forEach(function(it){
    var b=doc.createElement('button');b.type='button';b.className='ibn-btn';b.setAttribute('data-ibn',it.key);
    var base=String(it.key).split(/[._-]/)[0];
    var ic=ICONS[it.key]||ICONS[base]||'•';
    b.innerHTML='<span class="ibn-ic">'+ic+'</span><span class="ibn-lb"></span>';
    b.querySelector('.ibn-lb').textContent=it.label;
    b.addEventListener('click',function(){fireNav(it.key)});
    bar.appendChild(b);
  });
  doc.body.appendChild(bar);
  doc.addEventListener('click',function(e){
    var t=e.target&&e.target.closest?e.target.closest('[onclick],[data-nav]'):null;
    if(!t)return;
    var oc=t.getAttribute&&(t.getAttribute('onclick')||''),m=oc.match(/nav\(\s*['"]([^'"]+)['"]\s*\)/);
    var k=m&&m[1]||(t.getAttribute&&t.getAttribute('data-nav'));
    if(k)markActive(k);
  },true);
}
/* ---- اختصارات لوحة مفاتيح لسطح المكتب (Ctrl+1..9) ---- */
if(!isDex&&!isAndroid&&!isIOS&&all.length){
  doc.addEventListener('keydown',function(e){
    if(!e.ctrlKey||e.altKey||e.metaKey)return;
    if(!/^[1-9]$/.test(e.key))return;
    var it=all[parseInt(e.key,10)-1]; if(!it)return;
    e.preventDefault(); fireNav(it.key);
  });
}
/* ---- شارة المنصة/الإصدار (تختفي تلقائيًا) ---- */
setTimeout(function(){
  try{
    var ver=window.APP_VERSION||'';
    var p=plat==='android'?'📱 نسخة أندرويد':plat==='desktop-app'?'🖥️ نسخة ويندوز (EXE)':plat==='windows'?'🖥️ نسخة ويندوز':plat==='ios'?'📱 نسخة iOS':'🌐 نسخة الويب';
    var c=doc.createElement('div');c.id='imdadChip';c.textContent=p+' • نظام إمداد '+ver;
    doc.body.appendChild(c);
    setTimeout(function(){c.classList.add('hide')},3400);
    setTimeout(function(){try{c.remove()}catch(e){}},6500);
  }catch(e){}
},600);
})();
