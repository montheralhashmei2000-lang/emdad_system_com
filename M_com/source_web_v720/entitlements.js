/* IMDAD Entitlements v6 - محرك استحقاق متغير: معدل الفرد × إجمالي القوة × المدة */
(function(){
'use strict';
var DB='imdad-ent',ST='plans';
function openDB(){return new Promise(function(res,rej){var r=indexedDB.open(DB,1);
  r.onupgradeneeded=function(e){var d=e.target.result;if(!d.objectStoreNames.contains(ST))d.createObjectStore(ST,{keyPath:'itemId'});};
  r.onsuccess=function(){res(r.result);};r.onerror=function(){rej(r.error);};});}
function pget(itemId){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(ST,'readonly'),r=t.objectStore(ST).get(itemId);
  r.onsuccess=function(){res(r.result||null);};r.onerror=function(){rej(r.error);};});});}
function pput(rec){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(ST,'readwrite'),r=t.objectStore(ST).put(rec);
  r.onsuccess=function(){res(true);};r.onerror=function(){rej(r.error);};});});}
function pall(){return openDB().then(function(db){return new Promise(function(res,rej){var r=db.transaction(ST,'readonly').objectStore(ST).getAll();
  r.onsuccess=function(){res(r.result||[]);};r.onerror=function(){rej(r.error);};});});}
function feedingRecords(){try{return JSON.parse(localStorage.getItem('imdad.feeding.camp')||'[]');}catch(e){return [];}}
function notifyTxt(t){try{if(window.toast)window.toast(t);}catch(e){}}
var E={
  getPlan:function(itemId){return pget(itemId);},
  setPlan:function(itemId,plan){plan=plan||{};plan.itemId=String(itemId);plan.updatedAt=new Date().toISOString();return pput(plan);},
  allPlans:function(){return pall();},
  personsFor:function(campId){
    var recs=feedingRecords();
    if(campId){var m=recs.filter(function(r){return r.campId===campId;}).sort(function(a,b){return (b.ts||0)-(a.ts||0);})[0];
      if(m&&m.total)return Number(m.total);}
    var last=recs.slice().sort(function(a,b){return (b.ts||0)-(a.ts||0);})[0];
    return last&&last.total?Number(last.total):0;},
  compute:function(itemId,totalPersons,days){return pget(itemId).then(function(p){
      var rate=p&&p.perPerson?Number(p.perPerson):0;days=Math.max(1,Number(days)||1);var n=Math.max(0,Number(totalPersons)||0);
      var raw=rate*n*days;return {itemId:itemId,ratePerPerson:rate,persons:n,days:days,total:Math.ceil(raw),formula:'معدل الفرد × القوة × المدة'};});},
  computeCamp:function(itemId,campId,days){return E.compute(itemId,E.personsFor(campId),days);},
  autoTransferQty:function(itemId,campId,days){return E.computeCamp(itemId,campId,days).then(function(r){return r.total;});},
  assess:function(itemId,totalPersons,days,currentStock){return E.compute(itemId,totalPersons,days).then(function(r){
      var stock=Number(currentStock)||0;var alarm=stock<r.total;
      if(alarm){notifyTxt('⚠ رصيد '+itemId+' ('+stock+') أقل من الاستحقاق ('+r.total+')');
        try{if(typeof Notification!=='undefined'&&Notification.permission==='granted'){
          new Notification('⚠ تنبيه استحقاق - نظام الإمداد',{body:'الرصيد الحالي ('+stock+') أقل من الاستحقاق المحسوب ('+r.total+') للصنف '+itemId,tag:'imdad-ent'});}}catch(e){}}
      return {due:r.total,stock:stock,alarm:alarm,formula:r.formula};});},
  defaultRate:function(itemId){return pget(itemId).then(function(p){return p&&p.perPerson?Number(p.perPerson):0;});},
  /* مفتاح خادم FCM لا يُخزَّن في العميل؛ الإرسال عبر FCM يتم من الخادم فقط */
  setFcmKey:function(){try{localStorage.removeItem('imdad.fcm.serverKey');}catch(e){}}
};
try{localStorage.removeItem('imdad.fcm.serverKey');}catch(e){}
window.IMDAD_ENT=E;
})();
