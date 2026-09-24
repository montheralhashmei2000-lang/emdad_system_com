/* IMDAD Excel Resumable v1 — استيراد/تصدير Excel قابل للاستئناف (شرائح 200 صف مع حفظ الموضع) */
(function(){
'use strict';
var STORE_KEY='imdad.imp.resume';
function loadSheet(){return new Promise(function(res,rej){
  if(window.XLSX){res(window.XLSX);return;}
  var s=document.createElement('script');s.src='vendor/xlsx.full.min.js';
  s.onload=function(){res(window.XLSX);};s.onerror=function(){rej(new Error('تعذّر تحميل مكتبة Excel — تحقق من الاتصال بالإنترنت أول مرة'));};
  document.head.appendChild(s);});}
function stGet(){try{return JSON.parse(localStorage.getItem(STORE_KEY)||'null');}catch(e){return null;}}
function stSet(s){try{localStorage.setItem(STORE_KEY,JSON.stringify(s));}catch(e){}}
function stClear(){try{localStorage.removeItem(STORE_KEY);}catch(e){}}
var X={
  downloadTemplate:function(headers,fileName){return loadSheet().then(function(XLSX){
    var ws=XLSX.utils.aoa_to_sheet([headers||['العمود1','العمود2','العمود3']]);
    var wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,ws,'نموذج');
    XLSX.writeFile(wb,fileName||'imdad-model.xlsx');return true;});},
  exportTable:function(rows,sheetName,fileName){return loadSheet().then(function(XLSX){
    var ws=XLSX.utils.aoa_to_sheet(rows||[]);
    var wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,ws,sheetName||'بيانات');
    XLSX.writeFile(wb,fileName||'imdad-export.xlsx');return (rows||[]).length;});},
  import:function(file,opts){opts=opts||{};var chunk=opts.chunk||200;var form=opts.form||'generic';
    return loadSheet().then(function(XLSX){return new Promise(function(res,rej){
      var fr=new FileReader();
      fr.onload=function(){try{
        var wb=XLSX.read(new Uint8Array(fr.result),{type:'array'});
        var name=opts.sheet||wb.SheetNames[0];
        var rows=XLSX.utils.sheet_to_json(wb.Sheets[name],{header:1,defval:''});
        var st=stGet();var resumed=0;var offset=0;
        if(st&&st.form===form&&st.file===file.name){offset=st.offset||0;resumed=offset;}
        st={form:form,file:file.name,total:rows.length,offset:offset,processed:offset};
        stSet(st);
        function step(){
          var end=Math.min(st.offset+chunk,st.total);
          var slice=rows.slice(st.offset,end);
          try{var out=(opts.onChunk&&opts.onChunk(slice,st.offset,end))||{ok:true,count:slice.length};}
          catch(e){stSet(st);rej(e);return;}
          st.offset=end;st.processed=end;stSet(st);
          if(end<st.total){setTimeout(step,0);}
          else{stClear();res({total:st.total,processed:st.processed,resumed:resumed>0});}
        }
        step();
      }catch(e){rej(e);}};
      fr.onerror=rej;fr.readAsArrayBuffer(file);});});},
  resumeState:stGet
};
window.IMDAD_EXCEL=X;
})();
