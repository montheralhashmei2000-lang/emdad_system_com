/* IMDAD Stock Ledger v1 — رصيد مستقل لكل مستودع
   رصيد الصنف في المستودع = الرصيد الافتتاحي لذلك المستودع + الوارد + المرتجع الصالح من الوحدات
     + التحويلات المستلمة إليه − المنصرف − المرتجع إلى الموردين − التحويلات الصادرة منه.
   يُستخدم في: عرض الرصيد داخل سطور الإدخال، فحص كفاية الرصيد قبل الصرف/التحويل/الإرجاع،
   وشاشة الأرصدة الحالية (مع محدد المستودع). رصيد الصنف الإجمالي يبقى كما هو في شاشة الأصناف. */
(function(){
'use strict';
var d=document;
function $(id){return d.getElementById(id);}
function E(s){return (typeof esc==='function')?esc(s):String(s==null?'':s);}
function N(n){return (typeof nf==='function')?nf(Math.round((+n||0)*1000)/1000):String(n);}
function T(m){if(typeof toast==='function')toast(m);}
var ACTIVE={DRAFT:0,ORDER:0,CANCELLED:0,REJECTED:0};
function live(st){return ACTIVE[st]!==0;}

var cache={at:0,map:null,whs:null};
function invalidate(){cache.map=null;}
async function all(col){try{var s=await db.collection(col).limit(20000).get();return s.docs.map(function(x){var o=x.data()||{};o.id=x.id;return o;});}catch(e){return [];}}
/* map[warehouse][itemId] = رصيد */
async function build(){
  if(cache.map&&Date.now()-cache.at<5000)return cache.map;
  var r=await Promise.all([all('receipts'),all('issues'),all('transfers'),all('returns'),all('openingBalances'),all('warehouses')]);
  var map={},whs=r[5].map(function(w){return w.name;}).filter(Boolean);
  function add(wh,item,q){if(!wh||!item||!q)return;(map[wh]=map[wh]||{});map[wh][item]=Math.round(((map[wh][item]||0)+q)*1000)/1000;}
  r[4].forEach(function(o){add(o.warehouse||'',o.itemId,+o.qty||0);});                       /* افتتاحي */
  r[0].forEach(function(x){if(live(x.status))add(x.warehouse,x.itemId,+x.baseQty||0);});      /* وارد */
  r[1].forEach(function(x){if(live(x.status))add(x.warehouse,x.itemId,-(+x.baseQty||0));});   /* منصرف */
  r[3].forEach(function(x){if(!live(x.status))return;                                         /* مرتجعات */
    if(x.type==='TO_SUPPLIER')add(x.warehouse,x.itemId,-(+x.baseQty||0));
    else if(x.condition!=='تالفة')add(x.warehouse,x.itemId,+x.baseQty||0);});
  r[2].forEach(function(x){if(x.status==='REJECTED'||x.status==='CANCELLED')return;           /* تحويلات */
    add(x.warehouse,x.itemId,-(+x.baseQty||0));
    if(x.status==='RECEIVED')add(x.destWarehouse,x.itemId,+x.baseQty||0);});
  cache.map=map;cache.whs=whs;cache.at=Date.now();
  return map;
}
async function balances(wh){var m=await build();
  if(wh)return Object.assign({},m[wh]||{});
  var out={};Object.keys(m).forEach(function(w){Object.keys(m[w]).forEach(function(i){out[i]=Math.round(((out[i]||0)+m[w][i])*1000)/1000;});});return out;}
async function balanceOf(itemId,wh){var b=await balances(wh);return +b[itemId]||0;}
/* نسخة متزامنة من آخر حساب (للاستخدام داخل الفحوص الحية) */
var SNAP={wh:'',map:{}};
async function snap(wh){SNAP.wh=wh||'';SNAP.map=await balances(wh);return SNAP.map;}
function snapQty(itemId){return +SNAP.map[itemId]||0;}

/* ───── المستودع الحالي في كل شاشة ───── */
var WH_OF={receive:'rWh',issue:'isWh',transfer:'trWhFrom',returns:null,stocktake:'stkWh'};
function currentWh(){
  var p=window.curPage;
  if(p==='returns')return ($('ruWh')&&$('ruWh').offsetParent!==null?($('ruWh')||{}).value:($('rsWh')||{}).value)||'';
  var id=WH_OF[p];return id&&$(id)?$(id).value:'';
}
async function refreshSnap(){try{await snap(currentWh());}catch(e){}}

/* ───── فحص الكفاية حسب المستودع ───── */
function install(){
  var oErr=window.stockErrorFromMap;
  if(typeof oErr==='function'&&!oErr.__wh){
    var w=function(items,qtyMap){
      var wh=currentWh();
      if(!wh||!SNAP.map||SNAP.wh!==wh)return oErr(items,qtyMap);
      for(var id in (qtyMap||{})){var need=+qtyMap[id]||0;if(need<=0)continue;var have=snapQty(id);
        if(need>have+1e-9){var it=(items||[]).filter(function(x){return x.id===id;})[0]||{};
          return '✖ رصيد «'+(it.name||'')+'» في مستودع «'+wh+'» لا يكفي ('+N(have)+' '+(it.baseUnit||'')+' متاح، المطلوب '+N(need)+')';}}
      return '';
    };w.__wh=1;window.stockErrorFromMap=w;
  }
  /* فحص السطر الواحد في الصرف والمرتجع للمورد + عرض الرصيد */
  ['issCollect','retCollect','trfCollect','rcCollect'].forEach(function(n){
    var o=window[n];if(typeof o!=='function'||o.__wh)return;
    var w=function(){var res=o.apply(this,arguments);try{
      var wh=currentWh();
      if(wh&&SNAP.wh===wh&&res&&res.rows&&(n==='issCollect'||n==='trfCollect'||(n==='retCollect'&&arguments[1]))){
        var sum={};res.rows.forEach(function(r){if(r.itemId)sum[r.itemId]=(sum[r.itemId]||0)+(+r.baseQty||0);});
        for(var id in sum){if(sum[id]>snapQty(id)+1e-9){var nm=(res.rows.filter(function(r){return r.itemId===id;})[0]||{}).itemName||'';
          res.err='✖ رصيد «'+nm+'» في مستودع «'+wh+'» لا يكفي ('+N(snapQty(id))+' متاح)';break;}}
      }
    }catch(e){}return res;};
    w.__wh=1;window[n]=w;
  });
  /* تحديث اللقطة عند تغيير المستودع أو فتح الشاشة، وعرض رصيد المستودع في سطور الإدخال */
  d.addEventListener('change',function(e){var id=e.target&&e.target.id;
    if(id==='rWh'||id==='isWh'||id==='trWhFrom'||id==='ruWh'||id==='rsWh'||id==='stkWh'){refreshSnap().then(paintRowInfo);}},true);
  setInterval(function(){var p=window.curPage;if(['receive','issue','transfer','returns'].indexOf(p)<0)return;
    var wh=currentWh();if(wh&&SNAP.wh!==wh)refreshSnap().then(paintRowInfo);else paintRowInfo();},1200);
  wrapBalances();
  hookOpening();
  ['rcSave','issSubmit','trfSend','retSaveUnit','retSaveSupplier'].forEach(function(n){var o=window[n];if(typeof o!=='function'||o.__whInv)return;
    var w=async function(){var r=await o.apply(this,arguments);invalidate();refreshSnap();return r;};w.__whInv=1;window[n]=w;});
}
/* عرض رصيد المستودع بدل الرصيد الكلي داخل سطور الإدخال */
function paintRowInfo(){
  var wh=SNAP.wh;if(!wh)return;
  [['.rvrow .rItem','.rinfo'],['.rvrow .isItem','.isInfo'],['.rvrow .trItem','.trInfo'],['.rvrow .reItem','.reInfo']].forEach(function(p){
    [].forEach.call(d.querySelectorAll(p[0]),function(sel){
      var row=sel.closest('.rvrow'),info=row&&row.querySelector(p[1]);if(!info||!sel.value)return;
      var q=snapQty(sel.value),base='';
      try{var lists=[window.RC&&RC.items,window.ISS&&ISS.items,window.TRF&&TRF.items,window.RET&&RET.items];
        for(var i=0;i<lists.length;i++){var it=(lists[i]||[]).filter(function(x){return x.id===sel.value;})[0];if(it){base=it.baseUnit||'';break;}}}catch(e){}
      var txt='رصيد «'+wh+'»: '+N(q)+' '+base;
      if(info.dataset.whTxt!==txt){info.dataset.whTxt=txt;info.textContent=txt;}
    });
  });
}
/* شاشة الأرصدة: محدد المستودع */
function wrapBalances(){
  var o=window.balLoad;if(typeof o!=='function'||o.__wh)return;
  var w=async function(){
    await o.apply(this,arguments);
    try{
      var host=$('balChips');if(!host)return;
      if(!$('balWh')){
        var whs=[];try{var s=await db.collection('warehouses').limit(500).get();whs=s.docs.map(function(x){return x.data().name;}).filter(Boolean);}catch(e){}
        var AC=window.IMDAD_ACCESS;if(AC&&AC.scopeOf()!=='ALL')whs=whs.filter(function(n){return AC.canWh(n);});
        var box=d.createElement('div');box.style.cssText='display:flex;gap:8px;align-items:center;margin:8px 0';
        box.innerHTML='<label for="balWh" style="font-weight:600;font-size:13px">المستودع:</label>'+
          '<select class="fld" id="balWh" style="max-width:280px;margin:0"><option value="">الإجمالي (كل المستودعات)</option>'+
          whs.map(function(n){return '<option value="'+E(n)+'">'+E(n)+'</option>';}).join('')+'</select>';
        host.parentNode.insertBefore(box,host);
        $('balWh').onchange=function(){applyBal(this.value);};
      }
      await applyBal($('balWh')?$('balWh').value:'');
    }catch(e){}
  };w.__wh=1;window.balLoad=w;
}
async function applyBal(wh){
  var B;try{B=BAL;}catch(e){return;}if(!B||!Array.isArray(B.items))return;
  var m;
  var AC=window.IMDAD_ACCESS;
  if(!wh&&AC&&AC.scopeOf()!=='ALL'){ /* الإجمالي لمستخدم محدود = مجموع مستودعات نطاقه فقط */
    var full=await build();m={};Object.keys(full).forEach(function(w){if(!AC.canWh(w))return;Object.keys(full[w]).forEach(function(i){m[i]=Math.round(((m[i]||0)+full[w][i])*1000)/1000;});});
  } else m=await balances(wh);
  B.items.forEach(function(it){it.qty=Math.round((m[it.id]||0)*1000)/1000;});
  try{balPaint();}catch(e){}
  var AC2=window.IMDAD_ACCESS;var scoped=AC2&&AC2.scopeOf()!=='ALL';
  var chip=$(scoped?'balScopeChip':'balWhChip');var txt=wh?('أرصدة مستودع: '+wh):(scoped?('إجمالي مستودعات نطاقك: '+AC2.scopeLabel()):'الإجمالي: كل المستودعات');
  if(!chip){var c=$('balChips');if(c)c.insertAdjacentHTML('beforeend','<span class="chip '+(scoped?'chip-pend':'chip-code')+'" id="'+(scoped?'balScopeChip':'balWhChip')+'">'+E(txt)+'</span>');}
  else chip.textContent=txt;
}
/* الأرصدة الافتتاحية: ربطها بمستودع */
function hookOpening(){
  var o=window.opbPaint;if(typeof o!=='function'||o.__wh)return;
  var w=function(){var r=o.apply(this,arguments);try{addOpeningWh();}catch(e){}return r;};w.__wh=1;window.opbPaint=w;
  var ol=window.opbLoad;if(typeof ol==='function'&&!ol.__wh){var wl=async function(){var r=await ol.apply(this,arguments);try{addOpeningWh();}catch(e){}return r;};wl.__wh=1;window.opbLoad=wl;}
}
async function addOpeningWh(){
  if($('opWh')||!$('opbTbl'))return;
  var whs=[];try{var s=await db.collection('warehouses').limit(500).get();whs=s.docs.map(function(x){return x.data().name;}).filter(Boolean);}catch(e){}
  var AC=window.IMDAD_ACCESS;if(AC&&AC.scopeOf()!=='ALL')whs=whs.filter(function(n){return AC.canWh(n);});
  var bar=d.querySelector('#main .icard .rbar');if(!bar)return;
  var box=d.createElement('div');box.style.cssText='min-width:220px';
  box.innerHTML='<label for="opWh" style="font-size:11px;font-weight:700;display:block;margin-bottom:4px">المستودع *</label>'+
    '<select class="fld" id="opWh" style="margin:0">'+(whs.length?whs.map(function(n){return '<option value="'+E(n)+'">'+E(n)+'</option>';}).join(''):'<option value="">— لا توجد مستودعات —</option>')+'</select>';
  bar.insertBefore(box,bar.firstChild);
  var note=d.createElement('div');note.className='note-box';note.style.marginTop='8px';
  note.textContent='الرصيد الافتتاحي يُسجَّل للمستودع المحدد أعلاه، ويدخل في رصيد ذلك المستودع فقط.';
  bar.parentNode.appendChild(note);
  hookOpeningSave();
}
function hookOpeningSave(){
  var tbl=$('opbTbl');if(!tbl||tbl.dataset.whHook)return;tbl.dataset.whHook='1';
  tbl.addEventListener('click',function(e){
    var b=e.target.closest&&e.target.closest('[data-set]');if(!b)return;
    var wh=($('opWh')||{}).value||'';
    if(!wh){e.preventDefault();e.stopImmediatePropagation();T('✖ اختر المستودع قبل تثبيت الرصيد الافتتاحي');return;}
    setTimeout(function(){stampOpeningWh(b.dataset.set,wh);},1500);
  },true);
}
async function stampOpeningWh(itemId,wh){
  try{var s=await db.collection('openingBalances').where('itemId','==',itemId).limit(50).get();
    var docs=s.docs.map(function(x){return {id:x.id,ref:x.ref,d:x.data()};}).filter(function(x){return !x.d.warehouse;});
    if(!docs.length)return;var b=db.batch();docs.forEach(function(x){b.update(x.ref,{warehouse:wh});});await b.commit();invalidate();
  }catch(e){}
}
if(d.readyState!=='loading')install();else d.addEventListener('DOMContentLoaded',install);
window.IMDAD_STOCK={balances:balances,balanceOf:balanceOf,build:build,invalidate:invalidate,snap:snap,currentWh:currentWh};
})();
