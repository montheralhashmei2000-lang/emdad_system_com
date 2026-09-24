/* IMDAD Strength v2 — قوة يوم محدد فقط + استحقاق التحويل من قوة المعسكر المستلم
   المشكلة السابقة: عند غياب سجل لليوم تُؤخذ «آخر قوة مسجلة» من أي يوم، ويُجمع المعسكر مع وحداته
   (مثال: وحدات 15/9 = 660 + إجمالي المعسكر 14/9 = 5940 ⇒ 6600).
   القواعد الآن:
   - قوة المعسكر ليوم D = سجل «إجمالي المعسكر» لذلك اليوم، وإلا مجموع سجلات وحداته لذلك اليوم.
   - قوة الوحدة الفرعية ليوم D = سجلها لذلك اليوم، وإلا حصتها من إجمالي المعسكر لذلك اليوم، وإلا صفر.
   - قوة المطبخ/الفرن = المعسكرات المرتبطة به (مرة واحدة) + الوحدات المرتبطة التي لا يُحسب معسكرها.
   - التحويل: القوة = إجمالي قوة المعسكر المرتبط بالمستودع المستلم لتاريخ التفريدة. */
(function(){
'use strict';
var d=document;
function $(id){return d.getElementById(id);}
function T(m){if(typeof toast==='function')toast(m);}
function N(n){return (+n||0).toLocaleString('ar-EG');}
function val(v){return +(v.total!=null?v.total:(+v.soldierCount||0)+(+v.officerCount||0))||0;}

var cache={at:0,rows:null};
async function allStrengths(){
  if(cache.rows&&Date.now()-cache.at<4000)return cache.rows;
  try{var s=await db.collection('strengths').limit(20000).get();cache.rows=s.docs.map(function(x){return x.data();});}catch(e){cache.rows=[];}
  cache.at=Date.now();return cache.rows;
}
function day(v){return String(v.strengthDate||v.date||'').slice(0,10);}
function isCampRec(r){return r.mode==='camp'||(r.unitId&&r.unitId===r.campId);}

async function campStrengthOn(campId,date){
  if(!campId||!date)return {total:0,source:'none',units:0};
  var rows=(await allStrengths()).filter(function(r){return day(r)===date&&(r.campId===campId||r.unitId===campId);});
  var camp=rows.filter(isCampRec)[0];
  if(camp)return {total:val(camp),source:'camp',units:0};
  var det=rows.filter(function(r){return !isCampRec(r);});
  return {total:det.reduce(function(a,r){return a+val(r);},0),source:det.length?'units':'none',units:det.length};
}
async function unitStrengthOn(unitId,date,units){
  if(!unitId||!date)return 0;
  units=units||[];
  var u=units.filter(function(x){return x.id===unitId;})[0];
  var rows=await allStrengths();
  var own=rows.filter(function(r){return r.unitId===unitId&&day(r)===date&&!isCampRec(r);})[0];
  if(own)return val(own);
  /* الوحدة نفسها معسكر */
  if(u&&(!u.parentId||u.isCamp||u.type==='camp')&&units.some(function(x){return x.parentId===unitId;}))return (await campStrengthOn(unitId,date)).total;
  if(u&&!u.parentId){var campOnly=rows.filter(function(r){return r.unitId===unitId&&day(r)===date;})[0];return campOnly?val(campOnly):0;}
  if(u&&u.parentId){
    var camp=rows.filter(function(r){return (r.unitId===u.parentId||r.campId===u.parentId)&&day(r)===date&&isCampRec(r);})[0];
    if(camp){
      var sibs=units.filter(function(x){return x.parentId===u.parentId;});
      /* النسبة من آخر قوة معروفة لكل وحدة (للتوزيع فقط)، وإلا بالتساوي */
      var last=sibs.map(function(sb){var h=rows.filter(function(r){return r.unitId===sb.id&&!isCampRec(r);}).sort(function(a,b){return day(a)<day(b)?1:-1;})[0];return h?val(h):0;});
      var sum=last.reduce(function(a,b){return a+b;},0),i=sibs.map(function(x){return x.id;}).indexOf(unitId);
      var share=sum>0?last[i]/sum:1/(sibs.length||1);
      return Math.round(val(camp)*share);
    }
  }
  return 0;
}
async function facilityStrengthOn(fid,date,units){
  units=units||[];
  var linked=units.filter(function(u){return u.facilityId===fid;});if(!linked.length||!date)return 0;
  var campIds={};linked.forEach(function(u){var isCamp=!u.parentId||u.isCamp||u.type==='camp';if(isCamp)campIds[u.id]=1;});
  var total=0;
  for(var c in campIds)total+=(await campStrengthOn(c,date)).total;
  for(var i=0;i<linked.length;i++){var u=linked[i];if(campIds[u.id])continue;if(u.parentId&&campIds[u.parentId])continue;total+=await unitStrengthOn(u.id,date,units);}
  return total;
}

/* ───── ربط الدوال في الشاشات ───── */
function install(){
  window.unitStrengthOn=unitStrengthOn;
  window.klogFacilityStrength=function(fid,date){var us=[];try{us=KLOG.units;}catch(e){}return facilityStrengthOn(fid,date,us);};
  window.trfCampHeadcount=async function(campId,date){var r=await campStrengthOn(campId,date);var of=0;try{of=TRF.units.filter(function(u){return u.parentId===campId;}).length;}catch(e){}
    return {total:r.total,found:r.source==='camp'?1:r.units,of:r.source==='camp'?1:of,camp:r.source==='camp'};};
  var oIss=window.issFetchStrength;
  if(typeof oIss==='function'&&!oIss.__day){
    var w=async function(){
      var S;try{S=ISS;}catch(e){return oIss.apply(this,arguments);}
      var t=S.targetType;if(t!==0&&t!==1)return;
      var date=($('isStrDate')||{}).value||($('isDate')||{}).value||'',total=0;
      if(t===0){var uid=($('isBenUnit')||{}).value;if(!uid)return;total=await unitStrengthOn(uid,date,S.units);}
      else{var fid=($('isFacility')||{}).value;if(!fid)return;total=await facilityStrengthOn(fid,date,S.units);}
      S.currentStrength=total;if($('isStrCount'))$('isStrCount').value=total;
      note('isStrCount',total?'':'لا توجد تفريدة بتاريخ '+date+' — القوة صفر');
      try{issRecalcAllEntitlements();}catch(e){}
    };w.__day=1;window.issFetchStrength=w;
  }
  /* تغيير تاريخ حصر القوة في الصرف يعيد الحساب */
  d.addEventListener('change',function(e){if(e.target&&e.target.id==='isStrDate'&&typeof window.issFetchStrength==='function')window.issFetchStrength();},true);
  wrapTransfer();
}
function note(anchorId,text){var a=$(anchorId);if(!a)return;var id=anchorId+'DayNote',n=$(id);
  if(!n){n=d.createElement('div');n.id=id;n.style.cssText='font-size:11px;margin-top:3px;color:var(--ui-warn,#b54708)';a.parentNode.appendChild(n);}
  n.textContent=text||'';}

/* ───── التحويل: المعسكر من المستودع المستلم + الاستحقاق تلقائيًا ───── */
var TR_IDS={trWhTo:1,trCamp:1,trAcDate:1,trDate:1,trAcDays:1};
function campsForWh(name){var w=null;try{w=TRF.whs.filter(function(x){return x.name===name;})[0];}catch(e){}if(!w)return null;
  return {all:w.feedsAllCamps===true&&!(w.campIds&&w.campIds.length),ids:Array.isArray(w.campIds)?w.campIds:[]};}
function rowsEmpty(){var box=$('trRows');if(!box)return true;return ![].some.call(box.querySelectorAll('.trItem'),function(s){return s.value;});}
var busy=false;
async function trfAuto(trigger){
  if(busy)return;var wt=$('trWhTo'),cs=$('trCamp');if(!wt||!cs)return;busy=true;
  try{
    var link=campsForWh(wt.value),campId=cs.value||'',msg='';
    if(link&&link.ids.length===1)campId=link.ids[0];
    else if(link&&link.ids.length>1){if(link.ids.indexOf(campId)<0)campId='';msg=campId?'':'المستودع المستلم يغذي أكثر من معسكر — اختر المعسكر المستفيد';}
    else if(link&&link.all&&!campId)msg='المستودع المستلم غير مرتبط بمعسكر محدد — اختر المعسكر المستفيد لاحتساب الاستحقاق';
    if(campId&&cs.value!==campId&&[].some.call(cs.options,function(o){return o.value===campId;}))cs.value=campId;
    var card=$('trAutoCalcCard');if(card)card.style.display=campId?'block':'none';
    var date=($('trAcDate')||{}).value||($('trDate')||{}).value||'';
    if(trigger==='trDate'&&$('trAcDate'))$('trAcDate').value=$('trDate').value,date=$('trDate').value;
    var head=$('trAcHead');
    if(campId&&head){
      var r=await campStrengthOn(campId,date);
      if(head.dataset.manual!=='1'){head.value=r.total||'';}
      msg=r.total?('قوة المعسكر بتاريخ '+date+': '+N(r.total)+(r.source==='camp'?' (إجمالي المعسكر)':' (مجموع وحداته)')):('لا توجد تفريدة للمعسكر بتاريخ '+date+' — أدخل العدد يدويًا');
      var auto=$('trRows')&&$('trRows').dataset.autoCalc==='1';
      if((+head.value>0)&&(rowsEmpty()||auto)&&typeof window.trfAutoCalcFromEntitlements==='function'){await window.trfAutoCalcFromEntitlements();if($('trRows'))$('trRows').dataset.autoCalc='1';}
    }
    note('trWhTo',msg);
  }finally{busy=false;}
}
function wrapTransfer(){
  d.addEventListener('change',function(e){var id=e.target&&e.target.id;if(!TR_IDS[id])return;setTimeout(function(){trfAuto(id);},0);},true);
  d.addEventListener('input',function(e){var t=e.target;if(t&&t.id==='trAcHead')t.dataset.manual=t.value?'1':'';
    if(t&&t.closest&&t.closest('#trRows')&&t.classList.contains('trQty')){var b=$('trRows');if(b)b.dataset.autoCalc='';}},true);
  new MutationObserver(function(){var wt=$('trWhTo');if(wt&&!wt.dataset.dayAuto){wt.dataset.dayAuto='1';setTimeout(function(){trfAuto('init');},50);}}).observe(d.documentElement,{childList:true,subtree:true});
  /* الطباعة والحفظ: إضافة المعسكر والقوة والمدة */
  try{var mp=militaryPrint,op=mp.printTransferVoucher;
    if(!op.__day){mp.printTransferVoucher=function(m,rows){m=Object.assign({},m);var cs=$('trCamp');
      if(cs&&!m.campName&&cs.value)m.campName=(cs.selectedOptions[0]||{}).text||'';if(!m.strength&&$('trAcHead'))m.strength=$('trAcHead').value||'';if(!m.days&&$('trAcDays'))m.days=$('trAcDays').value||'';
      return op.call(mp,m,rows);};mp.printTransferVoucher.__day=1;}}catch(e){}
  var os=window.trfSend;
  if(typeof os==='function'&&!os.__day){var ws=async function(){var ref=($('trRef')||{}).value,str=+(($('trAcHead')||{}).value)||0,days=+(($('trAcDays')||{}).value)||0;
    var r=await os.apply(this,arguments);
    if(ref&&(str||days)){try{var s=await db.collection('transfers').where('refNo','==',ref).limit(500).get();var b=db.batch(),n=0;
      s.docs.forEach(function(x){if(x.data().strength==null){b.update(x.ref,{strength:str,durationDays:days||1});n++;}});if(n)await b.commit();}catch(e){}}
    return r;};ws.__day=1;window.trfSend=ws;}
}
if(d.readyState!=='loading')install();else d.addEventListener('DOMContentLoaded',install);
window.IMDAD_STRENGTH={campStrengthOn:campStrengthOn,unitStrengthOn:unitStrengthOn,facilityStrengthOn:facilityStrengthOn,clear:function(){cache.rows=null;}};
})();
