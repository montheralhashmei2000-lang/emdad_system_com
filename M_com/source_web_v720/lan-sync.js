/* IMDAD LAN Sync v1 — تزامن الأجهزة والمخازن لاسلكيًا عبر LAN (WebRTC) + ملف نصي، يعمل بدون إنترنت */
(function(){
'use strict';
var DB='imdad-sync',ST='docs',dbp=null;
function openDB(){if(dbp)return dbp;dbp=new Promise(function(res,rej){var r=indexedDB.open(DB,1);
  r.onupgradeneeded=function(e){var d=e.target.result;if(!d.objectStoreNames.contains(ST))d.createObjectStore(ST,{keyPath:'key'});};
  r.onsuccess=function(){res(r.result);};r.onerror=function(){rej(r.error);};});return dbp;}
function sget(key){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(ST,'readonly'),r=t.objectStore(ST).get(key);
  r.onsuccess=function(){res(r.result||null);};r.onerror=function(){rej(r.error);};});});}
function sput(rec){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(ST,'readwrite'),r=t.objectStore(ST).put(rec);
  r.onsuccess=function(){res(true);};r.onerror=function(){rej(r.error);};});});}
function sall(){return openDB().then(function(db){return new Promise(function(res,rej){var r=db.transaction(ST,'readonly').objectStore(ST).getAll();
  r.onsuccess=function(){res(r.result||[]);};r.onerror=function(){rej(r.error);};});});}
