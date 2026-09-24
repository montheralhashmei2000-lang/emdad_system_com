/* IMDAD Rules Engine v1 — محرك قوانين بصياغة بشرية (IF ... THEN ...) بدون برمجة وبدون eval */
(function(){
'use strict';
var DB='imdad-rules',ST='rules';
function openDB(){return new Promise(function(res,rej){var r=indexedDB.open(DB,1);
  r.onupgradeneeded=function(e){var d=e.target.result;if(!d.objectStoreNames.contains(ST))d.createObjectStore(ST,{keyPath:'id'});};
  r.onsuccess=function(){res(r.result);};r.onerror=function(){rej(r.error);};});}
function rget(id){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(ST,'readonly'),r=t.objectStore(ST).get(id);
  r.onsuccess=function(){res(r.result||null);};r.onerror=function(){rej(r.error);};});});}
function rput(rec){return openDB().then(function(db){return new Promise(function(res,rej){var t=db.transaction(ST,'readwrite'),r=t.objectStore(ST).put(rec);
  r.onsuccess=function(){res(true);};r.onerror=function(){rej(r.error);};});});}
function rall(){return openDB().then(function(db){return new Promise(function(res,rej){var r=db.transaction(ST,'readonly').objectStore(ST).getAll();
  r.onsuccess=function(){res(r.result||[]);};r.onerror=function(){rej(r.error);};});});}
function cmp(op,a,b){switch(op){case '>':return a>b;case '<':return a<b;case '>=':return a>=b;case '<=':return a<=b;case '==':return a==b;case '!=':return a!=b;}return false;}
function resolvePath(src,path){if(!src||!path)return null;var parts=String(path).split('.');var cur=src;
  for(var i=0;i<parts.length;i++){if(cur==null)return null;cur=cur[parts[i]];}return cur;}
var DATA={};
var R={
  registerData:function(name,fn){DATA[name]=fn;},
  parse:function(text){var lines=String(text||'').split(/\r?\n/);var rules=[];
    lines.forEach(function(line,i){line=line.trim();if(!line||line.charAt(0)==='#')return;
      var m=line.match(/^IF\s+(.+)\s+THEN\s+(.+)$/i);if(!m)return;
      var conds=m[1].split(/\s+AND\s+/i);var acts=m[2].split(/\s*;\s*/);
      var pc=conds.map(function(c){var cm=c.match(/^([A-Za-z_][\w.]*)\(([^)]*)\)\s*(<=|>=|==|!=|<|>)\s*([\d.]+)$/);
        if(!cm)return null;return {fn:cm[1],arg:cm[2].replace(/^['"]|['"]$/g,''),op:cm[3],val:parseFloat(cm[4])};}).filter(Boolean);
      var pa=acts.map(function(a){var am=a.match(/^([A-Za-z_]+)\(([^)]*)\)$/);
        if(!am)return null;return {action:am[1],arg:am[2].replace(/^['"]|['"]$/g,'')};}).filter(Boolean);
      if(pc.length&&pa.length)rules.push({id:'rule-'+(i+1),line:line,conds:pc,acts:pa,enabled:true});});
    return rules;},
  evalRule:function(rule,ctx){ctx=ctx||{};
    for(var i=0;i<rule.conds.length;i++){var cn=rule.conds[i];var fn=DATA[cn.fn];var val=null;
      if(fn){try{val=Number(fn(cn.arg,ctx));}catch(e){val=0;}}
      else val=Number(resolvePath(ctx,cn.fn+'.'+cn.arg));
      if(isNaN(val))val=0;
      if(!cmp(cn.op,val,cn.val))return false;}
    return true;},
  run:function(text,ctx){var rules=(typeof text==='string')?R.parse(text):(text||[]);var fired=[];
    rules.forEach(function(r){if(r.enabled!==false&&R.evalRule(r,ctx)){
        r.acts.forEach(function(a){fired.push(a);
          if(a.action==='notify'){try{if(window.toast)window.toast('⚡ قاعدة: '+a.arg);
              if(typeof Notification!=='undefined'&&Notification.permission==='granted'){var n=new Notification('نظام الإمداد — تنبيه قاعدة',{body:a.arg,tag:'imdad-rule'});setTimeout(function(){try{n.close();}catch(e){}},8000);}}catch(e){}}
          else if(a.action==='block'){ctx.__blocked=true;fired.__blocked=true;}
        });}});
    return fired;},
  save:function(id,text){return rput({id:id,text:String(text||''),updatedAt:new Date().toISOString()});},
  load:function(id){return rget(id);},
  all:function(){return rall();},
  runSaved:function(id,ctx){return rget(id).then(function(rec){if(!rec)return [];return R.run(rec.text,ctx);});},
  runAll:function(ctx){return rall().then(function(recs){var fired=[];recs.forEach(function(rec){fired=fired.concat(R.run(rec.text,ctx));});return fired;});}
};
window.IMDAD_RULES=R;
/* حقول بيانات افتراضية قابلة للربط لاحقًا بمصادر الأرصدة */
R.registerData('stock',function(arg,ctx){try{if(ctx&&ctx.stockMap&&ctx.stockMap[arg]!=null)return ctx.stockMap[arg];}catch(e){}return 0;});
R.registerData('daysLeft',function(arg,ctx){return ctx&&ctx.daysLeft!=null?ctx.daysLeft:0;});
R.registerData('avgUse',function(arg,ctx){return ctx&&ctx.avgUse&&ctx.avgUse[arg]!=null?ctx.avgUse[arg]:0;});
R.registerData('transfers',function(arg,ctx){return ctx&&ctx.transfers&&ctx.transfers[arg]!=null?ctx.transfers[arg]:0;});
R.registerData('qty',function(arg,ctx){return ctx&&ctx.qty!=null?ctx.qty:0;});
})();
