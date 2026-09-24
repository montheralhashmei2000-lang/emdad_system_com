(function(){
'use strict';
var d=document;
function $(id){return d.getElementById(id);}
function applyLogoSize(){
  try{
    var px=Number(localStorage.getItem('imdad.brand.logoSize'))||140;
    if($('brandLogoSize'))$('brandLogoSize').value=px;
    d.documentElement.style.setProperty('--imp-logo-h', px+'px');
  }catch(e){}
}
function applyTheme(){
  try{
    var pref=localStorage.getItem('imdad.themePref')||'auto';
    var v=pref;
    if(pref==='auto')v=(window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches)?'dark':'light';
    d.documentElement.dataset.theme=v;
    if($('brandThemePref'))$('brandThemePref').value=pref;
  }catch(e){}
}
window.setTheme=function(v){try{localStorage.setItem('imdad.themePref',String(v));applyTheme();}catch(e){}};
function bindBrandPage(){
  applyLogoSize(); applyTheme();
  if($('brandThemePref')&&!$('brandThemePref').dataset.imd){$('brandThemePref').dataset.imd='1';$('brandThemePref').onchange=e=>window.setTheme(e.target.value);}
  if($('brandLogoSize')&&!$('brandLogoSize').dataset.imd){$('brandLogoSize').dataset.imd='1';$('brandLogoSize').onchange=e=>{localStorage.setItem('imdad.brand.logoSize', e.target.value); applyLogoSize();};}
}
function bindExitConfirm(){
  var msg='هل تريد الخروج من نظام الإمداد والتموين؟';
  window.addEventListener('beforeunload', function(e){
    try{
      var has=(window.me&&window.me.state);
      if(has){e.preventDefault(); e.returnValue=msg; return msg;}
    }catch(err){}
  });
}
function boot(){bindExitConfirm();applyLogoSize();applyTheme();setInterval(bindBrandPage,1200);}
if(/complete|interactive/.test(d.readyState))setTimeout(boot,0);else d.addEventListener('DOMContentLoaded',boot);
})();
