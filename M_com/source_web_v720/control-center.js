/* IMDAD Settings Center — inline only داخل شاشة الإعدادات */
(function(){
'use strict';
function byId(id){return document.getElementById(id);}
function toastx(m){try{if(window.toast)window.toast(m);else alert(m);}catch(e){}}
var C={
  html:function(){return ''+
  '<div class="panel"><h3>🔐 الحسابات المحلية</h3>'+
  '<div class="page-sub">تسجيل دخول محلي باسم المستخدم وكلمة المرور بدون الاعتماد على Firebase.</div>'+
  '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px">'+
  '<input class="fld" id="ccUser" placeholder="اسم مستخدم جديد">'+
  '<input class="fld" id="ccPass" type="password" placeholder="كلمة المرور (6+) ">'+
  '<select class="fld" id="ccRole"><option value="admin">مدير</option><option value="supervisor">مشرف</option><option value="user">مستخدم</option></select>'+
  '<button class="btn btn-p" id="ccAddUser" type="button">+ إضافة مستخدم محلي</button></div>'+
  '<div id="ccUserList" style="margin-top:10px;font-size:13px;line-height:1.9"></div></div>'+

  '<div class="panel"><h3>📡 مزامنة الأجهزة والمخازن</h3>'+
  '<div class="page-sub">مزامنة لاسلكية بين الأجهزة عبر LAN/WebRTC أو ملف مزامنة عند انعدام الشبكة.</div>'+
  '<div class="rbar"><button class="btn btn-o btn-sm" id="ccOffer" type="button">إنشاء رمز اقتران</button><button class="btn btn-o btn-sm" id="ccAnswer" type="button">الاتصال برمز</button><button class="btn btn-o btn-sm" id="ccComplete" type="button">إكمال الاقتران برمز الرد</button><button class="btn btn-o btn-sm" id="ccExport" type="button">تصدير ملف مزامنة</button><button class="btn btn-o btn-sm" id="ccImport" type="button">استيراد ملف مزامنة</button></div>'+
  '<div id="ccSyncInfo" class="note-box" style="margin-top:10px;direction:ltr;text-align:left;word-break:break-all"></div><input id="ccSyncFile" type="file" accept="application/json" hidden></div>'+

  '<div class="panel"><h3>✍️ التوقيع الإلكتروني</h3>'+
  '<div class="page-sub">توليد مفتاح محلي للقائد وتوقيع أوامر الصرف الحساسة.</div>'+
  '<div class="rbar"><button class="btn btn-o btn-sm" id="ccSignReady" type="button">تهيئة مفتاح القائد</button></div><div id="ccSignInfo" class="note-box" style="margin-top:10px"></div></div>'+

  '<div class="panel"><h3>📦 الاستحقاقات المتغيرة</h3>'+
  '<div class="page-sub">معدل الفرد × القوة × المدة بدل الرقم الثابت.</div>'+
  '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px">'+
  '<input class="fld" id="ccItem" placeholder="معرّف الصنف">'+
  '<input class="fld" id="ccRate" type="number" min="0" step="0.01" placeholder="معدل الفرد/اليوم">'+
  '<button class="btn btn-p" id="ccSetPlan" type="button">حفظ المعدل</button></div>'+
  '<div id="ccPlanList" style="margin-top:10px;font-size:13px;line-height:1.9"></div></div>'+

  '<div class="panel"><h3>🧠 محرك القوانين</h3>'+
  '<div class="page-sub">صياغة بشرية مثل: IF stock(arroz) &lt; 100 THEN notify(\'الرصيد منخفض\')</div>'+
  '<textarea class="fld" id="ccRules" rows="6" style="font-family:monospace;direction:ltr;text-align:left"></textarea>'+
  '<div class="rbar" style="margin-top:10px"><button class="btn btn-o btn-sm" id="ccSaveRules" type="button">حفظ القوانين</button><button class="btn btn-o btn-sm" id="ccRunRules" type="button">تشغيل الآن</button></div></div>'+

  '<div class="panel"><h3>🔔 الإشعارات</h3>'+
  '<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px;align-items:center">'+
  '<label><input type="checkbox" id="ccPush"> تنبيه محلي عند تجاوز الاستحقاق</label></div></div>';
  },
  /* صلاحيات: لوحة الحسابات المحلية لمدير النظام أو من يملك تعديل المستخدمين فقط،
     وباقي اللوحات التشغيلية تتطلب صلاحية تعديل الإعدادات. */
  may:function(page,action){try{return typeof hasPerm==='function'?hasPerm(page,action):true;}catch(e){return false;}},
  canUsers:function(){return C.may('usersAccess','edit');},
  canSettings:function(){return C.may('settings','edit');},
  renderInto:function(host){ if(!host) return;
    var h=C.html(),parts=h.split('<div class="panel">').filter(Boolean);
    var keep=parts.filter(function(p,i){ if(i===0) return C.canUsers(); return C.canSettings(); });
    host.innerHTML=keep.length?keep.map(function(p){return '<div class="panel">'+p;}).join(''):'<div class="panel"><div class="note-box">لا تملك صلاحية إدارة الإعدادات المتقدمة.</div></div>';
    C.bind(); C.refresh(); },
  refresh:function(){
    var u=byId('ccUserList'); if(u&&window.AUTH_LOCAL) window.AUTH_LOCAL.list().then(function(arr){u.innerHTML=arr.length?arr.map(function(x){return '• '+x.user+' — '+(x.role||'user');}).join('<br>'):'لا توجد حسابات محلية بعد';});
    var p=byId('ccPlanList'); if(p&&window.IMDAD_ENT) window.IMDAD_ENT.allPlans().then(function(arr){p.innerHTML=arr.length?arr.map(function(x){return '• '+x.itemId+' : '+x.perPerson+' /فرد/يوم';}).join('<br>'):'لا توجد معدلات محفوظة';});
    var s=byId('ccSignInfo'); if(s&&window.IMDAD_ESIGN) window.IMDAD_ESIGN.hasKey('commander').then(function(ok){s.textContent=ok?'مفتاح القائد جاهز على هذا الجهاز':'لم يتم إنشاء المفتاح بعد';});
    var rt=byId('ccRules'); if(rt&&window.IMDAD_RULES) window.IMDAD_RULES.load('main').then(function(rec){ if(rec) rt.value=rec.text||'';});
    var pu=byId('ccPush'); if(pu) pu.checked=localStorage.getItem('imdad.push')==='1';
  },
  bind:function(){
    var a=byId('ccAddUser'); if(a) a.onclick=function(){if(!C.canUsers())return toastx('✖ إنشاء الحسابات متاح لمدير النظام أو من يملك صلاحية تعديل المستخدمين');var u=(byId('ccUser').value||'').trim(), p=(byId('ccPass').value||''), r=(byId('ccRole').value||'user'); if(!u||p.length<6) return toastx('✖ أدخل اسم مستخدم وكلمة مرور صحيحة'); window.AUTH_LOCAL.register(u,p,{name:u,username:u,role:r}).then(function(){toastx('✔ تم إنشاء المستخدم'); C.refresh();}).catch(function(e){toastx('✖ '+(e&&e.message==='exists'?'المستخدم موجود':'تعذر الإنشاء'));});};
    var o=byId('ccOffer'); if(o) o.onclick=function(){window.IMDAD_SYNC.pairOffer().then(function(code){byId('ccSyncInfo').textContent=code;}).catch(function(e){byId('ccSyncInfo').textContent='ERR: '+e.message;});};
    var an=byId('ccAnswer'); if(an) an.onclick=function(){var code=prompt('ألصق رمز الاقتران'); if(!code) return; window.IMDAD_SYNC.pairAnswer(code).then(function(ans){byId('ccSyncInfo').textContent=ans;}).catch(function(e){byId('ccSyncInfo').textContent='ERR: '+e.message;});};
    var cp=byId('ccComplete'); if(cp) cp.onclick=function(){var code=prompt('ألصق رمز الرد من الجهاز الآخر'); if(!code) return; window.IMDAD_SYNC.pairComplete(code).then(function(){toastx('✔ تم الاقتران');}).catch(function(e){byId('ccSyncInfo').textContent='ERR: '+e.message;});};
    var ex=byId('ccExport'); if(ex) ex.onclick=function(){window.IMDAD_SYNC.exportFile().then(function(n){toastx('✔ تم تصدير '+n+' سجل');});};
    var im=byId('ccImport'); if(im) im.onclick=function(){byId('ccSyncFile').click();};
    var sf=byId('ccSyncFile'); if(sf) sf.onchange=function(){var f=sf.files&&sf.files[0]; if(!f) return; window.IMDAD_SYNC.importFile(f).then(function(n){toastx('✔ تم استيراد '+n+' سجل');}).catch(function(e){toastx('✖ '+e.message);});};
    var sg=byId('ccSignReady'); if(sg) sg.onclick=function(){window.IMDAD_ESIGN.ensureKey('commander').then(function(){toastx('✔ تم تهيئة مفتاح القائد'); C.refresh();});};
    var sp=byId('ccSetPlan'); if(sp) sp.onclick=function(){var it=(byId('ccItem').value||'').trim(), rate=parseFloat(byId('ccRate').value); if(!it||isNaN(rate)) return toastx('✖ أدخل الصنف والمعدل'); window.IMDAD_ENT.setPlan(it,{perPerson:rate}).then(function(){toastx('✔ تم حفظ المعدل'); C.refresh();});};
    var sv=byId('ccSaveRules'); if(sv) sv.onclick=function(){window.IMDAD_RULES.save('main',byId('ccRules').value||'').then(function(){toastx('✔ تم حفظ القوانين');});};
    var rn=byId('ccRunRules'); if(rn) rn.onclick=function(){var fired=window.IMDAD_RULES.run(byId('ccRules').value||'',{daysLeft:30,stockMap:{}}); toastx('⚡ عدد القواعد المفعلة: '+fired.length);};
    var pu=byId('ccPush'); if(pu) pu.onchange=function(){localStorage.setItem('imdad.push',pu.checked?'1':'0'); if(pu.checked&&window.Notification&&Notification.permission!=='granted') Notification.requestPermission();};
  }
};
window.IMDAD_SETTINGS_CENTER=C;
})();