var PEERS={};
var SYNC={
  ts:function(){return Date.now();},
  deviceId:function(){try{var k='imdad.sync.dev';var v=localStorage.getItem(k);if(!v){v='dev-'+Math.random().toString(36).slice(2,10);localStorage.setItem(k,v);}return v;}catch(e){return 'dev-0';}},
  enqueueDoc:function(key,data,id){key=String(key||'');if(!key)return Promise.resolve();var ts=this.ts();
    return sget(key).then(function(old){if(old&&old.ts>ts)return false;
      var rev=(old?old.rev:0)+1;return sput({key:key,ts:ts,rev:rev,data:data,id:id||null,src:SYNC.deviceId()}).then(function(){
        SYNC.broadcast({kind:'doc',key:key,ts:ts,rev:rev,data:data,id:id||null,src:SYNC.deviceId()});return true;});});},
  applyRemote:function(msg){if(!msg||msg.kind!=='doc')return Promise.resolve(false);var key=msg.key,ts=Number(msg.ts)||0,rev=msg.rev||0;
    return sget(key).then(function(old){if(old&&(old.ts>ts||(old.ts===ts&&old.rev>=rev)))return false;
      return sput({key:key,ts:ts,rev:rev,data:msg.data,id:msg.id||null,src:msg.src||'remote'}).then(function(){return true;});});},
  pushToFirestore:function(){try{if(!window.db||!window.SYNC_MIRROR)return Promise.resolve();
    return sall().then(function(docs){var col=window.db.collection('syncDocs');
      return Promise.all(docs.map(function(d){return col.doc(d.key).set({ts:d.ts,rev:d.rev,data:d.data,src:d.src},{merge:true}).catch(function(){});}));});}catch(e){return Promise.resolve();}},
  broadcast:function(msg){try{var bc=this._bc;if(bc)bc.postMessage(msg);}catch(e){}
    try{Object.keys(PEERS).forEach(function(k){var pc=PEERS[k];if(pc&&pc.dc&&pc.dc.readyState==='open'){try{pc.dc.send(JSON.stringify(msg));}catch(e){}}});}catch(e){}},
  exportFile:function(){return sall().then(function(docs){var blob=new Blob([JSON.stringify({app:'imdad-sync',v:1,docs:docs})],{type:'application/json'});
    var a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='imdad-sync-'+new Date().toISOString().slice(0,10)+'.json';
    document.body.appendChild(a);a.click();setTimeout(function(){URL.revokeObjectURL(a.href);},5000);return docs.length;});},
  importFile:function(file){return new Promise(function(res,rej){var fr=new FileReader();
    fr.onload=function(){try{var obj=JSON.parse(String(fr.result));var docs=obj&&obj.docs||[];
      Promise.all(docs.map(function(d){return SYNC.applyRemote({kind:'doc',key:d.key,ts:d.ts,rev:d.rev,data:d.data,id:d.id,src:d.src||'file'});})).then(function(){res(docs.length);}).catch(rej);}catch(e){rej(e);}};
    fr.onerror=rej;fr.readAsText(file);});},
  pairOffer:function(){return new Promise(function(res,rej){try{
    var pc=new RTCPeerConnection({iceServers:[]});var dc=pc.createDataChannel('imdad-sync',{ordered:true});
    pc.dc=dc;SYNC._pendingOffer=pc;
    dc.onopen=function(){PEERS['offer']=pc;};dc.onmessage=function(ev){try{SYNC.applyRemote(JSON.parse(ev.data));}catch(e){}};
    pc.onicecandidate=function(ev){if(ev.candidate)return;res(SYNC._code(pc.localDescription));};
    pc.createOffer().then(function(o){return pc.setLocalDescription(o);}).catch(rej);
  }catch(e){rej(e);}});},
  /* الخطوة الأخيرة عند الجهاز صاحب العرض: إدخال رمز الرد لإتمام الاتصال */
  pairComplete:function(answerCode){try{var pc=SYNC._pendingOffer;if(!pc)return Promise.reject(new Error('أنشئ رمز اقتران أولًا'));
    return pc.setRemoteDescription(new RTCSessionDescription(JSON.parse(SYNC._decode(answerCode)))).then(function(){SYNC._pendingOffer=null;return true;});
  }catch(e){return Promise.reject(e);}},
  pairAnswer:function(offerCode){return new Promise(function(res,rej){try{
    var pc=new RTCPeerConnection({iceServers:[]});
    pc.ondatachannel=function(ev){var dc=ev.channel;pc.dc=dc;dc.onopen=function(){PEERS['answer']=pc;};
      dc.onmessage=function(ev2){try{SYNC.applyRemote(JSON.parse(ev2.data));}catch(e){}};};
    pc.onicecandidate=function(ev){if(ev.candidate)return;res(SYNC._code(pc.localDescription));};
    pc.setRemoteDescription(new RTCSessionDescription(JSON.parse(SYNC._decode(offerCode)))).then(function(){return pc.createAnswer();}).then(function(a){return pc.setLocalDescription(a);},rej);
  }catch(e){rej(e);}});},
  _code:function(desc){try{return btoa(unescape(encodeURIComponent(JSON.stringify(desc))));}catch(e){return '';}},
  _decode:function(c){try{return decodeURIComponent(escape(atob(c)));}catch(e){return c;}},
  start:function(){try{var bc=(typeof BroadcastChannel!=='undefined')?new BroadcastChannel('imdad-sync'):null;
    if(bc){SYNC._bc=bc;bc.onmessage=function(ev){SYNC.applyRemote(ev.data);};}}catch(e){}
    try{setInterval(function(){SYNC.pushToFirestore();},30000);}catch(e){}
    try{var conn=navigator.connection||navigator.mozConnection||navigator.webkitConnection;
      if(conn)conn.addEventListener('change',function(){SYNC.pushToFirestore();});}catch(e){}},
  get:function(key){return sget(key);},
  all:function(){return sall();}
};
window.IMDAD_SYNC=SYNC;
/* اعتراض كتابات Firestore لالتقاط أي تغيير تلقائيًا في سجل التزامن (LWW بالطابع الزمني) */
function patchDB(){try{if(!window.db||window.__syncPatched)return;window.__syncPatched=true;
  var oc=window.db.collection.bind(window.db);
  window.db.collection=function(name){var col=oc(name);var od=col.doc.bind(col);
    col.doc=function(id){var dr=od(id);var s=dr.set.bind(dr);
      dr.set=function(data,opt){try{var payload=Object.assign({},data);SYNC.enqueueDoc(name+'/'+id,payload,id);}catch(e){}return s(data,opt);};
      var u=dr.update.bind(dr);
      dr.update=function(){try{var args=[].slice.call(arguments);var payload=(args[0]&&typeof args[0]==='object')?args[0]:{};SYNC.enqueueDoc(name+'/'+id,Object.assign({_partial:true},payload),id);}catch(e){}return u.apply(null,arguments);};
      return dr;};return col;};
}catch(e){}}
function boot(){SYNC.start();patchDB();}
if(/complete|interactive/.test(document.readyState))setTimeout(boot,0);else document.addEventListener('DOMContentLoaded',boot);
})();
