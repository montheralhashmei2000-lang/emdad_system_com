// غلاف سطح المكتب لنظام الإمداد: يعرض نسخة الويب نفسها (مجلد web) في نافذة مستقلة.
// يُحمَّل عبر بروتوكول app:// بأصل ثابت حتى تبقى بيانات IndexedDB وLocalStorage بين التشغيلات.
const { app, BrowserWindow, protocol, net, shell } = require('electron');
const path = require('path');
const { pathToFileURL } = require('url');

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true } },
]);

const WEB = path.join(__dirname, 'web');

function createWindow() {
  const win = new BrowserWindow({
    width: 1366,
    height: 860,
    minWidth: 1024,
    minHeight: 680,
    title: 'نظام الإمداد والتموين',
    icon: path.join(process.resourcesPath || __dirname, 'icon.png'),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  // الروابط الخارجية تُفتح في المتصفح لا داخل النظام.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('app://')) return { action: 'allow' };
    shell.openExternal(url);
    return { action: 'deny' };
  });
  win.loadURL('app://imdad/index.html');
}

app.whenReady().then(() => {
  protocol.handle('app', (request) => {
    const rel = decodeURIComponent(new URL(request.url).pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.normalize(path.join(WEB, rel));
    if (!file.startsWith(WEB)) return new Response('Forbidden', { status: 403 });
    return net.fetch(pathToFileURL(file).toString());
  });
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
