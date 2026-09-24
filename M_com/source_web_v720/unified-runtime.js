/* IMDAD Unified Runtime v3
   Durable offline command queue, idempotency, conflict states, push bridge.
   Firestore remains the shared source of truth; inventory mutations are
   processed by the trusted backend, never by last-write-wins client logic.
*/
(() => {
  'use strict';
  const DB='imdad-command-queue-v3', VER=1;
  let _db;
  function db(){return _db ||= new Promise((resolve,reject)=>{
    const r=indexedDB.open(DB,VER);
    r.onupgradeneeded=()=>{
      const d=r.result;
      if(!d.objectStoreNames.contains('commands')){
        const s=d.createObjectStore('commands',{keyPath:'id'});
        s.createIndex('status','status'); s.createIndex('createdAt','createdAt');
      }
      if(!d.objectStoreNames.contains('conflicts')) d.createObjectStore('conflicts',{keyPath:'id'});
      if(!d.objectStoreNames.contains('meta')) d.createObjectStore('meta',{keyPath:'key'});
    };
    r.onsuccess=()=>resolve(r.result); r.onerror=()=>reject(r.error);
  });}
  async function tx(store,mode,fn){const d=await db();return new Promise((res,rej)=>{
    const t=d.transaction(store,mode), s=t.objectStore(store); let out;
    try{out=fn(s)}catch(e){rej(e);return} t.oncomplete=()=>res(out);t.onerror=()=>rej(t.error);
  });}
  const all=store=>tx(store,'readonly',s=>new Promise((res,rej)=>{const r=s.getAll();r.onsuccess=()=>res(r.result||[]);r.onerror=()=>rej(r.error)}));
  const put=(store,v)=>tx(store,'readwrite',s=>s.put(v));
  const get=(store,k)=>tx(store,'readonly',s=>new Promise((res,rej)=>{const r=s.get(k);r.onsuccess=()=>res(r.result);r.onerror=()=>rej(r.error)}));

  const Runtime={
    version:'3.0', online:navigator.onLine, flushing:false,
    deviceId(){let id=localStorage.getItem('imdad.deviceId');if(!id){id=crypto.randomUUID();localStorage.setItem('imdad.deviceId',id)}return id},
    async enqueue(type,payload,permission,baseRevision=null){
      if(!permission) throw new Error('PERMISSION_REQUIRED');
      const id=payload.operationId || crypto.randomUUID();
      const cmd={id,idempotencyKey:id,type,payload,permission,baseRevision,
        actorUid:window.me?.state?.id||window.me?.state?.uid||null,
        deviceId:this.deviceId(),createdAt:Date.now(),attempts:0,status:'PENDING',schemaVersion:3};
      await put('commands',cmd); this.emit(); if(this.online) this.flush(); return cmd;
    },
    async mark(id,status,extra={}){const c=await get('commands',id);if(c)await put('commands',{...c,status,...extra});this.emit()},
    async pending(){return (await all('commands')).filter(x=>['PENDING','RETRY'].includes(x.status)).sort((a,b)=>a.createdAt-b.createdAt)},
    async conflicts(){return (await all('conflicts')).filter(x=>x.status==='OPEN')},
    async recordConflict(c){await put('conflicts',{...c,id:c.id||crypto.randomUUID(),status:'OPEN',createdAt:Date.now()});this.emit()},
    async flush(){
      if(this.flushing||!navigator.onLine)return; this.flushing=true; this.online=true; this.emit();
      try{
        /* The queue is uploaded as immutable commands. A trusted backend consumes
           them and writes operationResults atomically. We do not replay arbitrary
           set/update calls from the client because that can duplicate stock moves. */
        const list=await this.pending();
        for(const c of list){
          try{ await this.uploadCommand(c); }
          catch(e){ await this.mark(c.id,'RETRY',{attempts:c.attempts+1,lastError:String(e)}); }
        }
      } finally {this.flushing=false;this.emit()}
    },
    async uploadCommand(c){
      if(!window.db || !window.firebase) throw new Error('FIREBASE_NOT_READY');
      /* Firebase v8 style API, matching B. Offline Firestore can persist this write;
         the immutable command ID makes backend execution idempotent. */
      await window.db.collection('operationCommands').doc(c.id).set(c,{merge:false});
      await this.mark(c.id,'UPLOADED',{uploadedAt:Date.now()});
    },
    emit(){
      this.online=navigator.onLine;
      Promise.all([this.pending(),this.conflicts()]).then(([p,c])=>{
        const el=document.getElementById('imdadSync');
        if(el){el.classList.toggle('offline',!this.online);el.classList.toggle('pending',this.online&&p.length>0);el.classList.toggle('online',this.online&&!p.length);const t=el.querySelector('.sync-text');if(t)t.textContent=!this.online?'غير متصل — محفوظ محليًا':p.length?`مزامنة معلقة (${p.length})`:'متصل — متزامن'}
        const badge=document.getElementById('imdadQueueBadge');if(badge){badge.textContent=p.length;badge.style.display=p.length?'inline-block':'none'}
        window.dispatchEvent(new CustomEvent('imdad:sync-state',{detail:{online:this.online,pending:p.length,conflicts:c.length}}));
      });
    }
  };
  window.IMDAD_UNIFIED=Runtime;
  window.IMDAD_OPERATION=async (module,action,type,payload,baseRevision=null)=>{
    if(window.requirePermission && !window.requirePermission(module,action)) return null;
    return Runtime.enqueue(type,payload,`${module}.${action}`,baseRevision);
  };
  window.addEventListener('online',()=>{Runtime.online=true;Runtime.flush()});
  window.addEventListener('offline',()=>{Runtime.online=false;Runtime.emit()});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)Runtime.flush()});
  setInterval(()=>Runtime.flush(),30000);
  Runtime.emit();
})();
