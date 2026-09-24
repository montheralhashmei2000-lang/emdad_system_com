// يولّد lib/core/ui/imd_icon_data.dart من مكتبة أيقونات نسخة الويب (ui-icons.js)
// حتى تكون الأيقونات في Flutter هي نفسها حرفيًا.
// التشغيل من مجلد imdad_flutter:  node tool/gen_icons.js
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '../../source_web_v720/ui-icons.js'), 'utf8');
const I = eval('(' + src.match(/var I=(\{[\s\S]*?\n\});/)[1] + ')');
const M = eval('(' + src.match(/var M=(\{[\s\S]*?\n\});/)[1] + ')');
const q = (s) => "'" + s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$') + "'";

let out = '// مولَّد من source_web_v720/ui-icons.js عبر tool/gen_icons.js — لا تعدّله يدويًا.\n';
out += '// كل أيقونة: عناصر SVG داخل viewBox 24×24 بخط 2 (نفس مكتبة أيقونات نسخة الويب).\n\n';
out += 'const Map<String, String> kImdIconBodies = {\n';
for (const [name, parts] of Object.entries(I)) {
  let body = '';
  for (const s of parts) {
    const t = s[0], v = s.slice(2), a = v.split(' ');
    if (t === 'p') body += `<path d="${v}"/>`;
    else if (t === 'c') body += `<circle cx="${a[0]}" cy="${a[1]}" r="${a[2]}"/>`;
    else if (t === 'f') body += `<circle cx="${a[0]}" cy="${a[1]}" r="${a[2]}" fill="#000" stroke="none"/>`;
    else if (t === 'r') body += `<rect x="${a[0]}" y="${a[1]}" width="${a[2]}" height="${a[3]}" rx="${a[4] || 0}"/>`;
    else if (t === 'e') body += `<ellipse cx="${a[0]}" cy="${a[1]}" rx="${a[2]}" ry="${a[3]}"/>`;
  }
  out += `  ${q(name)}: ${q(body)},\n`;
}
out += '};\n\n/// الرمز التعبيري ← [الأيقونة، النغمة اللونية]\n';
out += 'const Map<String, List<String>> kImdEmojiIcons = {\n';
for (const [k, v] of Object.entries(M)) out += `  ${q(k)}: [${v.map(q).join(', ')}],\n`;
out += '};\n';

const dest = path.join(__dirname, '../lib/core/ui/imd_icon_data.dart');
fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.writeFileSync(dest, out);
console.log(Object.keys(I).length, 'icons,', Object.keys(M).length, 'emoji');
