const {app, BrowserWindow, ipcMain, Menu, session, shell} = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const {spawn} = require('node:child_process');
const base = path.resolve(__dirname, '..');
const preview = process.argv.includes('--preview') || process.argv.includes('--verify-ui');
const profile = path.join(app.getPath('userData'), preview?'ShuniangPreview':'ShuniangGuardPet');
process.env.DSH_HOME = profile;
process.env.BOOK_GUARD_PROFILE = profile;
app.setPath('userData',profile);
const stateFile = path.join(process.env.ProgramData || 'C:\\ProgramData','ShuniangGuard','status.json');
let panel;
function status() {
  if(preview) return {allowed:false,preview:true,reason:'演示模式 · Claude 启动已禁用',checks:[
    {id:'preview',ok:true,message:'桌宠交互在本机运行，不调用模型'},
    {id:'launch',ok:false,message:'开发与测试禁止启动 Claude'},
    {id:'gate',ok:false,message:'演示状态不代表实际网络已经通过检查'}]};
  try {
    const s=JSON.parse(fs.readFileSync(stateFile,'utf8').replace(/^\uFEFF/,''));
    const age=Date.now()-Date.parse(s.checkedAt);
    if(!s.monitor || !Number.isFinite(age)||age<0||age>3000)throw new Error('stale');
    return s;
  }catch{return {allowed:false,reason:'保护后台未就绪，启动保持锁定',checks:[]};}
}
function showPanel() {
  if(panel&&!panel.isDestroyed()){panel.show();panel.focus();return;}
  panel=new BrowserWindow({width:700,height:720,title:'书娘守护',backgroundColor:'#faf5ed',autoHideMenuBar:true,
    webPreferences:{preload:path.join(__dirname,'panel-preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
  panel.loadFile(path.join(__dirname,'panel.html'));
}
function permitted(event) {const u=event.sender.getURL();return u.startsWith('file://')&&(u.endsWith('/panel.html')||u.includes('/runtime/electron-helper/index.html'));}
ipcMain.handle('book:status',e=>permitted(e)?status():{allowed:false,reason:'Unknown viewer'});
ipcMain.handle('book:action',async(e,action)=>{
  if(!permitted(e))return {ok:false};
  if(action==='panel'){showPanel();return {ok:true};}
  if(action==='launch') {
    if(preview || !status().allowed)return {ok:false,message:preview?'演示模式不会启动 Claude':'检查尚未通过，Claude 已锁定'};
    const guard=path.join(process.env.ProgramFiles || 'C:\\Program Files','ShuniangGuard','ShuniangGuard.exe');
    if(!fs.existsSync(guard))return {ok:false,message:'未安装保护后台'};
    // Fixed executable and fixed arguments. No shell, user-provided paths or URL handlers.
    spawn(guard,['--launch'],{detached:false,windowsHide:true,stdio:'ignore'}).on('error',()=>{});
    return {ok:true,message:'正在进行启动前复检'};
  }
  if(action==='menu') {
    const win=BrowserWindow.fromWebContents(e.sender);
    Menu.buildFromTemplate([
      {label:'查看保护状态',click:showPanel},
      {label:preview?'演示模式 · 禁止启动 Claude':'安全启动 Claude',enabled:!preview&&status().allowed,click:()=>showPanel()},
      {type:'separator'},
      {label:'摸摸头',click:()=>e.sender.send('book:pet','pat')},
      {label:'一起读书',click:()=>e.sender.send('book:pet','read')},
      {label:'打个招呼',click:()=>e.sender.send('book:pet','wave')},
      {type:'separator'},
      {label:'退出桌宠（后台保护继续）',click:()=>app.quit()}
    ]).popup({window:win});return {ok:true};
  }
  return {ok:false};
});
// Disable every upstream "open website / AI settings" path. Ctrl-click opens our local panel only.
shell.openExternal = async()=>{showPanel();};
app.on('web-contents-created',(_e,w)=>{
  w.setWindowOpenHandler(()=>({action:'deny'}));
  w.on('will-navigate',(e,url)=>{if(!url.startsWith('file://'))e.preventDefault();});
});
app.whenReady().then(()=>{
  session.defaultSession.webRequest.onBeforeRequest((details,callback)=>{
    try {const u=new URL(details.url);callback({cancel:!['file:','data:','blob:','devtools:','dsh-pet:'].includes(u.protocol)&&!((u.protocol==='http:'||u.protocol==='ws:')&&u.hostname==='127.0.0.1')});}
    catch{callback({cancel:true});}
  });
});
const verifyIndex=process.argv.indexOf('--verify-ui');
if(verifyIndex>=0) {
  const out=path.resolve(process.argv[verifyIndex+1]);fs.mkdirSync(out,{recursive:true});
  const snapshot=async(w,file)=>{let last;for(let i=0;i<4;i++){try{await w.webContents.executeJavaScript('new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))');const shot=await w.webContents.capturePage();if(shot.isEmpty())throw new Error('Empty window capture');fs.writeFileSync(file,shot.toPNG());return;}catch(e){last=e;await new Promise(r=>setTimeout(r,700));}}throw last;};
  app.whenReady().then(()=>setTimeout(async()=>{
    try {
      const pets=BrowserWindow.getAllWindows().filter(w=>w.webContents.getURL().includes('electron-helper/index.html'));
      if(pets.length!==1)throw new Error('Expected one pet window');
      const w=pets[0];
      const before=await w.webContents.executeJavaScript('window.__bookDebug');
      if(!before?.painted)throw new Error('Sprite did not paint');
      w.webContents.send('book:pet','pat');
      await new Promise(r=>setTimeout(r,300));
      const after=await w.webContents.executeJavaScript('window.__bookDebug');
      await snapshot(w,path.join(out,'pet.png'));
      showPanel();await new Promise(r=>setTimeout(r,800));
      const panelState=await panel.webContents.executeJavaScript('({disabled:document.querySelector("#launch").disabled,title:document.querySelector("h1").textContent})');
      const launchResult=await panel.webContents.executeJavaScript('window.book.action("launch")');
      await snapshot(panel,path.join(out,'panel.png'));
      const layout=await panel.webContents.executeJavaScript(`(()=>{const ul=document.querySelector('#checks');while(ul.children.length<14)ul.append(ul.firstElementChild.cloneNode(true));const b=document.querySelector('#launch').getBoundingClientRect();return {checks:ul.children.length,buttonVisible:b.bottom<=innerHeight,checkListScrollable:ul.scrollHeight>ul.clientHeight,bodyFits:document.body.scrollHeight<=innerHeight+1}})()`);
      const ok=after.interaction==='pat'&&panelState.disabled&&launchResult.ok===false&&layout.buttonVisible&&layout.checkListScrollable&&layout.bodyFits;
      fs.writeFileSync(path.join(out,'ui.json'),JSON.stringify({ok,before,after,panelState,launchResult,layout,claudeLaunchAttempted:false},null,2));
      app.exit(ok?0:1);
    }catch(e){fs.writeFileSync(path.join(out,'error.txt'),String(e.stack));app.exit(1);}
  },7000));
}
import(require('node:url').pathToFileURL(path.join(base,'vendor/dsh-pet/lib/app.mjs')).href).catch(e=>{console.error(e);app.exit(1);});
