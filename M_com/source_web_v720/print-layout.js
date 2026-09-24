/* IMDAD Print Layout v1 — تخطيط المستندات الرسمية القابل للتحكم
   يستبدل رأس الصفحة وبيانات السند والتوقيعات والتذييل في محرك الطباعة الرسمي (militaryPrint)
   بتخطيط يضبطه المستخدم من «إعدادات الطباعة والنماذج»:
   - رأس يمين: أسطر الجهة (نص، حجم، عريض، محاذاة، لون، ترتيب).
   - رأس يسار: الحقول (التاريخ، رقم السند، رقم القيد، حقول مخصصة) بعنوان يمين وبيانات يسار.
   - بيانات السند لكل نوع مستند: الحقول الظاهرة وعناوينها وترتيبها وعدد الأعمدة.
   - التوقيعات لكل نوع، والتذييل، والخط والألوان.
   يُحفظ في settings/printLayout مع نسخة محلية. */
(function(){
'use strict';
var d=document;
function $(id){return d.getElementById(id);}
function E(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
function T(m){if(typeof toast==='function')toast(m);}
function clone(o){return JSON.parse(JSON.stringify(o));}
function MP(){try{return militaryPrint;}catch(e){return null;}}
function APP(){try{return APP_CFG;}catch(e){return {};}}

var TYPE_LBL={receive:'سند توريد مخزني',issue:'أمر صرف مخزني',receipt:'استلام مخزني (إشعار)',transfer:'إذن تحويل مخزني',return_unit:'مرتجع من وحدة',return_supplier:'مرتجع إلى مورّد',generic:'التقارير والكشوف'};
var REF_LBL={receive:'رقم سند التوريد',issue:'رقم أمر الصرف',receipt:'رقم الاستلام',transfer:'رقم إذن التحويل',return_unit:'رقم سند المرتجع',return_supplier:'رقم سند المرتجع',generic:'المرجع'};
function F(key,label,show){return {key:key,label:label,show:show!==false};}
function S(title,name,show){return {title:title,name:name||'',show:show!==false};}
function defaults(){
  var a=APP();
  return {
    font:'Cairo',size:12,accent:'#2E6B35',
    logo:{show:true,size:85},
    right:[{text:a.orgLine1||'الجمهورية اليمنية',size:15,bold:true,align:'right',color:'#0e6b3e'},{text:a.orgLine2||'',size:13,bold:true,align:'right',color:'#123524'},
      {text:a.orgLine3||'',size:13,bold:true,align:'right',color:'#123524'},{text:a.orgLine4||'',size:13,bold:true,align:'right',color:'#123524'}],
    left:[{key:'date',label:'التاريخ',value:'',show:true,bold:true,size:12},{key:'ref',label:'',value:'',show:true,bold:true,size:12},{key:'entry',label:'رقم القيد',value:'',show:true,bold:false,size:12}],
    leftAlign:'left',
    approval:{show:true,title:'مصادقة رئيس شعبة الإمداد والتموين'},
    title:{size:18,align:'center',underline:true,showRef:true},
    info:{columns:2,labelBold:true,size:12,valueAlign:'left',labelAlign:'right'},
    table:{headAlign:'center',cellAlign:'center',firstColAlign:'center',numAlign:'center',headBg:'',size:11.5},
    types:{
      receive:{info:[F('warehouse','المستودع'),F('ref','رقم السند'),F('supplier','الجهة الموردة'),F('date','تاريخ التوريد'),F('invoiceNo','رقم الفاتورة / التاجر'),F('notes','ملاحظات السند'),F('committee','لجنة الاستلام',false)],
        sigs:[S('ركن إدارة الإمداد'),S('مدير مخزن ({warehouse})'),S('المراجعة والتدقيق','{audit}'),S('الرقابة والتفتيش','{supervision}')]},
      issue:{info:[F('warehouse','جهة الصرف'),F('beneficiary','اسم الوحدة / الجهة'),F('strength','قوة الأفراد'),F('days','مدة الإعاشة (يوم)'),F('start_date','من تاريخ'),F('end_date','إلى تاريخ'),F('ref','رقم أمر الصرف',false),F('notes','المبررات والملاحظات')],
        sigs:[S('ركن إدارة الإمداد'),S('مكتب إدارة الإمداد')]},
      receipt:{info:[F('receiverName','اسم المستلم'),F('receiverRank','الرتبة'),F('beneficiary','الوحدة المستفيدة'),F('strength','قوة الأفراد'),F('date','تاريخ الاستلام'),F('days','مدة الإعاشة (يوم)')],
        sigs:[S('الجهة المسلّمة ({warehouse})'),S('المستلم / المعتمد')],statement:'استلمت أنا الموضحة بياناتي أعلاه الأصناف المبينة في الجدول بتمامها وكمالها.'},
      transfer:{info:[F('warehouse','المستودع المصدر'),F('destWarehouse','المستودع المستقبل'),F('campName','المعسكر المستفيد'),F('strength','قوة المعسكر'),F('days','مدة الإعاشة (يوم)'),F('statusLabel','حالة التحويل'),F('date','تاريخ الإرسال'),F('notes','مبررات وملاحظات')],
        sigs:[S('ركن إدارة الإمداد'),S('مكتب إدارة الإمداد')]},
      return_unit:{info:[F('warehouse','المستودع'),F('party','الوحدة المرتجعة'),F('condition','حالة الأصناف'),F('date','تاريخ المرتجع'),F('notes','مبررات وملاحظات')],
        sigs:[S('الجهة المسلّمة ({party})'),S('المستلم ({warehouse})')]},
      return_supplier:{info:[F('warehouse','المستودع'),F('party','الجهة الموردة'),F('date','تاريخ المرتجع'),F('origRef','مرجع السند الأصلي'),F('notes','مبررات وملاحظات')],
        sigs:[S('الجهة المسلّمة ({warehouse})'),S('المستلم ({party})')]},
      generic:{info:[],sigs:[S('ركن إدارة الإمداد'),S('مكتب إدارة الإمداد')]}
    },
    footer:{text:'',align:'center',size:10,bold:true,printedBy:true,pageNo:true}
  };
}
/* دمج المحفوظ مع الافتراضي (للحقول الجديدة مستقبلًا) */
function mergeCfg(base,saved){if(!saved||typeof saved!=='object')return base;
  Object.keys(saved).forEach(function(k){var v=saved[k];
    if(v&&typeof v==='object'&&!Array.isArray(v)&&base[k]&&typeof base[k]==='object'&&!Array.isArray(base[k]))base[k]=mergeCfg(base[k],v);else base[k]=v;});return base;}
var PL=defaults(),LS='imdad.printLayout';
try{var ls=localStorage.getItem(LS);if(ls)PL=mergeCfg(defaults(),JSON.parse(ls));}catch(e){}
async function loadPL(){try{var s=await db.collection('settings').doc('printLayout').get();if(s.exists){PL=mergeCfg(defaults(),s.data().layout||s.data());try{localStorage.setItem(LS,JSON.stringify(PL));}catch(e){}}}catch(e){}}
async function savePL(){try{localStorage.setItem(LS,JSON.stringify(PL));}catch(e){}
  await db.collection('settings').doc('printLayout').set({layout:clone(PL),updatedAt:ST(),updatedBy:(me.state&&me.state.email)||''});}

/* ───── العرض ───── */
function fontStack(){return "'"+PL.font+"', Cairo, 'Traditional Arabic', Arial, sans-serif";}
function fill(tpl,m){return String(tpl||'').replace(/\{(\w+)\}/g,function(_,k){var v=m&&m[k];return v==null||v===''?'……':String(v);});}
function rightBlock(){
  return '<div dir="rtl" style="font-family:'+fontStack()+';line-height:1.45">'+PL.right.filter(function(l){return l.text;}).map(function(l){
    return '<div style="text-align:'+(l.align||'right')+';font-size:'+(+l.size||13)+'px;font-weight:'+(l.bold?'800':'500')+';color:'+E(l.color||'#123524')+'">'+E(l.text)+'</div>';}).join('')+'</div>';
}
function kv(label,value,o){o=o||{};var sz=+o.size||PL.info.size;
  return '<table dir="rtl" width="100%" cellpadding="0" cellspacing="0" style="border:none;font-family:'+fontStack()+';font-size:'+sz+'px"><tr>'+
    '<td style="text-align:'+(o.labelAlign||PL.info.labelAlign||'right')+';white-space:nowrap;font-weight:'+(o.bold===false?'500':'800')+';color:#333;padding:2px 0 2px 8px">'+E(label)+(label?':':'')+'</td>'+
    '<td style="text-align:'+(o.valueAlign||PL.info.valueAlign||'left')+';padding:2px 0;'+(o.valueStyle||'')+'">'+value+'</td></tr></table>';
}
function leftBlock(dateStr,refStr,refLabel){
  var vals={date:E(dateStr||'……'),ref:'<span style="font-weight:900;color:#b78103">'+E(refStr||'……')+'</span>',entry:'……'};
  return '<div style="display:inline-block;min-width:190px;text-align:right">'+PL.left.filter(function(f){return f.show!==false;}).map(function(f){
    var label=f.label||(f.key==='ref'?refLabel:f.key==='date'?'التاريخ':f.key==='entry'?'رقم القيد':'');
    var val=f.key==='custom'?E(f.value||'……'):(f.value?E(f.value):vals[f.key]||'……');
    return kv(label,val,{bold:f.bold,size:f.size});}).join('')+'</div>';
}
function documentHeader(dateStr,refStr,title,titleColor,refLabel,showApproval){
  var a=APP(),logo=PL.logo.show?(a.logoUrl?'<img src="'+E(a.logoUrl)+'" style="width:'+PL.logo.size+'px;height:'+PL.logo.size+'px;object-fit:contain" alt="شعار">'
    :'<img src="assets/logo.png" style="width:'+PL.logo.size+'px;height:'+PL.logo.size+'px;object-fit:contain" alt="شعار">'):'';
  var appr=(showApproval&&PL.approval.show)?'<div style="border:1.5px solid '+E(PL.accent)+';padding:4px 8px;text-align:center;width:170px;border-radius:6px;margin-bottom:6px;display:inline-block">'+
    '<div style="font-size:10.5px;font-weight:900;border-bottom:1px solid #ddd;padding-bottom:3px;margin-bottom:12px;color:'+E(PL.accent)+'">'+E(PL.approval.title)+'</div><div style="font-size:10px;color:#666">التوقيع: ……………</div></div>':'';
  var la=PL.leftAlign||'left';
  return '<table dir="rtl" width="100%" cellpadding="0" cellspacing="0" style="border:none;font-family:'+fontStack()+';margin-bottom:4px"><tr>'+
    '<td width="38%" valign="top" style="text-align:right">'+rightBlock()+'</td>'+
    '<td width="24%" valign="middle" style="text-align:center">'+logo+'</td>'+
    '<td width="38%" valign="top" style="text-align:'+la+'">'+(appr?appr+'<br>':'')+leftBlock(dateStr,refStr,refLabel||'رقم السند')+'</td></tr></table>'+
    '<hr style="border:0;border-top:2.5px solid '+E(PL.accent)+';margin:4px 0 8px">'+
    '<table dir="rtl" width="100%" cellpadding="0" cellspacing="0" style="border:none;margin:2px 0 8px;font-family:'+fontStack()+'"><tr>'+
    '<td width="22%" style="text-align:right;font-size:13px;font-weight:700;color:#555">'+(PL.title.showRef&&refStr?'المرجع: '+E(refStr):'&nbsp;')+'</td>'+
    '<td width="56%" style="text-align:'+(PL.title.align||'center')+'"><h2 style="color:'+E(titleColor||PL.accent)+';margin:0;font-size:'+(+PL.title.size||18)+'px;font-weight:900;display:inline-block;padding-bottom:3px;'+(PL.title.underline?'border-bottom:2px dashed '+E(titleColor||PL.accent):'')+'">'+title+'</h2></td>'+
    '<td width="22%">&nbsp;</td></tr></table>';
}
/* بيانات السند: عنوان الحقل يمينًا وبياناته يسارًا، بعدد أعمدة قابل للضبط */
function infoTable(sectionTitle,pairs){
  if(!pairs.length)return '';
  var cols=Math.max(1,Math.min(3,+PL.info.columns||2)),rows='';
  for(var i=0;i<pairs.length;i+=cols){rows+='<tr>';
    for(var j=0;j<cols;j++){var p=pairs[i+j];
      rows+='<td width="'+Math.floor(100/cols)+'%" style="padding:4px 8px;border-bottom:1px dotted #bbb;vertical-align:top">'+(p?kv(p[0],p[1],{bold:PL.info.labelBold}):'&nbsp;')+'</td>';}
    rows+='</tr>';}
  return '<table dir="rtl" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:8px;border-collapse:collapse;border:1px solid #ddd;font-family:'+fontStack()+'">'+
    (sectionTitle?'<tr><td colspan="'+cols+'" style="text-align:right;padding:4px 8px;font-weight:900;font-size:13px;border-bottom:1.5px solid '+E(PL.accent)+';color:'+E(PL.accent)+';background:#f0f6f2">'+E(sectionTitle)+'</td></tr>':'')+rows+'</table>';
}
function typeInfo(type,m){
  var t=PL.types[type]||{info:[]},v=Object.assign({receiverName:'……………………',receiverRank:'……………………'},m||{});
  if(type==='issue'||type==='receipt'||type==='transfer'){if(v.days)v.days=String(v.days);}
  return t.info.filter(function(f){return f.show!==false;}).map(function(f){var x=v[f.key];return [f.label,E(x==null||x===''?'—':x)];});
}
function signatures(type,m){
  var t=PL.types[type]||PL.types.generic,list=(t.sigs||[]).filter(function(s){return s.show!==false&&s.title;});if(!list.length)return '';
  var w=Math.floor(100/list.length);
  return '<table dir="rtl" width="100%" style="border:none;margin-top:22px;font-family:'+fontStack()+';font-size:'+(PL.size+1)+'px"><tr>'+list.map(function(s){
    var nm=fill(s.name,m);return '<td width="'+w+'%" style="text-align:center;vertical-align:top"><b>'+E(fill(s.title,m))+'</b><br><br>'+(s.name&&nm!=='……'?'<span style="font-size:11px;color:#555">'+E(nm)+'</span>':'……………………')+'</td>';}).join('')+'</tr></table>';
}
function footer(i,n){
  var f=PL.footer,h='';
  if(f.text)h+='<div dir="rtl" style="text-align:'+f.align+';font-size:'+(+f.size||10)+'px;font-weight:'+(f.bold?'800':'500')+';color:'+E(PL.accent)+';margin-top:6px;font-family:'+fontStack()+'">'+E(f.text)+'</div>';
  else{var mp=MP();try{var old=window.CFG&&CFG.footer?String(CFG.footer).trim():'';if(old)h+='<div dir="rtl" style="text-align:'+f.align+';font-size:'+(+f.size||10)+'px;font-weight:700;color:'+E(PL.accent)+';margin-top:6px">'+E(old)+'</div>';}catch(e){}}
  var parts=[];if(f.printedBy){var mp2=MP();parts.push('طُبع بواسطة: '+E(mp2?mp2.getCurrentUsername():'')+' — '+new Date().toLocaleString('ar-EG'));}
  if(f.pageNo&&n>1)parts.push('صفحة '+(i+1)+' من '+n);
  if(parts.length)h+='<p dir="rtl" style="text-align:center;font-size:9px;color:#888;margin-top:12px;border-top:1px dotted #ccc;padding-top:4px">'+parts.join(' · ')+'</p>';
  return h;
}
var SECTION={receive:'بيانات سند التوريد',issue:'بيانات الصرف والجهة المستفيدة',receipt:'بيانات الاستلام',transfer:'بيانات التحويل المخزني',return_unit:'بيانات مرتجع من وحدة مستفيدة',return_supplier:'بيانات مرتجع إلى مورّد'};
function buildPages(m,rows,title,titleColor,type){
  var mp=MP(),dateStr=m.start_date||m.date||new Date().toISOString().slice(0,10),first=18,other=28,chunks=[];
  if(!rows||!rows.length)chunks.push([]);else{chunks.push(rows.slice(0,first));var left=rows.slice(first);while(left.length){chunks.push(left.slice(0,other));left=left.slice(other);}}
  var head=documentHeader(dateStr,m.ref||'',title,titleColor,REF_LBL[type]||'رقم السند',type==='receive'||type==='daily_work');
  var info=infoTable(SECTION[type]||'',typeInfo(type,m));
  var headers=m.is_multi_unit?['م','اسم الصنف','الكمية','الوحدة','الوحدة المستفيدة','ملاحظات']:['م','الكود','اسم الصنف','الكمية','الوحدة','ملاحظات'];
  return chunks.map(function(ch,i){
    var h=head+(i===0?info:'')+'<table dir="rtl" width="100%" style="border:none;margin:4px 0;font-family:'+fontStack()+'"><tr><td style="text-align:right;font-weight:900;font-size:13px;color:'+E(PL.accent)+'">جدول الأصناف والمواد:</td>'+
      '<td style="text-align:left;font-size:11px;color:#555">صفحة '+(i+1)+' من '+chunks.length+'</td></tr></table>'+mp.itemsTable(headers,ch);
    if(type==='receipt'&&(PL.types.receipt||{}).statement)h+='<div dir="rtl" style="font-size:12px;font-weight:bold;margin-top:8px;color:#123524">'+E(PL.types.receipt.statement)+'</div>';
    if(i===chunks.length-1)h+=signatures(type,m);
    return h+footer(i,chunks.length);
  });
}
function install(){
  var mp=MP();if(!mp||mp.__pl)return;mp.__pl=true;
  mp.getOrgHtml=rightBlock;
  mp.documentHeader=function(dateStr,refStr,title,titleColor,refLabel,showApproval){return documentHeader(dateStr,refStr,title,titleColor,refLabel,showApproval);};
  mp.infoRow2Cols=function(lr,vr,ll,vl){var cells=[[lr,vr]];if(ll)cells.push([ll,vl]);return '<tr>'+cells.map(function(c){return '<td colspan="'+(cells.length===1?4:2)+'" style="padding:4px 8px;border-bottom:1px dotted #bbb">'+kv(c[0],c[1]==null?'':c[1],{bold:PL.info.labelBold})+'</td>';}).join('')+'</tr>';};
  mp.infoRowFull=function(l,v){return '<tr><td colspan="4" style="padding:4px 8px;border-bottom:1px dotted #bbb">'+kv(l,v,{bold:PL.info.labelBold})+'</td></tr>';};
  mp.signatures=function(type,m){return signatures(type==='issue'||type==='transfer'||type==='receive'||type==='receipt'||type==='return_unit'||type==='return_supplier'?type:'generic',m||{});};
  mp.customFooterLine=function(){return '';};
  var oTbl=mp.itemsTable;
  mp.itemsTable=function(headers,rows){var t=PL.table||{},acc=E(PL.accent);
    var h='<table dir="rtl" width="100%" style="border-collapse:collapse;font-family:'+fontStack()+';font-size:'+(+t.size||11.5)+'px;margin-bottom:8px"><thead><tr>';
    headers.forEach(function(x){h+='<th style="background:'+(t.headBg||acc)+';color:#fff;padding:5px 6px;border:1px solid #222;text-align:'+(t.headAlign||'center')+';font-weight:900">'+x+'</th>';});
    h+='</tr></thead><tbody>';
    if(!rows||!rows.length)h+='<tr><td colspan="'+headers.length+'" style="padding:10px;text-align:center">لا توجد أصناف</td></tr>';
    else rows.forEach(function(r,i){h+='<tr style="background:'+(i%2===0?'#fbfdfc':'#fff')+'">';
      r.forEach(function(c,j){var al=j===0?(t.firstColAlign||'center'):(/^[0-9٠-٩.,٬ \t+-]+$/.test(String(c).replace(/<[^>]*>/g,''))?(t.numAlign||'center'):(t.cellAlign||'center'));
        h+='<td style="padding:4px 5px;border:1px solid #999;text-align:'+al+'">'+c+'</td>';});
      h+='</tr>';});
    return h+'</tbody></table>';};
  mp.buildPages=buildPages;
  loadPL();
}
if(d.readyState!=='loading')install();else d.addEventListener('DOMContentLoaded',install);

/* ───── المحرر داخل «إعدادات الطباعة والنماذج» ───── */
var SEL_TYPE='receive';
function ctl(type,val,attrs){return '<input class="fld" type="'+type+'" value="'+E(val)+'" '+(attrs||'')+' style="margin:0;padding:6px 8px">';}
function sel(opts,val,attrs){return '<select class="fld" '+(attrs||'')+' style="margin:0;padding:6px 8px">'+opts.map(function(o){return '<option value="'+E(o[0])+'"'+(String(o[0])===String(val)?' selected':'')+'>'+E(o[1])+'</option>';}).join('')+'</select>';}
var ALIGN=[['right','يمين'],['center','وسط'],['left','يسار']];
/* محرر قائمة عامة: كل سطر حقول + تحريك/حذف */
function listEditor(id,items,cols,addTpl){
  var h='<div class="twrap"><table class="u" id="'+id+'"><thead><tr>'+cols.map(function(c){return '<th>'+c.t+'</th>';}).join('')+'<th>ترتيب</th></tr></thead><tbody>';
  items.forEach(function(it,i){h+='<tr data-i="'+i+'">'+cols.map(function(c){return '<td>'+c.r(it,i)+'</td>';}).join('')+
    '<td style="white-space:nowrap"><button class="btn btn-o btn-sm" data-mv="-1" type="button" aria-label="أعلى">▲</button> <button class="btn btn-o btn-sm" data-mv="1" type="button" aria-label="أسفل">▼</button>'+
    (addTpl?' <button class="btn btn-d btn-sm" data-rm type="button" aria-label="حذف">✕</button>':'')+'</td></tr>';});
  h+='</tbody></table></div>'+(addTpl?'<button class="btn btn-o btn-sm" data-add="'+id+'" type="button" style="margin-top:6px">+ إضافة</button>':'');
  return h;
}
function bindList(host,id,arr,readRow,addTpl,rerender){
  var t=host.querySelector('#'+id);if(!t)return;
  var sync=function(){[].forEach.call(t.querySelectorAll('tbody tr'),function(tr){readRow(tr,arr[+tr.dataset.i]);});};
  t.addEventListener('input',sync);t.addEventListener('change',sync);
  t.addEventListener('click',function(e){var b=e.target.closest('button');if(!b)return;var tr=b.closest('tr'),i=+tr.dataset.i;sync();
    if(b.dataset.mv){var j=i+(+b.dataset.mv);if(j<0||j>=arr.length)return;var x=arr[i];arr[i]=arr[j];arr[j]=x;rerender();}
    else if(b.hasAttribute('data-rm')){arr.splice(i,1);rerender();}});
  var add=host.querySelector('[data-add="'+id+'"]');if(add)add.onclick=function(){sync();arr.push(clone(addTpl));rerender();};
}
function v(tr,sel){var e=tr.querySelector(sel);return e?(e.type==='checkbox'?e.checked:e.value):'';}
function renderEditor(){
  var host=$('plCard');if(!host)return;var t=PL.types[SEL_TYPE];
  host.innerHTML='<h4>5) تخطيط المستندات الرسمية (السندات والتقارير)</h4>'+
   '<div class="note-box" style="margin-bottom:10px">يُطبَّق على كل النماذج المطبوعة: التوريد والصرف والاستلام والتحويل والمرتجعات والجرد والتقارير. عنوان كل حقل يظهر يمينًا وبياناته يسارًا.</div>'+
   '<h5 style="margin:10px 0 6px">عام</h5><div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:8px">'+
    '<label>الخط'+sel([['Cairo','Cairo'],['IBM Plex Sans Arabic','IBM Plex Sans Arabic'],['Tajawal','Tajawal'],['Traditional Arabic','Traditional Arabic'],['Arial','Arial']],PL.font,'data-g="font"')+'</label>'+
    '<label>حجم الخط الأساسي'+ctl('number',PL.size,'min="9" max="16" data-g="size"')+'</label>'+
    '<label>لون الهوية'+ctl('color',PL.accent,'data-g="accent"')+'</label>'+
    '<label>إظهار الشعار'+sel([['1','نعم'],['0','لا']],PL.logo.show?'1':'0','data-g="logo.show"')+'</label>'+
    '<label>حجم الشعار'+ctl('number',PL.logo.size,'min="40" max="140" data-g="logo.size"')+'</label>'+
    '<label>حجم العنوان'+ctl('number',PL.title.size,'min="12" max="28" data-g="title.size"')+'</label>'+
    '<label>محاذاة العنوان'+sel(ALIGN,PL.title.align,'data-g="title.align"')+'</label>'+
    '<label>تسطير العنوان'+sel([['1','نعم'],['0','لا']],PL.title.underline?'1':'0','data-g="title.underline"')+'</label></div>'+
   '<h5 style="margin:14px 0 6px">رأس الصفحة — يمين (بيانات الجهة)</h5><div id="plRightHost">'+listEditor('plRight',PL.right,[
     {t:'النص',r:function(l){return ctl('text',l.text,'data-f="text" style="min-width:220px"');}},{t:'الحجم',r:function(l){return ctl('number',l.size,'data-f="size" min="8" max="24" style="width:70px"');}},
     {t:'عريض',r:function(l){return '<input type="checkbox" data-f="bold"'+(l.bold?' checked':'')+' aria-label="عريض">';}},{t:'المحاذاة',r:function(l){return sel(ALIGN,l.align,'data-f="align"');}},
     {t:'اللون',r:function(l){return ctl('color',l.color||'#123524','data-f="color"');}}],{text:'',size:13,bold:true,align:'right',color:'#123524'})+'</div>'+
   '<h5 style="margin:14px 0 6px">رأس الصفحة — يسار (التاريخ والأرقام)</h5><label style="display:inline-flex;gap:6px;align-items:center;margin-bottom:6px">موضع الكتلة '+sel(ALIGN,PL.leftAlign,'data-g="leftAlign"')+'</label>'+
    ' <label style="display:inline-flex;gap:6px;align-items:center;margin-bottom:6px">مربع المصادقة '+sel([['1','يظهر في سند التوريد'],['0','مخفي']],PL.approval.show?'1':'0','data-g="approval.show"')+'</label>'+
    ' <label style="display:inline-flex;gap:6px;align-items:center;margin-bottom:6px">عنوانه '+ctl('text',PL.approval.title,'data-g="approval.title" style="min-width:240px"')+'</label>'+
    '<div id="plLeftHost">'+listEditor('plLeft',PL.left,[
     {t:'الحقل',r:function(f){return sel([['date','التاريخ'],['ref','رقم السند (حسب النوع)'],['entry','رقم القيد'],['custom','حقل مخصص']],f.key,'data-f="key"');}},
     {t:'العنوان (فارغ = الافتراضي)',r:function(f){return ctl('text',f.label,'data-f="label"');}},{t:'قيمة ثابتة / مخصصة',r:function(f){return ctl('text',f.value,'data-f="value"');}},
     {t:'إظهار',r:function(f){return '<input type="checkbox" data-f="show"'+(f.show!==false?' checked':'')+' aria-label="إظهار">';}},{t:'عريض',r:function(f){return '<input type="checkbox" data-f="bold"'+(f.bold?' checked':'')+' aria-label="عريض">';}},
     {t:'الحجم',r:function(f){return ctl('number',f.size||12,'data-f="size" min="8" max="18" style="width:70px"');}}],{key:'custom',label:'حقل جديد',value:'',show:true,bold:true,size:12})+'</div>'+
   '<h5 style="margin:14px 0 6px">بيانات المستند والتوقيعات حسب النوع</h5><div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center">'+
    '<label>نوع المستند '+sel(Object.keys(TYPE_LBL).map(function(k){return [k,TYPE_LBL[k]];}),SEL_TYPE,'id="plType"')+'</label>'+
    '<label>أعمدة الحقول '+sel([['1','عمود واحد'],['2','عمودان'],['3','ثلاثة أعمدة']],PL.info.columns,'data-g="info.columns"')+'</label>'+
    '<label>محاذاة البيانات '+sel(ALIGN,PL.info.valueAlign,'data-g="info.valueAlign"')+'</label>'+
    '<label>عناوين عريضة '+sel([['1','نعم'],['0','لا']],PL.info.labelBold?'1':'0','data-g="info.labelBold"')+'</label>'+
    '<label>حجم خط البيانات '+ctl('number',PL.info.size,'min="9" max="16" data-g="info.size" style="width:80px"')+'</label>'+
    '<label>محاذاة العناوين '+sel(ALIGN,PL.info.labelAlign,'data-g="info.labelAlign"')+'</label></div>'+
   '<h5 style="margin:14px 0 6px">جدول الأصناف</h5><div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:8px">'+
    '<label>محاذاة رؤوس الأعمدة'+sel(ALIGN,PL.table.headAlign,'data-g="table.headAlign"')+'</label>'+
    '<label>محاذاة النصوص'+sel(ALIGN,PL.table.cellAlign,'data-g="table.cellAlign"')+'</label>'+
    '<label>محاذاة الأرقام'+sel(ALIGN,PL.table.numAlign,'data-g="table.numAlign"')+'</label>'+
    '<label>محاذاة عمود التسلسل'+sel(ALIGN,PL.table.firstColAlign,'data-g="table.firstColAlign"')+'</label>'+
    '<label>حجم خط الجدول'+ctl('number',PL.table.size,'min="8" max="15" step="0.5" data-g="table.size"')+'</label>'+
    '<label>لون رأس الجدول'+ctl('color',PL.table.headBg||PL.accent,'data-g="table.headBg"')+'</label></div>'+
   (SEL_TYPE==='generic'?'<div class="rc-meta" style="margin:6px 0">حقول التقارير تُحدَّد من كل تقرير؛ يمكنك هنا ضبط التوقيعات فقط.</div>':
    '<div id="plInfoHost" style="margin-top:8px">'+listEditor('plInfo',t.info,[{t:'عنوان الحقل',r:function(f){return ctl('text',f.label,'data-f="label" style="min-width:200px"');}},
     {t:'مصدر البيانات',r:function(f){return '<code>'+E(f.key)+'</code>';}},{t:'إظهار',r:function(f){return '<input type="checkbox" data-f="show"'+(f.show!==false?' checked':'')+' aria-label="إظهار">';}}],null)+'</div>')+
   '<div id="plSigHost" style="margin-top:10px"><b>التوقيعات</b> <span class="rc-meta">يمكن استخدام {warehouse} و{party} و{audit} و{supervision}</span>'+listEditor('plSig',t.sigs,[
     {t:'صفة الموقّع',r:function(s){return ctl('text',s.title,'data-f="title" style="min-width:200px"');}},{t:'الاسم (اختياري)',r:function(s){return ctl('text',s.name,'data-f="name"');}},
     {t:'إظهار',r:function(s){return '<input type="checkbox" data-f="show"'+(s.show!==false?' checked':'')+' aria-label="إظهار">';}}],{title:'توقيع جديد',name:'',show:true})+'</div>'+
   '<h5 style="margin:14px 0 6px">التذييل</h5><div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:8px">'+
    '<label style="grid-column:span 2">نص التذييل'+ctl('text',PL.footer.text,'data-g="footer.text" placeholder="مثال: وثيقة داخلية — نظام الإمداد"')+'</label>'+
    '<label>المحاذاة'+sel(ALIGN,PL.footer.align,'data-g="footer.align"')+'</label><label>الحجم'+ctl('number',PL.footer.size,'min="8" max="14" data-g="footer.size"')+'</label>'+
    '<label>عريض'+sel([['1','نعم'],['0','لا']],PL.footer.bold?'1':'0','data-g="footer.bold"')+'</label>'+
    '<label>اسم الطابع والوقت'+sel([['1','يظهر'],['0','مخفي']],PL.footer.printedBy?'1':'0','data-g="footer.printedBy"')+'</label>'+
    '<label>رقم الصفحة'+sel([['1','يظهر'],['0','مخفي']],PL.footer.pageNo?'1':'0','data-g="footer.pageNo"')+'</label></div>'+
   '<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:14px"><button class="btn btn-p btn-sm" id="plSave" type="button">حفظ تخطيط المستندات</button>'+
    '<button class="btn btn-o btn-sm" id="plPreview" type="button">معاينة '+E(TYPE_LBL[SEL_TYPE])+'</button><button class="btn btn-o btn-sm" id="plReset" type="button">استعادة الافتراضي</button></div>';
  [].forEach.call(host.querySelectorAll('[data-g]'),function(el){el.onchange=el.oninput=function(){var path=el.dataset.g.split('.'),o=PL;for(var i=0;i<path.length-1;i++)o=o[path[i]];
    var val=el.value;if(el.type==='number')val=+val;else if(/^(logo\.show|title\.underline|approval\.show|info\.labelBold|footer\.bold|footer\.printedBy|footer\.pageNo)$/.test(el.dataset.g))val=val==='1';else if(el.dataset.g==='info.columns')val=+val;
    o[path[path.length-1]]=val;};});
  bindList(host,'plRight',PL.right,function(tr,l){l.text=v(tr,'[data-f=text]');l.size=+v(tr,'[data-f=size]');l.bold=v(tr,'[data-f=bold]');l.align=v(tr,'[data-f=align]');l.color=v(tr,'[data-f=color]');},{text:'',size:13,bold:true,align:'right',color:'#123524'},renderEditor);
  bindList(host,'plLeft',PL.left,function(tr,f){f.key=v(tr,'[data-f=key]');f.label=v(tr,'[data-f=label]');f.value=v(tr,'[data-f=value]');f.show=v(tr,'[data-f=show]');f.bold=v(tr,'[data-f=bold]');f.size=+v(tr,'[data-f=size]');},{key:'custom',label:'حقل جديد',value:'',show:true,bold:true,size:12},renderEditor);
  if(t.info)bindList(host,'plInfo',t.info,function(tr,f){f.label=v(tr,'[data-f=label]');f.show=v(tr,'[data-f=show]');},null,renderEditor);
  bindList(host,'plSig',t.sigs,function(tr,s){s.title=v(tr,'[data-f=title]');s.name=v(tr,'[data-f=name]');s.show=v(tr,'[data-f=show]');},{title:'توقيع جديد',name:'',show:true},renderEditor);
  $('plType').onchange=function(){SEL_TYPE=this.value;renderEditor();};
  $('plSave').onclick=async function(){try{if(typeof guardPerm==='function'&&!guardPerm('settings','edit'))return;await savePL();T('✔ حُفظ تخطيط المستندات — يُطبَّق على كل الطباعة');}catch(e){T('✖ '+(e.code||e.message));}};
  $('plReset').onclick=function(){if(!confirm('استعادة التخطيط الافتراضي؟'))return;PL=defaults();renderEditor();T('استُعيد الافتراضي — اضغط حفظ لتثبيته');};
  $('plPreview').onclick=preview;
}
function preview(){
  var mp=MP();if(!mp)return;var today=new Date().toISOString().slice(0,10);
  var m={warehouse:'المخزن الرئيسي',ref:'و-000001',supplier:'مورد الخير',date:today,start_date:today,end_date:today,invoiceNo:'F-120',notes:'—',beneficiary:'الكتيبة الأولى',strength:'660',days:'1',
    destWarehouse:'مخزن المعسكر',campName:'معسكر الثنية',statusLabel:'قيد الاستلام',party:'الكتيبة الأولى',condition:'صالحة',origRef:'و-000001'};
  var rows=[['1','A01','أرز 40 كجم','5','كيس','—'],['2','A01','أرز 40 كجم','10','كجم','—'],['3','B02','زيت 20 لتر','3','دبة','—']];
  if(SEL_TYPE==='generic')mp.printGenericReport({date:today,refLabel:'المرجع',infoTitle:'محددات التقرير',infoLines:[['المستودع','المخزن الرئيسي','الفترة','اليوم']]},rows.map(function(r){return r.slice(0,5);}),['م','الكود','الصنف','الكمية','الوحدة'],'كشف تجريبي');
  else mp.printHtml(buildPages(m,rows,TYPE_LBL[SEL_TYPE],SEL_TYPE==='issue'?'#C0392B':SEL_TYPE==='transfer'?'#2980b9':/^return/.test(SEL_TYPE)?'#8E44AD':PL.accent,SEL_TYPE));
}
new MutationObserver(function(){var save=$('imdDzSave');if(save&&!$('plCard')){var card=save.closest('.icard');if(!card)return;var box=d.createElement('div');box.className='icard';box.id='plCard';card.parentNode.insertBefore(box,card);renderEditor();}})
  .observe(d.documentElement,{childList:true,subtree:true});

window.IMDAD_PRINT_LAYOUT={get:function(){return PL;},set:function(x){PL=mergeCfg(defaults(),x);},defaults:defaults,save:savePL,load:loadPL,buildPages:buildPages};
})();
