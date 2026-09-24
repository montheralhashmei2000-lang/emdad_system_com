/* IMDAD v4 - integrated functional upgrade layer */
(function(){'use strict';
const $=id=>document.getElementById(id);
const escv=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
const num=v=>Number(v)||0;
function notify(msg){try{window.toast?toast(msg):alert(msg)}catch(e){}}
function camps(units){return (units||[]).filter(u=>!u.parentId).sort((a,b)=>(parseInt(a.code)||0)-(parseInt(b.code)||0))}
function nextCode(units,parentId){
  const siblings=(units||[]).filter(u=>(u.parentId||'')===(parentId||''));
  let max=0;siblings.forEach(u=>{const m=String(u.code||'').match(/(\d+)$/);if(m)max=Math.max(max,parseInt(m[1],10)||0)});
  const p=parentId?(units||[]).find(u=>u.id===parentId):null;
  return p?(String(p.code||'1')+'-'+(max+1)):String(max+1);
}
async function getUnits(){try{const s=await db.collection('units').limit(1000).get();return s.docs.map(d=>({id:d.id,...d.data()}));}catch(e){return window.UN?.units||[]}}

/* 1) Automatic camp / child-unit numbering */
function installUnitNumbering(){
  const code=$('uCode'), parent=$('uParent'); if(!code||!parent)return;
  code.readOnly=true;code.title='يتم توليد الكود تلقائيًا';code.style.background='#eef1ee';code.style.fontWeight='900';
  const refresh=()=>{if(!window.UN?.editId)code.value=nextCode(UN.units,parent.value)};
  refresh(); if(!parent.dataset.v4){parent.dataset.v4='1';parent.addEventListener('change',refresh)}
}

/* 2) Camera barcode scanner */
const scanner={stream:null,timer:null,overlay:null,callback:null,async open(cb){
  if(!navigator.mediaDevices?.getUserMedia||!('BarcodeDetector' in window)){notify('✖ ماسح الكاميرا غير مدعوم في هذا المتصفح. استخدم الإدخال اليدوي.');return}
  try{this.stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:720}}})}catch(e){notify('✖ تعذر فتح الكاميرا: '+(e.name||e.message));return}
  this.callback=cb;const o=document.createElement('div');o.className='ovl';o.style.display='flex';o.innerHTML='<div class="modal" style="max-width:480px"><h3 style="margin-bottom:10px">📷 مسح الباركود بالكاميرا</h3><video id="v4ScanVideo" playsinline muted autoplay style="width:100%;min-height:260px;background:#000;border-radius:12px;object-fit:cover"></video><div id="v4ScanHint" style="margin-top:8px;font-weight:800;font-size:12px">وجّه الكاميرا نحو الباركود…</div><button class="btn btn-d" id="v4ScanClose" style="margin-top:10px">إلغاء</button></div>';document.body.appendChild(o);this.overlay=o;
  const v=$('v4ScanVideo');v.srcObject=this.stream;try{await v.play()}catch(e){}
  o.querySelector('#v4ScanClose').onclick=()=>this.close();o.onclick=e=>{if(e.target===o)this.close()};
  let fm=[];try{fm=await BarcodeDetector.getSupportedFormats()}catch(e){};const wanted=['code_128','code_39','ean_13','ean_8','upc_a','upc_e','itf','qr_code'].filter(x=>!fm.length||fm.includes(x));let det;try{det=new BarcodeDetector({formats:wanted})}catch(e){det=new BarcodeDetector()}
  this.timer=setInterval(async()=>{if(!v.videoWidth)return;try{const a=await det.detect(v);if(a?.[0]?.rawValue){const val=String(a[0].rawValue).trim();this.close();cb&&cb(val)}}catch(e){}},220);
},close(){if(this.timer)clearInterval(this.timer);this.timer=null;if(this.stream)this.stream.getTracks().forEach(t=>t.stop());this.stream=null;if(this.overlay)this.overlay.remove();this.overlay=null}};
window.IMDAD_SCANNER=scanner;window.scanWithCamera=(target)=>scanner.open(v=>{if(target){target.value=v;target.dispatchEvent(new Event('change',{bubbles:true}));target.focus()}});
function addCameraButton(inputId,label){const input=$(inputId);if(!input||input.dataset.v4cam)return;input.dataset.v4cam='1';const b=document.createElement('button');b.type='button';b.className='btn btn-o btn-sm';b.textContent='📷 '+label;b.style.marginTop='6px';b.onclick=()=>scanner.open(v=>{input.value=v;input.dispatchEvent(new Event('change',{bubbles:true}));input.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));});input.parentElement?.appendChild(b)}

