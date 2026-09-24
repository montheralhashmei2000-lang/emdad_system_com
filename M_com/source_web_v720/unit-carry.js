/* IMDAD Unit Carry v1 — ترحيل الكميات من الوحدة الصغرى إلى الكبرى تلقائيًا
   عند تكرار الصنف نفسه بوحدتين أو أكثر في سند (توريد، صرف، تحويل، مرتجعات):
   يُحوَّل المجموع إلى وحدة الأساس ثم يُوزَّع من الوحدة الأكبر إلى الأصغر بين الوحدات المُدخلة،
   فلا يبقى في كل وحدة إلا ما هو أقل من معامل الوحدة الأكبر منها.
   مثال: أرز 4 كيس (×50) + أرز 60 كجم  ←  أرز 5 كيس + أرز 10 كجم. */
(function(){
'use strict';
var d=document;
/* الحاويات: rows=حاوية السطور، item/unit/qty=أصناف الحقول، extra=حقول تفصل السطور (أسطوانة/مستفيد)، items=قائمة الأصناف */
var SCREENS=[
  {rows:'rvRows',item:'.rItem',unit:'.rUnit',qty:'.rQty',extra:function(r){var b=r.querySelector('.cy'),s=r.querySelector('.rCy');return (b&&s&&b.style.display!=='none')?s.value:'';},items:function(){try{return RC.items;}catch(e){return [];}}},
  {rows:'isRows',item:'.isItem',unit:'.isUnit',qty:'.isQty',extra:function(r){var b=r.querySelector('.cy'),s=r.querySelector('.isCy'),ben=r.querySelector('.isRowBen select');
     return ((b&&s&&b.style.display!=='none')?s.value:'')+'|'+(ben&&ben.offsetParent!==null?ben.value:'');},items:function(){try{return ISS.items;}catch(e){return [];}}},
  {rows:'trRows',item:'.trItem',unit:'.trUnit',qty:'.trQty',extra:function(){return '';},items:function(){try{return TRF.items;}catch(e){return [];}}},
  {rows:'ruRows',item:'.reItem',unit:'.reUnit',qty:'.reQty',extra:function(){return '';},items:function(){try{return RET.items;}catch(e){return [];}}},
  {rows:'rsRows',item:'.reItem',unit:'.reUnit',qty:'.reQty',extra:function(){return '';},items:function(){try{return RET.items;}catch(e){return [];}}}
];
var EPS=1e-9;
function round(x){return Math.round(x*1e6)/1e6;}
function factorOf(sc,row,itemId,uname){
  var sel=row.querySelector(sc.unit),o=sel&&sel.selectedOptions&&sel.selectedOptions[0];
  if(o&&o.dataset&&o.dataset.factor)return +o.dataset.factor||1;
  var list=sc.items()||[],it=null;for(var i=0;i<list.length;i++){if(list[i].id===itemId){it=list[i];break;}}
  var u=it&&(it.units||[]).filter(function(x){return x.name===uname;})[0];return u?(+u.factor||1):1;
}
function nameOf(sc,itemId){var list=sc.items()||[];for(var i=0;i<list.length;i++)if(list[i].id===itemId)return list[i].name||'';return '';}

/* يعيد وصف التحويلات التي تمت (للتنبيه) أو مصفوفة فارغة */
function normalize(sc){
  var box=d.getElementById(sc.rows);if(!box)return [];
  var groups={},order=[];
  [].forEach.call(box.querySelectorAll('.rvrow'),function(r){
    var iSel=r.querySelector(sc.item),uSel=r.querySelector(sc.unit),qIn=r.querySelector(sc.qty);
    if(!iSel||!uSel||!qIn||!iSel.value||!uSel.value)return;
    var qty=+qIn.value;if(!(qty>0))return;
    var k=iSel.value+'#'+sc.extra(r);
    if(!groups[k]){groups[k]={itemId:iSel.value,rows:[]};order.push(k);}
    groups[k].rows.push({el:r,qIn:qIn,unit:uSel.value,f:factorOf(sc,r,iSel.value,uSel.value),qty:qty});
  });
  var notes=[];
  order.forEach(function(k){
    var g=groups[k],units={};
    g.rows.forEach(function(x){(units[x.unit]=units[x.unit]||{name:x.unit,f:x.f,rows:[]}).rows.push(x);});
    var list=Object.keys(units).map(function(n){return units[n];});
    if(list.length<2)return;                         /* الترحيل فقط عند تكرار الصنف بوحدات مختلفة */
    list.sort(function(a,b){return b.f-a.f;});
    if(list[0].f===list[list.length-1].f)return;
    var before={},total=0;
    list.forEach(function(u){var s=0;u.rows.forEach(function(x){s+=x.qty;});before[u.name]=s;total+=s*u.f;});
    var rest=total,changed=false;
    list.forEach(function(u,i){
      var q;
      if(i<list.length-1){q=Math.floor((rest+EPS)/u.f);rest=round(rest-q*u.f);}
      else q=round(rest/u.f);
      if(Math.abs(q-before[u.name])>EPS||u.rows.length>1)changed=true;
      u.newQty=q;
    });
    if(!changed)return;
    list.forEach(function(u){
      u.rows.forEach(function(x,j){
        if(j===0&&u.newQty>EPS){x.qIn.value=String(u.newQty);}
        else x.el.remove();
      });
    });
    notes.push(nameOf(sc,g.itemId)+': '+list.filter(function(u){return u.newQty>EPS;}).map(function(u){return u.newQty+' '+u.name;}).join(' + '));
  });
  if(notes.length){
    if(!box.querySelector('.rvrow')&&typeof window[{rvRows:'rcAddRow',isRows:'issAddRow',trRows:'trfAddRow'}[sc.rows]]==='function')window[{rvRows:'rcAddRow',isRows:'issAddRow',trRows:'trfAddRow'}[sc.rows]]();
    var any=box.querySelector('.rvrow '+sc.qty);if(any)any.dispatchEvent(new Event('input',{bubbles:true}));  /* تحديث الفحص الحي */
  }
  return notes;
}
function screenOf(el){for(var i=0;i<SCREENS.length;i++){var b=d.getElementById(SCREENS[i].rows);if(b&&b.contains(el))return SCREENS[i];}return null;}

/* حيًّا: عند مغادرة السطر فقط (الانتقال إلى سطر آخر أو خارج منطقة السطور)،
   لا أثناء التنقل بين حقول السطر نفسه */
d.addEventListener('focusout',function(e){
  var t=e.target;if(!t||!t.closest)return;
  var row=t.closest('.rvrow');if(!row)return;
  var sc=screenOf(row);if(!sc)return;
  setTimeout(function(){
    var a=d.activeElement;
    if(a&&row.contains(a))return;                     /* ما زال داخل السطر نفسه */
    var n=normalize(sc);if(n.length&&typeof toast==='function')toast('↑ رُحّلت الكميات للوحدة الأكبر — '+n.join(' · '));
  },0);
},true);

/* احتياطًا قبل الحفظ — بعد تحميل الصفحة كي تكون دوال الجمع معرّفة.
   دوال الجمع تُستدعى أيضًا من الفحص الحي مع كل حرف؛ لذلك لا يُرحَّل شيء ما دام التركيز
   داخل منطقة السطور (المستخدم ما زال يُدخل)، ويُرحَّل عند الحفظ حين يكون التركيز على زر خارجها. */
function editing(sc){var box=d.getElementById(sc.rows),a=d.activeElement;return !!(box&&a&&box.contains(a));}
function safeNormalize(sc){try{if(!editing(sc))normalize(sc);}catch(e){}}
function wrapCollectors(){
  [['rcCollect',0],['issCollect',1],['trfCollect',2]].forEach(function(p){
    var orig=window[p[0]];if(typeof orig!=='function'||orig.__carry)return;
    var w=function(){safeNormalize(SCREENS[p[1]]);return orig.apply(this,arguments);};w.__carry=1;window[p[0]]=w;
  });
  var oRet=window.retCollect;
  if(typeof oRet==='function'&&!oRet.__carry){var w=function(boxId){SCREENS.forEach(function(s){if(s.rows===boxId)safeNormalize(s);});return oRet.apply(this,arguments);};w.__carry=1;window.retCollect=w;}
}
/* بعد تنفيذ كل السكربتات (DOMContentLoaded) لا عند load: load قد يتأخر كثيرًا دون إنترنت بسبب الخطوط */
if(d.readyState!=='loading')wrapCollectors();else d.addEventListener('DOMContentLoaded',wrapCollectors);

window.IMDAD_UNIT_CARRY={normalize:function(rowsId){var s=SCREENS.filter(function(x){return x.rows===rowsId;})[0];return s?normalize(s):[];}};
})();
