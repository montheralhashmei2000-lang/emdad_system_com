/* IMDAD Auth v1 — دخول احترافي باسم المستخدم + كلمة مرور، قفل، جلسات، بوتستراب، دخول محلي */
(function(){
'use strict';
window.IMDAD_ALLOW_FIREBASE_AUTH=false;
var doc=document;
function $(id){return doc.getElementById(id);}
function nof(m){try{if(window.toast)window.toast(m);else alert(m);}catch(e){}}
function iso(){return new Date().toISOString();}

/*__AUTHCORE_START__*/
var AUTHCORE=(function(){
  function hex(b){return Array.prototype.map.call(new Uint8Array(b),function(x){return (x<16?'0':'')+x.toString(16);}).join('');}
  function enc(s){return new TextEncoder().encode(s);}
  function parseHex(s){var out=new Uint8Array(s.length/2);for(var i=0;i<out.length;i++)out[i]=parseInt(s.substr(i*2,2),16);return out;}
  async function derive(pw,saltHex,iter){var salt=parseHex(saltHex);var key=await crypto.subtle.importKey('raw',enc(pw),'PBKDF2',false,['deriveBits']);
    return hex(await crypto.subtle.deriveBits({name:'PBKDF2',salt:salt,iterations:iter||45000,hash:'SHA-256'},key,256));}
  function saltHex(){var a=new Uint8Array(16);crypto.getRandomValues(a);return hex(a);}
  return {
    derive:derive,saltHex:saltHex,MAX_FAILS:5,LOCK_MS:180000,
    lockKey:function(u){return 'imdad.auth.lock.'+u;},
    parseState:function(st){try{var o=JSON.parse(st||'{}');return {fails:o.fails||0,until:o.until||0};}catch(e){return {fails:0,until:0};}},
    isLocked:function(s,now){return !!(s.until && now<s.until);},
    remaining:function(s,now){return s.until?Math.max(0,s.until-now):0;},
    next:function(s,now){if(s.fails+1>=this.MAX_FAILS)return {fails:0,until:now+this.LOCK_MS};return {fails:s.fails+1,until:0};}
  };
})();
/*__AUTHCORE_END__*/

var REG='imdad.auth.reg';           // localStorage: {"user":{salt,h,role,profile,cached:1}}
var SES='imdad.auth.ses';           // localStorage: {"user":"...","at":ts,"exp":ts+12h,"profile":{}}
var DOMAIN='@imdad.local';
function norm(u){u=String(u||'').trim();return u;}
function toEmail(u){u=norm(u);return u.indexOf('@')>-1?u:(u+DOMAIN);}
function toUser(u){u=norm(u);return u.indexOf('@')>-1?u.split('@')[0]:u;}
function regGet(){try{return JSON.parse(localStorage.getItem(REG)||'{}');}catch(e){return {};}}
function regSet(r){try{localStorage.setItem(REG,JSON.stringify(r));}catch(e){}}
function sesGet(){try{return JSON.parse(localStorage.getItem(SES)||'null');}catch(e){return null;}}
function sesSet(s){try{if(s)localStorage.setItem(SES,JSON.stringify(s));else localStorage.removeItem(SES);}catch(e){}}
function cacheProfile(){try{return JSON.parse(localStorage.getItem('sw_profile_v1')||'null');}catch(e){return null;}}

var bootShown=false;
function now(){return Date.now();}
function fmt(ms){var s=Math.ceil(ms/1000);return s<60?s+' ثانية':Math.ceil(s/60)+' دقيقة';}

function lErr(msg){var e=$('lErr');if(e){e.style.display='block';e.textContent=msg;}var m=$('loginMsg');if(m)m.textContent='';}
function lMsg(msg){var e=$('lErr');if(e){e.style.display='none';e.textContent='';}var m=$('loginMsg');if(m)m.textContent=msg;}
function btnState(on){var b=$('btnLogin');if(!b)return;b.disabled=on;b.textContent=on?'جارٍ التحقق…':'دخول إلى النظام';}

function lockStore(u,st){try{localStorage.setItem(AUTHCORE.lockKey(toUser(u)),JSON.stringify(st));}catch(e){}}
function lockRead(u){return AUTHCORE.parseState(localStorage.getItem(AUTHCORE.lockKey(toUser(u)))||'{}');}

function setMeState(profile,email,username){try{var me=window.me;if(me){me.state=me.state||{};me.state.name=profile&&profile.name?profile.name:username;me.state.email=email;me.state.uid=profile&&profile.id?profile.id:(me.state.uid);me.state.username=username;me.state.profile=profile||{};}}catch(e){}}

function enterApp(){try{var fn=window.__IMDAD_ENTER_FN__;if(fn&&typeof window[fn]==='function'){window[fn]();return true;}var app=$('app');if(app){app.style.display='block';var ls=$('loginScreen');if(ls)ls.style.display='none';return true;}}catch(e){}return false;}

async function afterFirebaseLogin(us){
  try{
    var email=toEmail(us);var uid=(window.AUTH_LOCAL && window.AUTH_LOCAL.currentUser)?window.AUTH_LOCAL.currentUser.uid:null;
    var profile={name:toUser(us),username:toUser(us),email:email};
    if(uid&&window.db){
      try{var d=await window.db.collection('users').doc(uid).get();
        if(d.exists){var dd=d.data();
          if(dd.status!=='active'&&dd.status!==true){if(window.AUTH_LOCAL)window.AUTH_LOCAL.signOut().catch(function(e){IMDAD_ERRORS?.add(e,{kind:'signout-on-inactive'},'warn');});lErr('✖ الحساب غير مفعّل — اطلب من مدير النظام تفعيل حسابك');return false;}
          if(dd.approved===false){if(window.AUTH_LOCAL)window.AUTH_LOCAL.signOut().catch(function(e){IMDAD_ERRORS?.add(e,{kind:'signout-on-unapproved'},'warn');});lErr('✖ الحساب غير معتمد بعد — انتظر اعتماد المدير');return false;}
          profile.name=dd.name||dd.username||profile.name;profile.username=dd.username||profile.name;profile.role=dd.role||'user';profile.id=uid;
        }}catch(e){}
    }
    setMeState(profile,email,toUser(us));
    var r=regGet();r[toUser(us)]={salt:null,role:profile.role||'user',profile:profile,alias:email};regSet(r);
    sesSet({user:toUser(us),at:now(),exp:now()+12*3600*1000,profile:profile});
    return true;
  }catch(e){return true;}
}

async function doLogin(){
  var u=norm(($('lgUser')||{}).value||'');var p=($('lgPass')||{}).value||'';
  if(!u||!p){lErr('✖ أدخل اسم المستخدم وكلمة المرور');return;}
  var user=toUser(u);
  var st=lockRead(user);var t=now();
  if(AUTHCORE.isLocked(st,t)){lErr('⏳ تم قفل الدخول مؤقتًا بسبب محاولات كثيرة. حاول بعد '+fmt(AUTHCORE.remaining(st,t)));return;}
  btnState(true);
  try{
    var localOk=await localLogin(user,p);
    if(localOk){lockStore(user,{fails:0,until:0});return;}
    if(window.IMDAD_ALLOW_FIREBASE_AUTH===true && window.AUTH_LOCAL && window.db){
      await window.AUTH_LOCAL.login(toEmail(u),p);
      lockStore(user,{fails:0,until:0});
      enterApp();
      return;
    }
    var ns=AUTHCORE.next(st,t);lockStore(user,ns);
    if(AUTHCORE.isLocked(ns,now()))lErr('⛔ كثير جدًا من المحاولات — تم قفل الدخول لهذا المستخدم مؤقتًا.');
    else lErr('✖ اسم المستخدم أو كلمة المرور غير صحيحة'+(ns.fails?' ('+ns.fails+'/'+AUTHCORE.MAX_FAILS+')':''));
  }catch(e){
    var ns2=AUTHCORE.next(st,t);lockStore(user,ns2);
    lErr('✖ تعذر تسجيل الدخول: '+((e&&e.message)||'خطأ غير معروف'));
  }finally{btnState(false);}
}

async function localLogin(user,p){
  try{
    if(window.AUTH_LOCAL){
      var loc=await window.AUTH_LOCAL.login(user,p);
      if(loc){setMeState(loc.profile,user+DOMAIN,user);sesSet({user:user,at:now(),exp:now()+12*3600*1000,profile:loc.profile});nof('🌐 تم الدخول محليًا (بدون إنترنت)');enterApp();return true;}
    }
    var r=regGet();var rec=r[user];
    if(!rec||!rec.salt){var prof=cacheProfile();if(prof&&prof.username===user&&prof._localHash){/* legacy */return false;}return false;}
    var h=await AUTHCORE.derive(p,rec.salt,45000);
    if(h!==rec.h)return false;
    var prof=rec.profile||{name:user,username:user};
    setMeState(prof,user+DOMAIN,user);
    sesSet({user:user,at:now(),exp:now()+12*3600*1000,profile:prof});
    nof('🌐 تم الدخول محليًا (وضع دون اتصال) — قد تكون البيانات غير محدثة');
    enterApp();return true;
  }catch(e){return false;}
}

function registerLocal(user,p,profile){
  return new Promise(function(resolve,reject){
    (async function(){
      try{
        var salt=AUTHCORE.saltHex();var h=await AUTHCORE.derive(p,salt,45000);
        var r=regGet();r[user]={salt:salt,h:h,role:(profile&&profile.role)||'admin',profile:profile||{name:user,username:user}};regSet(r);
        if(window.AUTH_LOCAL){window.AUTH_LOCAL.register(user,p,profile||{name:user,username:user,role:(profile&&profile.role)||'admin'}).catch(function(){});}
        resolve(true);
      }catch(e){reject(e);}
    })();
  });
}

async function doBootstrap(){
  var u=norm(($('bsUser')||{}).value||'');var p=($('bsPass')||{}).value||'';var p2=($('bsPass2')||{}).value||'';
  var b=$('lgBootstrapGo');
  if(!/^[A-Za-z0-9_.]{3,20}$/.test(u)){lErr('✖ اسم المستخدم: 3-20 حرفًا إنجليزيًا/أرقام/نقطة/شرطة سفلية');return;}
  if(p.length<6){lErr('✖ كلمة المرور 6 أحرف على الأقل');return;}
  if(p!==p2){lErr('✖ كلمتا المرور غير متطابقتين');return;}
  if(b){b.disabled=true;b.textContent='جارٍ الإنشاء…';}
  try{
    var email=toEmail(u);var uid='local-'+u;
    await registerLocal(u,p,{name:u,username:u,role:'admin',id:uid,status:'active',approved:true,email:email});
    setMeState({name:u,username:u,role:'admin',status:'active',approved:true,id:uid},email,u);
    sesSet({user:u,at:now(),exp:now()+12*3600*1000,profile:{name:u,username:u,role:'admin',id:uid}});
    lMsg('✔ تم إنشاء حساب المدير محليًا — جارٍ الدخول…');
    try{window.IMDAD_PRO&&window.IMDAD_PRO.appendChange('auth.bootstrap',{user:u});}catch(_e){}
    enterApp();
    nof('✔ مرحبًا بك — تم إنشاء حساب المدير محليًا بنجاح');
  }catch(e){lErr('✖ '+(e&&e.message||'خطأ غير متوقع'));}
  finally{if(b){b.disabled=false;b.textContent='إنشاء حساب المدير والدخول';}}
}

function showBootstrapIfNeeded(){
  try{
    var wrap=$('lgBootstrapWrap');if(!wrap)return;
    var r=regGet();var has=Object.keys(r).length>0;
    var ses=sesGet();var fireUser=window.AUTH_LOCAL && window.AUTH_LOCAL.currentUser;
    if(has||ses||fireUser){wrap.style.display='none';}else{wrap.style.display='block';try{wrap.open=true;}catch(e){}}
    if(window.AUTH_LOCAL){window.AUTH_LOCAL.hasUsers().then(function(h){if(h){var w=$('lgBootstrapWrap');if(w)w.style.display='none';}});}
  }catch(e){}
}

function showForgotPanel(){var p=$('lgResetPanel');if(p)p.hidden=!p.hidden;}

function localReset(){if(!confirm('سيتم مسح بيانات الدخول المحلية. سيظهر خيار تهيئة حساب مدير جديد. (حساب Firebase القديم يبقى — استخدم اسم مستخدم جديدًا). متابعة؟'))return;
  try{localStorage.removeItem(REG);localStorage.removeItem(SES);for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);if(k&&k.indexOf('imdad.auth.lock.')===0)localStorage.removeItem(k);}}catch(e){}
  if(window.AUTH_LOCAL){window.AUTH_LOCAL.reset().catch(function(){});}
  nof('✔ تمت إعادة التعيين المحلية — يمكنك الآن تهيئة حساب مدير جديد');showBootstrapIfNeeded();}

