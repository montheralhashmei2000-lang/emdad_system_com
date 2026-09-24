/* IMDAD Reports Center v1 — مركز التقارير التفصيلية
   تسعة تقارير بفلاتر مخصصة لكل تقرير + بحث وفرز + ملخص رقمي + طباعة وتصدير Excel.
   يعتمد على: db, esc, nf, toast, renderPage, renderReports (لوحة المؤشرات)، IMDAD_EXPORT (forms-ux.js). */
(function(){
'use strict';
var d=document;
function $(id){return d.getElementById(id);}
function ic(n){return window.IMDAD_ICON?window.IMDAD_ICON(n):'';}
function num(v){var x=+v;return isFinite(x)?x:0;}
function fmt(v){var x=num(v);return (Math.round(x*100)/100).toLocaleString('ar-EG');}
function today(){return new Date().toISOString().slice(0,10);}
function daysAgo(n){var t=new Date();t.setDate(t.getDate()-n);return t.toISOString().slice(0,10);}
function dOf(r){if(r.date)return String(r.date).slice(0,10);if(r.strengthDate)return String(r.strengthDate).slice(0,10);
  var s=r.createdAt&&r.createdAt.seconds;return s?new Date(s*1000).toISOString().slice(0,10):'';}
var LS_KEY='imdad.reports.last';

var REPORTS=[
  {id:'moves',   icon:'repeat',    name:'حركة المخزون اليومية',   desc:'كل الحركات حسب الفترة والمستودع والنوع'},
  {id:'unitAcc', icon:'file',      name:'كشف حساب وحدة مستفيدة',  desc:'المصروف والمرتجع لوحدة وفروعها'},
  {id:'stock',   icon:'package',   name:'تقرير أرصدة المخزون',     desc:'الرصيد وحالة كل صنف، إجمالي أو لكل مستودع'},
  {id:'consume', icon:'chart',     name:'تحليل الاستهلاك',          desc:'المصروف مجمّعًا حسب الصنف أو الوحدة أو المستودع'},
  {id:'strength',icon:'users',     name:'تقرير حصر القوة',          desc:'القوة الأساسية والزيادة لكل معسكر ووحدة'},
  {id:'kitchen', icon:'utensils',  name:'أداء المطابخ والأفران',     desc:'الاستهلاك الفعلي مقابل المتوقع لكل وجبة'},
  {id:'supplier',icon:'truck',     name:'ملخص توريدات الموردين',    desc:'تفصيلي حسب السند أو مجمّع بالكميات'},
  {id:'returns', icon:'undo',      name:'تقرير المرتجعات',           desc:'المرتجع من الوحدات وإلى الموردين'},
  {id:'daily',   icon:'clipboard', name:'تقرير العمل اليومي',        desc:'ملخص وحركات يوم واحد'}
];
var TYPE_LBL={IN:'وارد',OUT:'صادر',TRANSFER:'تحويل مخزني',RETURN_IN:'مرتجع من وحدة',RETURN_OUT:'مرتجع لمورد',OPENING:'رصيد افتتاحي'};
var MEAL_LBL={BREAKFAST:'فطور',LUNCH:'غداء',DINNER:'عشاء',BREAD:'خبز (أفران)'};
var STATUS_LBL={COMPLETED:'مكتمل',DRAFT:'مسودة',ORDER:'أمر معلق',RECEIVED:'مستلم',IN_TRANSIT:'قيد النقل',PENDING:'معلق',CANCELLED:'ملغى'};
var INACTIVE={DRAFT:1,ORDER:1,CANCELLED:1};

var RC=window.RC_STATE=window.RC_STATE||{idx:0,data:null,f:{},q:'',sort:null,rows:[],cols:[]};
try{var li=+localStorage.getItem(LS_KEY);if(li>=0&&li<REPORTS.length)RC.idx=li;}catch(e){}

/* ───── تحميل البيانات ───── */
async function load(col,limit){try{var s=await db.collection(col).limit(limit||5000).get();return s.docs.map(function(x){var o=x.data()||{};o.id=x.id;return o;});}catch(e){return [];}}
async function loadAll(){
  var n=['items','units','warehouses','categories','suppliers','facilities','receipts','issues','transfers','returns','openingBalances','strengths','kitchenLogs'];
  var res=await Promise.all(n.map(function(c){return load(c);}));var o={};n.forEach(function(c,i){o[c]=res[i];});
  o.itemById={};o.items.forEach(function(it){o.itemById[it.id]=it;});
  o.unitById={};o.units.forEach(function(u){o.unitById[u.id]=u;});
  o.moves=buildMoves(o);
  var AC=window.IMDAD_ACCESS;if(AC&&AC.scopeOf()!=='ALL'){o.moves=o.moves.filter(function(m){return AC.canWh(m.wh)||(m.destWh&&AC.canWh(m.destWh));});o.warehouses=o.warehouses.filter(function(w){return AC.canWh(w.name);});o.scoped=true;}
  RC.data=o;RC.loadedAt=new Date();
}
function buildMoves(o){
  var m=[];
  function base(r,it){return num(r.baseQty!=null?r.baseQty:num(r.qty)*num(r.factor||1));}
  function push(r,type,wh,party,extra){var it=o.itemById[r.itemId]||{};
    m.push(Object.assign({date:dOf(r),type:type,typeLbl:TYPE_LBL[type],ref:r.refNo||'',itemId:r.itemId||'',itemCode:r.itemCode||it.code||'',itemName:r.itemName||it.name||'',
      qty:num(r.qty),unit:r.unitName||it.baseUnit||'',baseQty:base(r,it),baseUnit:it.baseUnit||r.unitName||'',wh:wh||'',party:party||'',
      status:r.status||'',statusLbl:STATUS_LBL[r.status]||r.status||'',notes:r.notes||'',active:!INACTIVE[r.status]},extra||{}));}
  o.receipts.forEach(function(r){push(r,'IN',r.warehouse,r.supplier);});
  o.issues.forEach(function(r){push(r,'OUT',r.warehouse,r.beneficiaryUnitName||r.recipientDisplay,{unitId:r.beneficiaryUnitId||r.unitId||'',facilityId:r.facilityId||''});});
  o.transfers.forEach(function(r){push(r,'TRANSFER',r.warehouse,'إلى: '+(r.destWarehouse||'—'),{destWh:r.destWarehouse||''});});
  o.returns.forEach(function(r){push(r,r.type==='TO_SUPPLIER'?'RETURN_OUT':'RETURN_IN',r.warehouse,r.party,{condition:r.condition||''});});
  o.openingBalances.forEach(function(r){push(r,'OPENING','',r.setBy||'',{});});
  m.sort(function(a,b){return a.date<b.date?1:a.date>b.date?-1:0;});
  return m;
}

/* ───── الفلاتر ───── */
function whOpts(){return [['','الكل']].concat(RC.data.warehouses.map(function(w){return [w.name,(w.code?w.code+' — ':'')+w.name];}));}
function unitLabel(u){return ((u.code?u.code+' - ':'')+(u.name||'')).trim();}
function FILTERS(id){
  var D=RC.data;
  var typeOpts=[['','الكل']].concat(Object.keys(TYPE_LBL).map(function(k){return [k,TYPE_LBL[k]];}));
  switch(id){
    case 'moves':return [{k:'range',t:'range',def:true,from:daysAgo(30)},{k:'wh',t:'select',l:'المستودع',o:whOpts},{k:'type',t:'select',l:'نوع الحركة',o:typeOpts}];
    case 'unitAcc':return [{k:'parent',t:'select',l:'الوحدة الرئيسية',o:[['','— اختر —']].concat(D.units.filter(function(u){return !u.parentId;}).map(function(u){return [u.id,unitLabel(u)];}))},
      {k:'child',t:'select',l:'الوحدة الفرعية',o:function(f){return [['','الكل (مع الفروع)']].concat(D.units.filter(function(u){return f.parent&&u.parentId===f.parent;}).map(function(u){return [u.id,unitLabel(u)];}));}},
      {k:'range',t:'range',from:daysAgo(30)}];
    case 'stock':return [{k:'wh',t:'select',l:'المستودع',o:whOpts},{k:'cat',t:'select',l:'التصنيف',o:[['','الكل']].concat(D.categories.map(function(c){return [c.id,c.name];}))},
      {k:'status',t:'select',l:'حالة الرصيد',o:[['','الكل'],['OK','طبيعي'],['LOW','منخفض'],['EMPTY','نفد']]}];
    case 'consume':return [{k:'range',t:'range',def:true,from:daysAgo(30)},{k:'group',t:'select',l:'تجميع حسب',o:[['item','الصنف'],['unit','الوحدة المستفيدة'],['wh','المستودع']]}];
    case 'strength':return [{k:'range',t:'range',from:daysAgo(30)},{k:'camp',t:'select',l:'المعسكر',o:[['','الكل']].concat(D.units.filter(function(u){return u.isCamp||u.type==='camp';}).map(function(u){return [u.id,unitLabel(u)];}))},
      {k:'mode',t:'select',l:'مستوى العرض',o:[['','الكل'],['camp','إجمالي المعسكر'],['detail','الوحدات الفرعية']]}];
    case 'kitchen':return [{k:'range',t:'range',from:daysAgo(30)},{k:'fac',t:'select',l:'المنشأة',o:[['','الكل']].concat(D.facilities.map(function(x){return [x.id,x.name];}))},
      {k:'meal',t:'select',l:'الوجبة',o:[['','الكل']].concat(Object.keys(MEAL_LBL).map(function(k){return [k,MEAL_LBL[k]];}))}];
    case 'supplier':return [{k:'range',t:'range',from:daysAgo(90)},{k:'sup',t:'select',l:'المورد',o:[['','الكل']].concat(D.suppliers.map(function(s){return [s.name,s.name];}))},
      {k:'view',t:'select',l:'نوع العرض',o:[['detail','تفصيلي (حسب السند)'],['summary','مجمّع (إجمالي الكميات)']]}];
    case 'returns':return [{k:'range',t:'range',from:daysAgo(90)},{k:'type',t:'select',l:'نوع المرتجع',o:[['','الكل'],['RETURN_OUT','إرجاع إلى مورد'],['RETURN_IN','مرتجع من وحدة']]},{k:'wh',t:'select',l:'المستودع',o:whOpts}];
    case 'daily':return [{k:'day',t:'date',l:'تاريخ اليوم'},{k:'wh',t:'select',l:'المستودع',o:whOpts},{k:'type',t:'select',l:'نوع الحركة',o:typeOpts}];
  }
  return [];
}
function fState(){var id=REPORTS[RC.idx].id;if(!RC.f[id]){var s={};FILTERS(id).forEach(function(x){
    if(x.t==='range'){s.dateOn=!!x.def;s.from=x.from||daysAgo(30);s.to=today();}
    else if(x.t==='date')s[x.k]=today();
    else{var o=typeof x.o==='function'?x.o(s):x.o;s[x.k]=o.length?o[0][0]:'';}
  });RC.f[id]=s;}return RC.f[id];}
function inRange(date,f){if(!f.dateOn)return true;if(!date)return false;return (!f.from||date>=f.from)&&(!f.to||date<=f.to);}

/* ───── التقارير ───── */
function stockStatus(bal,min){return bal<=0?'EMPTY':(min>0&&bal<=min?'LOW':'OK');}
var ST_CHIP={OK:'<span class="chip chip-ok">طبيعي</span>',LOW:'<span class="chip chip-pend">منخفض</span>',EMPTY:'<span class="chip chip-err">نفد</span>'};
function C(k,t,o){return Object.assign({k:k,t:t},o||{});}

var RUN={
  moves:function(f){var rows=RC.data.moves.filter(function(m){return inRange(m.date,f)&&(!f.wh||m.wh===f.wh||m.destWh===f.wh)&&(!f.type||m.type===f.type);});
    return {cols:[C('date','التاريخ'),C('typeLbl','النوع'),C('ref','رقم السند'),C('itemCode','الكود'),C('itemName','الصنف'),C('qty','الكمية',{num:1,nosum:1}),C('unit','الوحدة'),C('wh','المستودع'),C('party','الجهة'),C('statusLbl','الحالة')],
      rows:rows,summary:countBy(rows,'typeLbl')};},

  unitAcc:function(f){
    var D=RC.data,root=f.child||f.parent;if(!root)return {msg:'اختر الوحدة الرئيسية لعرض كشف الحساب.'};
    var ids={};(function add(id){ids[id]=1;D.units.forEach(function(u){if(u.parentId===id&&!ids[u.id])add(u.id);});})(root);
    var names={};Object.keys(ids).forEach(function(id){var u=D.unitById[id];if(u&&u.name)names[u.name]=1;});
    var rows=D.moves.filter(function(m){if(!inRange(m.date,f))return false;
      return (m.type==='OUT'&&(ids[m.unitId]||names[m.party]))||(m.type==='RETURN_IN'&&names[m.party]);}).map(function(m){
      return Object.assign({},m,{out:m.type==='OUT'?m.qty:0,back:m.type==='RETURN_IN'?m.qty:0,outB:m.type==='OUT'?m.baseQty:0,backB:m.type==='RETURN_IN'?m.baseQty:0});});
    var byItem={};rows.forEach(function(r){var k=r.itemId||r.itemName;var x=byItem[k]=byItem[k]||{n:r.itemName,u:r.baseUnit,net:0};x.net+=r.outB-r.backB;});
    var u=D.unitById[root];
    return {cols:[C('date','التاريخ'),C('typeLbl','الحركة'),C('ref','رقم السند'),C('party','الوحدة'),C('itemName','الصنف'),C('out','المصروف',{num:1,nosum:1}),C('back','المرتجع',{num:1,nosum:1}),C('unit','الوحدة'),C('wh','المستودع'),C('notes','ملاحظات')],
      rows:rows,title:u?unitLabel(u):'',
      summary:[['عدد الحركات',rows.length],['أصناف مستلمة',Object.keys(byItem).length],['وحدات مشمولة',Object.keys(ids).length]]};},

  stock:function(f){
    var D=RC.data,wbal=null;
    var whSet=f.wh?[f.wh]:(D.scoped?D.warehouses.map(function(w){return w.name;}):null);if(whSet){wbal={};D.moves.forEach(function(m){if(!m.active)return;var k=m.itemId;if(!k)return;
      if(whSet.indexOf(m.wh)>=0){if(m.type==='IN'||m.type==='RETURN_IN')wbal[k]=(wbal[k]||0)+m.baseQty;else if(m.type!=='OPENING')wbal[k]=(wbal[k]||0)-m.baseQty;}
      if(m.type==='TRANSFER'&&whSet.indexOf(m.destWh)>=0&&m.status==='RECEIVED')wbal[k]=(wbal[k]||0)+m.baseQty;});}
    var cats={};D.categories.forEach(function(c){cats[c.id]=c.name;});
    var rows=D.items.filter(function(it){return !f.cat||it.categoryId===f.cat;}).map(function(it){
      var bal=wbal?(wbal[it.id]||0):num(it.qty),min=num(it.min),st=stockStatus(bal,min);
      return {code:it.code||'',name:it.name||'',cat:it.categoryName||cats[it.categoryId]||'',min:min,bal:bal,unit:it.baseUnit||'',st:st,stHtml:ST_CHIP[st],stLbl:{OK:'طبيعي',LOW:'منخفض',EMPTY:'نفد'}[st]};
    }).filter(function(r){return !f.status||r.st===f.status;});
    rows.sort(function(a,b){return String(a.code).localeCompare(String(b.code),'ar',{numeric:true});});
    return {cols:[C('code','الكود'),C('name','الصنف'),C('cat','التصنيف'),C('min','حد التنبيه',{num:1,nosum:1}),C('bal','الرصيد',{num:1,nosum:1}),C('unit','الوحدة'),C('stLbl','الحالة',{html:'stHtml'})],
      rows:rows,note:whSet?'رصيد المستودع محسوب من الحركات المعتمدة (الوارد والمرتجع من الوحدات والتحويلات المستلمة ناقص المنصرف والتحويلات الصادرة). الأرصدة الافتتاحية غير مرتبطة بمستودع فلا تدخل هنا.':'',
      summary:[['الأصناف',rows.length],['منخفض',rows.filter(function(r){return r.st==='LOW';}).length],['نفد',rows.filter(function(r){return r.st==='EMPTY';}).length]]};},

  consume:function(f){
    var src=RC.data.moves.filter(function(m){return m.type==='OUT'&&m.active&&inRange(m.date,f);});
    var g={},total=0;
    src.forEach(function(m){var key,label,unit='';
      if(f.group==='unit'){key=m.party||'—';label=key;}else if(f.group==='wh'){key=m.wh||'—';label=key;}else{key=m.itemId||m.itemName;label=(m.itemCode?m.itemCode+' - ':'')+m.itemName;unit=m.baseUnit;}
      var x=g[key]=g[key]||{label:label,unit:unit,qty:0,refs:{},items:{}};x.qty+=m.baseQty;x.refs[m.ref]=1;x.items[m.itemId]=1;total+=m.baseQty;});
    var rows=Object.keys(g).map(function(k){var x=g[k];return {label:x.label,qty:x.qty,unit:x.unit,refs:Object.keys(x.refs).length,items:Object.keys(x.items).length,share:total?Math.round(x.qty/total*1000)/10:0};});
    rows.sort(function(a,b){return b.qty-a.qty;});
    var cols=[C('label',{unit:'الوحدة المستفيدة',wh:'المستودع'}[f.group]||'الصنف')];
    if(f.group==='item')cols.push(C('qty','الكمية المصروفة',{num:1,nosum:1}),C('unit','وحدة الأساس'),C('refs','عدد السندات',{num:1,nosum:1}),C('share','النسبة %',{num:1,nosum:1}));
    else cols.push(C('items','عدد الأصناف',{num:1,nosum:1}),C('refs','عدد السندات',{num:1}),C('share','حصة الكمية %',{num:1,nosum:1}));
    return {cols:cols,rows:rows,summary:[['سطور الصرف',src.length],['المجموعات',rows.length]]};},

  strength:function(f){
    var rows=RC.data.strengths.filter(function(s){return inRange(String(s.strengthDate||'').slice(0,10),f)&&(!f.camp||s.campId===f.camp)&&(!f.mode||s.mode===f.mode);}).map(function(s){
      return {date:String(s.strengthDate||'').slice(0,10),camp:s.campName||'',unit:s.mode==='camp'?'— إجمالي المعسكر —':(s.unitName||''),mode:s.mode==='camp'?'إجمالي':'تفصيلي',
        base:num(s.soldierCount),pct:num(s.pct),inc:num(s.officerCount),total:num(s.total||(num(s.soldierCount)+num(s.officerCount)))};});
    rows.sort(function(a,b){return a.date<b.date?1:a.date>b.date?-1:String(a.camp).localeCompare(b.camp,'ar');});
    var last={};rows.forEach(function(r){if(r.mode==='إجمالي'||!last[r.camp+'|'+r.date])last[r.camp+'|'+r.date]=r.total;});
    return {cols:[C('date','تاريخ الحصر'),C('camp','المعسكر'),C('unit','الوحدة'),C('mode','المستوى'),C('base','القوة الأساسية',{num:1}),C('pct','الزيادة %',{num:1,nosum:1}),C('inc','الزيادة',{num:1}),C('total','الإجمالي',{num:1})],
      rows:rows,summary:[['سجلات الحصر',rows.length],['المعسكرات',Object.keys(countMap(rows,'camp')).length],['أيام الحصر',Object.keys(countMap(rows,'date')).length]]};},

  kitchen:function(f){
    var g={};RC.data.kitchenLogs.forEach(function(r){var date=dOf(r);if(!inRange(date,f)||(f.fac&&r.facilityId!==f.fac)||(f.meal&&r.mealType!==f.meal))return;
      var k=date+'|'+r.facilityId+'|'+r.mealType;var x=g[k]=g[k]||{date:date,fac:r.facilityName||'',meal:MEAL_LBL[r.mealType]||r.mealType||'',strength:num(r.strength),lines:0,actual:0,expected:0};
      x.lines++;x.actual+=num(r.baseQty);x.expected+=num(r.expectedBase);});
    var rows=Object.keys(g).map(function(k){var x=g[k];x.variance=x.actual-x.expected;x.vpct=x.expected?Math.round(x.variance/x.expected*1000)/10:0;
      x.flag=!x.expected?'—':(Math.abs(x.vpct)<=10?'ضمن الحد':(x.vpct>0?'زيادة':'نقص'));x.flagHtml=!x.expected?'—':'<span class="chip '+(Math.abs(x.vpct)<=10?'chip-ok':'chip-pend')+'">'+x.flag+'</span>';return x;});
    rows.sort(function(a,b){return a.date<b.date?1:a.date>b.date?-1:0;});
    return {cols:[C('date','التاريخ'),C('fac','المنشأة'),C('meal','الوجبة'),C('strength','القوة',{num:1,nosum:1}),C('lines','عدد الأصناف',{num:1}),C('actual','الفعلي (أساس)',{num:1,nosum:1}),C('expected','المتوقع (أساس)',{num:1,nosum:1}),C('variance','الفرق',{num:1,nosum:1}),C('vpct','الفرق %',{num:1,nosum:1}),C('flag','التقييم',{html:'flagHtml'})],
      rows:rows,summary:[['وجبات مسجلة',rows.length],['تجاوز ±10%',rows.filter(function(r){return r.expected&&Math.abs(r.vpct)>10;}).length]],
      note:'الكميات بوحدة الأساس لكل صنف؛ المتوقع محسوب من نسب الاستحقاق × القوة.'};},

  supplier:function(f){
    var src=RC.data.moves.filter(function(m){return m.type==='IN'&&m.active&&inRange(m.date,f)&&(!f.sup||m.party===f.sup);});
    if(f.view==='summary'){var g={};src.forEach(function(m){var k=m.party+'|'+(m.itemId||m.itemName);var x=g[k]=g[k]||{sup:m.party||'—',item:m.itemName,unit:m.baseUnit,qty:0,refs:{}};x.qty+=m.baseQty;x.refs[m.ref]=1;});
      var rows=Object.keys(g).map(function(k){var x=g[k];return {sup:x.sup,item:x.item,qty:x.qty,unit:x.unit,refs:Object.keys(x.refs).length};});
      rows.sort(function(a,b){return String(a.sup).localeCompare(b.sup,'ar')||b.qty-a.qty;});
      return {cols:[C('sup','المورد'),C('item','الصنف'),C('qty','إجمالي الكمية',{num:1,nosum:1}),C('unit','وحدة الأساس'),C('refs','عدد السندات',{num:1})],rows:rows,
        summary:[['الموردون',Object.keys(countMap(rows,'sup')).length],['الأصناف',rows.length]]};}
    return {cols:[C('date','التاريخ'),C('ref','رقم السند'),C('party','المورد'),C('wh','المستودع'),C('itemName','الصنف'),C('qty','الكمية',{num:1,nosum:1}),C('unit','الوحدة'),C('statusLbl','الحالة')],rows:src,
      summary:[['سطور التوريد',src.length],['السندات',Object.keys(countMap(src,'ref')).length]]};},

  returns:function(f){
    var rows=RC.data.moves.filter(function(m){return (m.type==='RETURN_IN'||m.type==='RETURN_OUT')&&inRange(m.date,f)&&(!f.type||m.type===f.type)&&(!f.wh||m.wh===f.wh);});
    return {cols:[C('date','التاريخ'),C('typeLbl','النوع'),C('ref','رقم السند'),C('party','الجهة'),C('wh','المستودع'),C('itemName','الصنف'),C('qty','الكمية',{num:1,nosum:1}),C('unit','الوحدة'),C('condition','الحالة'),C('notes','ملاحظات')],
      rows:rows,summary:countBy(rows,'typeLbl')};},

  daily:function(f){
    var D=RC.data,day=f.day||today();
    var rows=D.moves.filter(function(m){return m.date===day&&(!f.wh||m.wh===f.wh||m.destWh===f.wh)&&(!f.type||m.type===f.type);});
    var meals={};D.kitchenLogs.forEach(function(r){if(dOf(r)===day)meals[r.facilityId+'|'+r.mealType]=1;});
    var str=D.strengths.filter(function(s){return String(s.strengthDate||'').slice(0,10)===day;}).length;
    return {cols:[C('typeLbl','النوع'),C('ref','رقم السند'),C('itemName','الصنف'),C('qty','الكمية',{num:1,nosum:1}),C('unit','الوحدة'),C('wh','المستودع'),C('party','الجهة'),C('statusLbl','الحالة'),C('notes','ملاحظات')],
      rows:rows,title:day,summary:countBy(rows,'typeLbl').concat([['وجبات مسجلة',Object.keys(meals).length],['سجلات حصر القوة',str]])};}
};
function countMap(rows,k){var o={};rows.forEach(function(r){o[r[k]]=(o[r[k]]||0)+1;});return o;}
function countBy(rows,k){var o=countMap(rows,k);return [['إجمالي السطور',rows.length]].concat(Object.keys(o).map(function(x){return [x,o[x]];}));}

/* ───── الواجهة ───── */
function css(){if($('rcStyle'))return;var s=d.createElement('style');s.id='rcStyle';s.textContent=
 '.rc-wrap{display:grid;grid-template-columns:280px minmax(0,1fr);gap:16px;align-items:start}'+
 '.rc-nav{position:sticky;top:70px;background:var(--ui-surface,#fff);border:1px solid var(--ui-line,#e3e3e8);border-radius:12px;padding:8px;display:flex;flex-direction:column;gap:2px}'+
 '.rc-nav button{display:flex;gap:10px;align-items:flex-start;text-align:right;width:100%;border:0;background:transparent;padding:9px 10px;border-radius:10px;cursor:pointer;color:var(--ui-text,#202123);font:inherit}'+
 '.rc-nav button:hover{background:var(--ui-hover,#f2f2f5)}.rc-nav button.on{background:var(--ui-accent-soft,#e6f4f2);color:var(--ui-accent-hover,#115e59)}'+
 '.rc-nav .ic{margin-top:3px;color:var(--ui-accent,#0f766e)}.rc-nav b{display:block;font-weight:600;font-size:13.5px}.rc-nav small{display:block;color:var(--ui-muted,#5b5e6b);font-size:11.5px;line-height:1.5}'+
 '.rc-filters{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:10px 12px;align-items:end}'+
 '.rc-filters label{display:block;font-size:12px;font-weight:600;color:var(--ui-text-2,#343541);margin-bottom:4px}'+
 '.rc-range{grid-column:1/-1;display:flex;flex-wrap:wrap;gap:8px 12px;align-items:end}.rc-range>div{min-width:150px}'+
 '.rc-check{display:flex!important;align-items:center;gap:6px;font-size:13px!important;margin:0 0 10px!important;cursor:pointer}'+
 '.rc-actions{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-top:14px}.rc-actions .rc-q{margin-inline-start:auto;min-width:200px;max-width:280px}'+
 '.rc-head{display:flex;flex-wrap:wrap;align-items:center;gap:8px;justify-content:space-between;margin-bottom:10px}.rc-head h3{margin:0}'+
 '#rcTbl th[data-k]{cursor:pointer;user-select:none}#rcTbl th[data-k]:hover{color:var(--ui-text,#202123)}#rcTbl .rc-sum td{font-weight:700;background:var(--ui-accent-soft,#e6f4f2)}'+
 '.rc-empty{padding:28px;text-align:center;color:var(--ui-muted,#5b5e6b)}.rc-meta{font-size:12px;color:var(--ui-muted,#5b5e6b)}'+
 '@media (max-width:900px){.rc-wrap{grid-template-columns:1fr}.rc-nav{position:static;flex-direction:row;overflow-x:auto;padding:6px}.rc-nav button{flex:none;width:auto;white-space:nowrap}.rc-nav small{display:none}.rc-actions .rc-q{margin-inline-start:0;max-width:none;flex:1}}';
 d.head.appendChild(s);}

async function renderReportCenter(){
  css();
  $('main').innerHTML='<div class="page-title">'+ic('chart')+' مركز التقارير</div><div class="page-sub">تقارير تفصيلية بفلاتر مخصصة لكل تقرير، مع الطباعة والتصدير إلى Excel</div><div class="ld">جارٍ تحميل البيانات…</div>';
  await loadAll();
  if(window.curPage!=='reports')return;
  $('main').innerHTML=
   '<div class="rc-head"><div><div class="page-title">'+ic('chart')+' مركز التقارير</div><div class="page-sub" style="margin:0">تقارير تفصيلية بفلاتر مخصصة لكل تقرير، مع الطباعة والتصدير إلى Excel</div></div>'+
   '<div style="display:flex;gap:8px;flex-wrap:wrap"><button class="btn btn-o btn-sm" id="rcRefresh" type="button">'+ic('refresh')+' تحديث البيانات</button>'+
   '<button class="btn btn-o btn-sm" id="rcOverview" type="button">'+ic('trending')+' لوحة المؤشرات</button></div></div>'+
   '<div class="rc-wrap"><nav class="rc-nav" id="rcNav" aria-label="قائمة التقارير">'+REPORTS.map(function(r,i){
      return '<button type="button" data-i="'+i+'"'+(i===RC.idx?' class="on" aria-current="true"':'')+'>'+ic(r.icon)+'<span><b>'+esc(r.name)+'</b><small>'+esc(r.desc)+'</small></span></button>';}).join('')+'</nav>'+
   '<div style="min-width:0"><div class="panel"><div class="rc-head"><h3 id="rcTitle"></h3><span class="rc-meta" id="rcMeta"></span></div><div class="rc-filters" id="rcFilters"></div>'+
   '<div class="rc-actions"><button class="btn btn-p" id="rcRun" type="button">'+ic('search')+' عرض التقرير</button>'+
   '<button class="btn btn-o" id="rcPrint" type="button">'+ic('printer')+' طباعة</button>'+
   '<button class="btn btn-o" id="rcXlsx" type="button">'+ic('download')+' تصدير Excel</button>'+
   '<button class="btn btn-o btn-sm" id="rcReset" type="button">'+ic('eraser')+' إعادة تعيين</button>'+
   '<input class="fld rc-q" id="rcQ" placeholder="بحث داخل النتائج…" aria-label="بحث داخل النتائج"></div></div>'+
   '<div class="chips-row" id="rcChips"></div><div id="rcNote"></div><div class="twrap"><table class="u" id="rcTbl"></table></div></div></div>';
  $('rcNav').onclick=function(e){var b=e.target.closest('button[data-i]');if(!b)return;selectReport(+b.dataset.i);};
  $('rcRefresh').onclick=async function(){this.disabled=true;await loadAll();this.disabled=false;paintFilters();run();toast('✔ تم تحديث البيانات');};
  $('rcOverview').onclick=function(){if(typeof window.renderReports==='function')window.renderReports();};
  $('rcRun').onclick=run;
  $('rcReset').onclick=function(){delete RC.f[REPORTS[RC.idx].id];RC.q='';$('rcQ').value='';paintFilters();run();};
  $('rcQ').oninput=function(){RC.q=this.value.trim();paintTable();};
  $('rcPrint').onclick=doPrint;$('rcXlsx').onclick=doXlsx;
  selectReport(RC.idx);
}
function selectReport(i){
  RC.idx=i;RC.sort=null;RC.q='';if($('rcQ'))$('rcQ').value='';try{localStorage.setItem(LS_KEY,String(i));}catch(e){}
  [].forEach.call($('rcNav').querySelectorAll('button'),function(b){var on=+b.dataset.i===i;b.classList.toggle('on',on);if(on)b.setAttribute('aria-current','true');else b.removeAttribute('aria-current');});
  $('rcTitle').innerHTML=ic(REPORTS[i].icon)+' '+esc(REPORTS[i].name);
  paintFilters();run();
}
function paintFilters(){
  var f=fState(),id=REPORTS[RC.idx].id,h='';
  FILTERS(id).forEach(function(x){
    if(x.t==='range')h+='<div class="rc-range"><label class="rc-check"><input type="checkbox" data-f="dateOn"'+(f.dateOn?' checked':'')+'> تحديد فترة</label>'+
      '<div><label for="rcFrom">من تاريخ</label><input class="fld" type="date" id="rcFrom" data-f="from" value="'+esc(f.from)+'"'+(f.dateOn?'':' disabled')+'></div>'+
      '<div><label for="rcTo">إلى تاريخ</label><input class="fld" type="date" id="rcTo" data-f="to" value="'+esc(f.to)+'"'+(f.dateOn?'':' disabled')+'></div></div>';
    else if(x.t==='date')h+='<div><label for="rc_'+x.k+'">'+esc(x.l)+'</label><input class="fld" type="date" id="rc_'+x.k+'" data-f="'+x.k+'" value="'+esc(f[x.k])+'"></div>';
    else{var o=typeof x.o==='function'?x.o(f):x.o;if(!o.some(function(p){return p[0]===f[x.k];}))f[x.k]=o.length?o[0][0]:'';
      h+='<div><label for="rc_'+x.k+'">'+esc(x.l)+'</label><select class="fld" id="rc_'+x.k+'" data-f="'+x.k+'">'+o.map(function(p){return '<option value="'+esc(p[0])+'"'+(p[0]===f[x.k]?' selected':'')+'>'+esc(p[1])+'</option>';}).join('')+'</select></div>';}
  });
  var host=$('rcFilters');host.innerHTML=h;
  [].forEach.call(host.querySelectorAll('[data-f]'),function(el){el.onchange=function(){
    var k=el.dataset.f;f[k]=el.type==='checkbox'?el.checked:el.value;
    if(k==='dateOn'||k==='parent'){paintFilters();}
    if(k!=='from'&&k!=='to')run();
  };});
}
function run(){
  var rep=REPORTS[RC.idx],f=fState(),out;
  try{out=RUN[rep.id](f)||{};}catch(e){console.error(e);out={msg:'تعذر إنشاء التقرير: '+e.message};}
  RC.out=out;RC.sort=RC.sort&&RC.sort.id===rep.id?RC.sort:null;
  var parts=[];if(f.dateOn&&f.from)parts.push('من '+f.from+' إلى '+f.to);
  FILTERS(rep.id).forEach(function(x){if(x.t!=='select')return;var o=typeof x.o==='function'?x.o(f):x.o;var p=o.find(function(q){return q[0]===f[x.k];});if(p&&p[0])parts.push(x.l+': '+p[1]);});
  if(rep.id==='daily')parts.unshift('اليوم: '+(f.day||today()));
  RC.filterText=parts.join(' · ');
  $('rcMeta').textContent=RC.filterText||'بدون فلاتر';
  $('rcChips').innerHTML=(out.summary||[]).map(function(s,i){return '<span class="chip '+(i?'chip-code':'chip-ok')+'">'+esc(s[0])+': '+nf(s[1])+'</span>';}).join('');
  $('rcNote').innerHTML=out.note?'<div class="note-box" style="margin-bottom:10px">'+esc(out.note)+'</div>':'';
  paintTable();
}
function viewRows(){
  var out=RC.out||{},rows=(out.rows||[]).slice(),q=(RC.q||'').toLowerCase();
  if(q)rows=rows.filter(function(r){return out.cols.some(function(c){return String(r[c.k]==null?'':r[c.k]).toLowerCase().indexOf(q)>=0;});});
  if(RC.sort){var k=RC.sort.k,dir=RC.sort.dir,col=out.cols.find(function(c){return c.k===k;})||{};
    rows.sort(function(a,b){var x=a[k],y=b[k];var r=col.num?num(x)-num(y):String(x==null?'':x).localeCompare(String(y==null?'':y),'ar',{numeric:true});return r*dir;});}
  return rows;
}
function paintTable(){
  var out=RC.out||{},tbl=$('rcTbl');if(!tbl)return;
  if(out.msg){tbl.innerHTML='<tbody><tr><td class="rc-empty">'+esc(out.msg)+'</td></tr></tbody>';return;}
  var cols=out.cols||[],rows=viewRows();
  if(!rows.length){tbl.innerHTML='<tbody><tr><td class="rc-empty">'+ic('info')+' لا توجد بيانات مطابقة للفلاتر الحالية</td></tr></tbody>';return;}
  var h='<thead><tr><th>م</th>'+cols.map(function(c){var s=RC.sort&&RC.sort.k===c.k?(RC.sort.dir>0?' ▲':' ▼'):'';
    return '<th data-k="'+c.k+'" scope="col" aria-sort="'+(s?(RC.sort.dir>0?'ascending':'descending'):'none')+'">'+esc(c.t)+s+'</th>';}).join('')+'</tr></thead><tbody>';
  var LIMIT=2000;
  rows.slice(0,LIMIT).forEach(function(r,i){h+='<tr><td>'+(i+1)+'</td>'+cols.map(function(c){var v=r[c.k];
    return '<td>'+(c.html&&r[c.html]?r[c.html]:(c.num?fmt(v):esc(v==null||v===''?'—':v)))+'</td>';}).join('')+'</tr>';});
  var sums=cols.map(function(c){return c.num&&!c.nosum;});
  if(sums.some(Boolean)&&rows.length>1)h+='<tr class="rc-sum"><td>—</td>'+cols.map(function(c,i){if(i===0)return '<td>الإجمالي</td>';
    return '<td>'+(sums[i]?fmt(rows.reduce(function(a,r){return a+num(r[c.k]);},0)):'')+'</td>';}).join('')+'</tr>';
  h+='</tbody>';
  if(rows.length>LIMIT)h+='<caption class="rc-meta">يُعرض أول '+nf(LIMIT)+' سطر من '+nf(rows.length)+' — استخدم الفلاتر لتضييق النتائج</caption>';
  tbl.innerHTML=h;
  [].forEach.call(tbl.querySelectorAll('th[data-k]'),function(th){th.onclick=function(){var k=th.dataset.k;
    RC.sort=RC.sort&&RC.sort.k===k?{k:k,dir:-RC.sort.dir,id:REPORTS[RC.idx].id}:{k:k,dir:1,id:REPORTS[RC.idx].id};paintTable();};});
}
function hasRows(){if(!RC.out||RC.out.msg||!viewRows().length){toast('✖ لا توجد بيانات — اعرض التقرير أولًا');return false;}return true;}
function reportTitle(){var r=REPORTS[RC.idx];return r.name+(RC.out&&RC.out.title?' — '+RC.out.title:'');}
function doPrint(){if(!hasRows())return;
  var out=RC.out,rows=viewRows(),headers=['م'].concat(out.cols.map(function(c){return c.t;}));
  var data=rows.map(function(r,i){return [String(i+1)].concat(out.cols.map(function(c){var v=r[c.k];return c.num?fmt(v):esc(v==null||v===''?'—':v);}));});
  var info=[];if(RC.filterText)RC.filterText.split(' · ').forEach(function(p,i){var kv=p.split(': ');if(i%2===0)info.push([kv.length>1?kv[0]:'الفلتر',kv.length>1?kv.slice(1).join(': '):p,'','']);else{var last=info[info.length-1];last[2]=kv.length>1?kv[0]:'الفلتر';last[3]=kv.length>1?kv.slice(1).join(': '):p;}});
  var AC=window.IMDAD_ACCESS;if(AC&&AC.scopeLabel())info.push(['نطاق المستودعات',AC.scopeLabel(),'','']);
  try{militaryPrint.printGenericReport({date:today(),refLabel:'تاريخ الطباعة',infoTitle:'محددات التقرير',infoLines:info},data,headers,reportTitle(),'#2E6B35','issue',28);}
  catch(e){var X=window.IMDAD_EXPORT;if(X&&X.print)X.print('rcTbl',reportTitle());else window.print();}}
function doXlsx(){if(!hasRows())return;var X=window.IMDAD_EXPORT;
  var out=RC.out,rows=viewRows(),headers=['م'].concat(out.cols.map(function(c){return c.t;}));
  var data=rows.map(function(r,i){var o={'م':i+1};out.cols.forEach(function(c){var v=r[c.k];o[c.t]=c.num?Math.round(num(v)*100)/100:(v==null?'':String(v));});return o;});
  var fn=('تقرير_'+REPORTS[RC.idx].name+'_'+today()).replace(/[\\/:*?"<>|\s]+/g,'_');
  if(X&&X.json)X.json(headers,data,fn);else toast('✖ خدمة التصدير غير متاحة');}

window.renderReportCenter=renderReportCenter;
window.IMDAD_REPORTS={list:REPORTS,run:function(id,f){var i=REPORTS.findIndex(function(r){return r.id===id;});return RUN[id](Object.assign({},f||{}));},load:loadAll,state:RC};
})();