/* 3) Warehouse ↔ camp links */
let v4Camps=[];
async function loadCamps(){v4Camps=await getUnits();return camps(v4Camps)}
/* 4) التحقق من ربط مستودع الصرف بمعسكر الوحدة (التصفية نفسها في index.html: issFilterWhByCamp) */
function validateIssueWH(){const sel=$('isWh'),uid=$('isBenUnit')?.value;if(!sel||!uid||!window.ISS)return true;const whs=ISS.whs||[];const u=(ISS.units||[]).find(x=>x.id===uid),campId=u?.parentId||'';if(!campId)return true;const linked=whs.some(x=>x.feedsAllCamps===true||(x.campIds||[]).includes(campId));const w=whs.find(x=>x.name===sel.value);if(linked&&w&&w.feedsAllCamps!==true&&!(w.campIds||[]).includes(campId)){notify('✖ المستودع غير مرتبط بمعسكر الوحدة المستفيدة');return false}return true}

/* 5) Transfer beneficiary camp + strength + duration + automatic quantity */
async function injectTransferPlan(){const body=$('trfBody');if(!body||$('v4TrPlan'))return;const host=body.querySelector('.icard');if(!host)return;const box=document.createElement('div');box.id='v4TrPlan';box.className='icard';box.innerHTML='<h4>🏕️ استحقاق التحويل للجهة المستفيدة</h4><div class="f4"><div><label style="font-size:11px;font-weight:700">المعسكر المستفيد *</label><select class="fld" id="trCamp"><option value="">— اختر المعسكر —</option></select></div><div><label style="font-size:11px;font-weight:700">الوحدة المستفيدة</label><select class="fld" id="trBenUnit"><option value="">— اختر الوحدة —</option></select></div><div><label style="font-size:11px;font-weight:700">القوة</label><input class="fld" id="trStrength" type="number" min="0" readonly value="0"></div><div><label style="font-size:11px;font-weight:700">المدة (يوم)</label><input class="fld" id="trDays" type="number" min="1" value="1"></div></div><div class="note-box" id="trPlanInfo" style="margin-top:8px">اختر المعسكر والوحدة لحساب الاستحقاق.</div>';
  host.parentNode.insertBefore(box,host.nextSibling);await loadTransferUnits();
  $('trCamp').onchange=()=>{fillTransferUnits();refreshTransferStrength()};$('trBenUnit').onchange=refreshTransferStrength;$('trDays').oninput=()=>autoTransferQuantities();document.querySelectorAll('.trItem').forEach(x=>x.addEventListener('change',autoTransferQuantities));
}
let trUnits=[];async function loadTransferUnits(){trUnits=await getUnits();const cs=camps(trUnits);$('trCamp').innerHTML='<option value="">— اختر المعسكر —</option>'+cs.map(c=>`<option value="${escv(c.id)}">${escv(c.code+' — '+c.name)}</option>`).join('')}
function fillTransferUnits(){const cid=$('trCamp').value;const kids=trUnits.filter(u=>u.parentId===cid);$('trBenUnit').innerHTML='<option value="">— اختر الوحدة —</option>'+kids.map(u=>`<option value="${escv(u.id)}">${escv(u.code+' — '+u.name)}</option>`).join('')}
async function refreshTransferStrength(){const uid=$('trBenUnit').value,cid=$('trCamp').value;if(!uid){$('trStrength').value=0;autoTransferQuantities();return}let total=0;try{const s=await db.collection('strengths').where('unitId','==',uid).orderBy('strengthDate','desc').limit(1).get();if(!s.empty){const d=s.docs[0].data();total=num(d.total||d.soldierCount)}}catch(e){}$('trStrength').value=total;autoTransferQuantities()}
async function autoTransferQuantities(){const strength=num($('trStrength')?.value),days=Math.max(1,num($('trDays')?.value)||1);const rows=document.querySelectorAll('#trRows .rvrow');let changed=0;for(const r of rows){const item=r.querySelector('.trItem')?.value;if(!item)continue;let ent=null;try{const s=await db.collection('entitlements').where('itemId','==',item).limit(1).get();if(!s.empty)ent=s.docs[0].data()}catch(e){}if(!ent?.qtyPerPerson||!strength)continue;const unit=r.querySelector('.trUnit');const f=num(unit?.selectedOptions?.[0]?.dataset?.factor)||1;const q=(num(ent.qtyPerPerson)/30)*strength*days/f;r.querySelector('.trQty').value=Math.round(q*1000)/1000;changed++}const info=$('trPlanInfo');if(info)info.textContent=changed?'✔ تم حساب كميات الاستحقاق تلقائيًا حسب القوة والمدة.':'اختر صنفًا ومقررًا وقوة حتى يتم الحساب التلقائي.'}

