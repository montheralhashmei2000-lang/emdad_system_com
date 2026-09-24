/* IMDAD Item Picker v1 — اختيار الصنف بالكتابة أو من القائمة
   يحوّل قوائم اختيار الصنف في شاشات الاستلام والصرف والتحويل والمرتجعات والجرد
   إلى حقل بحث يقترح الأصناف أثناء الكتابة (بالاسم أو الكود أو الباركود)،
   مع إبقاء عنصر <select> الأصلي مخفيًا حتى يعمل باقي كود الشاشات كما هو. */
(function(){
'use strict';
var d=document;
var SEL='.rItem,.isItem,.trItem,.reItem,.klItem,.deItem,.rvrow select[class*="Item"]';
function norm(s){return String(s==null?'':s).toLowerCase().replace(/[أإآ]/g,'ا').replace(/ى/g,'ي').replace(/ة/g,'ه').replace(/[ًٌٍَُِّْ]/g,'').trim();}
function css(){if(d.getElementById('ipCss'))return;var s=d.createElement('style');s.id='ipCss';s.textContent=
 '.ip-wrap{position:relative;min-width:0}'+
 '.ip-input{width:100%;box-sizing:border-box}'+
 '.ip-list{position:absolute;z-index:9999;inset-inline:0;top:calc(100% + 2px);max-height:260px;overflow:auto;background:var(--ui-surface,#fff);border:1px solid var(--ui-line,#e3e3e8);border-radius:10px;box-shadow:0 12px 28px rgba(16,24,40,.14);display:none}'+
 '.ip-list.on{display:block}'+
 '.ip-opt{padding:8px 10px;font-size:13.5px;cursor:pointer;display:flex;gap:8px;justify-content:space-between;align-items:center;border-bottom:1px solid var(--ui-line,#eee)}'+
 '.ip-opt:last-child{border-bottom:0}.ip-opt:hover,.ip-opt.on{background:var(--ui-accent-soft,#e6f4f2)}'+
 '.ip-opt small{color:var(--ui-muted,#5b5e6b);font-size:11.5px;white-space:nowrap}'+
 '.ip-empty{padding:10px;font-size:13px;color:var(--ui-muted,#5b5e6b)}';
 d.head.appendChild(s);}

function optionsOf(sel){return [].slice.call(sel.options).filter(function(o){return o.value;}).map(function(o){return {v:o.value,t:o.textContent.trim()};});}
function upgrade(sel){
  if(!sel||sel.dataset.ip||sel.tagName!=='SELECT')return;
  sel.dataset.ip='1';css();
  var wrap=d.createElement('div');wrap.className='ip-wrap';
  sel.parentNode.insertBefore(wrap,sel);wrap.appendChild(sel);
  var inp=d.createElement('input');inp.type='text';inp.className='fld ip-input';inp.setAttribute('role','combobox');inp.setAttribute('aria-expanded','false');
  inp.setAttribute('aria-label','الصنف — اكتب للبحث أو اختر من القائمة');inp.placeholder='اكتب اسم الصنف أو الكود…';inp.autocomplete='off';
  var list=d.createElement('div');list.className='ip-list';list.setAttribute('role','listbox');
  wrap.appendChild(inp);wrap.appendChild(list);
  sel.style.display='none';
  var idx=-1,rows=[];
  function label(){var o=sel.selectedOptions[0];return o&&o.value?o.textContent.trim():'';}
  function syncFromSelect(){inp.value=label();}
  function close(){list.classList.remove('on');inp.setAttribute('aria-expanded','false');idx=-1;}
  function open(q){
    var all=optionsOf(sel),nq=norm(q);
    rows=nq?all.filter(function(o){return norm(o.t).indexOf(nq)>=0;}):all;
    rows=rows.slice(0,60);
    list.innerHTML=rows.length?rows.map(function(o,i){
      var parts=o.t.split('—');var name=(parts[1]||o.t).trim(),code=(parts[1]?parts[0]:'').trim();
      return '<div class="ip-opt'+(i===idx?' on':'')+'" role="option" data-v="'+o.v.replace(/"/g,'&quot;')+'" data-i="'+i+'"><span>'+name.replace(/</g,'&lt;')+'</span>'+(code?'<small>'+code.replace(/</g,'&lt;')+'</small>':'')+'</div>';
    }).join(''):'<div class="ip-empty">لا توجد أصناف مطابقة</div>';
    list.classList.add('on');inp.setAttribute('aria-expanded','true');
  }
  function pick(v){
    if(!v)return;sel.value=v;syncFromSelect();close();
    sel.dispatchEvent(new Event('change',{bubbles:true}));
  }
  inp.addEventListener('focus',function(){open(inp.value===label()?'':inp.value);});
  inp.addEventListener('input',function(){idx=-1;open(inp.value);});
  inp.addEventListener('keydown',function(e){
    if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();if(!list.classList.contains('on'))open(inp.value);
      idx=Math.max(0,Math.min(rows.length-1,idx+(e.key==='ArrowDown'?1:-1)));
      [].forEach.call(list.children,function(c,i){c.classList.toggle('on',i===idx);});
      var el=list.children[idx];if(el&&el.scrollIntoView)el.scrollIntoView({block:'nearest'});return;}
    if(e.key==='Enter'){if(list.classList.contains('on')&&rows.length){e.preventDefault();pick((rows[idx>=0?idx:0]||{}).v);}return;}
    if(e.key==='Escape'){close();syncFromSelect();}
  });
  inp.addEventListener('blur',function(){setTimeout(function(){if(!wrap.contains(d.activeElement)){close();syncFromSelect();}},120);});
  list.addEventListener('mousedown',function(e){var o=e.target.closest('.ip-opt');if(!o)return;e.preventDefault();pick(o.dataset.v);});
  /* عند تغيير القائمة برمجيًا (تحميل الأصناف أو تحميل مسودة) */
  sel.addEventListener('change',syncFromSelect);
  new MutationObserver(syncFromSelect).observe(sel,{childList:true});
  syncFromSelect();
}
function scan(){[].forEach.call(d.querySelectorAll(SEL),upgrade);}
var pend=0;
new MutationObserver(function(){if(pend)return;pend=requestAnimationFrame(function(){pend=0;try{scan();}catch(e){}});}).observe(d.documentElement,{childList:true,subtree:true});
if(d.readyState!=='loading')scan();else d.addEventListener('DOMContentLoaded',scan);
window.IMDAD_ITEM_PICKER={scan:scan,upgrade:upgrade};
})();
