/* IMDAD E-Sign v1 — التوقيع الإلكتروني للقائد على أوامر الصرف الحساسة (مفتاح RSA + بصمة الحمولة) */
(function(){
'use strict';
var DB='imdad-esig',ST='keys';
function openDB(){return new Promise(function(res,rej){var r=indexedDB.open(DB,1);
  r.onupgradeneeded=function(e){var d=e.target.result;if(!d.objectStoreNames.contains(ST))d.createObjectStore(ST,{keyPath:'kid'});};
  r.onsuccess=function(){res(r.result);};r.onerror=function(){rej(r.error);};});}
function kget(kid){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(ST,'readonly'),r=t.objectStore(ST).get(kid);
  r.onsuccess=function(){res(r.result||null);};r.onerror=function(){rej(r.error);};});});}
function kput(rec){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(ST,'readwrite'),r=t.objectStore(ST).put(rec);
  r.onsuccess=function(){res(true);};r.onerror=function(){rej(r.error);};});});}
function canon(obj){try{var keys=Object.keys(obj||{}).sort();var out={};keys.forEach(function(k){out[k]=obj[k];});return JSON.stringify(out);}catch(e){return JSON.stringify(obj);}}
function b64(buf){var s='';var u8=new Uint8Array(buf);for(var i=0;i<u8.length;i++)s+=String.fromCharCode(u8[i]);return btoa(s);}
function unb64(s){var bin=atob(s);var u8=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u8[i]=bin.charCodeAt(i);return u8.buffer;}
var KC={};
function loadKP(owner){return kget(owner).then(function(rec){if(!rec)return null;
  return Promise.all([
    crypto.subtle.importKey('jwk',rec.priv,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']),
    crypto.subtle.importKey('jwk',rec.pub,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify'])
  ]).then(function(k){KC[owner]={privateKey:k[0],publicKey:k[1],pub:rec.pub};return KC[owner];});});}
function ensure(owner){if(KC[owner])return Promise.resolve(KC[owner]);
  return loadKP(owner).then(function(kp){if(kp)return kp;
    return crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']).then(function(kp2){
      return Promise.all([crypto.subtle.exportKey('jwk',kp2.privateKey),crypto.subtle.exportKey('jwk',kp2.publicKey)]).then(function(j){
        return kput({kid:owner,priv:j[0],pub:j[1],createdAt:new Date().toISOString()}).then(function(){KC[owner]={privateKey:kp2.privateKey,publicKey:kp2.publicKey,pub:j[1]};return KC[owner];});});});});}
var E={
  ensureKey:function(owner){return ensure(owner||'commander');},
  hasKey:function(owner){return kget(owner||'commander').then(function(r){return !!r;});},
  sign:function(owner,orderId,payload){owner=owner||'commander';
    return ensure(owner).then(function(kp){
      var ts=Date.now();
      var msg=canon({id:orderId,ts:ts,payload:payload});
      return crypto.subtle.sign('RSASSA-PKCS1-v1_5',kp.privateKey,new TextEncoder().encode(msg)).then(function(sig){
        return {orderId:orderId,signer:owner,pub:kp.pub,sig:b64(sig),msg:msg,ts:ts,alg:'RS256'};});});},
  /* التحقق يتم بالمفتاح العام الموثوق للموقِّع (trustedPub أو المخزن محليًا) وليس بالمفتاح المرفق مع التوقيع */
  verify:function(sigObj,payload,trustedPub){try{var rec=sigObj||{};
    var pubP=trustedPub?Promise.resolve(trustedPub):kget(rec.signer||'commander').then(function(k){return k&&k.pub;});
    return pubP.then(function(pub){if(!pub||!rec.pub||pub.n!==rec.pub.n||pub.e!==rec.pub.e)return false;
    return crypto.subtle.importKey('jwk',pub,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},true,['verify']).then(function(pubk){
      var expected=canon({id:rec.orderId,ts:rec.ts,payload:payload});
      if(expected!==rec.msg)return Promise.resolve(false);
      return crypto.subtle.verify('RSASSA-PKCS1-v1_5',pubk,unb64(rec.sig),new TextEncoder().encode(rec.msg));});}).catch(function(){return false;});}catch(e){return Promise.resolve(false);}},
  signOrderPayload:function(order){return E.sign('commander',order&&order.id||'order-'+Date.now(),order&&order.payload||order);}
};
window.IMDAD_ESIGN=E;
})();
