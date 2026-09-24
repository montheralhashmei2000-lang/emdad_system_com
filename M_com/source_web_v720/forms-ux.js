/* IMDAD Forms UX v1 — طباعة/PDF/Excel/استيراد/مصمم نماذج/فلترة/ماسح كاميرا/تمرير */
(function(){
'use strict';
var doc=document;
function $(id){return doc.getElementById(id);}
function escv(s){return String(s==null?'':s).replace(/[&<>"']/g,function(m){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m];});}
function nof(m){try{if(window.toast)window.toast(m);else alert(m);}catch(e){}}
function iso(){return new Date().toISOString();}
function forEach(a,fn){for(var i=0;i<a.length;i++)fn(a[i],i);}

/* ---------- إعدادات النماذج (header/footer/logo/توقيعات/أعمدة) ---------- */
var CFG={header:'نظام الإمداد والتموين',sub:'إدارة المخزون والاستحقاقات',footer:'وثيقة داخلية — نظام إمداد',logo:'',entity:{name:'',addr:'',phone:''},signatures:[{role:'المسؤول',name:''},{role:'أمين المستودع',name:''},{role:'قائد الوحدة',name:''}],pageSize:'A4',orient:'portrait',hideCols:{},loaded:false};
function localLoad(){try{var s=localStorage.getItem('imdad.formsCfg');if(s){var x=JSON.parse(s);for(var k in x)if(k in CFG)CFG[k]=x[k];CFG.loaded=true;}}catch(e){}}
function localSave(){try{localStorage.setItem('imdad.formsCfg',JSON.stringify(CFG));}catch(e){}}
function loadCfg(cb){cb=cb||function(){};if(CFG.loaded){cb();return;}try{var d=window.db;if(!d){localLoad();CFG.loaded=true;cb();return;}
 d.collection('settings').doc('forms').get().then(function(sn){try{var x=sn&&sn.exists?sn.data():{};for(var k in x)if(k in CFG)CFG[k]=x[k];}catch(e){}CFG.loaded=true;cb();})
 .catch(function(){localLoad();CFG.loaded=true;cb();});}catch(e){localLoad();CFG.loaded=true;cb();}}
function saveCfg(t){try{var d=window.db;if(!d){localSave();nof(t?t:'✔ حُفظت إعدادات النماذج محليًا');return;}
 d.collection('settings').doc('forms').set(JSON.parse(JSON.stringify(CFG)),{merge:true}).then(function(){nof(t?t:'✔ تم حفظ إعدادات الطباعة والنماذج');localSave();})
 .catch(function(e){localSave();nof('✖ الحفظ السحابي فشل — حُفظ محليًا: '+(e&&(e.code||e.message)||''));});}catch(e){localSave();}}
function brandToApp(){try{if(!window.db)return;var db2=window.db;var n=(CFG.header||'نظام الإمداد والتموين');
 var data={name:n,entityName:CFG.entity.name||'',entityAddr:CFG.entity.addr||'',entityPhone:CFG.entity.phone||'',footerText:CFG.footer||'',logoUrl:CFG.logo||'',updatedAt:iso()};
 db2.collection('settings').doc('app').set(data,{merge:true}).then(function(){try{if(window.APP_CFG && typeof APP_CFG==='object'){APP_CFG.name=n;APP_CFG.logoUrl=CFG.logo||APP_CFG.logoUrl;}if(window.applyBranding)applyBranding();}catch(e){}}).catch(function(){});}catch(e){}}
localLoad();

/* ---------- رأس/تذييل/توقيع للطباعة ---------- */
function printHeaderHTML(){var e=CFG.entity;return '<div class="imd-head">'+(CFG.logo?'<img class="imd-logo" src="'+escv(CFG.logo)+'" alt="الشعار">':'')+
 '<div class="imd-head-t"><b>'+escv(CFG.header||'نظام الإمداد والتموين')+'</b>'+(CFG.sub?'<span>'+escv(CFG.sub)+'</span>':'')+
 '<span class="imd-head-e">'+(e.name?(escv(e.name)+(e.addr?' — '+escv(e.addr):'')):'')+(e.phone?' — هاتف: '+escv(e.phone):'')+'</span></div></div>';}
function printFooterHTML(){return '<div class="imd-foot">'+escv(CFG.footer||'')+'</div>';}
function signatureHTML(){var h='<div class="imd-sig">';forEach(CFG.signatures,function(s){h+='<div class="imd-sig-i"><b>'+escv(s.role||'')+'</b><span class="sig-line"></span><span>'+escv(s.name||'')+'</span></div>';});return h+'</div>';}
function printCSS(){return '@page{margin:13mm}body{font-family:Cairo,"Segoe UI",Tahoma,sans-serif;direction:rtl;color:#15231d;font-size:12.5px;margin:0}'+
 '.imd-head{display:flex;gap:10px;align-items:center;border-bottom:2.5px solid #0b8f6b;padding-bottom:8px;margin-bottom:12px}'+
 '.imd-logo{width:62px;height:62px;object-fit:contain}.imd-head-t{display:flex;flex-direction:column}.imd-head-t b{font-size:17px;color:#0a4f41}.imd-head-t span{font-size:11.5px;color:#33564b}.imd-head-e{color:#5c6f68}'+
 '.imd-body table{width:100%;border-collapse:collapse;font-size:11.5px}.imd-body th,.imd-body td{border:1px solid #9db4ab;padding:5px 7px;text-align:center}.imd-body th{background:#0b8f6b;color:#fff}'+
 '.imd-sig{display:flex;justify-content:space-between;gap:20px;margin-top:36px}.imd-sig-i{text-align:center;min-width:130px;flex:1}.imd-sig-i .sig-line{display:block;border-top:1.5px solid #333;margin:30px 0 6px}'+
 '.imd-foot{border-top:1px solid #9db4ab;margin-top:18px;padding-top:6px;font-size:10.5px;color:#5c6f68}';}
function printHTML(body,title){return '<!doctype html><html dir="rtl" lang="ar"><head><meta charset="utf-8"><title>'+escv(title||'طباعة')+'</title><style>'+printCSS()+'</style></head><body>'+printHeaderHTML()+'<div class="imd-body">'+body+'</div>'+signatureHTML()+printFooterHTML()+'</body></html>';}

/* ---------- تطبيق إخفاء الأعمدة ---------- */
function applyHide(tblEl){var id=(tblEl&&tblEl.id)||'';var hid=CFG.hideCols[id]||[];if(!hid.length)return;
 forEach(tblEl.querySelectorAll('tr'),function(tr){var cells=tr.children;for(var i=cells.length-1;i>=0;i--){if(hid.indexOf(i)>=0)cells[i].style.display='none';}});}
function visibleClone(tblId){var tb=$(tblId);if(!tb)return null;var cl=tb.cloneNode(true);var hid=CFG.hideCols[tblId]||[];if(hid.length){forEach(cl.querySelectorAll('tr'),function(tr){var cells=tr.children;for(var i=cells.length-1;i>=0;i--)if(hid.indexOf(i)>=0)cells[i].remove();});}return cl;}

/* ---------- معاينة/طباعة ---------- */
function showPrintModal(html){var ovl=doc.createElement('div');ovl.className='ovl';ovl.style.cssText='position:fixed;inset:0;background:rgba(0,0,0,.46);z-index:999999;display:flex;align-items:center;justify-content:center;padding:14px';
 ovl.innerHTML='<div style="background:#fff;border-radius:14px;width:min(980px,96vw);max-height:94vh;display:flex;flex-direction:column;overflow:hidden;direction:rtl">'+
 '<div style="display:flex;gap:8px;padding:10px 14px;border-bottom:1px solid #e2e8e5;align-items:center"><b style="flex:1;color:#123524">🖨️ معاينة الطباعة / تصدير PDF</b>'+
 '<button class="btn btn-p btn-sm" id="imdPrnDo" type="button">🖨️ طباعة</button><button class="btn btn-o btn-sm" id="imdPrnClose" type="button">إغلاق</button></div>'+
 '<iframe id="imdPrnFrame" style="flex:1;border:0;width:100%;min-height:72vh"></iframe></div>';
 doc.body.appendChild(ovl);
 var f=ovl.querySelector('#imdPrnFrame');try{f.srcdoc=html;}catch(e){f.src='data:text/html;charset=utf-8,'+encodeURIComponent(html);}
 ovl.querySelector('#imdPrnClose').onclick=function(){ovl.remove();};
 ovl.querySelector('#imdPrnDo').onclick=function(){try{var w=f.contentWindow;if(w&&w.print){w.focus();w.print();}else nof('الطباعة غير مدعومة هنا — استخدم تصدير Excel');}catch(e){nof('تعذر الطباعة: '+e.message);}};
 ovl.onclick=function(e){if(e.target===ovl)ovl.remove();};}
function openPrint(tblId,title){var cl=visibleClone(tblId);var body=cl?('<table>'+cl.innerHTML+'</table>'):'<p>لا يوجد جدول للطباعة في هذه الشاشة.</p>';showPrintModal(printHTML(body,title));}

/* ---------- Excel (SheetJS مع بديل CSV) ---------- */
function loadXLSX(cb){if(window.XLSX){cb();return;}var s=doc.createElement('script');s.src='vendor/xlsx.full.min.js';
 s.onload=function(){cb();};s.onerror=function(){cb('ERR');};doc.head.appendChild(s);}
function jsonToXLSX(headers,rows,fn){loadXLSX(function(err){if(err||!window.XLSX){csvFallback(headers,rows,fn);return;}
 var aoa=[headers];forEach(rows,function(r){var row=[];forEach(headers,function(h){row.push(r[h]!=null?r[h]:'');});aoa.push(row);});
 var ws=XLSX.utils.aoa_to_sheet(aoa);var wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,ws,'Sheet1');XLSX.writeFile(wb,(fn||'export')+'.xlsx');});}
function tableXLSX(tblId,fn){var tb=$(tblId);if(!tb){nof('✖ لا يوجد جدول للتصدير');return;}loadXLSX(function(err){if(err||!window.XLSX){csvFromTable(tb,fn);return;}
 var cl=tb.cloneNode(true);applyHide(cl);var wb=XLSX.utils.table_to_book(cl,{raw:true});XLSX.writeFile(wb,(fn||'export')+'.xlsx');});}
function readXLSX(file,cb){loadXLSX(function(err){if(err||!window.XLSX){nof('✖ مكتبة Excel غير متاحة (تحتاج إنترنت)');return;}
 var r=new FileReader();r.onload=function(){try{var wb=XLSX.read(new Uint8Array(r.result),{type:'array'});var ws=wb.Sheets[wb.SheetNames[0]];var rows=XLSX.utils.sheet_to_json(ws,{defval:''});cb(rows);}catch(e){nof('✖ تعذر قراءة الملف: '+e.message);}};r.readAsArrayBuffer(file);});}
function csvFallback(headers,rows,fn){var lines=[headers.join(',')];forEach(rows,function(r){lines.push(headers.map(function(h){var v=String(r[h]!=null?r[h]:'');return /[",]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v;}).join(','));});
 var blob=new Blob(['\ufeff'+lines.join('\n')],{type:'text/csv;charset=utf-8'});dl(blob,(fn||'export')+'.csv');}
function csvFromTable(tb,fn){var head=[],rows=[];forEach(tb.querySelectorAll('tr'),function(tr){var cells=tr.querySelectorAll('th,td');var r=[];forEach(cells,function(c){if(c.style.display==='none')return;r.push(c.textContent.trim());});if(!head.length)head=r.slice();else rows.push(r);});
 var lines=[head.join(',')];forEach(rows,function(r){lines.push(r.map(function(v){return /[",]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v;}).join(','));});
 var blob=new Blob(['\ufeff'+lines.join('\n')],{type:'text/csv;charset=utf-8'});dl(blob,(fn||'export')+'.csv');}
function dl(blob,fn){var a=doc.createElement('a');a.href=URL.createObjectURL(blob);a.download=fn;doc.body.appendChild(a);a.click();setTimeout(function(){URL.revokeObjectURL(a.href);a.remove();},400);}
function filePick(accept,cb){var inp=doc.createElement('input');inp.type='file';inp.accept=accept||'.xlsx,.xls,.csv';inp.onchange=function(){var f=inp.files&&inp.files[0];if(f)cb(f);inp.remove();};inp.click();}

/* ---------- ماسح الباركود بالكاميرا لكل الحقول ---------- */
function bindScan(inp){if(!inp||inp.dataset.imdscan)return;inp.dataset.imdscan='1';
 if(!window.scanWithCamera){if(!window.IMDAD_SCANNER)return;}
 var b=doc.createElement('button');b.type='button';b.className='btn btn-o btn-sm';b.textContent='📷';b.title='مسح الباركود بالكاميرا';
 b.style.cssText='margin:0 6px 0 0;padding:7px 11px;flex:0 0 auto';
 b.onclick=function(ev){ev.preventDefault();ev.stopPropagation();try{window.scanWithCamera(inp);}catch(e){nof('✖ الماسح غير متاح: '+(e&&e.message||''));}};
 try{if(inp.closest&&inp.closest('.fld-row,.field')){var h=inp.closest('.fld-row,.field');if(h){h.style.display='flex';h.style.alignItems='center';h.style.flexWrap='wrap';inp.style.flex='1';h.appendChild(b);return;}}}catch(e){}
 inp.parentNode.insertBefore(b,inp.nextSibling);}
function autobind(){try{var els=doc.querySelectorAll('input');for(var i=0;i<els.length;i++){var el=els[i];var m=(el.id||'')+' '+(el.placeholder||'');
  if(/scan|barcode|barcod|باركود|bc/i.test(m))bindScan(el);}}catch(e){}}
setInterval(autobind,2500);

/* ---------- إصلاح التمرير: فتح الشاشة من الأعلى ---------- */
function scrollTopFix(){try{window.scrollTo(0,0);var m=$('main');if(m)m.scrollTop=0;}catch(e){}}

/* ---------- شريط أدوات التصدير/الطباعة/الفلترة ---------- */
/* الأدوات لكل شاشة: p طباعة القائمة، x تصدير Excel، i استيراد Excel مع القالب.
   الافتراضي: تظهر فقط حيث تلزم؛ شاشات المستندات تُطبع من زر طباعة السند داخلها.
   يمكن تغييرها من الإعدادات ← الطباعة والتصدير والاستيراد (تُحفظ في imdad.toolbarCfg). */
var PM={items:{t:'itmTbl',x:1,i:1,label:'الأصناف',grp:'البيانات الأساسية'},
 units:{label:'الوحدات المستفيدة',grp:'البيانات الأساسية'},
 suppliers:{t:'supTbl',label:'الموردون',grp:'البيانات الأساسية'},
 stores:{t:'stoTbl',label:'المستودعات',grp:'البيانات الأساسية'},
 kitchens:{label:'المطابخ والأفران',grp:'البيانات الأساسية'},
 receive:{label:'الاستلام (الواردات)',grp:'العمليات المخزنية',doc:1},
 issue:{label:'الصرف',grp:'العمليات المخزنية',doc:1},
 transfer:{label:'التحويل المخزني',grp:'العمليات المخزنية',doc:1},
 returns:{label:'المرتجعات',grp:'العمليات المخزنية',doc:1},
 pendingOrders:{label:'أوامر التوريد',grp:'العمليات المخزنية'},
 feeding:{a:'tfBody',i:1,label:'التغذية اليومية',grp:'التشغيل اليومي',own:1},
 kitchenLog:{label:'سجل التشغيل',grp:'التشغيل اليومي'},
 ratios:{t:'ratTbl',i:1,label:'نسب الاستهلاك',grp:'التشغيل اليومي',own:1},
 balances:{t:'balTbl',label:'الأرصدة الحالية',grp:'التقارير والجرد',own:1},
 stocktake:{label:'جرد المخزون',grp:'التقارير والجرد',own:1},
 auditTrail:{t:'audOut',x:1,label:'سجل النشاط والتدقيق',grp:'التقارير والجرد'}};
var IMP={feeding:'importFeeding',items:'importItems',ratios:'importRatios'};
var TB_KEY='imdad.toolbarCfg';
function tbOverrides(){try{return JSON.parse(localStorage.getItem(TB_KEY)||'{}')||{};}catch(e){return {};}}
function tbAnchor(meta){var id=meta.t||meta.a;if(!id)return null;var t=$(id);if(!t)return null;
 if(meta.t&&t.tagName!=='TABLE'&&!t.querySelector('table'))return null;
 var a=(t.tagName==='TABLE'&&t.closest)?(t.closest('.twrap')||t):t;return a.offsetParent===null?null:a;}
/* يُرجع معرّف جدول قابل للطباعة/التصدير حتى لو كان المعرّف لحاوية */
function tbTableId(meta){var el=$(meta.t);if(!el)return '';if(el.tagName==='TABLE')return meta.t;var x=el.querySelector('table');if(!x)return '';if(!x.id)x.id=meta.t+'_tbl';return x.id;}
/* يُستدعى دوريًا: يضيف الشريط عند ظهور الجدول ويزيله عند اختفائه أو الانتقال لشاشة لا تحتاجه */
function syncToolbar(p){try{var bar=$('imdTbar'),meta=PM[p],tb=meta&&tbFor(p),anchor=meta&&tbAnchor(meta);
 if(!meta||!anchor||(!tb.p&&!tb.x&&!tb.i)){if(bar)bar.remove();return;}
 if(!bar||bar.nextElementSibling!==anchor)injectToolbar(p);}catch(e){}}
function tbFor(page){var m=PM[page];if(!m)return null;var o=tbOverrides()[page]||{};function v(k){return (k in o)?!!o[k]:!!m[k];}return {p:!!m.t&&v('p'),x:!!m.t&&v('x'),i:!!IMP[page]&&v('i')};}
window.IMDAD_EXPORT={print:openPrint,xlsx:tableXLSX,json:jsonToXLSX};
window.IMDAD_TOOLBAR={get:tbFor,renderMatrix:function(host){if(!host)return;
 var h='<div class="note-box" style="margin-bottom:10px">حدّد الأدوات التي تظهر فوق جدول كل شاشة (تختفي تلقائيًا عند فتح نموذج إضافة/تعديل). افتراضيًا تظهر فقط حيث تلزم: شاشات المستندات تُطبع من زر السند داخلها، والشاشات الموسومة «أزرار خاصة» فيها طباعة/تصدير مسبقًا فلا تُكرَّر. الاستيراد متاح فقط للشاشات التي تدعمه.</div>'+
  '<div class="twrap"><table class="u tb-matrix"><thead><tr><th>الشاشة</th><th>🖨️ طباعة</th><th>📊 تصدير Excel</th><th>⬆️ استيراد + قالب</th></tr></thead><tbody>';
 var grp='';Object.keys(PM).forEach(function(k){var m=PM[k],t=tbFor(k);
  if(m.grp!==grp){grp=m.grp;h+='<tr><td colspan="4" style="background:var(--lgreen);font-weight:900">'+escv(grp)+'</td></tr>';}
  function cb(fl,dis){return '<td><input type="checkbox" data-tb="'+k+'" data-f="'+fl+'"'+(t[fl]?' checked':'')+(dis?' disabled title="غير متاح في هذه الشاشة"':'')+'></td>';}
  h+='<tr><td>'+escv(m.label)+(m.doc?' <span class="chip chip-code">مستند</span>':'')+(m.own?' <span class="chip chip-pend">أزرار خاصة</span>':'')+'</td>'+cb('p',!m.t)+cb('x',!m.t)+cb('i',!IMP[k])+'</tr>';});
 h+='</tbody></table></div><div class="rbar" style="margin-top:10px"><button class="btn btn-o btn-sm" id="tbReset" type="button">↺ استعادة الافتراضي</button></div>';
 host.innerHTML=h;
 host.onchange=function(e){var c=e.target;if(!c||!c.getAttribute||!c.getAttribute('data-tb'))return;var pg=c.getAttribute('data-tb'),fl=c.getAttribute('data-f');var all=tbOverrides();all[pg]=all[pg]||{};all[pg][fl]=c.checked;try{localStorage.setItem(TB_KEY,JSON.stringify(all));}catch(err){}nof('✔ حُفظ: '+PM[pg].label);};
 var r=$('tbReset');if(r)r.onclick=function(){try{localStorage.removeItem(TB_KEY);}catch(e){}window.IMDAD_TOOLBAR.renderMatrix(host);nof('✔ أُعيدت الأدوات الافتراضية');};
}};
function injectToolbar(page){try{var m=$('imdTbar');if(m)m.remove();var meta=PM[page];if(!meta)return;var tb=tbFor(page);if(!tb.p&&!tb.x&&!tb.i)return;var anchor=tbAnchor(meta);if(!anchor)return;
 var bar=doc.createElement('div');bar.id='imdTbar';bar.className='imd-tbar';bar.style.cssText='display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:4px 0 10px';
 function b(txt,fn,cls){var x=doc.createElement('button');x.type='button';x.className='btn '+(cls||'btn-o')+' btn-sm';x.textContent=txt;x.onclick=fn;bar.appendChild(x);return x;}
 if(tb.p)b('🖨️ طباعة / PDF',function(){var t=tbTableId(meta);if($(t))openPrint(t,meta.label);else nof('✖ افتح القائمة/الجدول أولًا');},'btn-p');
 if(tb.x)b('📊 تصدير Excel',function(){var t=tbTableId(meta);if($(t))tableXLSX(t,meta.label+' '+new Date().toISOString().slice(0,10));else nof('✖ لا يوجد جدول حالي');});
 if(tb.i)b('⬇️ قالب Excel',function(){templateXLSX(page);},'btn-o');
 if(tb.i)b('⬆️ استيراد Excel',function(){filePick('.xlsx,.xls,.csv',function(f){readXLSX(f,function(rows){var h=IMP[page];if(h&&window[h])window[h](rows);else nof('✖ لا توجد معالجة استيراد لهذه الشاشة');});});},'btn-p');
 anchor.parentNode.insertBefore(bar,anchor);
 /* إصلاح (بطلب المستخدم): أُزيل استدعاء شريط الفلترة العام addFilter لأنه كان
    يُضاف تكرارًا فوق حقول البحث/الفلترة الأصلية الموجودة أصلاً في كل شاشة على
    حدة (مثل #itmSearch في الأصناف، #ratSearch في الاستحقاقات...). أزرار
    الطباعة/التصدير/الاستيراد أعلاه بقيت كما هي دون أي تغيير. */
 }catch(e){}}
function addFilter(page,tblId){try{var _old=$('imdFilterBar');if(_old)_old.remove();var tb=$(tblId);if(!tb)return;
 var bar=doc.createElement('div');bar.id='imdFilterBar';bar.className='imd-fbar';bar.style.cssText='display:flex;gap:6px;align-items:center;margin:0 0 8px;flex-wrap:wrap';
 bar.innerHTML='<span style="font-size:12px;font-weight:800;color:#0a4f41">🔍 فلترة:</span><input placeholder="اكتب للبحث في الجدول…" style="flex:1;min-width:180px" class="fld">';
 var inp=bar.querySelector('input');inp.oninput=function(){var q=inp.value.trim().toLowerCase();var trs=tb.querySelectorAll('tbody tr');var n=0;
  forEach(trs,function(tr){var ok=!q||(tr.textContent||'').toLowerCase().indexOf(q)>=0;tr.style.display=ok?'':'none';if(ok)n++;});
  var cnt=bar.querySelector('.imd-fcnt');if(cnt)cnt.textContent=' ('+n+')';};
 bar.insertAdjacentHTML('beforeend','<span class="imd-fcnt" style="font-size:11px;color:#5c6f68"></span>');
 var hosts=tb.closest?tb.closest('.twrap'):null;var parent=hosts||tb.parentNode;if(parent)parent.insertBefore(bar,hosts||tb);}catch(e){}}

/* ---------- قوالب + معالجات استيراد ---------- */
function templateXLSX(page){try{if(page==='feeding')feedingTemplate();else if(page==='items')itemsTemplate();else if(page==='ratios')ratiosTemplate();}catch(e){nof('✖ '+e.message);}}
function feedingTemplate(){loadUnits(function(us){var rows=[];forEach(us,function(u){if(!u.parentId){rows.push({campCode:u.code||'',unitCode:'',unitName:'المعسكر كامل',total:'',date:new Date().toISOString().slice(0,10)});
  forEach(us,function(v){if(v.parentId===u.id)rows.push({campCode:u.code||'',unitCode:v.code||'',unitName:v.name||'',total:'',date:''});});}});
  if(!rows.length)rows=[{campCode:'1',unitCode:'',unitName:'المعسكر كامل',total:'',date:''}];
  jsonToXLSX(['campCode','unitCode','unitName','total','date'],rows,'تفريدة-قالب');});}
function itemsTemplate(){jsonToXLSX(['code','name','category','unit','min','qty'],[{code:'',name:'',category:'',unit:'',min:'',qty:''}],'أصناف-قالب');}
function ratiosTemplate(){jsonToXLSX(['code','name','qtyPerPerson','unit','notes'],[{code:'كود الصنف',name:'اسم الصنف (اختياري)',qtyPerPerson:'المقرر الشهري للفرد',unit:'وحدة القياس (فارغ = الأساسية)',notes:''}],'مقررات-شهرية-قالب');}
function loadUnits(cb){try{var d=window.db;if(!d){cb(window.UN?window.UN.units||[]:[]);return;}
 d.collection('units').limit(1000).get().then(function(s){var u=[];forEach(s.docs,function(dc){u.push({id:dc.id,code:dc.data().code||'',name:dc.data().name||'',parentId:dc.data().parentId||null});});cb(u);}).catch(function(){cb(window.UN?window.UN.units||[]:[]);});}catch(e){cb([]);}}
window.importFeeding=function(rows){loadUnits(function(us){var byCode={};forEach(us,function(u){byCode[u.code]=u;});var d=window.db;if(!d){nof('✖ قاعدة البيانات غير جاهزة');return;}
 var ok=0,skip=0;var create=[];forEach(rows,function(r){var code=(r.unitCode||'').toString().trim();var campCode=(r.campCode||'').toString().trim();var total=Number(r.total)||0;var date=(r.date||new Date().toISOString().slice(0,10)).toString().trim();
  if(!total){skip++;return;}
  if(code){var u=byCode[code];if(!u){skip++;return;}create.push({unitId:u.id,campId:u.parentId?u.parentId:u.id,total:total,strengthDate:date,mode:'detail',source:'excel'});}
  else if(campCode){var c=byCode[campCode];if(!c){skip++;return;}create.push({unitId:c.id,campId:c.id,total:total,strengthDate:date,mode:'camp',source:'excel'});}
  else{skip++;}});
 if(!create.length){nof('✖ لا صفوف صالحة للاستيراد');return;}
 var batch=d.batch();forEach(create,function(r){batch.set(d.collection('strengths').doc('x-'+r.unitId+'-'+r.strengthDate),{unitId:r.unitId,campId:r.campId,total:r.total,strengthDate:r.strengthDate,mode:r.mode,source:r.source,createdAt:iso(),updatedAt:iso()},{merge:true});});
 batch.commit().then(function(){nof('✔ تم استيراد '+create.length+' صف تفريدة'+(skip?' (تجاهل '+skip+')':''));}).catch(function(e){nof('✖ فشل الاستيراد: '+(e.code||e.message));});});};
window.importItems=function(rows){var d=window.db;if(!d){nof('✖ قاعدة البيانات غير جاهزة');return;}var ok=0,skip=0;
 loadUnits(function(){forEach(rows,function(r){var code=(r.code||'').toString().trim();var name=(r.name||'').toString().trim();if(!code||!name){skip++;return;}
  var data={code:code,name:name,category:(r.category||'').toString().trim(),unit:(r.unit||'').toString().trim(),qty:Number(r.qty)||0,min:Number(r.min)||0,updatedAt:iso()};
  d.collection('items').where('code','==',code).limit(1).get().then(function(s){if(!s.empty){var doc2=s.docs[0];data.updatedAt=iso();return d.collection('items').doc(doc2.id).update(data);}
   data.createdAt=iso();return d.collection('items').add(data);}).then(function(){ok++;if(ok+skip===rows.length)nof('✔ استيراد الأصناف: '+ok+' صنفًا'+(skip?' (تجاهل '+skip+')':''));})
  .catch(function(e){skip++;nof('✖ خطأ لصف '+(code||'?'));});
 });});};
window.importRatios=function(rows){var d=window.db;if(!d){nof('✖ قاعدة البيانات غير جاهزة');return;}
 d.collection('items').limit(5000).get().then(function(s){var byCode={};forEach(s.docs,function(dc){var x=dc.data();byCode[String(x.code||'').trim()]={id:dc.id,code:x.code||'',name:x.name||'',units:x.units||[],baseUnit:x.baseUnit||''};});
  var batch=d.batch(),ok=0,skip=[];
  forEach(rows,function(r,i){var code=String(r.code||'').trim();var it=byCode[code];var q=Number(r.qtyPerPerson);
   if(!code||code==='كود الصنف')return;
   if(!it){skip.push((i+2)+': كود غير موجود');return;}
   if(isNaN(q)||q<0){skip.push((i+2)+': كمية غير صحيحة');return;}
   var units=it.units.length?it.units:[{name:it.baseUnit||'قطعة',isBase:true}];var un=String(r.unit||'').trim();
   var u=units.filter(function(x){return x.name===un;})[0]||units.filter(function(x){return x.isBase;})[0]||units[0];
   batch.set(d.collection('entitlements').doc(it.id),{itemId:it.id,itemCode:it.code,itemName:it.name,qtyPerPerson:Math.round(q*1000)/1000,qtyUnit:'measure',measureUnitName:u.name,unitName:u.name,notes:String(r.notes||'').trim(),updatedAt:iso(),source:'excel'});ok++;});
  if(!ok){nof('✖ لا توجد سطور صالحة للاستيراد'+(skip.length?' — '+skip.slice(0,3).join('، '):''));return;}
  batch.commit().then(function(){nof('✔ استيراد المقررات: '+ok+' صنفًا'+(skip.length?' (تجاهل '+skip.length+': '+skip.slice(0,3).join('، ')+')':''));
   if(window.curPage==='ratios'&&typeof window.ratLoadData==='function')window.ratLoadData();}).catch(function(e){nof('✖ فشل الاستيراد: '+(e.code||e.message));});
 }).catch(function(e){nof('✖ تعذر تحميل الأصناف: '+(e.code||e.message));});};

/* ---------- مستودع: حقل "يغذي معسكر" تحت الموقع ---------- */
/* قائمة منبثقة متعددة الاختيار: أول خيار «جميع المعسكرات»، ثم المعسكرات مع بحث.
   العقد مع الحفظ لم يتغير: feedsAllCamps + campIds عبر IMDAD_CAMP_LINK. */
function afterField(id,html){var inp=$(id);if(!inp)return null;var host=(inp.closest&&inp.closest('.field,.fld-row'))||inp.parentNode;if(!host||!host.parentNode)return null;
 host.insertAdjacentHTML('afterend',html);return host.nextSibling;}
var CAMP_DD={camps:[],all:true,ids:[]};
function campDDStyle(){if($('imdCampDDStyle'))return;var s=doc.createElement('style');s.id='imdCampDDStyle';
 s.textContent='#imdCampLinkRow .dd-anchor{position:relative}'+
 '#imdCampDDBtn{display:flex;align-items:center;justify-content:space-between;gap:8px;width:100%;box-sizing:border-box;cursor:pointer;text-align:right;background:#fff}'+
 '#imdCampDDBtn .dd-txt{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}'+
 '#imdCampDDBtn .dd-car{font-size:11px;color:#5c6f68;transition:transform .15s}'+
 '#imdCampDDBtn[aria-expanded="true"] .dd-car{transform:rotate(180deg)}'+
 '#imdCampDDPop{position:absolute;inset-inline:0;top:100%;margin-top:4px;z-index:60;background:#fff;border:1px solid #cfdcd6;border-radius:10px;box-shadow:0 10px 28px rgba(15,40,30,.18);padding:8px;max-height:320px;display:flex;flex-direction:column}'+
 '#imdCampDDPop[hidden]{display:none!important}'+
 '#imdCampDDPop .dd-search{margin-bottom:6px}'+
 '#imdCampDDPop .dd-list{overflow:auto;flex:1}'+
 '#imdCampDDPop .dd-opt{display:flex;align-items:center;gap:8px;padding:8px 10px;border-radius:8px;cursor:pointer;font-size:13px}'+
 '#imdCampDDPop .dd-opt:hover{background:#f2f7f5}'+
 '#imdCampDDPop .dd-opt input{width:16px;height:16px;margin:0}'+
 '#imdCampDDPop .dd-all{font-weight:700;border-bottom:1px solid #e6eeea;border-radius:8px 8px 0 0;margin-bottom:4px}'+
 '#imdCampDDPop .dd-foot{display:flex;justify-content:space-between;align-items:center;gap:8px;border-top:1px solid #e6eeea;padding-top:8px;margin-top:6px;font-size:12px;color:#5c6f68}'+
 ':root[data-theme=dark] #imdCampDDBtn,:root[data-theme=dark] #imdCampDDPop{background:#18231f;border-color:#2c3b35;color:#e6efeb}'+
 ':root[data-theme=dark] #imdCampDDPop .dd-opt:hover{background:#22302a}';
 doc.head.appendChild(s);}
function campDDSummary(){if(CAMP_DD.all)return 'جميع المعسكرات';
 var names=[];forEach(CAMP_DD.camps,function(c){if(CAMP_DD.ids.indexOf(c.id)>=0)names.push(c.name);});
 if(!names.length)return 'اختر المعسكرات…';
 return names.length<=2?names.join('، '):names.slice(0,2).join('، ')+' +'+(names.length-2);}
function campDDPaint(){var t=$('imdCampDDTxt');if(t)t.textContent=campDDSummary();
 var pop=$('imdCampDDPop');if(!pop)return;var q=(($('imdCampDDSearch')||{}).value||'').trim();
 var allChk=$('imdCampDDAll');if(allChk)allChk.checked=CAMP_DD.all;
 var h='';forEach(CAMP_DD.camps,function(c){var label=(c.code?c.code+'-':'')+c.name;if(q&&label.indexOf(q)<0)return;
  var on=!CAMP_DD.all&&CAMP_DD.ids.indexOf(c.id)>=0;
  h+='<label class="dd-opt"><input type="checkbox" data-camp="'+escv(c.id)+'"'+(on?' checked':'')+'> '+escv(label)+'</label>';});
 if(!CAMP_DD.camps.length)h='<div style="padding:10px;font-size:12px;color:#98a8a0">لا توجد معسكرات بعد — أضف المعسكرات أولًا من شاشة الوحدات</div>';
 else if(!h)h='<div style="padding:10px;font-size:12px;color:#98a8a0">لا نتائج مطابقة</div>';
 var list=$('imdCampDDList');if(list)list.innerHTML=h;
 var cnt=$('imdCampDDCount');if(cnt)cnt.textContent=CAMP_DD.all?'كل المعسكرات':(CAMP_DD.ids.length+' محدد');}
function campDDOpen(open){var pop=$('imdCampDDPop'),btn=$('imdCampDDBtn');if(!pop||!btn)return;
 pop.hidden=!open;btn.setAttribute('aria-expanded',open?'true':'false');
 if(open){campDDPaint();var s=$('imdCampDDSearch');if(s){s.value='';setTimeout(function(){try{s.focus();}catch(e){}},0);}}}
function injectCampLinkRow(){if($('imdCampLinkRow')||!$('stoLocation'))return;
 loadUnits(function(us){if($('imdCampLinkRow'))return;campDDStyle();
  var camps=[];forEach(us,function(u){if(!u.parentId)camps.push(u);});
  CAMP_DD={camps:camps,all:true,ids:[]};
  try{var st=window.STO;var ed=st&&st.editId?st.items.find(function(x){return x.id===st.editId;}):null;
   if(ed){CAMP_DD.ids=(ed.campIds||[]).slice();CAMP_DD.all=ed.feedsAllCamps!==false&&!CAMP_DD.ids.length;}}catch(e){}
  var html='<div class="field" id="imdCampLinkRow"><label>🏕️ يغذي معسكر <span style="font-weight:400;color:#5c6f68">(يتيح ربط المستودع بالصرف/التحويل تلقائيًا)</span></label>'+
  '<div class="dd-anchor"><button type="button" class="fld" id="imdCampDDBtn" aria-haspopup="listbox" aria-expanded="false"><span class="dd-txt" id="imdCampDDTxt"></span><span class="dd-car">▼</span></button>'+
  '<div id="imdCampDDPop" hidden>'+
   (camps.length>6?'<input class="fld dd-search" id="imdCampDDSearch" placeholder="🔍 بحث عن معسكر">':'')+
   '<label class="dd-opt dd-all"><input type="checkbox" id="imdCampDDAll"> جميع المعسكرات</label>'+
   '<div class="dd-list" id="imdCampDDList"></div>'+
   '<div class="dd-foot"><span id="imdCampDDCount"></span><button type="button" class="btn btn-p btn-sm" id="imdCampDDDone">تم</button></div>'+
  '</div></div>'+
  '<div class="note-box" style="margin-top:7px">سيظهر المستودع في الصرف والتحويل فقط عندما يكون مسموحًا لمعسكر الجهة المستفيدة.</div></div>';
  afterField('stoLocation',html);campDDPaint();
  var btn=$('imdCampDDBtn');if(btn)btn.onclick=function(e){e.preventDefault();campDDOpen($('imdCampDDPop').hidden);};
  var all=$('imdCampDDAll');if(all)all.onchange=function(){CAMP_DD.all=all.checked;if(CAMP_DD.all)CAMP_DD.ids=[];campDDPaint();};
  var list=$('imdCampDDList');if(list)list.onchange=function(e){var t=e.target;if(!t||!t.getAttribute)return;var id=t.getAttribute('data-camp');if(!id)return;
   var i=CAMP_DD.ids.indexOf(id);if(t.checked&&i<0)CAMP_DD.ids.push(id);if(!t.checked&&i>=0)CAMP_DD.ids.splice(i,1);
   CAMP_DD.all=false;campDDPaint();};
  var srch=$('imdCampDDSearch');if(srch)srch.oninput=campDDPaint;
  var done=$('imdCampDDDone');if(done)done.onclick=function(){campDDOpen(false);};
  /* إغلاق عند النقر خارج القائمة أو بمفتاح Esc */
  doc.addEventListener('mousedown',function(e){var row=$('imdCampLinkRow');var pop=$('imdCampDDPop');if(!row||!pop||pop.hidden)return;if(!row.contains(e.target))campDDOpen(false);});
  doc.addEventListener('keydown',function(e){if(e.key==='Escape'){var pop=$('imdCampDDPop');if(pop&&!pop.hidden)campDDOpen(false);}});
 });}
function collectCampLink(){
 /* «محدد» بلا أي معسكر يُعامل كجميع المعسكرات حتى لا يختفي المستودع من الصرف والتحويل */
 var all=CAMP_DD.all||!CAMP_DD.ids.length;
 var out={feedsAllCamps:all,campIds:all?[]:CAMP_DD.ids.slice()};
 window.__imdadCampLink=out;return out;}
/* يُستدعى من دالة حفظ المستودع في index.html لإضافة ربط المعسكرات إلى بيانات المستودع */
window.IMDAD_CAMP_LINK=function(){return $('imdCampLinkRow')?collectCampLink():{};};
/* ---------- هوية/شعار: لوحة حفظ موثوقة ---------- */
function renderFormsDesigner(){try{var editable=window.hasPerm?hasPerm('settings','edit'):true;
 var hideRows='';var hSel='';try{var tb=doc.querySelector('#main table');if(tb){hSel=tb.id||'current';}}catch(e){}
 var h='<div class="page-title">🖨️ إعدادات الطباعة والنماذج</div><div class="page-sub">تصميم الرأس الرسمي والتذييل والشعار والتوقيعات والتحكم في الأعمدة — يُطبَّق على كل النماذج (PDF/طابعة/Excel)</div>';
 h+='<div class="icard"><h4>1) بيانات النموذج</h4>'+brandFieldsHTML()+'</div>';
 h+='<div class="icard"><h4>2) التوقيعات</h4><div id="imdSigRows"></div></div>';
 h+='<div class="icard"><h4>3) التحكم في الأعمدة الظاهرة</h4><p style="font-size:12px;color:#5c6f68">افتح أي شاشة (مثل الأصناف) ثم اضغط «التقاط أعمدة الجدول الحالي» لإظهار مربعات الإخفاء.</p>'+
 '<div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center"><button class="btn btn-o btn-sm" id="imdColCapture" type="button">🎯 التقاط أعمدة الجدول الحالي</button><span id="imdColHost" style="font-size:12px;color:#5c6f68"></span></div></div>';
 h+='<div class="icard"><h4>4) الحفظ والمعاينة</h4><div style="display:flex;gap:8px;flex-wrap:wrap">'+
 '<button class="btn btn-p btn-sm" id="imdDzSave" type="button">💾 حفظ الإعدادات</button>'+
 '<button class="btn btn-o btn-sm" id="imdDzPrev" type="button">🖨️ معاينة نموذج</button>'+
 '<button class="btn btn-o btn-sm" id="imdDzReset" type="button">↩️ تصفير</button></div></div>';
 var main=$('main');if(main)main.innerHTML=h;
 renderSigRows();bindBrandFields();
 var cs=$('imdColCapture');if(cs)cs.onclick=function(){try{
  var tb=doc.querySelector('#main table');
  var id, heads;
  if(tb){id=tb.id||('tbl_'+Date.now());heads=tb.querySelectorAll('th');}
  else if(lastTableSnapshot){id=lastTableSnapshot.id;heads=null;}
  else{nof('✖ افتح شاشة بها جدول أولًا (مثل الأصناف)، ثم عد لهذه الشاشة والتقط أعمدتها');return;}
  var hid=CFG.hideCols[id]||[];var html='';
  if(heads){forEach(heads,function(th,i){var on=hid.indexOf(i)<0;html+='<label style="display:inline-flex;gap:4px;align-items:center;margin:4px 8px 4px 0;font-size:12px"><input type="checkbox" data-col="'+i+'"'+(on?' checked':'')+'> '+escv((th.textContent||('عمود '+(i+1))).trim())+'</label>';});}
  else{forEach(lastTableSnapshot.headers,function(label,i){var on=hid.indexOf(i)<0;html+='<label style="display:inline-flex;gap:4px;align-items:center;margin:4px 8px 4px 0;font-size:12px"><input type="checkbox" data-col="'+i+'"'+(on?' checked':'')+'> '+escv(label)+'</label>';});}
  if(!html)html='<span style="color:#98a8a0">لا توجد رؤوس</span>';var host=$('imdColHost');host.innerHTML='<b>('+id+'):</b> '+html;host.setAttribute('data-tbl',id);/* إصلاح: كان data-tbl لا يُضبط إطلاقًا فيفشل الحفظ لاحقًا بصمت */}
  catch(e){nof('✖ '+e.message);}};
 var sv=$('imdDzSave');if(sv)sv.onclick=function(){collectBrandFields();try{var host=$('imdColHost');var id=(host&&host.getAttribute('data-tbl'))||'';if(id&&host){var hid=[];forEach(host.querySelectorAll('input[data-col]'),function(c){if(!c.checked)hid.push(Number(c.getAttribute('data-col')));});CFG.hideCols[id]=hid;}}catch(e){}
  brandToApp();saveCfg();};
 var pv=$('imdDzPrev');if(pv)pv.onclick=function(){collectBrandFields();showPrintModal(printHTML('<table class="tbl-d"><tr><th>الكود</th><th>الصنف</th><th>الكمية</th><th>الوحدة</th></tr><tr><td>1001</td><td>مثال</td><td>10</td><td>كرتون</td></tr></table>','معاينة النموذج'));};
 var rs=$('imdDzReset');if(rs)rs.onclick=function(){if(!confirm('تصفير إعدادات النماذج؟'))return;CFG=defaultCfg();window.CFG=CFG;renderFormsDesigner();nof('✔ تم التصفير');};}catch(e){nof('✖ '+e.message);}}
function defaultCfg(){return {header:'نظام الإمداد والتموين',sub:'إدارة المخزون والاستحقاقات',footer:'وثيقة داخلية — نظام إمداد',logo:'',entity:{name:'',addr:'',phone:''},signatures:[{role:'المسؤول',name:''},{role:'أمين المستودع',name:''},{role:'قائد الوحدة',name:''}],pageSize:'A4',orient:'portrait',hideCols:{},loaded:true};}
function brandFieldsHTML(){return '<div style="display:flex;flex-wrap:wrap;gap:8px">'+
 '<div class="field" style="flex:1;min-width:200px"><label>الرأس الرسمي (اسم النظام)</label><input class="fld" id="imdBrHeader" value="'+escv(CFG.header||'')+'"></div>'+
 '<div class="field" style="flex:1;min-width:200px"><label>العنوان الفرعي</label><input class="fld" id="imdBrSub" value="'+escv(CFG.sub||'')+'"></div>'+
 '<div class="field" style="flex:1;min-width:200px"><label>اسم الجهة</label><input class="fld" id="imdBrEntity" value="'+escv(CFG.entity.name||'')+'"></div>'+
 '<div class="field" style="flex:1;min-width:200px"><label>عنوان الجهة</label><input class="fld" id="imdBrAddr" value="'+escv(CFG.entity.addr||'')+'"></div>'+
 '<div class="field" style="flex:1;min-width:160px"><label>هاتف الجهة</label><input class="fld" id="imdBrPhone" value="'+escv(CFG.entity.phone||'')+'"></div>'+
 '<div class="field" style="flex:1;min-width:220px"><label>التذييل</label><input class="fld" id="imdBrFooter" value="'+escv(CFG.footer||'')+'"></div>'+
 '<div class="field" style="width:100%"><label>الشعار</label><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><img id="imdBrLogoPrev" style="width:52px;height:52px;object-fit:contain;border:1px solid #dfe9e4;border-radius:8px;background:#f6faf8;display:'+(CFG.logo?'block':'none')+'" src="'+escv(CFG.logo||'')+'">'+
 '<button class="btn btn-o btn-sm" id="imdBrLogoPick" type="button">📷 اختيار شعار</button><button class="btn btn-o btn-sm" id="imdBrLogoClear" type="button">🗑️ إزالة</button></div></div></div>';}
function bindBrandFields(){try{var pv=$('imdBrLogoPrev');var pk=$('imdBrLogoPick');if(pk)pk.onclick=function(){filePick('image/*',function(f){var r=new FileReader();r.onload=function(){CFG.logo=String(r.result);if(pv){pv.src=CFG.logo;pv.style.display='block';}nof('✔ الشعار جاهز — اضغط حفظ الإعدادات');};r.readAsDataURL(f);});};
 var cl=$('imdBrLogoClear');if(cl)cl.onclick=function(){CFG.logo='';if(pv){pv.src='';pv.style.display='none';}};}catch(e){}}
function collectBrandFields(){try{var g=function(id){var e=$(id);return e?e.value.trim():'';};if($('imdBrHeader'))CFG.header=g('imdBrHeader')||'نظام الإمداد والتموين';if($('imdBrSub'))CFG.sub=g('imdBrSub');if($('imdBrFooter'))CFG.footer=g('imdBrFooter');
 if($('imdBrEntity'))CFG.entity.name=g('imdBrEntity');if($('imdBrAddr'))CFG.entity.addr=g('imdBrAddr');if($('imdBrPhone'))CFG.entity.phone=g('imdBrPhone');
 forEach(doc.querySelectorAll('#imdSigRows .imd-sig-row'),function(row){var i=Number(row.getAttribute('data-i')||0);var c=CFG.signatures[i];if(!c)return;var rl=row.querySelector('.imd-sig-role'),rn=row.querySelector('.imd-sig-name');if(rl)c.role=rl.value.trim();if(rn)c.name=rn.value.trim();});}catch(e){}}
function renderSigRows(){var host=$('imdSigRows');if(!host)return;var html='';forEach(CFG.signatures,function(s,i){html+='<div class="imd-sig-row" data-i="'+i+'" style="display:flex;gap:8px;margin-bottom:6px;flex-wrap:wrap"><div class="field" style="flex:1;min-width:150px;margin:0"><label>الوظيفة</label><input class="fld imd-sig-role" value="'+escv(s.role||'')+'"></div><div class="field" style="flex:1;min-width:180px;margin:0"><label>الاسم</label><input class="fld imd-sig-name" value="'+escv(s.name||'')+'"></div></div>';});host.innerHTML=html;}

/* ---------- تفعيل الصفحات ---------- */
var lastTableSnapshot=null; /* إصلاح: يحفظ آخر جدول ظاهر قبل مغادرة الشاشة، لأن
  "التقاط أعمدة الجدول الحالي" في شاشة الإعدادات كان يبحث دائمًا عن جدول في
  #main وقت الضغط — وبما أن شاشة الإعدادات نفسها لا تحتوي جدولاً، كان الالتقاط
  يفشل دائمًا بلا استثناء (لم يكن يعمل إطلاقًا على أي شاشة). */
function onPage(p){try{injectToolbar(p);
 try{var meta=PM[p];if(meta&&meta.t){var tb=doc.getElementById(meta.t);if(tb){var heads=tb.querySelectorAll('th');var labels=[];forEach(heads,function(th,i){labels.push((th.textContent||('عمود '+(i+1))).trim());});lastTableSnapshot={id:meta.t,headers:labels};}}}catch(e){}
 if(p==='stores'){injectCampLinkRow();}
}catch(e){}}
var SET_SUB={branding:'company',formsDesigner:'print'};
function injectBackToSettings(p){var main=$('main');if(!main||!main.firstChild)return;
 var bar=doc.createElement('div');bar.id='imdBackSet';bar.className='rbar';bar.style.margin='0 0 8px';
 var b=doc.createElement('button');b.type='button';b.className='btn btn-o btn-sm';b.textContent='→ رجوع إلى الإعدادات';
 b.onclick=function(){try{localStorage.setItem('imdad.settings.sec',SET_SUB[p]);}catch(e){}window.curPage='settings';if(typeof window.renderPage==='function')window.renderPage();};
 bar.appendChild(b);main.insertBefore(bar,main.firstChild);}
function boot(){loadCfg(function(){autobind();var last='';
 setInterval(function(){try{var p=window.curPage;if(p&&p!==last){last=p;setTimeout(function(){onPage(p);},200);}
  if(p==='stores'&&!$('imdCampLinkRow')&&$('stoLocation'))injectCampLinkRow();
  if(SET_SUB[p]&&!$('imdBackSet'))injectBackToSettings(p);
  syncToolbar(p);}catch(e){} },800);
 var main=$('main');if(main&&typeof MutationObserver!=='undefined'){var obs=new MutationObserver(function(muts){try{var ae=doc.activeElement;if(ae&&/INPUT|TEXTAREA|SELECT/.test(ae.tagName))return;
  var top=0;for(var i=0;i<muts.length;i++){if(muts[i].target===main&&muts[i].type==='childList'){top=1;break;}}
  if(top){setTimeout(function(){window.scrollTo(0,0);main.scrollTop=0;},30);}}catch(e){}});
  obs.observe(main,{childList:true,subtree:false});}
 setInterval(autobind,2500);});}
/* إصلاح جوهري (استكمال شاشة إعدادات الطباعة والنماذج): كانت renderFormsDesigner
   وCFG محصورتين داخل النطاق الخاص بهذا الملف (IIFE) ولم تُصدَّرا إلى window
   إطلاقًا — بينما استدعاء الشاشة من index.html (عبر النقر على القائمة) يتم من
   نطاق مختلف تمامًا ويحتاج window.renderFormsDesigner. النتيجة: الشاشة كانت
   غير قابلة للفتح إطلاقًا منذ إضافتها — أي نقر على «🖨️ إعدادات الطباعة
   والنماذج» في القائمة كان يفشل بصمت (الخطأ كان يُلتقط ويُتجاهل عبر try/catch
   في index.html فلا يظهر أي أثر له). كذلك window.CFG مطلوبة لتطبيق التذييل
   المخصص على الطباعة الفعلية (militaryPrint.customFooterLine). */
window.renderFormsDesigner=renderFormsDesigner;
window.CFG=CFG;
if(/complete|interactive/.test(doc.readyState))setTimeout(boot,0);else doc.addEventListener('DOMContentLoaded',boot);
})();
