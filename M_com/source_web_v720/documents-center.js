/* IMDAD Documents Registry v1 — سجل المستندات المخزنية
   عرض وإعادة طباعة وتعديل وإلغاء مستندات: الاستلام، الصرف، التحويل، المرتجعات.
   - الصلاحيات: view/print/edit/delete لكل نوع حسب شاشته (receive/issue/transfer/returns).
   - النطاق: لا يظهر ولا يُعدَّل إلا ما يخص مستودعات المستخدم (IMDAD_ACCESS.canWh).
   - الأرصدة: التعديل والإلغاء يطبقان الفرق فقط على رصيد الصنف، ويُمنعان على مستودع مجمّد للجرد.
   - كل تعديل/إلغاء يُسجَّل في المستند (editLog) وفي سجل التدقيق. */
(function(){
'use strict';
var d=document;
function $(id){return d.getElementById(id);}
function ic(n){return window.IMDAD_ICON?window.IMDAD_ICON(n):'';}
function E(s){return (typeof esc==='function')?esc(s):String(s==null?'':s);}
function N(n){return (Math.round((+n||0)*1000)/1000).toLocaleString('ar-EG');}
function T(m){if(typeof toast==='function')toast(m);}
function email(){try{return me.state?me.state.email:'';}catch(e){return '';}}
function today(){return new Date().toISOString().slice(0,10);}
function P(page,action){try{return hasPerm(page,action);}catch(e){return false;}}
function canWh(wh){return !window.IMDAD_ACCESS||IMDAD_ACCESS.canWh(wh);}
async function audit(a,s,x){try{await auditWrite(a,'document',s,x||{});}catch(e){}}

/* تسجيل الشاشة في كتالوج الصلاحيات */
try{PERM_CATALOG.documents={label:'سجل المستندات (السندات المحفوظة)',actions:['view','print','edit','delete']};DEFAULT_USER_PERMS.documents={view:true,print:false,edit:false,delete:false};}catch(e){}

var TYPES={
  receipt:{col:'receipts',perm:'receive',label:'استلام بضاعة',icon:'download',party:'supplier',partyLbl:'المورد',whs:['warehouse'],
    sign:function(f){return f.status==='COMPLETED'?1:0;},editable:function(){return true;}},
  issue:{col:'issues',perm:'issue',label:'صرف بضاعة',icon:'upload',party:'recipientDisplay',partyLbl:'الجهة المستفيدة',whs:['warehouse'],
    sign:function(f){return f.status==='COMPLETED'?-1:0;},editable:function(){return true;}},
  transfer:{col:'transfers',perm:'transfer',label:'تحويل مخزني',icon:'repeat',party:'destWarehouse',partyLbl:'إلى المستودع',whs:['warehouse','destWarehouse'],
    sign:function(){return 0;},editable:function(f){return f.status==='PENDING';}},
  ret:{col:'returns',perm:'returns',label:'مرتجعات',icon:'undo',party:'party',partyLbl:'الجهة',whs:['warehouse'],
    sign:function(f){if(f.status==='CANCELLED')return 0;return f.type==='TO_SUPPLIER'?-1:(f.condition==='تالفة'?0:1);},editable:function(){return true;}}
};
var STATUS={COMPLETED:'معتمد',DRAFT:'مسودة',ORDER:'أمر معلق',PENDING:'قيد الاستلام',RECEIVED:'مستلم',REJECTED:'مرفوض',CANCELLED:'ملغى'};
var STATUS_CHIP={COMPLETED:'chip-ok',RECEIVED:'chip-ok',DRAFT:'chip-off',ORDER:'chip-pend',PENDING:'chip-pend',REJECTED:'chip-err',CANCELLED:'chip-err'};

var R=window.DOCS_STATE=window.DOCS_STATE||{type:'',from:'',to:'',wh:'',status:'',q:'',groups:[],items:[],whs:[],sups:[]};

function DP(a){return P('documents',a);}
function allowedTypes(){return Object.keys(TYPES).filter(function(k){return P(TYPES[k].perm,'view')||DP('view');});}
function inScope(f,t){return TYPES[t].whs.some(function(k){return f[k]&&canWh(f[k]);});}
function dOf(r){if(r.date)return String(r.date).slice(0,10);var s=r.createdAt&&r.createdAt.seconds;return s?new Date(s*1000).toISOString().slice(0,10):'';}

async function getAll(col,limit){try{var s=await db.collection(col).limit(limit||5000).get();return s.docs.map(function(x){var o=x.data()||{};o.id=x.id;return o;});}catch(e){return [];}}
async function load(){
  var types=allowedTypes();
  var res=await Promise.all(types.map(function(t){return getAll(TYPES[t].col);}).concat([getAll('items',3000),getAll('warehouses',500),getAll('suppliers',1000)]));
  var groups=[];
  types.forEach(function(t,i){var map={};
    res[i].forEach(function(doc){var k=(doc.refNo?doc.refNo:'_'+doc.id)+(t==='ret'?'|'+(doc.type||''):'');(map[k]=map[k]||[]).push(doc);});
    Object.keys(map).forEach(function(k){var lines=map[k],f=lines[0];if(!inScope(f,t))return;
      groups.push({key:t+':'+k,t:t,ref:f.refNo||'—',date:dOf(f),wh:f.warehouse||'',party:f[TYPES[t].party]||'',status:f.status||(t==='ret'?'COMPLETED':''),
        by:f.createdBy||'',lines:lines,edits:+f.editCount||0,ts:(f.createdAt&&f.createdAt.seconds)||0});});
  });
  groups.sort(function(a,b){return a.date<b.date?1:a.date>b.date?-1:b.ts-a.ts;});
  R.groups=groups;R.items=res[types.length];R.whs=res[types.length+1];R.sups=res[types.length+2];
}
function itemById(id){return R.items.filter(function(x){return x.id===id;})[0]||null;}
function unitsOf(it){return (it&&it.units&&it.units.length)?it.units.map(function(u){return {name:u.name,f:+u.factor||1};}):[{name:(it&&it.baseUnit)||'وحدة',f:1}];}
function statusLbl(g){var s=g.status;if(g.t==='ret'&&s!=='CANCELLED')return g.lines[0].type==='TO_SUPPLIER'?'إلى مورد':('من وحدة — '+(g.lines[0].condition||''));return STATUS[s]||s||'—';}

/* ───── الواجهة ───── */
function css(){if($('docsCss'))return;var s=d.createElement('style');s.id='docsCss';s.textContent=
 '.docs-filters{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:10px 12px;align-items:end}.docs-filters label{display:block;font-size:12px;font-weight:600;margin-bottom:4px}'+
 '.docs-actions{display:flex;gap:6px;flex-wrap:wrap}.docs-actions .btn{padding:5px 10px;font-size:12.5px}'+
 '.docs-modal{max-width:980px;width:calc(100% - 24px);max-height:calc(100vh - 40px);overflow:auto}'+
 '.docs-head{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:10px;margin:10px 0}.docs-head label{display:block;font-size:12px;font-weight:600;margin-bottom:4px}'+
 '.docs-info{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:8px;margin:10px 0}.docs-info div{background:var(--ui-bg,#f7f7f8);border:1px solid var(--ui-line,#e3e3e8);border-radius:10px;padding:8px 10px}.docs-info small{display:block;color:var(--ui-muted,#5b5e6b);font-size:11.5px}'+
 '#docEditTbl .fld{margin:0;min-width:90px;padding:6px 8px}.docs-log{font-size:12.5px;color:var(--ui-muted,#5b5e6b);line-height:1.9}'+
 '.docs-empty{padding:26px;text-align:center;color:var(--ui-muted,#5b5e6b)}';d.head.appendChild(s);}

async function renderDocuments(){
  css();
  var types=allowedTypes();
  if(!types.length){$('main').innerHTML='<div class="page-title">'+ic('folder')+' سجل المستندات</div><div class="icard"><div class="ld">لا تملك صلاحية عرض أي نوع من المستندات.</div></div>';return;}
  $('main').innerHTML='<div class="page-title">'+ic('folder')+' سجل المستندات</div><div class="page-sub">عرض وطباعة وتعديل سندات الاستلام والصرف والتحويل والمرتجعات حسب صلاحياتك</div><div class="ld">جارٍ التحميل…</div>';
  await load();if(window.curPage!=='documents')return;
  if(R.type&&types.indexOf(R.type)<0)R.type='';
  var scope=window.IMDAD_ACCESS?IMDAD_ACCESS.scopeLabel():'';
  $('main').innerHTML='<div class="page-title">'+ic('folder')+' سجل المستندات</div>'+
   '<div class="page-sub">عرض وطباعة وتعديل سندات الاستلام والصرف والتحويل والمرتجعات حسب صلاحياتك'+(scope?' — نطاقك: <b>'+E(scope)+'</b>':'')+'</div>'+
   '<div class="panel"><div class="docs-filters">'+
    '<div><label for="dcType">نوع المستند</label><select class="fld" id="dcType"><option value="">الكل</option>'+types.map(function(t){return '<option value="'+t+'"'+(R.type===t?' selected':'')+'>'+TYPES[t].label+'</option>';}).join('')+'</select></div>'+
    '<div><label for="dcFrom">من تاريخ</label><input class="fld" type="date" id="dcFrom" value="'+E(R.from)+'"></div>'+
    '<div><label for="dcTo">إلى تاريخ</label><input class="fld" type="date" id="dcTo" value="'+E(R.to)+'"></div>'+
    '<div><label for="dcWh">المستودع</label><select class="fld" id="dcWh"><option value="">الكل</option>'+R.whs.filter(function(w){return canWh(w.name);}).map(function(w){return '<option value="'+E(w.name)+'"'+(R.wh===w.name?' selected':'')+'>'+E(w.name)+'</option>';}).join('')+'</select></div>'+
    '<div><label for="dcStatus">الحالة</label><select class="fld" id="dcStatus"><option value="">الكل (بدون الملغى)</option>'+Object.keys(STATUS).map(function(k){return '<option value="'+k+'"'+(R.status===k?' selected':'')+'>'+STATUS[k]+'</option>';}).join('')+'</select></div>'+
    '<div><label for="dcQ">بحث</label><input class="fld" id="dcQ" placeholder="رقم السند، الجهة، الصنف…" value="'+E(R.q)+'"></div>'+
   '</div><div class="stk-foot" style="display:flex;gap:8px;margin-top:12px"><button class="btn btn-o btn-sm" id="dcRefresh" type="button">'+ic('refresh')+' تحديث</button><span class="chip chip-ok" id="dcCount"></span></div></div>'+
   '<div class="twrap"><table class="u" id="dcTbl"></table></div>';
  [['dcType','type'],['dcFrom','from'],['dcTo','to'],['dcWh','wh'],['dcStatus','status']].forEach(function(p){$(p[0]).onchange=function(){R[p[1]]=this.value;paint();};});
  $('dcQ').oninput=function(){R.q=this.value.trim();paint();};
  $('dcRefresh').onclick=async function(){await load();paint();T('✔ تم التحديث');};
  paint();
}
function filtered(){
  var q=(R.q||'').toLowerCase();
  return R.groups.filter(function(g){
    if(R.type&&g.t!==R.type)return false;if(R.from&&g.date<R.from)return false;if(R.to&&g.date>R.to)return false;
    if(R.wh&&g.wh!==R.wh&&g.party!==R.wh)return false;
    if(R.status){if(g.status!==R.status)return false;}else if(g.status==='CANCELLED')return false;
    if(!q)return true;
    return [g.ref,g.party,g.wh,g.by].concat(g.lines.map(function(l){return l.itemName;})).some(function(v){return String(v||'').toLowerCase().indexOf(q)>=0;});
  });
}
function paint(){
  var t=$('dcTbl');if(!t)return;var rows=filtered();$('dcCount').textContent='المستندات: '+N(rows.length);
  if(!rows.length){t.innerHTML='<tbody><tr><td class="docs-empty">لا توجد مستندات مطابقة</td></tr></tbody>';return;}
  t.innerHTML='<thead><tr><th>النوع</th><th>رقم السند</th><th>التاريخ</th><th>المستودع</th><th>الجهة</th><th>الأصناف</th><th>الحالة</th><th>المُنشئ</th><th>إجراءات</th></tr></thead><tbody>'+
   rows.slice(0,1500).map(function(g){var ty=TYPES[g.t],pm=ty.perm,live=g.status!=='CANCELLED';
     var mine=canWh(g.wh),canEdit=live&&mine&&(DP('edit')||P(pm,'edit'))&&ty.editable(g.lines[0]),canDel=live&&mine&&(DP('delete')||P(pm,'delete')),canPrint=DP('print')||P(pm,'print');
     return '<tr><td>'+ic(ty.icon)+' '+ty.label+'</td><td><b>'+E(g.ref)+'</b>'+(g.edits?' <span class="chip chip-code" title="عدد التعديلات">معدّل '+N(g.edits)+'</span>':'')+'</td><td>'+E(g.date||'—')+'</td><td>'+E(g.wh||'—')+'</td><td>'+E(g.party||'—')+'</td><td>'+N(g.lines.length)+'</td>'+
      '<td><span class="chip '+(STATUS_CHIP[g.status]||'chip-code')+'">'+E(statusLbl(g))+'</span></td><td>'+E(g.by||'—')+'</td>'+
      '<td><div class="docs-actions"><button class="btn btn-o" data-act="view" data-k="'+E(g.key)+'" type="button">'+ic('eye')+' عرض</button>'+
      (canPrint?'<button class="btn btn-o" data-act="print" data-k="'+E(g.key)+'" type="button">'+ic('printer')+' طباعة</button>':'')+
      (canEdit?'<button class="btn btn-p" data-act="edit" data-k="'+E(g.key)+'" type="button">'+ic('edit')+' تعديل</button>':'')+
      (canDel?'<button class="btn btn-d" data-act="cancel" data-k="'+E(g.key)+'" type="button">'+ic('ban')+' إلغاء</button>':'')+'</div></td></tr>';}).join('')+'</tbody>';
  [].forEach.call(t.querySelectorAll('[data-act]'),function(b){b.onclick=function(){var g=R.groups.filter(function(x){return x.key===b.dataset.k;})[0];if(!g)return;
    ({view:viewDoc,print:printDoc,edit:editDoc,cancel:cancelDoc})[b.dataset.act](g);};});
}

/* ───── عرض ───── */
function modal(html){var ov=d.createElement('div');ov.className='ovl';ov.style.cssText='display:flex;align-items:flex-start;justify-content:center;padding:20px 0;position:fixed;inset:0;z-index:9999;overflow:auto';
  ov.innerHTML='<div class="modal docs-modal" role="dialog" aria-modal="true">'+html+'</div>';d.body.appendChild(ov);
  ov.addEventListener('click',function(e){if(e.target===ov)ov.remove();});return ov;}
function viewDoc(g){
  var ty=TYPES[g.t],f=g.lines[0],log=[];g.lines.forEach(function(l){(l.editLog||[]).forEach(function(x){log.push(x);});});
  var seen={};log=log.filter(function(x){var k=x.at+x.summary;if(seen[k])return false;seen[k]=1;return true;});
  var ov=modal('<div style="display:flex;justify-content:space-between;align-items:center;gap:8px"><h3>'+ic(ty.icon)+' '+ty.label+' — '+E(g.ref)+'</h3><button class="btn btn-o btn-sm" data-close type="button">إغلاق</button></div>'+
   '<div class="docs-info"><div><small>التاريخ</small><b>'+E(g.date||'—')+'</b></div><div><small>المستودع</small><b>'+E(g.wh||'—')+'</b></div><div><small>'+ty.partyLbl+'</small><b>'+E(g.party||'—')+'</b></div>'+
   '<div><small>الحالة</small><b>'+E(statusLbl(g))+'</b></div><div><small>المُنشئ</small><b>'+E(g.by||'—')+'</b></div><div><small>ملاحظات</small><b>'+E(f.notes||'—')+'</b></div></div>'+
   '<div class="twrap"><table class="u"><thead><tr><th>م</th><th>الكود</th><th>الصنف</th><th>الكمية</th><th>الوحدة</th><th>بوحدة الأساس</th>'+(g.t==='issue'?'<th>المستفيد</th>':'')+'<th>ملاحظات</th></tr></thead><tbody>'+
   g.lines.map(function(l,i){var it=itemById(l.itemId);return '<tr><td>'+(i+1)+'</td><td>'+E(l.itemCode||'')+'</td><td>'+E(l.itemName)+'</td><td>'+N(l.qty)+'</td><td>'+E(l.unitName||'')+'</td><td>'+N(l.baseQty)+' '+E(it&&it.baseUnit||'')+'</td>'+
     (g.t==='issue'?'<td>'+E(l.beneficiaryUnitName||'—')+'</td>':'')+'<td>'+E(l.notes||'—')+'</td></tr>';}).join('')+'</tbody></table></div>'+
   (log.length?'<h4 style="margin-top:14px">'+ic('clock')+' سجل التعديلات</h4><div class="docs-log">'+log.map(function(x){return E(x.at)+' — '+E(x.by)+': '+E(x.summary);}).join('<br>')+'</div>':'')+
   (f.cancelReason?'<div class="note-box" style="margin-top:10px">سبب الإلغاء: '+E(f.cancelReason)+'</div>':''));
  ov.querySelector('[data-close]').onclick=function(){ov.remove();};
}

/* ───── طباعة من البيانات المحفوظة ───── */
function printDoc(g){
  var ty=TYPES[g.t];if(!(DP('print')||P(ty.perm,'print')))return T('✖ لا تملك صلاحية طباعة المستندات المحفوظة');
  var f=g.lines[0],rows6=g.lines.map(function(l,i){return [String(i+1),E(l.itemCode||''),E(l.itemName),N(l.qty),E(l.unitName||''),E(l.notes||'—')];});
  try{
    if(g.t==='receipt')militaryPrint.printReceiveVoucher({warehouse:E(f.warehouse||'—'),ref:E(f.refNo||'—'),supplier:E(f.supplier||'—'),date:E(f.date||'—'),invoiceNo:E(f.invoiceNo||'—'),notes:E(f.notes||'—'),committee:E(f.committee||'—'),supervision:E(f.supervision||'—'),audit:E(f.audit||'—')},rows6);
    else if(g.t==='issue'){var days=+f.durationDays||1,end='—';try{var dt=new Date(f.date);dt.setDate(dt.getDate()+days-1);end=dt.toISOString().slice(0,10);}catch(e){}
      var multi=f.targetType===3;
      militaryPrint.printIssueVoucher({warehouse:E(f.warehouse||'—'),beneficiary:E(f.recipientDisplay||'—'),strength:String(f.soldierCount||'—'),days:String(days),start_date:E(f.date||'—'),end_date:end,ref:E(f.refNo||'—'),notes:E(f.notes||'—'),is_multi_unit:multi},
        multi?g.lines.map(function(l,i){return [String(i+1),E(l.itemName),N(l.qty),E(l.unitName||''),E(l.beneficiaryUnitName||'—'),E(l.notes||'—')];}):rows6);}
    else if(g.t==='transfer')militaryPrint.printTransferVoucher({warehouse:E(f.warehouse||'—'),destWarehouse:E(f.destWarehouse||'—'),ref:E(f.refNo||'—'),date:E(f.date||'—'),notes:E(f.notes||'—'),statusLabel:E(STATUS[f.status]||f.status||'')},
      g.lines.map(function(l,i){return [String(i+1),E(l.itemCode||''),E(l.itemName),N(l.qty),E(l.unitName||''),'—'];}));
    else{var isU=f.type!=='TO_SUPPLIER';
      militaryPrint.printReturnVoucher(isU?{warehouse:E(f.warehouse||'—'),party:E(f.party||'—'),date:E(f.date||'—'),ref:E(f.refNo||'—'),condition:E(f.condition||'—'),notes:E(f.notes||'—')}
        :{warehouse:E(f.warehouse||'—'),party:E(f.party||'—'),date:E(f.date||'—'),ref:E(f.refNo||'—'),origRef:E(f.origRef||'—'),notes:E(f.notes||'—')},
        g.lines.map(function(l,i){return [String(i+1),E(l.itemCode||''),E(l.itemName),N(l.qty),E(l.unitName||''),'—'];}),isU);}
  }catch(e){T('✖ خدمة الطباعة غير متاحة: '+e.message);}
}

/* ───── فحوص مشتركة للتعديل والإلغاء ───── */
async function checkWrite(g,action,newWh){
  var ty=TYPES[g.t];
  if(!(DP(action)||P(ty.perm,action))){T('✖ لا تملك صلاحية '+(action==='edit'?'تعديل':'إلغاء')+' المستندات المحفوظة ('+ty.label+')');return false;}
  var whs=ty.whs.map(function(k){return g.lines[0][k];}).concat(newWh?[newWh]:[]).filter(Boolean);
  var src=g.t==='transfer'?[g.lines[0].warehouse].concat(newWh?[newWh]:[]):whs;
  for(var i=0;i<src.length;i++){if(!canWh(src[i])){T('✖ المستودع «'+src[i]+'» خارج نطاق صلاحياتك');return false;}}
  if(window.IMDAD_STOCKTAKE){for(var j=0;j<whs.length;j++){var o=await IMDAD_STOCKTAKE.frozenOrder(whs[j]);if(o){T('✖ المستودع «'+whs[j]+'» مجمّد بسبب الجرد '+(o.orderNo||''));return false;}}}
  return true;
}
function effect(lines,sign){var m={};if(!sign)return m;lines.forEach(function(l){if(l.itemId)m[l.itemId]=(m[l.itemId]||0)+sign*(+l.baseQty||0);});return m;}

/* ───── تعديل ───── */
function editDoc(g){
  var ty=TYPES[g.t],f=g.lines[0];if(!ty.editable(f))return T('✖ لا يمكن تعديل هذا المستند في حالته الحالية');
  var whOpts=function(sel){return R.whs.filter(function(w){return canWh(w.name)||w.name===sel;}).map(function(w){return '<option value="'+E(w.name)+'"'+(w.name===sel?' selected':'')+'>'+E(w.name)+'</option>';}).join('');};
  var partyField=g.t==='transfer'?'<select class="fld" id="deParty">'+R.whs.map(function(w){return '<option value="'+E(w.name)+'"'+(w.name===f.destWarehouse?' selected':'')+'>'+E(w.name)+'</option>';}).join('')+'</select>'
    :(g.t==='receipt'||f.type==='TO_SUPPLIER')?'<input class="fld" id="deParty" list="deSupList" value="'+E(f[ty.party]||'')+'"><datalist id="deSupList">'+R.sups.map(function(s){return '<option value="'+E(s.name)+'">';}).join('')+'</datalist>'
    :'<input class="fld" id="deParty" value="'+E(f[ty.party]||'')+'">';
  var ov=modal('<div style="display:flex;justify-content:space-between;align-items:center;gap:8px"><h3>'+ic('edit')+' تعديل '+ty.label+' — '+E(g.ref)+'</h3><button class="btn btn-o btn-sm" data-close type="button">إغلاق</button></div>'+
   (ty.sign(f)?'<div class="note-box">المستند '+E(statusLbl(g))+': سيُطبَّق فرق الكميات فقط على الأرصدة عند الحفظ.</div>':'')+
   '<div class="docs-head"><div><label for="deDate">التاريخ</label><input class="fld" type="date" id="deDate" value="'+E(f.date||'')+'"></div>'+
   '<div><label for="deWh">'+(g.t==='transfer'?'من المستودع':'المستودع')+'</label><select class="fld" id="deWh">'+whOpts(f.warehouse)+'</select></div>'+
   '<div><label for="deParty">'+ty.partyLbl+'</label>'+partyField+'</div>'+
   '<div><label for="deNotes">ملاحظات</label><input class="fld" id="deNotes" value="'+E(f.notes||'')+'"></div>'+
   '<div style="grid-column:1/-1"><label for="deReason">سبب التعديل *</label><input class="fld" id="deReason" placeholder="مطلوب لسجل التدقيق"></div></div>'+
   '<div class="twrap"><table class="u" id="docEditTbl"><thead><tr><th>الصنف</th><th>الوحدة</th><th>الكمية</th><th>ملاحظات</th><th></th></tr></thead><tbody></tbody></table></div>'+
   '<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:10px"><button class="btn btn-o btn-sm" id="deAdd" type="button">'+ic('plus')+' إضافة سطر</button></div>'+
   '<div class="sticky-actions" style="display:flex;gap:8px;margin-top:14px"><button class="btn btn-p" id="deSave" type="button">'+ic('save')+' حفظ التعديلات</button><button class="btn btn-o" data-close type="button">إلغاء</button></div>');
  [].forEach.call(ov.querySelectorAll('[data-close]'),function(b){b.onclick=function(){ov.remove();};});
  var tb=ov.querySelector('#docEditTbl tbody');
  function addRow(l){l=l||{};var tr=d.createElement('tr');tr._line=l.id?l:null;
    tr.innerHTML='<td><select class="fld deItem" aria-label="الصنف"><option value="">— اختر —</option>'+R.items.map(function(it){return '<option value="'+it.id+'"'+(it.id===l.itemId?' selected':'')+'>'+E((it.code?it.code+' — ':'')+it.name)+'</option>';}).join('')+'</select></td>'+
      '<td><select class="fld deUnit" aria-label="الوحدة"></select></td><td><input class="fld deQty" type="number" min="0" step="any" value="'+(l.qty!=null?l.qty:'')+'" aria-label="الكمية"></td>'+
      '<td><input class="fld deNote" value="'+E(l.notes||'')+'" aria-label="ملاحظات السطر"></td><td><button class="btn btn-d btn-sm deDel" type="button" aria-label="حذف السطر">'+ic('trash')+'</button></td>';
    var si=tr.querySelector('.deItem'),su=tr.querySelector('.deUnit');
    var fill=function(sel){var it=itemById(si.value);su.innerHTML=unitsOf(it).map(function(u){return '<option value="'+E(u.name)+'" data-f="'+u.f+'"'+(u.name===sel?' selected':'')+'>'+E(u.name)+(u.f!==1?' ×'+N(u.f):'')+'</option>';}).join('');};
    fill(l.unitName);si.onchange=function(){fill();};tr.querySelector('.deDel').onclick=function(){tr.remove();};tb.appendChild(tr);}
  g.lines.forEach(addRow);ov.querySelector('#deAdd').onclick=function(){addRow();};
  ov.querySelector('#deSave').onclick=async function(){
    var btn=this,reason=ov.querySelector('#deReason').value.trim();if(!reason)return T('✖ اكتب سبب التعديل');
    var newWh=ov.querySelector('#deWh').value,party=ov.querySelector('#deParty').value.trim();
    if(g.t==='transfer'&&party===newWh)return T('✖ لا يمكن التحويل إلى نفس المستودع');
    var rows=[],err='';
    [].forEach.call(tb.querySelectorAll('tr'),function(tr){if(err)return;var id=tr.querySelector('.deItem').value;if(!id)return;var it=itemById(id),o=tr.querySelector('.deUnit').selectedOptions[0];
      var q=+tr.querySelector('.deQty').value;if(!(q>0)){err='✖ كمية غير صالحة للصنف '+(it?it.name:'');return;}var fct=o?+o.dataset.f||1:1;
      var old=tr._line||g.lines.filter(function(x){return x.itemId===id;})[0]||{};
      rows.push({itemId:id,itemCode:it.code||'',itemName:it.name||'',unitName:o?o.value:(it.baseUnit||''),factor:fct,qty:q,baseQty:Math.round(q*fct*1000)/1000,notes:tr.querySelector('.deNote').value.trim(),
        beneficiaryUnitId:old.beneficiaryUnitId||null,beneficiaryUnitName:old.beneficiaryUnitName||null,cylinderAction:old.cylinderAction||''});});
    if(err)return T(err);if(!rows.length)return T('✖ يجب أن يحتوي المستند على صنف واحد على الأقل');
    if(!(await checkWrite(g,'edit',newWh)))return;
    var sign=ty.sign(f),before=effect(g.lines,sign),after=effect(rows,sign),delta={};
    Object.keys(before).concat(Object.keys(after)).forEach(function(k){var v=Math.round(((after[k]||0)-(before[k]||0))*1000)/1000;if(v)delta[k]=v;});
    for(var k in delta){if(delta[k]<0){var it=itemById(k),have=+(it&&it.qty)||0;if(have+delta[k]<-1e-9)return T('✖ الرصيد لا يكفي للصنف «'+(it?it.name:k)+'» (المتاح '+N(have)+')');}}
    btn.disabled=true;
    try{
      var master={};Object.keys(f).forEach(function(key){if(['id','itemId','itemCode','itemName','unitName','factor','qty','baseQty','notes','beneficiaryUnitId','beneficiaryUnitName','cylinderAction','editLog'].indexOf(key)<0)master[key]=f[key];});
      master.date=ov.querySelector('#deDate').value||f.date;master.warehouse=newWh;master[ty.party]=party;if(g.t==='issue'&&f.recipientDisplay!==party)master.recipientDisplay=party;
      var noteHead=ov.querySelector('#deNotes').value.trim();
      var summary='تعديل: '+g.lines.length+' سطر → '+rows.length+' سطر'+(Object.keys(delta).length?'، فروقات أرصدة على '+Object.keys(delta).length+' صنف':'')+' — السبب: '+reason;
      var log=(f.editLog||[]).concat([{at:new Date().toISOString().replace('T',' ').slice(0,16),by:email(),summary:summary}]);
      var batch=db.batch();
      g.lines.forEach(function(l){batch.delete(db.collection(ty.col).doc(l.id));});
      rows.forEach(function(r){var docData=Object.assign({},master,r,{editCount:(+f.editCount||0)+1,editedAt:ST(),editedBy:email(),editLog:log});
        if(g.t!=='issue'){delete docData.beneficiaryUnitId;delete docData.beneficiaryUnitName;}
        docData.notes=r.notes||noteHead;batch.set(db.collection(ty.col).doc(),docData);});
      Object.keys(delta).forEach(function(k){batch.update(db.collection('items').doc(k),{qty:firebase.firestore.FieldValue.increment(delta[k])});});
      await batch.commit();
      await audit('DOCUMENT_EDITED','تعديل '+ty.label+' '+g.ref,{refNo:g.ref,docType:ty.col,warehouse:newWh,target:party,itemCount:rows.length,reason:reason,stockDelta:delta,risk:'critical'});
      T('✔ حُفظ تعديل المستند '+g.ref);ov.remove();await load();paint();
    }catch(e){btn.disabled=false;T('✖ '+(e.code||e.message));}
  };
}

/* ───── إلغاء ───── */
async function cancelDoc(g){
  var ty=TYPES[g.t],f=g.lines[0];
  if(!(await checkWrite(g,'delete')))return;
  var sign=ty.sign(f),eff=effect(g.lines,sign);
  var why=prompt('إلغاء '+ty.label+' «'+g.ref+'»'+(sign?' سيعكس أثره على الأرصدة':'')+'.\nاكتب سبب الإلغاء:','');if(why===null)return;
  if(!why.trim())return T('✖ سبب الإلغاء مطلوب');
  try{
    var batch=db.batch(),log=(f.editLog||[]).concat([{at:new Date().toISOString().replace('T',' ').slice(0,16),by:email(),summary:'إلغاء المستند — السبب: '+why.trim()}]);
    g.lines.forEach(function(l){batch.update(db.collection(ty.col).doc(l.id),{status:'CANCELLED',prevStatus:l.status||'',cancelReason:why.trim(),cancelledBy:email(),cancelledAt:ST(),editLog:log});});
    Object.keys(eff).forEach(function(k){if(eff[k])batch.update(db.collection('items').doc(k),{qty:firebase.firestore.FieldValue.increment(-eff[k])});});
    await batch.commit();
    await audit('DOCUMENT_CANCELLED','إلغاء '+ty.label+' '+g.ref,{refNo:g.ref,docType:ty.col,warehouse:f.warehouse||'',reason:why.trim(),itemCount:g.lines.length,risk:'critical'});
    T('✔ أُلغي المستند '+g.ref+(sign?' وعُكس أثره على الأرصدة':''));await load();paint();
  }catch(e){T('✖ '+(e.code||e.message));}
}

window.renderDocuments=renderDocuments;
window.IMDAD_DOCUMENTS={types:TYPES,state:R,load:load,effect:effect};
})();
