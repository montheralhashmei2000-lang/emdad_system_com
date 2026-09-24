/* IMDAD UI Icons v1 — مكتبة أيقونات متجهة (SVG بأسلوب خطّي احترافي) + تحويل الرموز التعبيرية تلقائيًا
   - تُحقن مجموعة الرموز <symbol> مرة واحدة في الصفحة.
   - أي رمز تعبيري داخل نصوص الواجهة (بما فيها المحتوى المولَّد ديناميكيًا) يُستبدل بأيقونة SVG مكافئة دلاليًا.
   - لا تُمس: حقول الإدخال، معاينة الطباعة الرسمية، والعناصر الموسومة data-noicon.
   - الاستخدام البرمجي: IMDAD_ICON('printer') يُرجع وسم SVG نصيًا. */
(function(){
'use strict';

/* p=path d | c=circle cx cy r | r=rect x y w h rx | e=ellipse cx cy rx ry | f=دائرة مصمتة */
var I={
  x:['p:M18 6 6 18','p:M6 6l12 12'],
  check:['p:M20 6 9 17l-5-5'],
  'check-circle':['p:M22 11.08V12a10 10 0 1 1-5.93-9.14','p:M22 4 12 14.01l-3-3'],
  ban:['c:12 12 10','p:M4.93 4.93l14.14 14.14'],
  hourglass:['p:M5 22h14','p:M5 2h14','p:M17 22v-4.17a2 2 0 0 0-.59-1.42L12 12l-4.41 4.41A2 2 0 0 0 7 17.83V22','p:M7 2v4.17a2 2 0 0 0 .59 1.42L12 12l4.41-4.41A2 2 0 0 0 17 6.17V2'],
  clock:['c:12 12 10','p:M12 6v6l4 2'],
  save:['p:M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z','p:M17 21v-8H7v8','p:M7 3v5h8'],
  printer:['p:M6 9V2h12v7','p:M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2','r:6 14 12 8 1'],
  alert:['p:M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z','p:M12 9v4','p:M12 17h.01'],
  search:['c:11 11 8','p:M21 21l-4.35-4.35'],
  clipboard:['p:M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2','r:8 2 8 4 1','p:M9 12h6','p:M9 16h6'],
  eye:['p:M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z','c:12 12 3'],
  users:['p:M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2','c:9 7 4','p:M23 21v-2a4 4 0 0 0-3-3.87','p:M16 3.13a4 4 0 0 1 0 7.75'],
  user:['p:M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2','c:12 7 4'],
  warehouse:['p:M22 8.35V20a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8.35A2 2 0 0 1 3.26 6.5l8-3.2a2 2 0 0 1 1.48 0l8 3.2A2 2 0 0 1 22 8.35z','p:M6 18h12','p:M6 14h12','p:M6 22V10h12v12'],
  building:['r:4 2 16 20 2','p:M9 22v-4h6v4','p:M8 6h.01','p:M12 6h.01','p:M16 6h.01','p:M8 10h.01','p:M12 10h.01','p:M16 10h.01','p:M8 14h.01','p:M12 14h.01','p:M16 14h.01'],
  target:['c:12 12 10','c:12 12 6','c:12 12 2'],
  edit:['p:M12 20h9','p:M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z'],
  refresh:['p:M23 4v6h-6','p:M1 20v-6h6','p:M3.51 9a9 9 0 0 1 14.85-3.36L23 10','p:M1 14l4.64 4.36A9 9 0 0 0 20.49 15'],
  'rotate-ccw':['p:M1 4v6h6','p:M3.51 15a9 9 0 1 0 2.13-9.36L1 10'],
  repeat:['p:M17 1l4 4-4 4','p:M3 11V9a4 4 0 0 1 4-4h14','p:M7 23l-4-4 4-4','p:M21 13v2a4 4 0 0 1-4 4H3'],
  undo:['p:M9 14 4 9l5-5','p:M4 9h10.5a5.5 5.5 0 0 1 0 11H11'],
  chart:['p:M18 20V10','p:M12 20V4','p:M6 20v-6'],
  trending:['p:M23 6l-9.5 9.5-5-5L1 18','p:M17 6h6v6'],
  file:['p:M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z','p:M14 2v6h6','p:M16 13H8','p:M16 17H8','p:M10 9H8'],
  plus:['p:M12 5v14','p:M5 12h14'],
  'plus-square':['r:3 3 18 18 2','p:M12 8v8','p:M8 12h8'],
  trash:['p:M3 6h18','p:M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6','p:M10 11v6','p:M14 11v6','p:M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2'],
  tent:['p:M3.5 21 14 3','p:M20.5 21 10 3','p:M15.5 21 12 15l-3.5 6','p:M2 21h20'],
  shield:['p:M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z'],
  bulb:['p:M9 18h6','p:M10 22h4','p:M12 2a7 7 0 0 0-4 12.7V17h8v-2.3A7 7 0 0 0 12 2z'],
  package:['p:M16.5 9.4 7.5 4.21','p:M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z','p:M3.27 6.96 12 12.01l8.73-5.05','p:M12 22.08V12'],
  upload:['p:M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4','p:M17 8l-5-5-5 5','p:M12 3v12'],
  download:['p:M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4','p:M7 10l5 5 5-5','p:M12 15V3'],
  calculator:['r:4 2 16 20 2','p:M8 6h8','p:M8 10h.01','p:M12 10h.01','p:M16 10h.01','p:M8 14h.01','p:M12 14h.01','p:M16 14h.01','p:M8 18h.01','p:M12 18h.01','p:M16 18h.01'],
  settings:['c:12 12 3','p:M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z'],
  sliders:['p:M4 21v-7','p:M4 10V3','p:M12 21v-9','p:M12 8V3','p:M20 21v-5','p:M20 12V3','p:M1 14h6','p:M9 8h6','p:M17 16h6'],
  wrench:['p:M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z'],
  bell:['p:M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9','p:M13.73 21a2 2 0 0 1-3.46 0'],
  zap:['p:M13 2 3 14h9l-1 8 10-12h-9l1-8z'],
  'arrow-left':['p:M19 12H5','p:M12 19l-7-7 7-7'],
  'arrow-right':['p:M5 12h14','p:M12 5l7 7-7 7'],
  'arrow-up':['p:M12 19V5','p:M5 12l7-7 7 7'],
  'arrow-down':['p:M12 5v14','p:M19 12l-7 7-7-7'],
  'arrow-down-right':['p:M7 7l10 10','p:M17 7v10H7'],
  external:['p:M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6','p:M15 3h6v6','p:M10 14 21 3'],
  swap:['p:M8 3 4 7l4 4','p:M4 7h16','p:M16 21l4-4-4-4','p:M20 17H4'],
  'chevron-down':['p:M6 9l6 6 6-6'],
  'chevron-left':['p:M15 18l-6-6 6-6'],
  'chevron-right':['p:M9 18l6-6-6-6'],
  eraser:['p:M20 20H7L3 16l10-10 7 7-3.5 3.5','p:M6.5 13.5l5 5'],
  info:['c:12 12 10','p:M12 16v-4','p:M12 8h.01'],
  pin:['p:M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z','c:12 10 3'],
  truck:['r:1 3 15 13 1','p:M16 8h4l3 3v5h-7V8z','c:5.5 18.5 2.5','c:18.5 18.5 2.5'],
  utensils:['p:M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2','p:M7 2v20','p:M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3z','p:M21 15v7'],
  home:['p:M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z','p:M9 22V12h6v10'],
  folder:['p:M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z'],
  tag:['p:M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z','p:M7 7h.01'],
  image:['r:3 3 18 18 2','c:8.5 8.5 1.5','p:M21 15l-5-5L5 21'],
  lock:['r:3 11 18 11 2','p:M7 11V7a5 5 0 0 1 10 0v4'],
  unlock:['r:3 11 18 11 2','p:M7 11V7a5 5 0 0 1 9.9-1'],
  calendar:['r:3 4 18 18 2','p:M16 2v4','p:M8 2v4','p:M3 10h18'],
  scale:['p:M16 16l3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1z','p:M2 16l3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1z','p:M7 21h10','p:M12 3v18','p:M3 7h2c2 0 5-1 7-2 2 1 5 2 7 2h2'],
  phone:['r:5 2 14 20 2','p:M12 18h.01'],
  monitor:['r:2 3 20 14 2','p:M8 21h8','p:M12 17v4'],
  compass:['c:12 12 10','p:M16.24 7.76l-2.12 6.36-6.36 2.12 2.12-6.36z'],
  dot:['f:12 12 5'],
  square:['r:4 4 16 16 2'],
  globe:['c:12 12 10','p:M2 12h20','p:M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z'],
  database:['e:12 5 9 3','p:M21 12c0 1.66-4 3-9 3s-9-1.34-9-3','p:M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5'],
  link:['p:M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71','p:M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71'],
  sun:['c:12 12 4','p:M12 2v2','p:M12 20v2','p:M4.93 4.93l1.41 1.41','p:M17.66 17.66l1.41 1.41','p:M2 12h2','p:M20 12h2','p:M6.34 17.66l-1.41 1.41','p:M19.07 4.93l-1.41 1.41'],
  moon:['p:M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z'],
  radio:['p:M5 12.55a11 11 0 0 1 14.08 0','p:M1.42 9a16 16 0 0 1 21.16 0','p:M8.53 16.11a6 6 0 0 1 6.94 0','p:M12 20h.01'],
  activity:['p:M22 12h-4l-3 9L9 3l-3 9H2'],
  scan:['p:M3 7V5a2 2 0 0 1 2-2h2','p:M17 3h2a2 2 0 0 1 2 2v2','p:M21 17v2a2 2 0 0 1-2 2h-2','p:M7 21H5a2 2 0 0 1-2-2v-2','c:12 12 3'],
  camera:['p:M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z','c:12 13 4'],
  flask:['p:M9 3h6','p:M10 3v6L4 20a1 1 0 0 0 .9 1.5h14.2a1 1 0 0 0 .9-1.5L14 9V3'],
  dollar:['p:M12 1v22','p:M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6'],
  hash:['p:M4 9h16','p:M4 15h16','p:M10 3 8 21','p:M16 3l-2 18'],
  award:['c:12 8 7','p:M8.21 13.89 7 23l5-3 5 3-1.21-9.12'],
  star:['p:M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01z'],
  menu:['p:M3 12h18','p:M3 6h18','p:M3 18h18']
};

/* الرمز التعبيري → [الأيقونة، النغمة اللونية] */
var M={
  '✖':['x','danger'],'❌':['x','danger'],'⛔':['ban','danger'],'🔴':['dot','danger'],'🚨':['alert','danger'],
  '✔':['check','success'],'✅':['check-circle','success'],'👌':['check','success'],'🎉':['check-circle','success'],'🟢':['dot','success'],
  '⚠':['alert','warn'],'🚧':['alert','warn'],
  '⏳':['hourglass'],'🕘':['clock'],'💾':['save'],'🖨':['printer'],'🔍':['search'],'🔎':['search'],
  '📋':['clipboard'],'📑':['file'],'📜':['file'],'🧾':['file'],'📝':['file'],
  '👁':['eye'],'👥':['users'],'🤝':['users'],'👤':['user'],'👋':['user'],'👑':['award'],'⭐':['star'],
  '🏬':['warehouse'],'🏢':['building'],'🏫':['building'],'🏛':['building'],
  '🎯':['target'],'✏':['edit'],'✍':['edit'],'🔄':['refresh'],'🔁':['repeat'],'↺':['rotate-ccw'],'↩':['undo'],
  '📊':['chart'],'📈':['trending'],'➕':['plus'],'🆕':['plus-square'],'🗑':['trash'],
  '🏕':['tent'],'🌳':['tent'],'🛡':['shield'],'🔐':['lock'],'🔒':['lock'],'🔓':['unlock'],
  '🧠':['bulb'],'💡':['bulb'],'🔮':['bulb'],'📦':['package'],'🧊':['package'],
  '📤':['upload'],'📥':['download'],'⬆':['arrow-up'],'⬇':['arrow-down'],'↗':['external'],'↘':['arrow-down-right'],
  '🧮':['calculator'],'🔢':['hash'],'⚙':['settings'],'🎛':['sliders'],'🛠':['wrench'],
  '🔔':['bell'],'📢':['bell'],'⚡':['zap'],'🔥':['zap'],'💥':['zap'],'🚀':['zap'],
  '←':['arrow-left'],'→':['arrow-right'],'↔':['swap'],'▼':['chevron-down'],'▶':['chevron-right'],'◀':['chevron-left'],
  '🧹':['eraser'],'ℹ':['info'],'📌':['pin'],'🚚':['truck'],'🍴':['utensils'],'🍽':['utensils'],'🍲':['utensils'],
  '🏠':['home'],'🗂':['folder'],'🏷':['tag'],'🎨':['image'],'🖼':['image'],
  '📅':['calendar'],'⚖':['scale'],'📏':['scale'],'📱':['phone'],'🖥':['monitor'],'💻':['monitor'],'🧭':['compass'],
  '🔹':['dot','accent'],'⬜':['square'],'🌐':['globe'],'🛢':['database'],'🔗':['link'],
  '🌅':['sun'],'🌞':['sun'],'🌙':['moon'],'📡':['radio'],'🩺':['activity'],'🕵':['scan'],'📷':['camera'],
  '🧪':['flask'],'💰':['dollar'],'☰':['menu']
};

var NS='http://www.w3.org/2000/svg';
function esc(s){return String(s).replace(/[.*+?^${}()|[\]\\]/g,'\\$&');}
var keys=Object.keys(M).sort(function(a,b){return b.length-a.length;});
/* يلتقط الرمز مع محدِّد الشكل ‎FE0F‎ الاختياري ومسافة لاحقة واحدة */
var RE=new RegExp('('+keys.map(esc).join('|')+')\\uFE0F?','g');
var TEST=new RegExp('('+keys.map(esc).join('|')+')');

function buildSprite(){
  if(document.getElementById('imdIconSprite'))return;
  var svg=document.createElementNS(NS,'svg');
  svg.setAttribute('id','imdIconSprite');svg.setAttribute('aria-hidden','true');
  svg.style.cssText='position:absolute;width:0;height:0;overflow:hidden';
  var html='';
  Object.keys(I).forEach(function(name){
    html+='<symbol id="ic-'+name+'" viewBox="0 0 24 24">';
    I[name].forEach(function(s){
      var t=s.charAt(0),v=s.slice(2),n=v.split(' ');
      if(t==='p')html+='<path d="'+v+'"/>';
      else if(t==='c')html+='<circle cx="'+n[0]+'" cy="'+n[1]+'" r="'+n[2]+'"/>';
      else if(t==='f')html+='<circle cx="'+n[0]+'" cy="'+n[1]+'" r="'+n[2]+'" fill="currentColor" stroke="none"/>';
      else if(t==='r')html+='<rect x="'+n[0]+'" y="'+n[1]+'" width="'+n[2]+'" height="'+n[3]+'" rx="'+(n[4]||0)+'"/>';
      else if(t==='e')html+='<ellipse cx="'+n[0]+'" cy="'+n[1]+'" rx="'+n[2]+'" ry="'+n[3]+'"/>';
    });
    html+='</symbol>';
  });
  svg.innerHTML=html;
  document.body.insertBefore(svg,document.body.firstChild);
}

function iconEl(name,tone){
  var s=document.createElementNS(NS,'svg');
  s.setAttribute('class','ic ic-'+name+(tone?' ic-'+tone:''));
  s.setAttribute('aria-hidden','true');s.setAttribute('focusable','false');
  var u=document.createElementNS(NS,'use');
  u.setAttribute('href','#ic-'+name);
  s.appendChild(u);return s;
}
window.IMDAD_ICON=function(name,tone){
  return '<svg class="ic ic-'+name+(tone?' ic-'+tone:'')+'" aria-hidden="true" focusable="false"><use href="#ic-'+name+'"></use></svg>';
};

var SKIP='script,style,textarea,input,select,svg,#militaryPrintSheet,[data-noicon],[contenteditable="true"]';
function convertText(node){
  var p=node.parentNode;if(!p||p.nodeType!==1)return;
  var t=node.nodeValue;if(!t||!TEST.test(t))return;
  if(p.closest&&p.closest(SKIP))return;
  if(p.tagName==='OPTION'||p.tagName==='TITLE'){node.nodeValue=t.replace(RE,'').replace(/^\s+/,'');return;}
  var frag=document.createDocumentFragment(),last=0,m;RE.lastIndex=0;
  while((m=RE.exec(t))){
    if(m.index>last)frag.appendChild(document.createTextNode(t.slice(last,m.index)));
    var def=M[m[1]];frag.appendChild(iconEl(def[0],def[1]));
    last=RE.lastIndex;
  }
  if(last<t.length)frag.appendChild(document.createTextNode(t.slice(last)));
  p.replaceChild(frag,node);
}
function convertAttr(el){
  ['title','placeholder','aria-label'].forEach(function(a){
    var v=el.getAttribute&&el.getAttribute(a);
    if(v&&TEST.test(v))el.setAttribute(a,v.replace(RE,'').replace(/^\s+/,''));
  });
}
function walk(root){
  if(!root)return;
  if(root.nodeType===3){convertText(root);return;}
  if(root.nodeType!==1)return;
  if(root.closest&&root.closest('#militaryPrintSheet,[data-noicon]'))return;
  convertAttr(root);
  root.querySelectorAll&&root.querySelectorAll('[title],[placeholder],[aria-label]').forEach(convertAttr);
  var w=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,null),list=[],n;
  while((n=w.nextNode()))if(TEST.test(n.nodeValue))list.push(n);
  list.forEach(convertText);
}

var queue=[],scheduled=false;
function flush(){scheduled=false;var q=queue;queue=[];q.forEach(walk);}
function enqueue(n){queue.push(n);if(!scheduled){scheduled=true;(window.requestAnimationFrame||setTimeout)(flush);}}

function start(){
  buildSprite();
  walk(document.body);
  new MutationObserver(function(muts){
    for(var i=0;i<muts.length;i++){
      var m=muts[i];
      if(m.type==='characterData')enqueue(m.target);
      else if(m.type==='attributes')convertAttr(m.target);
      else for(var j=0;j<m.addedNodes.length;j++)enqueue(m.addedNodes[j]);
    }
  }).observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:['title','placeholder','aria-label']});
}
window.IMDAD_ICONS={map:M,icons:I,convert:walk};
if(document.body)start();else document.addEventListener('DOMContentLoaded',start);
})();