function bind(){
  var b=$('btnLogin');
  if(b&&!b.dataset.imd){
    var nb=b.cloneNode(false);nb.removeAttribute('id');nb.id='btnLogin';nb.dataset.imd='1';
    if(b.parentNode)b.parentNode.replaceChild(nb,b);
    nb.onclick=function(){doLogin();};
  }
  var inp=$('lgPass');if(inp&&!inp.dataset.imd){inp.dataset.imd='1';inp.addEventListener('keydown',function(e){if(e.key==='Enter')doLogin();});}
  var uin=$('lgUser');if(uin&&!uin.dataset.imd){uin.dataset.imd='1';uin.addEventListener('keydown',function(e){if(e.key==='Enter')doLogin();});}
  var sh=$('lgShowPass');if(sh&&!sh.dataset.imd){sh.dataset.imd='1';sh.onclick=function(){var x=$('lgPass');if(x){x.type=x.type==='password'?'text':'password';}};}
  var fg=$('lgForgot');if(fg&&!fg.dataset.imd){fg.dataset.imd='1';fg.onclick=showForgotPanel;}
  var rs=$('lgResetGo');if(rs&&!rs.dataset.imd){rs.dataset.imd='1';rs.onclick=localReset;}
  var bg=$('lgBootstrapGo');if(bg&&!bg.dataset.imd){bg.dataset.imd='1';bg.onclick=doBootstrap;}
  // auto-fill username cache
  try{var ses=sesGet();if(ses&&ses.user){var u=$('lgUser');if(u&&!u.value)u.value=ses.user;}}catch(e){}
}

function boot(){
  try{showBootstrapIfNeeded();bind();
    setInterval(function(){try{var ls=$('loginScreen');if(ls&&ls.style.display!=='none'){bind();showBootstrapIfNeeded();}}catch(e){}},1200);
    setInterval(function(){try{var ses=sesGet();if(ses&&ses.exp&&now()>ses.exp){/* جلسة منتهية — نترك معالجة الخروج لطبقة النظام */}}catch(e){}},60000);
  }catch(e){}
}
window.IMDAD_AUTH={login:doLogin,bootstrap:doBootstrap,localReset:localReset,registerLocal:registerLocal,toEmail:toEmail,toUser:toUser,AUTHCORE:AUTHCORE,createUser:function(u,p,role){return doBootstrapWith(u,p,role);}};
async function doBootstrapWith(u,p,role){var _u=$('bsUser'),_p=$('bsPass'),_p2=$('bsPass2');if(_u)_u.value=u;if(_p)_p.value=p;if(_p2)_p2.value=p;return doBootstrap();}
if(/complete|interactive/.test(doc.readyState))setTimeout(boot,0);else doc.addEventListener('DOMContentLoaded',boot);
})();
