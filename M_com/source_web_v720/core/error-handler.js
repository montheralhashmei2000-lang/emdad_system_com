/* IMDAD Error Handler v2 — التقاط الأخطاء وحفظها محليًا وإظهار رسالة مفهومة للمستخدم */
(function(){
'use strict';
var IS_DEV=/^(localhost|127\.|192\.168\.|dev\.)/.test(location.hostname);
var KEY='imdad.error.queue',MAX=100;
var FB={
'auth/invalid-email':'صيغة البريد غير صحيحة',
'auth/user-disabled':'تم إيقاف الحساب — راجع المدير',
'auth/user-not-found':'لا يوجد حساب بهذا الاسم',
'auth/wrong-password':'كلمة المرور غير صحيحة',
'auth/invalid-credential':'بيانات الدخول غير صحيحة',
'auth/too-many-requests':'محاولات كثيرة — انتظر قليلاً',
'auth/network-request-failed':'تحقق من الاتصال بالإنترنت',
'permission-denied':'ليس لديك صلاحية لهذه العملية',
'unavailable':'الخدمة غير متاحة مؤقتاً',
'not-found':'العنصر المطلوب غير موجود',
'already-exists':'العنصر موجود مسبقاً',
'QuotaExceededError':'مساحة التخزين على الجهاز ممتلئة',
'ConstraintError':'السجل موجود مسبقاً (تكرار في المفتاح)'
};
function translateError(err){
  if(!err)return 'خطأ غير معروف';
  if(typeof err==='string')return err;
  var code=err.code||err.name;
  if(code&&FB[code])return FB[code];
  var m=String(err.message||'');
  if(/network|offline|Failed to fetch/i.test(m))return 'خطأ في الاتصال — تحقق من الشبكة';
  if(/permission/i.test(m))return 'ليس لديك صلاحية';
  return m||'خطأ غير متوقع';
}
function load(){try{var q=JSON.parse(localStorage.getItem(KEY)||'[]');return Array.isArray(q)?q:[];}catch(e){return [];}}
var lastToast={msg:'',at:0};
var ErrorLog={
  queue:load(),
  _save:function(){
    try{localStorage.setItem(KEY,JSON.stringify(this.queue));}
    catch(e){this.queue=this.queue.slice(-20);try{localStorage.setItem(KEY,JSON.stringify(this.queue));}catch(e2){}}
  },
  add:function(err,context,severity){
    context=context||{};severity=severity||'error';
    var entry={
      id:'err_'+Date.now()+'_'+Math.random().toString(36).slice(2,8),
      ts:Date.now(),severity:severity,
      message:translateError(err),
      originalMessage:(err&&err.message)||String(err),
      code:err&&err.code,
      stack:(err&&err.stack?String(err.stack).split('\n').slice(0,5).join('\n'):''),
      context:Object.assign({},context,{page:window.curPage||'',url:location.pathname+location.hash}),
      user:(window.me&&window.me.state&&(window.me.state.username||window.me.state.email))||'anonymous'
    };
    this.queue.push(entry);
    if(this.queue.length>MAX)this.queue.splice(0,this.queue.length-MAX);
    this._save();
    if(IS_DEV){(severity==='warn'||severity==='info'?console.warn:console.error)('[IMDAD '+severity.toUpperCase()+']',entry.message,err,context);}
    if(severity!=='info'&&!context.silent&&typeof window.toast==='function'){
      var now=Date.now(),msg=(severity==='critical'?'🔴 ':'⚠️ ')+entry.message;
      if(msg!==lastToast.msg||now-lastToast.at>5000){lastToast={msg:msg,at:now};try{window.toast(msg);}catch(e){}}
    }
    return entry;
  },
  getRecent:function(n){return this.queue.slice(-(n||20));},
  clear:function(){this.queue=[];this._save();}
};
window.onerror=(function(prev){return function(message,source,line,col,error){
  /* أخطاء السكربتات الخارجية تصل بدون تفاصيل (Script error.) فلا فائدة من إظهارها */
  if(message==='Script error.'&&!error)return prev?prev.apply(this,arguments):false;
  ErrorLog.add(error||new Error(String(message)),{kind:'window.onerror',file:source,line:line,col:col},'critical');
  return prev?prev.apply(this,arguments):false;
};})(window.onerror);
window.addEventListener('unhandledrejection',function(e){ErrorLog.add(e.reason,{kind:'unhandledrejection'},'error');});
window.IMDAD_ERRORS=ErrorLog;
window.IMDAD_UTILS={translateError:translateError};
})();
