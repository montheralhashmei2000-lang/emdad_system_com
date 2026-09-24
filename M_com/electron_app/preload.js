// لا يُكشف أي وصول لـ Node للواجهة؛ فقط معلومة أن النظام يعمل كتطبيق سطح مكتب.
const { contextBridge } = require('electron');
contextBridge.exposeInMainWorld('imdadDesktop', { isDesktop: true, platform: process.platform });
