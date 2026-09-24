/* IMDAD Stocktake v2 — إدارة الجرد المخزني
   التبويبات: إنشاء أمر جرد · العد الفعلي · تحليل الفروقات · التسوية والاعتماد · سجل الجرد
   البيانات: stocktakes (الأمر) و stocktakeLines (سطر لكل صنف) — متوافقة مع الإصدار السابق (COUNTING/CLOSED).
   الكميات تُحفظ بوحدة الأساس (countedQty/systemQty) مع تفصيل العد لكل وحدة (counts).
   التسوية تضيف الفرق إلى رصيد الصنف (qty += variance) فلا تمس أرصدة المستودعات الأخرى. */
(function(){
'use strict';
var d=document;
function $(id){return d.getElementById(id);}
function ic(n){return window.IMDAD_ICON?window.IMDAD_ICON(n):'';}
function E(s){return (typeof esc==='function')?esc(s):String(s==null?'':s);}
function SG(n){n=Math.round((+n||0)*1000)/1000;return (n>0?'+':n<0?'-':'')+N(Math.abs(n));}
function N(n){return (Math.round((+n||0)*1000)/1000).toLocaleString('ar-EG');}
function T(m){if(typeof toast==='function')toast(m);}
function today(){return new Date().toISOString().slice(0,10);}
function email(){try{return me.state?me.state.email:'';}catch(e){return '';}}
function canWrite(){try{return can()||pageManage('stocktake');}catch(e){return true;}}
function perm(a){try{return guardPerm('stocktake',a);}catch(e){return true;}}
async function audit(action,summary,details){try{await auditWrite(action,'stocktake',summary,details||{});}catch(e){}}

var TYPE={FULL:'جرد كامل',PARTIAL:'جرد جزئي (تصنيف)',SURPRISE:'جرد مفاجئ',CYCLE:'جرد دوري'};
var STATUS={COUNTING:'قيد التنفيذ',CLOSED:'معتمد ومغلق',CANCELLED:'ملغى'};
var STATUS_CHIP={COUNTING:'chip-pend',CLOSED:'chip-ok',CANCELLED:'chip-off'};
var REASONS=['','تلف','فقد / عجز','خطأ في الإدخال','حركة غير مسجلة','خطأ في وحدة القياس','زيادة غير مبررة','أخرى'];
var DECISIONS={ADJUST:'تسوية الرصيد',IGNORE:'تجاهل الفرق',RECOUNT:'إعادة العد'};
var TABS=[['create','إنشاء أمر جرد','plus-square'],['count','العد الفعلي','clipboard'],['analysis','تحليل الفروقات','scale'],['approve','التسوية والاعتماد','check-circle'],['history','سجل الجرد','clock']];

var S=window.STK2=window.STK2||{tab:'create',orders:[],items:[],whs:[],cats:[],cur:'',lines:[],q:''};

/* ───── البيانات ───── */
async function getAll(col,limit){try{var s=await db.collection(col).limit(limit||3000).get();return s.docs.map(function(x){var o=x.data()||{};o.id=x.id;return o;});}catch(e){return [];}}
function tsOf(o,k){var v=o[k];return v&&v.seconds?v.seconds*1000:(v?new Date(v).getTime()||0:0);}
async function loadBase(){
  var r=await Promise.all([getAll('items',3000),getAll('warehouses',500),getAll('categories',500),getAll('stocktakes',1000)]);
  S.items=r[0].sort(function(a,b){return String(a.code||'').localeCompare(String(b.code||''),'ar',{numeric:true});});
  S.whs=r[1];S.cats=r[2];
  S.orders=r[3].sort(function(a,b){return tsOf(b,'createdAt')-tsOf(a,'createdAt');});
}
async function loadLines(id){
  try{var s=await db.collection('stocktakeLines').where('sessionId','==',id).limit(3000).get();
    S.lines=s.docs.map(function(x){var o=x.data()||{};o.id=x.id;return o;}).sort(function(a,b){return String(a.itemCode||'').localeCompare(String(b.itemCode||''),'ar',{numeric:true});});}
  catch(e){S.lines=[];}
}
function order(id){return S.orders.filter(function(o){return o.id===id;})[0]||null;}
function openOrders(){return S.orders.filter(function(o){return o.status==='COUNTING';});}
function itemById(id){return S.items.filter(function(x){return x.id===id;})[0]||null;}
/* وحدات الصنف من الأكبر للأصغر (حتى 3) */
function unitsOf(it){
  var u=(it&&it.units&&it.units.length)?it.units.map(function(x){return {name:x.name,f:+x.factor||1};}):[{name:(it&&it.baseUnit)||'وحدة',f:1}];
  u.sort(function(a,b){return b.f-a.f;});return u.slice(0,3);
}
/* تفكيك كمية أساس إلى وحدات (الأكبر أولًا) */
function split(base,units){var rest=+base||0,out=[],neg=rest<0;rest=Math.abs(rest);
  units.forEach(function(u,i){var q=i<units.length-1?Math.floor((rest+1e-9)/u.f):Math.round(rest/u.f*1000)/1000;rest=Math.round((rest-q*u.f)*1000)/1000;out.push(neg?-q:q);});return out;}
/* الرصيد الدفتري للمستودع: من الحركات المعتمدة؛ وعند وجود مستودع واحد فقط يُستخدم رصيد الصنف */
async function bookBalances(whName){
  var map={};
  if(S.whs.length<=1||!window.IMDAD_REPORTS){S.items.forEach(function(it){map[it.id]=+it.qty||0;});return map;}
  try{await IMDAD_REPORTS.load();IMDAD_REPORTS.run('stock',{wh:whName}).rows.forEach(function(){});}catch(e){}
  try{var D=IMDAD_REPORTS.state.data;D.items.forEach(function(it){map[it.id]=0;});
    D.moves.forEach(function(m){if(!m.active||!m.itemId)return;
      if(m.wh===whName){if(m.type==='IN'||m.type==='RETURN_IN')map[m.itemId]=(map[m.itemId]||0)+m.baseQty;else if(m.type!=='OPENING')map[m.itemId]=(map[m.itemId]||0)-m.baseQty;}
      if(m.type==='TRANSFER'&&m.destWh===whName&&m.status==='RECEIVED')map[m.itemId]=(map[m.itemId]||0)+m.baseQty;});
  }catch(e){S.items.forEach(function(it){map[it.id]=+it.qty||0;});}
  return map;
}
function nextNo(){var y=new Date().getFullYear(),max=0;S.orders.forEach(function(o){var m=/^STK-(\d{4})-(\d+)$/.exec(o.orderNo||'');if(m&&+m[1]===y)max=Math.max(max,+m[2]);});
  return 'STK-'+y+'-'+String(max+1).padStart(3,'0');}
function ordLabel(o){return (o.orderNo||('#'+o.id.slice(0,6)))+' — '+(o.warehouse||'بدون مستودع')+' — '+(o.date||'');}

/* ───── الهيكل ───── */
function css(){if($('stk2css'))return;var s=d.createElement('style');s.id='stk2css';s.textContent=
 '.stk-tabs{display:flex;gap:6px;flex-wrap:wrap;border-bottom:1px solid var(--ui-line,#e3e3e8);margin:6px 0 16px;padding-bottom:0}'+
 '.stk-tabs button{border:1px solid transparent;border-bottom:0;background:transparent;color:var(--ui-muted,#5b5e6b);font:inherit;font-weight:600;font-size:13.5px;padding:10px 16px;border-radius:10px 10px 0 0;cursor:pointer;display:flex;gap:6px;align-items:center;margin-bottom:-1px}'+
 '.stk-tabs button:hover{color:var(--ui-text,#202123);background:var(--ui-hover,#f2f2f5)}'+
 '.stk-tabs button.on{background:var(--ui-surface,#fff);color:var(--ui-accent,#0f766e);border-color:var(--ui-line,#e3e3e8);box-shadow:inset 0 3px 0 var(--ui-accent,#0f766e)}'+
 '.stk-grid{display:grid;grid-template-columns:minmax(320px,1fr) minmax(0,1.1fr);gap:16px;align-items:start}'+
 '.stk-form{display:grid;grid-template-columns:150px 1fr;gap:12px 14px;align-items:center}.stk-form>label{font-weight:600;font-size:13px;color:var(--ui-text-2,#343541)}'+
 '.stk-bar{display:flex;flex-wrap:wrap;gap:8px 10px;align-items:center;margin-bottom:12px}.stk-bar>label{font-weight:600;font-size:13px;white-space:nowrap}'+
 '.stk-bar .fld{width:auto;min-width:240px;flex:0 1 340px;margin:0}.stk-grow{flex:1 1 260px!important}'+
 '.stk-foot{display:flex;justify-content:flex-start;gap:10px;margin-top:12px}'+
 '.stk-sum{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px;margin:4px 0 14px}'+
 '.stk-sum div{background:var(--ui-bg,#f7f7f8);border:1px solid var(--ui-line,#e3e3e8);border-radius:10px;padding:10px 12px}.stk-sum small{display:block;color:var(--ui-muted,#5b5e6b);font-size:12px}.stk-sum b{font-size:18px;font-variant-numeric:tabular-nums}'+
 '#stkCountTbl input.fld,#stkAnaTbl .fld{min-width:84px;padding:6px 8px;margin:0}#stkAnaTbl td,#stkAnaTbl th{white-space:nowrap}'+
 '.stk-pos{color:var(--ui-success,#067647);font-weight:700}.stk-neg{color:var(--ui-danger,#b42318);font-weight:700}'+
 '.stk-row-click{cursor:pointer}.stk-row-click:hover td{background:var(--ui-hover,#f2f2f5)}.stk-empty{padding:26px;text-align:center;color:var(--ui-muted,#5b5e6b)}'+
 '.stk-att{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}.stk-att a{display:block;width:74px;height:74px;border:1px solid var(--ui-line,#e3e3e8);border-radius:8px;overflow:hidden}.stk-att img{width:100%;height:100%;object-fit:cover}'+
 '@media (max-width:980px){.stk-grid{grid-template-columns:1fr}.stk-form{grid-template-columns:1fr}.stk-bar .fld{min-width:0;flex:1 1 100%}}';
 d.head.appendChild(s);}

async function renderStocktake2(){
  css();
  $('main').innerHTML='<div class="page-title">'+ic('clipboard')+' إدارة الجرد المخزني</div><div class="page-sub">أوامر الجرد، العد الفعلي بالوحدات، تحليل الفروقات، واعتماد التسوية</div><div class="ld">جارٍ التحميل…</div>';
  await loadBase();
  if(window.curPage!=='stocktake')return;
  $('main').innerHTML='<div class="page-title">'+ic('clipboard')+' إدارة الجرد المخزني</div>'+
    '<div class="page-sub">أوامر الجرد، العد الفعلي بالوحدات، تحليل الفروقات، واعتماد التسوية</div>'+
    '<div class="stk-tabs" role="tablist">'+TABS.map(function(t){return '<button type="button" role="tab" data-t="'+t[0]+'">'+ic(t[2])+' '+t[1]+'</button>';}).join('')+'</div>'+
    '<div id="stkPane"></div>';
  [].forEach.call(d.querySelectorAll('.stk-tabs button'),function(b){b.onclick=function(){go(b.dataset.t);};});
  if(S.cur&&!order(S.cur))S.cur='';
  go(S.tab);
}
function go(t){
  S.tab=t;[].forEach.call(d.querySelectorAll('.stk-tabs button'),function(b){var on=b.dataset.t===t;b.classList.toggle('on',on);b.setAttribute('aria-selected',on?'true':'false');});
  ({create:tabCreate,count:tabCount,analysis:tabAnalysis,approve:tabApprove,history:tabHistory})[t]();
}
function orderPicker(id,onlyOpen){
  var list=onlyOpen?openOrders():S.orders;
  if(S.cur&&!list.some(function(o){return o.id===S.cur;}))S.cur='';
  return '<label for="'+id+'">أمر الجرد:</label><select class="fld" id="'+id+'"><option value="">— اختر أمر الجرد —</option>'+
    list.map(function(o){return '<option value="'+o.id+'"'+(o.id===S.cur?' selected':'')+'>'+E(ordLabel(o))+(o.status!=='COUNTING'?' ('+STATUS[o.status]+')':'')+'</option>';}).join('')+'</select>';
}
function bindPicker(id,fn){var s=$(id);if(s)s.onchange=function(){S.cur=s.value;fn();};}

/* ───── 1) إنشاء أمر جرد ───── */
function tabCreate(){
  var W=canWrite(),p=$('stkPane');
  var wh=S.whs.map(function(w){return '<option value="'+E(w.name)+'">'+E((w.code?w.code+' — ':'')+w.name)+'</option>';}).join('');
  p.innerHTML='<div class="stk-grid">'+
   '<div class="panel"><h3>'+ic('plus-square')+' أمر جرد جديد</h3>'+
   (W?'':'<div class="note-box">عرض فقط — إنشاء أوامر الجرد يتطلب صلاحية.</div>')+
   '<div class="stk-form">'+
    '<label for="stkWh">المستودع:</label><select class="fld" id="stkWh">'+(wh||'<option value="">— لا توجد مستودعات —</option>')+'</select>'+
    '<label for="stkType">نوع الجرد:</label><select class="fld" id="stkType">'+Object.keys(TYPE).map(function(k){return '<option value="'+k+'">'+TYPE[k]+'</option>';}).join('')+'</select>'+
    '<label for="stkCat">التصنيف (للجرد الجزئي):</label><select class="fld" id="stkCat" disabled><option value="">كل التصنيفات</option>'+S.cats.map(function(c){return '<option value="'+c.id+'">'+E(c.name)+'</option>';}).join('')+'</select>'+
    '<label for="stkDate">تاريخ البدء:</label><input class="fld" type="date" id="stkDate" value="'+today()+'">'+
    '<label for="stkCommittee">أعضاء اللجنة:</label><input class="fld" id="stkCommittee" placeholder="أسماء أعضاء اللجنة (مفصولين بفاصلة)">'+
    '<label>تجميد المخزون:</label><label style="display:flex;gap:8px;align-items:center;font-weight:500"><input type="checkbox" id="stkFreeze" checked> تجميد المستودع (منع الحركات حتى الاعتماد)</label>'+
    '<label for="stkNotes">ملاحظات:</label><input class="fld" id="stkNotes">'+
   '</div>'+
   '<div class="stk-foot"><button class="btn btn-p" id="stkCreate" type="button" style="flex:1"'+(W?'':' disabled')+'>'+ic('check-circle')+' إنشاء أمر الجرد وسحب الأرصدة الدفترية</button></div></div>'+
   '<div class="panel"><h3>'+ic('hourglass')+' أوامر الجرد قيد التنفيذ</h3><div class="twrap"><table class="u" id="stkOpenTbl"></table></div></div>'+
  '</div>';
  $('stkType').onchange=function(){$('stkCat').disabled=this.value!=='PARTIAL';if(this.value!=='PARTIAL')$('stkCat').value='';};
  $('stkCreate').onclick=createOrder;
  var o=openOrders(),t=$('stkOpenTbl');
  t.innerHTML=o.length?'<thead><tr><th>رقم الأمر</th><th>المستودع</th><th>النوع</th><th>التاريخ</th><th>تجميد</th></tr></thead><tbody>'+o.map(function(x){
      return '<tr class="stk-row-click" data-open="'+x.id+'" title="فتح في العد الفعلي"><td><b>'+E(x.orderNo||'—')+'</b></td><td>'+E(x.warehouse||'—')+'</td><td>'+E(TYPE[x.type]||x.type)+'</td><td>'+E(x.date||'')+'</td><td>'+(x.freeze?'<span class="chip chip-pend">مجمّد</span>':'—')+'</td></tr>';}).join('')+'</tbody>'
    :'<tbody><tr><td class="stk-empty">لا توجد أوامر جرد مفتوحة</td></tr></tbody>';
  [].forEach.call(t.querySelectorAll('[data-open]'),function(r){r.onclick=function(){S.cur=r.dataset.open;go('count');};});
}
async function createOrder(){
  if(!perm('create'))return;
  var wh=$('stkWh').value,type=$('stkType').value,cat=$('stkCat').value,date=$('stkDate').value||today();
  if(!wh)return T('✖ اختر المستودع');
  if(type==='PARTIAL'&&!cat)return T('✖ اختر التصنيف للجرد الجزئي');
  var dup=openOrders().filter(function(o){return o.warehouse===wh;})[0];
  if(dup)return T('✖ يوجد أمر جرد مفتوح لهذا المستودع: '+(dup.orderNo||''));
  var sel=S.items.filter(function(it){return type!=='PARTIAL'||it.categoryId===cat;});
  if(!sel.length)return T('✖ لا توجد أصناف مطابقة');
  var btn=$('stkCreate');btn.disabled=true;
  try{
    var book=await bookBalances(wh);
    var ref=db.collection('stocktakes').doc(),no=nextNo();
    var catName=(S.cats.filter(function(c){return c.id===cat;})[0]||{}).name||'';
    var data={orderNo:no,type:type,date:date,warehouse:wh,categoryId:cat||'',categoryName:catName,committee:$('stkCommittee').value.trim(),
      freeze:$('stkFreeze').checked,notes:$('stkNotes').value.trim(),status:'COUNTING',itemsCount:sel.length,attachments:[],createdBy:email(),createdAt:ST()};
    await ref.set(data);
    var batch=db.batch(),n=0;
    for(var i=0;i<sel.length;i++){var it=sel[i];
      batch.set(db.collection('stocktakeLines').doc(),{sessionId:ref.id,itemId:it.id,itemCode:it.code||'',itemName:it.name||'',unitName:it.baseUnit||'',
        systemQty:Math.round((book[it.id]||0)*1000)/1000,countedQty:null,counts:{},variance:null,reason:'',decision:'ADJUST',status:'PENDING'});
      if(++n%400===0){await batch.commit();batch=db.batch();}
    }
    await batch.commit();
    await audit('STOCKTAKE_CREATED','إنشاء أمر جرد '+no,{refNo:no,warehouse:wh,status:'COUNTING',itemCount:sel.length,target:TYPE[type],freeze:data.freeze,risk:'sensitive'});
    T('✔ أُنشئ أمر الجرد '+no+' — '+N(sel.length)+' صنف');
    await loadBase();S.cur=ref.id;go('count');
  }catch(e){T('✖ '+(e.code||e.message));btn.disabled=false;}
}

/* ───── 2) العد الفعلي ───── */
async function tabCount(){
  var p=$('stkPane');
  p.innerHTML='<div class="panel"><div class="stk-bar">'+orderPicker('stkOrdC',true)+
   '<button class="btn btn-o" id="stkPrintBlank" type="button">'+ic('printer')+' طباعة استمارة الجرد (فارغة)</button>'+
   '<button class="btn btn-o" id="stkAttachBtn" type="button">'+ic('camera')+' إرفاق صورة الجرد اليدوي</button><input type="file" id="stkAttach" accept="image/*" hidden></div>'+
   '<div class="stk-bar"><label for="stkAddItem">'+ic('plus')+' إضافة صنف مكتشف:</label><select class="fld stk-grow" id="stkAddItem"><option value="">— اختر صنفًا غير مدرج —</option></select>'+
   '<button class="btn btn-warn" id="stkAddBtn" type="button">'+ic('plus')+' إضافة للجرد</button></div>'+
   '<div class="stk-bar"><label for="stkQ">'+ic('search')+' بحث في الجدول:</label><input class="fld stk-grow" id="stkQ" placeholder="ابحث برقم أو اسم الصنف…" value="'+E(S.q)+'"></div>'+
   '<div id="stkAttList" class="stk-att"></div></div>'+
   '<div class="twrap"><table class="u" id="stkCountTbl"></table></div>'+
   '<div class="stk-foot"><button class="btn btn-p" id="stkSaveCount" type="button">'+ic('save')+' حفظ العد الفعلي</button><span class="rc-meta" id="stkCountMeta"></span></div>';
  bindPicker('stkOrdC',tabCount);
  $('stkQ').oninput=function(){S.q=this.value.trim();paintCount();};
  $('stkPrintBlank').onclick=printBlank;
  $('stkAttachBtn').onclick=function(){if(!S.cur)return T('✖ اختر أمر الجرد أولًا');$('stkAttach').click();};
  $('stkAttach').onchange=attach;
  $('stkAddBtn').onclick=addItem;
  $('stkSaveCount').onclick=saveCount;
  if(!S.cur){$('stkCountTbl').innerHTML='<tbody><tr><td class="stk-empty">اختر أمر جرد مفتوحًا لبدء العد</td></tr></tbody>';return;}
  await loadLines(S.cur);
  var inList={};S.lines.forEach(function(l){inList[l.itemId]=1;});
  $('stkAddItem').innerHTML='<option value="">— اختر صنفًا غير مدرج —</option>'+S.items.filter(function(it){return !inList[it.id];}).map(function(it){return '<option value="'+it.id+'">'+E((it.code?it.code+' — ':'')+it.name)+'</option>';}).join('');
  paintAtt();paintCount();
}
function paintAtt(){var o=order(S.cur),box=$('stkAttList');if(!box)return;var a=(o&&o.attachments)||[];
  box.innerHTML=a.map(function(x,i){return '<a href="'+x.data+'" target="_blank" rel="noopener" title="'+E(x.name||('مرفق '+(i+1)))+'"><img src="'+x.data+'" alt="مرفق الجرد '+(i+1)+'"></a>';}).join('');}
function lineMatches(l){var q=(S.q||'').toLowerCase();return !q||[l.itemCode,l.itemName].some(function(v){return String(v||'').toLowerCase().indexOf(q)>=0;});}
function paintCount(){
  var t=$('stkCountTbl');if(!t||!S.cur)return;var o=order(S.cur)||{},open=o.status==='COUNTING'&&canWrite();
  var rows=S.lines.filter(lineMatches);
  if(!rows.length){t.innerHTML='<tbody><tr><td class="stk-empty">'+(S.lines.length?'لا نتائج مطابقة للبحث':'لا توجد أصناف في هذا الأمر')+'</td></tr></tbody>';return;}
  var h='<thead><tr><th>الكود</th><th>الصنف</th><th>الوحدة 1</th><th>الفعلي 1</th><th>الوحدة 2</th><th>الفعلي 2</th><th>الوحدة 3</th><th>الفعلي 3</th></tr></thead><tbody>';
  rows.forEach(function(l){var u=unitsOf(itemById(l.itemId)||{baseUnit:l.unitName}),c=l.counts||{};
    if(l.countedQty!=null&&!Object.keys(c).length){var sp=split(l.countedQty,u);u.forEach(function(x,i){c[x.name]=sp[i];});}
    h+='<tr data-lid="'+l.id+'"><td><b>'+E(l.itemCode||'—')+'</b></td><td>'+E(l.itemName)+'</td>';
    for(var i=0;i<3;i++){var x=u[i];
      h+=x?'<td>'+E(x.name)+(x.f!==1?' <span class="rc-meta">×'+N(x.f)+'</span>':'')+'</td><td><input class="fld stkCnt" type="number" min="0" step="any" inputmode="decimal" data-u="'+E(x.name)+'" data-f="'+x.f+'" value="'+(c[x.name]!=null&&c[x.name]!==''?c[x.name]:'')+'"'+(open?'':' disabled')+' aria-label="الكمية الفعلية '+E(x.name)+' — '+E(l.itemName)+'"></td>':'<td>—</td><td></td>';}
    h+='</tr>';});
  t.innerHTML=h+'</tbody>';
  var done=S.lines.filter(function(l){return l.countedQty!=null;}).length;
  $('stkCountMeta').textContent='تم عدّ '+N(done)+' من '+N(S.lines.length)+' صنف';
  $('stkSaveCount').disabled=!open;
}
async function saveCount(){
  if(!S.cur)return T('✖ اختر أمر الجرد');if(!perm('edit'))return;
  var batch=db.batch(),n=0;
  [].forEach.call(d.querySelectorAll('#stkCountTbl tr[data-lid]'),function(tr){
    var counts={},base=0,any=false;
    [].forEach.call(tr.querySelectorAll('.stkCnt'),function(inp){var v=inp.value.trim();if(v==='')return;any=true;counts[inp.dataset.u]=+v;base+=(+v)*(+inp.dataset.f||1);});
    var l=S.lines.filter(function(x){return x.id===tr.dataset.lid;})[0];if(!l)return;
    var cq=any?Math.round(base*1000)/1000:null;
    if(cq===l.countedQty&&JSON.stringify(counts)===JSON.stringify(l.counts||{}))return;
    batch.update(db.collection('stocktakeLines').doc(l.id),{counts:counts,countedQty:cq,variance:cq==null?null:Math.round((cq-(+l.systemQty||0))*1000)/1000,status:cq==null?'PENDING':'COUNTED',countedBy:email()});n++;
  });
  if(!n)return T('لا توجد تغييرات للحفظ');
  try{await batch.commit();T('✔ حُفظ العد الفعلي ('+N(n)+' صنف)');await loadLines(S.cur);paintCount();}catch(e){T('✖ '+(e.code||e.message));}
}
async function addItem(){
  if(!S.cur)return T('✖ اختر أمر الجرد أولًا');if(!perm('edit'))return;
  var id=$('stkAddItem').value,o=order(S.cur);if(!id)return T('✖ اختر الصنف');
  var it=itemById(id);
  try{var book=await bookBalances(o.warehouse);
    await db.collection('stocktakeLines').add({sessionId:S.cur,itemId:it.id,itemCode:it.code||'',itemName:it.name||'',unitName:it.baseUnit||'',systemQty:Math.round((book[it.id]||0)*1000)/1000,
      countedQty:null,counts:{},variance:null,reason:'',decision:'ADJUST',status:'PENDING',discovered:true});
    await db.collection('stocktakes').doc(S.cur).update({itemsCount:(+o.itemsCount||S.lines.length)+1});
    await loadBase();T('✔ أُضيف الصنف «'+it.name+'» إلى الجرد');S.q=it.code||it.name;tabCount();
  }catch(e){T('✖ '+(e.code||e.message));}
}
function attach(){
  var f=this.files&&this.files[0];this.value='';if(!f)return;if(!perm('edit'))return;
  var rd=new FileReader();rd.onload=function(){var img=new Image();img.onload=async function(){
    var max=1400,sc=Math.min(1,max/Math.max(img.width,img.height)),c=d.createElement('canvas');c.width=Math.round(img.width*sc);c.height=Math.round(img.height*sc);
    c.getContext('2d').drawImage(img,0,0,c.width,c.height);var data=c.toDataURL('image/jpeg',0.72);
    var o=order(S.cur),list=((o&&o.attachments)||[]).concat([{name:f.name,data:data,at:new Date().toISOString(),by:email()}]);
    try{await db.collection('stocktakes').doc(S.cur).update({attachments:list});o.attachments=list;paintAtt();T('✔ أُرفقت صورة الجرد اليدوي');}catch(e){T('✖ تعذر حفظ المرفق: '+(e.code||e.message));}
  };img.onerror=function(){T('✖ الملف ليس صورة صالحة');};img.src=rd.result;};rd.readAsDataURL(f);
}
function printBlank(){
  if(!S.cur)return T('✖ اختر أمر الجرد أولًا');var o=order(S.cur);
  var rows=S.lines.map(function(l,i){var u=unitsOf(itemById(l.itemId)||{baseUnit:l.unitName});
    return [String(i+1),E(l.itemCode||''),E(l.itemName),u.map(function(x){return E(x.name);}).join(' / '),'','',''];});
  try{militaryPrint.printGenericReport({date:o.date,ref:o.orderNo||'',refLabel:'رقم أمر الجرد',infoTitle:'بيانات أمر الجرد',
      infoLines:[['المستودع',o.warehouse||'—','نوع الجرد',TYPE[o.type]||o.type],['أعضاء اللجنة',o.committee||'—','التاريخ',o.date||'']]},
    rows,['م','الكود','الصنف','الوحدات','الفعلي 1','الفعلي 2','الفعلي 3'],'استمارة جرد فعلي','#0F766E','receive');}
  catch(e){T('✖ خدمة الطباعة غير متاحة');}
}

/* ───── 3) تحليل الفروقات ───── */
async function tabAnalysis(){
  var p=$('stkPane');
  p.innerHTML='<div class="panel"><div class="stk-bar">'+orderPicker('stkOrdA',false)+
   '<button class="btn btn-o" id="stkPrintVar" type="button">'+ic('printer')+' تقرير الفروقات</button>'+
   '<label style="font-weight:500;display:flex;gap:6px;align-items:center"><input type="checkbox" id="stkOnlyVar"'+(S.onlyVar?' checked':'')+'> الأصناف التي بها فروقات فقط</label></div>'+
   '<div class="chips-row" id="stkAnaChips"></div></div>'+
   '<div class="twrap"><table class="u" id="stkAnaTbl"></table></div>'+
   '<div class="stk-foot"><button class="btn btn-p" id="stkSaveAna" type="button">'+ic('save')+' حفظ الأسباب والقرارات</button></div>';
  bindPicker('stkOrdA',tabAnalysis);
  $('stkOnlyVar').onchange=function(){S.onlyVar=this.checked;paintAnalysis();};
  $('stkPrintVar').onclick=printVar;$('stkSaveAna').onclick=saveAnalysis;
  if(!S.cur){$('stkAnaTbl').innerHTML='<tbody><tr><td class="stk-empty">اختر أمر الجرد لعرض الفروقات</td></tr></tbody>';$('stkSaveAna').disabled=true;return;}
  await loadLines(S.cur);paintAnalysis();
}
function varOf(l){return l.countedQty==null?null:Math.round(((+l.countedQty)-(+l.systemQty||0))*1000)/1000;}
function paintAnalysis(){
  var t=$('stkAnaTbl');if(!t)return;var o=order(S.cur)||{},open=o.status==='COUNTING'&&canWrite();
  var counted=S.lines.filter(function(l){return l.countedQty!=null;}),withVar=counted.filter(function(l){return varOf(l)!==0;});
  $('stkAnaChips').innerHTML='<span class="chip chip-ok">المعدود: '+N(counted.length)+' / '+N(S.lines.length)+'</span><span class="chip '+(withVar.length?'chip-err':'chip-ok')+'">بها فروقات: '+N(withVar.length)+'</span>'+
    '<span class="chip chip-pend">لم تُعد: '+N(S.lines.length-counted.length)+'</span><span class="chip '+(STATUS_CHIP[o.status]||'chip-code')+'">'+E(STATUS[o.status]||'')+'</span>';
  var rows=S.lines.filter(function(l){return !S.onlyVar||(l.countedQty!=null&&varOf(l)!==0);});
  if(!rows.length){t.innerHTML='<tbody><tr><td class="stk-empty">لا توجد أصناف للعرض</td></tr></tbody>';$('stkSaveAna').disabled=true;return;}
  var h='<thead><tr><th>الصنف</th>';for(var k=1;k<=3;k++)h+='<th>و'+k+'</th><th>دفتري '+k+'</th><th>فعلي '+k+'</th><th>الفرق '+k+'</th>';
  h+='<th>الفرق (أساس)</th><th>السبب</th><th>القرار</th></tr></thead><tbody>';
  rows.forEach(function(l){var u=unitsOf(itemById(l.itemId)||{baseUnit:l.unitName}),has=l.countedQty!=null;
    var bk=split(l.systemQty,u),ac=has?split(l.countedQty,u):[];
    h+='<tr data-lid="'+l.id+'"><td><b>'+E(l.itemCode||'')+'</b> '+E(l.itemName)+(l.discovered?' <span class="chip chip-code">مكتشف</span>':'')+'</td>';
    for(var i=0;i<3;i++){var x=u[i];
      if(!x){h+='<td>—</td><td></td><td></td><td></td>';continue;}
      var df=has?Math.round((ac[i]-bk[i])*1000)/1000:null;
      h+='<td>'+E(x.name)+'</td><td>'+N(bk[i])+'</td><td>'+(has?N(ac[i]):'—')+'</td><td class="'+(df>0?'stk-pos':df<0?'stk-neg':'')+'">'+(df==null?'—':SG(df))+'</td>';}
    var v=varOf(l);
    h+='<td class="'+(v>0?'stk-pos':v<0?'stk-neg':'')+'">'+(v==null?'<span class="chip chip-pend">لم يُعد</span>':SG(v)+' '+E(u[u.length-1].name))+'</td>'+
      '<td><select class="fld stkReason"'+(open?'':' disabled')+' aria-label="سبب الفرق">'+REASONS.map(function(r){return '<option value="'+E(r)+'"'+(r===(l.reason||'')?' selected':'')+'>'+(r||'—')+'</option>';}).join('')+'</select></td>'+
      '<td><select class="fld stkDecision"'+(open?'':' disabled')+' aria-label="القرار">'+Object.keys(DECISIONS).map(function(k){return '<option value="'+k+'"'+(k===(l.decision||'ADJUST')?' selected':'')+'>'+DECISIONS[k]+'</option>';}).join('')+'</select></td></tr>';
  });
  t.innerHTML=h+'</tbody>';$('stkSaveAna').disabled=!open;
}
async function saveAnalysis(){
  if(!S.cur)return;if(!perm('edit'))return;var batch=db.batch(),n=0;
  [].forEach.call(d.querySelectorAll('#stkAnaTbl tr[data-lid]'),function(tr){var l=S.lines.filter(function(x){return x.id===tr.dataset.lid;})[0];if(!l)return;
    var r=tr.querySelector('.stkReason').value,dc=tr.querySelector('.stkDecision').value;
    if(r===(l.reason||'')&&dc===(l.decision||'ADJUST'))return;batch.update(db.collection('stocktakeLines').doc(l.id),{reason:r,decision:dc});n++;});
  if(!n)return T('لا توجد تغييرات للحفظ');
  try{await batch.commit();T('✔ حُفظت الأسباب والقرارات ('+N(n)+')');await loadLines(S.cur);paintAnalysis();}catch(e){T('✖ '+(e.code||e.message));}
}
function printVar(){
  if(!S.cur)return T('✖ اختر أمر الجرد أولًا');var o=order(S.cur);
  var rows=S.lines.filter(function(l){return l.countedQty!=null&&varOf(l)!==0;}).map(function(l,i){var u=unitsOf(itemById(l.itemId)||{baseUnit:l.unitName}),b=u[u.length-1].name,v=varOf(l);
    return [String(i+1),E(l.itemCode||''),E(l.itemName),N(l.systemQty)+' '+E(b),N(l.countedQty)+' '+E(b),SG(v),E(l.reason||'—'),E(DECISIONS[l.decision||'ADJUST'])];});
  if(!rows.length)return T('لا توجد فروقات في هذا الأمر');
  try{militaryPrint.printGenericReport({date:o.date,ref:o.orderNo||'',refLabel:'رقم أمر الجرد',infoTitle:'بيانات أمر الجرد',
      infoLines:[['المستودع',o.warehouse||'—','نوع الجرد',TYPE[o.type]||o.type],['أعضاء اللجنة',o.committee||'—','الحالة',STATUS[o.status]||'']]},
    rows,['م','الكود','الصنف','الدفتري','الفعلي','الفرق','السبب','القرار'],'تقرير فروقات الجرد','#B42318','receive');}
  catch(e){T('✖ خدمة الطباعة غير متاحة');}
}

/* ───── 4) التسوية والاعتماد ───── */
async function tabApprove(){
  var p=$('stkPane');
  p.innerHTML='<div class="panel"><div class="stk-bar">'+orderPicker('stkOrdP',true)+'</div><h3>'+ic('info')+' ملخص أمر الجرد</h3><div class="stk-sum" id="stkSum"></div><div id="stkWarn"></div>'+
   '<div class="stk-foot"><button class="btn btn-p" id="stkApprove" type="button">'+ic('check-circle')+' اعتماد التسوية وإغلاق الجرد</button>'+
   '<button class="btn btn-d" id="stkCancel" type="button">'+ic('x')+' إلغاء أمر الجرد (ورفع التجميد)</button></div></div>';
  bindPicker('stkOrdP',tabApprove);$('stkApprove').onclick=approve;$('stkCancel').onclick=cancelOrder;
  var o=S.cur?order(S.cur):null;if(o)await loadLines(S.cur);else S.lines=[];
  var counted=S.lines.filter(function(l){return l.countedQty!=null;}),withVar=counted.filter(function(l){return varOf(l)!==0;}),
      recount=withVar.filter(function(l){return l.decision==='RECOUNT';}),adjust=withVar.filter(function(l){return (l.decision||'ADJUST')==='ADJUST';});
  var cell=function(k,v){return '<div><small>'+k+'</small><b>'+v+'</b></div>';};
  $('stkSum').innerHTML=cell('رقم الأمر',E(o?o.orderNo||'—':'-'))+cell('المستودع',E(o?o.warehouse||'—':'-'))+cell('إجمالي الأصناف',o?N(S.lines.length):'-')+
    cell('تم جردها',o?N(counted.length):'-')+cell('أصناف بها فروقات',o?N(withVar.length):'-')+cell('ستُسوّى',o?N(adjust.length):'-')+cell('تجميد المستودع',o?(o.freeze?'مجمّد':'غير مجمّد'):'-');
  var w=[];if(o){if(counted.length<S.lines.length)w.push('يوجد '+N(S.lines.length-counted.length)+' صنف لم يُعد — لن تُعدّل أرصدتها.');
    if(recount.length)w.push('يوجد '+N(recount.length)+' صنف بقرار «إعادة العد» — عدّل القرار أو أعد العد قبل الاعتماد.');}
  $('stkWarn').innerHTML=w.length?'<div class="note-box" style="margin-bottom:6px">'+w.map(E).join('<br>')+'</div>':'';
  var W=canWrite()&&o&&o.status==='COUNTING';$('stkApprove').disabled=!W||!counted.length||!!recount.length;$('stkCancel').disabled=!W;
}
async function approve(){
  if(!S.cur)return;if(!perm('approve'))return;var o=order(S.cur);await loadLines(S.cur);
  var counted=S.lines.filter(function(l){return l.countedQty!=null;}),adjust=counted.filter(function(l){return varOf(l)!==0&&(l.decision||'ADJUST')==='ADJUST';});
  if(counted.some(function(l){return varOf(l)!==0&&l.decision==='RECOUNT';}))return T('✖ توجد أصناف بقرار إعادة العد');
  if(!confirm('اعتماد التسوية سيعدّل أرصدة '+adjust.length+' صنف ويغلق أمر الجرد '+(o.orderNo||'')+'. متابعة؟'))return;
  try{
    var items=await getAll('items',3000),qty={};items.forEach(function(it){qty[it.id]=+it.qty||0;});
    var batch=db.batch(),n=0,total=0;
    for(var i=0;i<counted.length;i++){var l=counted[i],v=varOf(l),adj=v!==0&&(l.decision||'ADJUST')==='ADJUST';
      batch.update(db.collection('stocktakeLines').doc(l.id),{variance:v,status:adj?'ADJUSTED':'CLOSED'});
      if(adj){batch.update(db.collection('items').doc(l.itemId),{qty:Math.round(((qty[l.itemId]||0)+v)*1000)/1000});total+=Math.abs(v);}
      if(++n%180===0){await batch.commit();batch=db.batch();}
    }
    batch.update(db.collection('stocktakes').doc(S.cur),{status:'CLOSED',freeze:false,closedBy:email(),closedAt:ST(),closedDate:today(),countedCount:counted.length,varianceCount:counted.filter(function(l){return varOf(l)!==0;}).length,adjustedCount:adjust.length});
    await batch.commit();
    await audit('STOCKTAKE_POSTED','اعتماد تسوية الجرد '+(o.orderNo||''),{refNo:o.orderNo||S.cur,warehouse:o.warehouse||'',status:'CLOSED',itemCount:adjust.length,totalBaseQty:total,risk:'critical'});
    T('✔ اعتُمدت التسوية وأُغلق أمر الجرد');await loadBase();S.tab='history';go('history');
  }catch(e){T('✖ '+(e.code||e.message));}
}
async function cancelOrder(){
  if(!S.cur)return;if(!perm('delete'))return;var o=order(S.cur);
  var why=prompt('سبب إلغاء أمر الجرد '+(o.orderNo||'')+':','');if(why===null)return;
  try{await db.collection('stocktakes').doc(S.cur).update({status:'CANCELLED',freeze:false,cancelReason:why.trim(),cancelledBy:email(),cancelledAt:ST(),closedDate:today()});
    await audit('STOCKTAKE_CANCELLED','إلغاء أمر الجرد '+(o.orderNo||''),{refNo:o.orderNo||S.cur,warehouse:o.warehouse||'',status:'CANCELLED',reason:why.trim(),risk:'sensitive'});
    T('✔ أُلغي أمر الجرد ورُفع تجميد المستودع');await loadBase();S.cur='';go('history');}
  catch(e){T('✖ '+(e.code||e.message));}
}

/* ───── 5) سجل الجرد ───── */
function tabHistory(){
  var p=$('stkPane');
  p.innerHTML='<div class="panel"><div class="stk-bar"><button class="btn btn-p" id="stkRefresh" type="button">'+ic('refresh')+' تحديث</button>'+
   '<input class="fld stk-grow" id="stkHQ" placeholder="بحث برقم الأمر أو المستودع…" aria-label="بحث في السجل"></div></div><div class="twrap"><table class="u" id="stkHistTbl"></table></div>';
  $('stkRefresh').onclick=async function(){await loadBase();paintHistory();T('✔ تم التحديث');};
  $('stkHQ').oninput=paintHistory;paintHistory();
}
function paintHistory(){
  var t=$('stkHistTbl'),q=(($('stkHQ')||{}).value||'').toLowerCase();
  var rows=S.orders.filter(function(o){return !q||[o.orderNo,o.warehouse].some(function(v){return String(v||'').toLowerCase().indexOf(q)>=0;});});
  if(!rows.length){t.innerHTML='<tbody><tr><td class="stk-empty">لا توجد أوامر جرد</td></tr></tbody>';return;}
  t.innerHTML='<thead><tr><th>رقم الأمر</th><th>المستودع</th><th>النوع</th><th>تاريخ البدء</th><th>تاريخ الإغلاق</th><th>الأصناف</th><th>الفروقات</th><th>الحالة</th></tr></thead><tbody>'+
   rows.map(function(o){var cd=o.closedDate||(o.closedAt&&o.closedAt.seconds?new Date(o.closedAt.seconds*1000).toISOString().slice(0,10):'');
     return '<tr class="stk-row-click" data-o="'+o.id+'" title="عرض الفروقات"><td><b>'+E(o.orderNo||('#'+o.id.slice(0,6)))+'</b></td><td>'+E(o.warehouse||'—')+'</td><td>'+E(TYPE[o.type]||o.type||'')+'</td><td>'+E(o.date||'')+'</td><td>'+E(cd||'—')+'</td>'+
       '<td>'+N(o.itemsCount||0)+'</td><td>'+(o.varianceCount!=null?N(o.varianceCount):'—')+'</td><td><span class="chip '+(STATUS_CHIP[o.status]||'chip-code')+'">'+E(STATUS[o.status]||o.status)+'</span></td></tr>';}).join('')+'</tbody>';
  [].forEach.call(t.querySelectorAll('[data-o]'),function(r){r.onclick=function(){S.cur=r.dataset.o;go('analysis');};});
}

/* ───── تجميد المستودع: منع الحركات أثناء الجرد ───── */
async function frozenOrder(wh){
  if(!wh)return null;
  try{var s=await db.collection('stocktakes').where('status','==','COUNTING').limit(200).get();
    var f=s.docs.map(function(x){return x.data();}).filter(function(o){return o.freeze&&o.warehouse===wh;});return f[0]||null;}catch(e){return null;}
}
var GUARDS=[['rcSave',['rWh']],['issSubmit',['isWh']],['trfSend',['trWhFrom','trWhTo']],['retSaveUnit',['ruWh']],['retSaveSupplier',['rsWh']]];
function wrapGuards(){
  GUARDS.forEach(function(g){var orig=window[g[0]];if(typeof orig!=='function'||orig.__stkFreeze)return;
    var w=async function(){var self=this,args=arguments;
      for(var i=0;i<g[1].length;i++){var el=$(g[1][i]),o=await frozenOrder(el&&el.value);
        if(o){T('✖ المستودع «'+o.warehouse+'» مجمّد بسبب أمر الجرد '+(o.orderNo||'')+' — لا يمكن تنفيذ الحركة حتى اعتماد الجرد أو إلغائه');return;}}
      return orig.apply(self,args);};
    w.__stkFreeze=1;window[g[0]]=w;});
}
function install(){window.renderStocktake=renderStocktake2;wrapGuards();}
/* بعد تنفيذ كل السكربتات (DOMContentLoaded) لا عند load: load قد يتأخر كثيرًا دون إنترنت بسبب الخطوط */
if(d.readyState!=='loading')install();else d.addEventListener('DOMContentLoaded',install);
window.IMDAD_STOCKTAKE={state:S,split:split,unitsOf:unitsOf,frozenOrder:frozenOrder};
})();
