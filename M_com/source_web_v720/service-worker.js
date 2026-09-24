/* IMDAD Service Worker v10 — وضع دون اتصال + إشعارات */
const CACHE='imdad-shell-v27-campdd';
const SHELL=['./','./index.html','./core/error-handler.js','./ui-icons.js','./reports-center.js','./unit-carry.js','./stocktake-center.js','./documents-center.js','./access-control.js','./strength-fix.js','./print-layout.js','./item-picker.js','./stock-ledger.js','./assets/logo.png','./ui-theme.css','./vendor/chart.umd.min.js','./vendor/xlsx.full.min.js','./platform-ux.css','./forms-ux.css','./unified-runtime.js','./imdad-upgrade-v4.js','./platform-ux.js','./forms-ux.js','./mi-app-ux.js','./auth-ux.js','./auth-local.js','./lan-sync.js','./esign.js','./entitlements.js','./rules-engine.js','./excel-resume.js','./control-center.js','./manifest.json','./icon-192.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()));});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET')return;
  e.respondWith(
    fetch(e.request).then(res=>{if(res.ok&&new URL(e.request.url).origin===self.location.origin){const cp=res.clone();caches.open(CACHE).then(c=>c.put(e.request,cp)).catch(()=>{});}return res;})
    .catch(()=>caches.match(e.request).then(m=>m||caches.match('./index.html')))
  );
});
self.addEventListener('push',function(e){let data={title:'إمداد',body:'إشعار من نظام الإمداد والتموين'};
  try{if(e.data)data=JSON.parse(e.data.text());}catch(err){}
  e.waitUntil(self.registration.showNotification(data.title||'إمداد',{body:data.body||'',icon:data.icon||'./icon-192.png',tag:'imdad-push'}));});
self.addEventListener('notificationclick',function(e){e.notification.close();e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{for(const c of list){if('focus' in c){c.focus();return;}}if(clients.openWindow)return clients.openWindow('./');}));});
