/* IMDAD Access Control v1 — الأدوار المتعددة ونطاق المستودعات
   - قوالب أدوار جاهزة (مدخل بيانات، أمين مخزن، ركن إمداد، مدير مكتب، مطّلع) تُجمع لمستخدم واحد،
     ويعدّلها المدير بعد تطبيقها على جدول الصلاحيات التفصيلي.
   - نطاق المستودعات لكل مستخدم: كل المستودعات أو مستودعات محددة (فرع/معسكر).
   - التطبيق: تصفية قوائم المستودعات في النماذج، منع الحفظ/الاعتماد خارج النطاق، وتصفية السجلات.
   - مدير النظام (role=admin) يتحكم في كل شيء ولا يخضع للنطاق. */
(function(){
'use strict';
var d=document;
function $(id){return d.getElementById(id);}
function E(s){return (typeof esc==='function')?esc(s):String(s==null?'':s);}
function T(m){if(typeof toast==='function')toast(m);}
function ic(n){return window.IMDAD_ICON?window.IMDAD_ICON(n):'';}
function st(){try{return me.state||null;}catch(e){return null;}}

var V='view',C='create',ED='edit',DL='delete',AP='approve',PR='print',EX='export';
function grant(pages,acts){var o={};pages.forEach(function(p){o[p]={};acts.forEach(function(a){o[p][a]=true;});});return o;}
function merge(){var out={};[].forEach.call(arguments,function(src){Object.keys(src).forEach(function(p){out[p]=out[p]||{};Object.keys(src[p]).forEach(function(a){if(src[p][a])out[p][a]=true;});});});return out;}
var BASIC=['dashboard','items','suppliers','units','stores','kitchens'];
var OPS=['receive','issue','transfer','returns'];
var ROLES={
  data_entry:{label:'مدخل بيانات',desc:'إدخال السندات والتغذية وسجل التشغيل في مستودعات نطاقه، دون اعتماد أو حذف',
    perms:merge(grant(BASIC,[V]),grant(OPS,[V,C]),grant(['feeding','kitchenLog'],[V,C,ED]),grant(['balances','pendingOrders'],[V]),grant(['documents'],[V]),grant(['stocktake'],[V,ED]))},
  storekeeper:{label:'أمين مخزن',desc:'الاستلام والصرف والتحويل والمرتجعات والجرد واعتمادها وطباعتها في مستودعات نطاقه',
    perms:merge(grant(BASIC,[V]),grant(OPS,[V,C,ED,AP,PR]),grant(['pendingOrders'],[V,AP,PR]),grant(['opening'],[V,C,PR]),grant(['balances'],[V,PR,EX]),
      grant(['stocktake'],[V,C,ED,PR]),grant(['reports'],[V,PR]),grant(['documents'],[V,PR,ED]))},
  supply_officer:{label:'ركن إمداد',desc:'التخطيط والتغذية والاستحقاقات وأوامر الصرف ومتابعة الأرصدة والتقارير',
    perms:merge(grant(BASIC,[V]),grant(['units','kitchens'],[V,C,ED]),grant(OPS,[V,PR]),grant(['issue'],[V,C,AP,PR]),grant(['pendingOrders'],[V,AP,PR]),
      grant(['feeding','kitchenLog'],[V,C,ED,PR,EX]),grant(['ratios'],[V,ED,PR,EX]),grant(['balances','reports'],[V,PR,EX]),grant(['stocktake'],[V,AP,PR]),grant(['documents'],[V,PR]))},
  office_manager:{label:'مدير مكتب',desc:'اطلاع شامل وطباعة وتصدير واعتماد، دون إدخال أو تعديل أو حذف',
    perms:merge(grant(BASIC,[V]),grant(OPS,[V,PR]),grant(['pendingOrders'],[V,AP,PR]),grant(['feeding','kitchenLog','ratios'],[V,PR,EX]),grant(['balances','reports','auditTrail','executiveCmd'],[V,PR,EX]),
      grant(['stocktake'],[V,AP,PR,EX]),grant(['activityIntel'],[V,EX]),grant(['sensitiveOps'],[V]),grant(['documents'],[V,PR]))},
  viewer:{label:'مطّلع',desc:'مشاهدة البيانات والأرصدة والتقارير فقط',
    perms:merge(grant(BASIC,[V]),grant(OPS,[V]),grant(['balances','reports','documents','stocktake'],[V]))}
};

function isAdmin(u){u=u||st();return !!(u&&u.role==='admin');}
function scopeOf(u){u=u||st();if(!u||isAdmin(u))return 'ALL';var s=u.warehouseScope;return Array.isArray(s)?s:'ALL';}
function canWh(wh,u){if(!wh)return true;var s=scopeOf(u);return s==='ALL'||s.indexOf(wh)>=0;}
function scopeLabel(u){var s=scopeOf(u);return s==='ALL'?'':(s.length?s.join('، '):'بدون مستودعات');}
function rolesLabel(u){return (u&&u.roles||[]).map(function(r){return ROLES[r]?ROLES[r].label:r;}).join('، ');}
function permsForRoles(list){return merge.apply(null,(list||[]).map(function(r){return ROLES[r]?ROLES[r].perms:{};}));}

/* ───── 1) تصفية قوائم المستودعات في النماذج ───── */
var WH_SELECTS=['rWh','isWh','trWhFrom','ruWh','rsWh','stkWh','deWh','opWh'];
function filterSelects(){
  if(scopeOf()==='ALL')return;
  WH_SELECTS.forEach(function(id){var s=$(id);if(!s||s.tagName!=='SELECT')return;var changed=false;
    [].slice.call(s.options).forEach(function(o){if(o.value&&!canWh(o.value)){o.remove();changed=true;}});
    if(changed){if(!s.value||!canWh(s.value)){var first=[].filter.call(s.options,function(o){return o.value;})[0];if(first)s.value=first.value;}
      if(![].some.call(s.options,function(o){return o.value;}))s.insertAdjacentHTML('beforeend','<option value="">— لا توجد مستودعات ضمن نطاقك —</option>');
      s.dispatchEvent(new Event('change',{bubbles:true}));}
  });
}
var pend=0;
new MutationObserver(function(){if(pend)return;pend=requestAnimationFrame(function(){pend=0;try{filterSelects();markUsers();}catch(e){}});}).observe(d.documentElement,{childList:true,subtree:true});

/* ───── 2) منع الحفظ خارج النطاق ───── */
var GUARDS=[['rcSave',['rWh']],['issSubmit',['isWh']],['trfSend',['trWhFrom']],['retSaveUnit',['ruWh']],['retSaveSupplier',['rsWh']]];
function blockMsg(wh){return '✖ المستودع «'+wh+'» خارج نطاق صلاحياتك — تواصل مع مدير النظام';}
function wrapGuards(){
  GUARDS.forEach(function(g){var orig=window[g[0]];if(typeof orig!=='function'||orig.__scope)return;
    var w=function(){for(var i=0;i<g[1].length;i++){var el=$(g[1][i]);if(el&&el.value&&!canWh(el.value)){T(blockMsg(el.value));return;}}return orig.apply(this,arguments);};
    w.__scope=1;window[g[0]]=w;});
  /* السجلات القديمة داخل الشاشات: تصفية حسب النطاق */
  [['rcHistPaint',function(){try{return RC;}catch(e){return null;}}],['issHistPaint',function(){try{return ISS;}catch(e){return null;}}]].forEach(function(p){
    var orig=window[p[0]];if(typeof orig!=='function'||orig.__scope)return;
    var w=function(){var S=p[1]();if(S&&Array.isArray(S.hist)&&scopeOf()!=='ALL')S.hist=S.hist.filter(function(r){return canWh(r.warehouse);});return orig.apply(this,arguments);};
    w.__scope=1;window[p[0]]=w;});
  /* حساب أرصدة الشاشة انتقل إلى stock-ledger.js: رصيد كل مستودع على حدة مع احترام النطاق */
  ['trfHist','retHist'].forEach(function(n){var orig=window[n];if(typeof orig!=='function'||orig.__scope)return;
    var w=function(){if(scopeOf()!=='ALL'&&typeof window.renderDocuments==='function'){try{DOCS_STATE.type=n==='trfHist'?'transfer':'ret';}catch(e){}window.curPage='documents';return renderPage();}return orig.apply(this,arguments);};
    w.__scope=1;window[n]=w;});
}
/* اعتماد المسودات والأوامر واستلام التحويلات من البطاقات: التحقق من المستودع المذكور في البطاقة */
d.addEventListener('click',function(e){
  if(scopeOf()==='ALL')return;
  var b=e.target.closest&&e.target.closest('[data-rv],[data-rj],[data-da],[data-dd],[data-appr],[data-approve],[data-del]');if(!b)return;
  var card=b.closest('.dcard');if(!card)return;
  var txt=card.textContent||'',wh='';
  if(b.hasAttribute('data-rv')||b.hasAttribute('data-rj')){var m=/←\s*([^\n]+?)\s*(?:$|\d|السبب)/.exec(txt);var chip=[].filter.call(card.querySelectorAll('.chip'),function(c){return c.textContent.indexOf('←')>=0;})[0];
    if(chip)wh=chip.textContent.split('←')[1].trim();else if(m)wh=m[1];}
  else{var names=(window._imdWhNames||[]).filter(function(n){return txt.indexOf(n)>=0;});if(names.length&&!names.some(function(n){return canWh(n);}))wh=names[0];}
  if(wh&&!canWh(wh)){e.preventDefault();e.stopImmediatePropagation();T(blockMsg(wh));}
},true);
async function scopedBalances(){
  var B;try{B=BAL;}catch(e){return;}if(!window.IMDAD_REPORTS||!Array.isArray(B.items))return;
  await IMDAD_REPORTS.load();var D=IMDAD_REPORTS.state.data,map={};
  D.moves.forEach(function(m){if(!m.active||!m.itemId)return;var k=m.itemId;
    if(canWh(m.wh)){if(m.type==='IN'||m.type==='RETURN_IN')map[k]=(map[k]||0)+m.baseQty;else if(m.type!=='OPENING')map[k]=(map[k]||0)-m.baseQty;}
    if(m.type==='TRANSFER'&&m.destWh&&canWh(m.destWh)&&m.status==='RECEIVED')map[k]=(map[k]||0)+m.baseQty;});
  B.items.forEach(function(it){it.qty=Math.round((map[it.id]||0)*1000)/1000;});
  try{balPaint();}catch(e){}
  var ch=$('balChips');if(ch&&!$('balScopeChip'))ch.insertAdjacentHTML('beforeend','<span class="chip chip-pend" id="balScopeChip">أرصدة نطاقك: '+E(scopeLabel())+'</span>');
}
async function cacheWhNames(){try{var s=await db.collection('warehouses').limit(500).get();window._imdWhNames=s.docs.map(function(x){return x.data().name;}).filter(Boolean).sort(function(a,b){return b.length-a.length;});}catch(e){}}

/* ───── 3) إدارة الأدوار والنطاق داخل نافذة صلاحيات المستخدم ───── */
function wrapUserModal(){
  var orig=window.openUserPermissions;if(typeof orig!=='function'||orig.__roles)return;
  var w=async function(id){var r=await orig.apply(this,arguments);try{await injectRoles(id);}catch(e){console.error(e);}return r;};
  w.__roles=1;window.openUserPermissions=w;
}
async function injectRoles(id){
  var grid=$('permGrid');if(!grid||$('acRoles'))return;
  var u=null;try{u=UAC.items.filter(function(x){return x.id===id;})[0];}catch(e){}if(!u)return;
  var whs=[];try{var s=await db.collection('warehouses').limit(500).get();whs=s.docs.map(function(x){return x.data();}).filter(function(w){return w.name;});}catch(e){}
  var roles=u.roles||[],scope=Array.isArray(u.warehouseScope)?u.warehouseScope:'ALL',adm=u.role==='admin';
  var box=d.createElement('div');box.className='panel';box.id='acRoles';box.style.margin='10px 0';
  box.innerHTML='<h3>'+ic('shield')+' الأدوار ونطاق المستودعات</h3>'+
   (adm?'<div class="note-box">هذا الحساب مدير نظام: يملك كل الصلاحيات وكل المستودعات. الأدوار والنطاق أدناه لا تنطبق عليه.</div>':'')+
   '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px">'+
    '<div><b style="display:block;margin-bottom:6px">الأدوار (يمكن اختيار أكثر من دور)</b>'+Object.keys(ROLES).map(function(k){
      return '<label style="display:flex;gap:8px;align-items:flex-start;padding:6px 0"><input type="checkbox" class="acRole" value="'+k+'"'+(roles.indexOf(k)>=0?' checked':'')+'><span><b>'+ROLES[k].label+'</b><br><small style="color:var(--ui-muted,#5b5e6b)">'+ROLES[k].desc+'</small></span></label>';}).join('')+
     '<button class="btn btn-o btn-sm" id="acApply" type="button" style="margin-top:6px">'+ic('check')+' تطبيق صلاحيات الأدوار على الجدول أدناه</button></div>'+
    '<div><b style="display:block;margin-bottom:6px">نطاق المستودعات (الفرع / المعسكر)</b>'+
     '<label style="display:flex;gap:8px;align-items:center;padding:4px 0"><input type="radio" name="acScope" value="ALL"'+(scope==='ALL'?' checked':'')+'> كل المستودعات</label>'+
     '<label style="display:flex;gap:8px;align-items:center;padding:4px 0"><input type="radio" name="acScope" value="LIST"'+(scope!=='ALL'?' checked':'')+'> مستودعات محددة فقط:</label>'+
     '<div id="acWhList" style="max-height:220px;overflow:auto;border:1px solid var(--ui-line,#e3e3e8);border-radius:10px;padding:6px 10px">'+
      (whs.length?whs.map(function(w){return '<label style="display:flex;gap:8px;align-items:center;padding:4px 0"><input type="checkbox" class="acWh" value="'+E(w.name)+'"'+(scope!=='ALL'&&scope.indexOf(w.name)>=0?' checked':'')+'> '+E((w.code?w.code+' — ':'')+w.name)+'</label>';}).join(''):'<div class="ld">لا توجد مستودعات</div>')+
     '</div><small style="display:block;margin-top:6px;color:var(--ui-muted,#5b5e6b)">يرى المستخدم ويُدخل ويعدّل ويعتمد مستندات هذه المستودعات فقط. في التحويل يُشترط أن يكون مستودع الإرسال ضمن نطاقه، والاستلام يتطلب أن يكون مستودع الوصول ضمن نطاقه.</small></div>'+
   '</div><div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:12px"><button class="btn btn-p" id="acSave" type="button">'+ic('save')+' حفظ الأدوار والنطاق والصلاحيات</button>'+
   '<span class="rc-meta" style="align-self:center">تسري التغييرات على المستخدم عند دخوله التالي.</span></div>';
  var anchor=grid.previousElementSibling&&grid.previousElementSibling.classList.contains('note-box')?grid.previousElementSibling:grid;
  anchor.parentNode.insertBefore(box,anchor);
  var syncList=function(){var all=box.querySelector('input[name=acScope][value=ALL]').checked;[].forEach.call(box.querySelectorAll('.acWh'),function(c){c.disabled=all;});$('acWhList').style.opacity=all?.5:1;};
  [].forEach.call(box.querySelectorAll('input[name=acScope]'),function(r){r.onchange=syncList;});syncList();
  $('acApply').onclick=function(){var sel=[].filter.call(box.querySelectorAll('.acRole'),function(c){return c.checked;}).map(function(c){return c.value;});
    if(!sel.length)return T('✖ اختر دورًا واحدًا على الأقل');var p=permsForRoles(sel);
    [].forEach.call(grid.querySelectorAll('input[data-page]'),function(c){c.checked=!!(p[c.dataset.page]&&p[c.dataset.page][c.dataset.action]);});
    T('✔ طُبّقت صلاحيات: '+sel.map(function(r){return ROLES[r].label;}).join(' + ')+' — يمكنك التعديل ثم الحفظ');};
  $('acSave').onclick=async function(){
    try{if(me.state&&me.state.id===id)return T('✖ لا يمكن تعديل أدوار حسابك الحالي من نفس الجلسة');}catch(e){}
    var sel=[].filter.call(box.querySelectorAll('.acRole'),function(c){return c.checked;}).map(function(c){return c.value;});
    var all=box.querySelector('input[name=acScope][value=ALL]').checked;
    var list=[].filter.call(box.querySelectorAll('.acWh'),function(c){return c.checked;}).map(function(c){return c.value;});
    if(!all&&!list.length)return T('✖ اختر مستودعًا واحدًا على الأقل أو «كل المستودعات»');
    var perms={};[].forEach.call(grid.querySelectorAll('input[data-page]'),function(c){perms[c.dataset.page]=perms[c.dataset.page]||{};perms[c.dataset.page][c.dataset.action]=c.checked;});
    var btn=this;btn.disabled=true;
    try{await db.collection('users').doc(id).update({roles:sel,warehouseScope:all?'ALL':list,permissions:perms,updatedAt:ST(),updatedBy:me.state?me.state.email:''});
      try{await auditWrite('USER_SCOPE_CHANGED','user_access','تغيير أدوار ونطاق مستخدم',{target:u.email||u.name||'',roles:sel,warehouseScope:all?'ALL':list,risk:'critical'});}catch(e){}
      u.roles=sel;u.warehouseScope=all?'ALL':list;u.permissions=perms;
      T('✔ حُفظت الأدوار ('+(sel.map(function(r){return ROLES[r].label;}).join('، ')||'بدون')+') والنطاق ('+(all?'كل المستودعات':list.join('، '))+')');
    }catch(e){T('✖ '+(e.code||e.message));}
    btn.disabled=false;};
}
/* إظهار الأدوار والنطاق في جدول المستخدمين */
function markUsers(){
  var t=$('permUsersTbl');if(!t)return;var items;try{items=UAC.items;}catch(e){return;}
  [].forEach.call(t.querySelectorAll('[data-openperm]'),function(b){var tr=b.closest('tr');if(!tr||tr.dataset.acMarked)return;
    var u=items.filter(function(x){return x.id===b.dataset.openperm;})[0];if(!u)return;tr.dataset.acMarked='1';
    var cell=tr.children[1];if(!cell)return;var rl=rolesLabel(u),sc=u.role==='admin'?'':(Array.isArray(u.warehouseScope)?u.warehouseScope.join('، '):'');
    if(rl)cell.insertAdjacentHTML('beforeend','<div style="margin-top:4px"><span class="chip chip-code">'+E(rl)+'</span></div>');
    if(sc)cell.insertAdjacentHTML('beforeend','<div style="margin-top:4px"><span class="chip chip-pend" title="نطاق المستودعات">'+ic('warehouse')+' '+E(sc)+'</span></div>');});
}

function install(){wrapGuards();wrapUserModal();cacheWhNames();}
/* بعد تنفيذ كل السكربتات (DOMContentLoaded) لا عند load: load قد يتأخر كثيرًا دون إنترنت بسبب الخطوط */
if(d.readyState!=='loading')install();else d.addEventListener('DOMContentLoaded',install);
window.IMDAD_ACCESS={roles:ROLES,canWh:canWh,scopeOf:scopeOf,scopeLabel:scopeLabel,permsForRoles:permsForRoles,isAdmin:isAdmin};
})();
