/* IMDAD AuthLocal v1 — مصادقة محلية بالكامل (IndexedDB + PBKDF2 SHA-256 45k) بدون الاعتماد على Firebase */
(function(){
'use strict';
var DB_NAME='imdad-auth',STORE='users',REG_LEGACY='imdad.auth.reg';
function hex(b){return Array.prototype.map.call(new Uint8Array(b),function(x){return (x<16?'0':'')+x.toString(16);}).join('');}
function enc(s){return new TextEncoder().encode(String(s));}
function parseHex(s){var out=new Uint8Array(s.length/2);for(var i=0;i<out.length;i++)out[i]=parseInt(s.substr(i*2,2),16);return out;}
function derive(pw,saltHex,iter){var salt=parseHex(saltHex);return crypto.subtle.importKey('raw',enc(pw),'PBKDF2',false,['deriveBits']).then(function(key){
  return crypto.subtle.deriveBits({name:'PBKDF2',salt:salt,iterations:iter||45000,hash:'SHA-256'},key,256).then(function(b){return hex(b);});});}
function saltHex(){var a=new Uint8Array(16);crypto.getRandomValues(a);return hex(a);}
var dbp=null;
function openDB(){if(dbp)return dbp;dbp=new Promise(function(res,rej){var r=indexedDB.open(DB_NAME,1);
  r.onupgradeneeded=function(e){var db=e.target.result;if(!db.objectStoreNames.contains(STORE))db.createObjectStore(STORE,{keyPath:'user'});};
  r.onsuccess=function(){res(r.result);};r.onerror=function(){rej(r.error);};});return dbp;}
function get(user){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(STORE,'readonly'),r=t.objectStore(STORE).get(user);
  r.onsuccess=function(){res(r.result||null);};r.onerror=function(){rej(r.error);};});});}
function put(rec){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(STORE,'readwrite'),r=t.objectStore(STORE).put(rec);
  r.onsuccess=function(){res(true);};r.onerror=function(){rej(r.error);};});});}
function allKeys(){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(STORE,'readonly'),r=t.objectStore(STORE).getAllKeys();
  r.onsuccess=function(){res(r.result||[]);};r.onerror=function(){rej(r.error);};});});}
var AUTHL={
  register:function(user,pass,profile){var u=String(user||'').trim();if(!u||!pass||pass.length<6)return Promise.reject(new Error('bad input'));
    return get(u).then(function(ex){if(ex)return Promise.reject(new Error('exists'));
      var salt=saltHex();return derive(pass,salt,45000).then(function(h){return put({user:u,salt:salt,h:h,role:(profile&&profile.role)||'user',profile:profile||{name:u,username:u},createdAt:new Date().toISOString()});});});},
  login:function(user,pass){var u=String(user||'').trim();return get(u).then(function(rec){
      if(!rec||!rec.salt||!rec.h)return null;
      return derive(pass,rec.salt,45000).then(function(h){if(h!==rec.h)return null;return {username:u,role:rec.role,profile:rec.profile};});});},
  get:get,
  hasUsers:function(){return allKeys().then(function(k){return k.length>0;});},
  list:function(){return allKeys().then(function(ks){return Promise.all(ks.map(function(k){return get(k);}));});},
  migrateLegacy:function(){try{var raw=localStorage.getItem(REG_LEGACY);if(!raw)return Promise.resolve(0);var r=JSON.parse(raw)||{};var users=Object.keys(r);
      return Promise.all(users.map(function(u2){var rec=r[u2];if(!rec||!rec.salt||!rec.h)return Promise.resolve(false);
        return get(u2).then(function(ex){if(ex)return false;return put({user:u2,salt:rec.salt,h:rec.h,role:rec.role||'user',profile:rec.profile||{name:u2,username:u2},createdAt:new Date().toISOString()});});})).then(function(rs){return rs.filter(Boolean).length;});}catch(e){return Promise.resolve(0);}},
  reset:function(){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(STORE,'readwrite');t.objectStore(STORE).clear();
    t.oncomplete=function(){res(true);};t.onerror=function(){rej(t.error);};});});},
  derive:derive
};
window.AUTH_LOCAL=AUTHL;
function boot(){AUTHL.migrateLegacy().then(function(n){if(n){try{console.log('[AUTH_LOCAL] تم ترحيل '+n+' حسابات إلى المخزن المحلي');}catch(e){}}});}
if(/complete|interactive/.test(document.readyState))setTimeout(boot,0);else document.addEventListener('DOMContentLoaded',boot);
})();