function patchPage(){
  const page=window.curPage||'';
  if(page==='units'||$('uCode'))installUnitNumbering();
  /* حقل ربط المعسكرات موحّد في forms-ux.js (يغذي معسكر) */
  if(page==='issue'||$('isScan'))addCameraButton('isScan','كاميرا');
  /* أُلغي حقن نموذج "استحقاق التحويل للجهة المستفيدة" هنا بطلب المستخدم — اختار
     تصميم الاحتساب التلقائي للمعسكر كاملاً (trfAutoCalcFromEntitlements في
     index.html) بدل هذا التصميم البديل الذي يتطلب اختيار وحدة مستفيدة محددة
     لكل تحويل. كان هذا الحقن يُنشئ عنصر <select id="trCamp"> مكررًا بنفس اسم
     العنصر الأصلي، فيستولي على معالج onchange الخاص بالعنصر الأصلي (بما أن
     getElementById يُعيد أول عنصر مطابق دومًا) ويُسقط تصفية المستودعات التي
     يطبّقها التصميم المعتمد. */
}
const observer=new MutationObserver(()=>{clearTimeout(window.__v4t);window.__v4t=setTimeout(patchPage,80)});observer.observe(document.documentElement,{childList:true,subtree:true});

/* Capture save buttons so generated codes / warehouse camp metadata are actually persisted. */
document.addEventListener('click',async e=>{
  const t=e.target.closest?.('button');if(!t)return;
  if(t.id==='uSave'&&window.UN){e.preventDefault();e.stopImmediatePropagation();const code=$('uCode');if(code&&!UN.editId)code.value=nextCode(UN.units,$('uParent')?.value||'');else if(code&&UN.editId)code.value=UN.units.find(x=>x.id===UN.editId)?.code||code.value;setTimeout(()=>{try{window.unSave&&unSave()}catch(err){}},0);return}
  /* أُزيل اعتراض trSend من هنا بطلب المستخدم (اختار "الخيار أ" — تصميم
     الاحتساب التلقائي للمعسكر كاملاً القائم في index.html، بلا اختيار وحدة
     مستفيدة محددة لكل تحويل). كان هذا الاعتراض يمنع دالة trfSend الأصلية من
     العمل إطلاقًا عند اختيار معسكر، ويتطلب حقولاً (trBenUnit/trStrength/
     trDays) غير موجودة في الواجهة الحالية. */
},true);
document.addEventListener('change',e=>{
  if(e.target.closest?.('#trRows')&&e.target.classList.contains('trItem'))autoTransferQuantities();
});
document.addEventListener('click',e=>{
  const t=e.target.closest?.('button'); if(!t)return;
  if((t.id==='isBtnSave'||t.id==='isBtnOrder'||t.id==='isBtnDraft')&&window.ISS?.targetType===0&&!validateIssueWH()){e.preventDefault();e.stopImmediatePropagation();}
},true);
window.addEventListener('load',()=>setTimeout(patchPage,300));
})();
