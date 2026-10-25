const {app, BrowserWindow, ipcMain, Menu, session, shell,dialog} = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const {spawn} = require('node:child_process');
const base = path.resolve(__dirname, '..');
const verifyWizard=process.argv.includes('--verify-wizard');
const setupOnly=process.argv.includes('--setup')||verifyWizard;
const preview = process.argv.includes('--preview') || process.argv.includes('--verify-ui')||verifyWizard;
const profile = path.join(app.getPath('userData'), preview?'ShuniangPreview':'ShuniangGuardPet');
process.env.DSH_HOME = profile;
process.env.BOOK_GUARD_PROFILE = profile;
app.setPath('userData',profile);
const stateFile = path.join(process.env.ProgramData || 'C:\\ProgramData','ShuniangGuard','status.json');
let panel,wizard,scanState,approvedPolicy,setupBusy=false,petLoaded=false;
function loadPet(){if(petLoaded)return;petLoaded=true;import(require('node:url').pathToFileURL(path.join(base,'vendor/dsh-pet/lib/app.mjs')).href).catch(e=>{console.error(e);app.exit(1);});}
function showWizard(){if(wizard&&!wizard.isDestroyed()){wizard.show();wizard.focus();return;}
 wizard=new BrowserWindow({width:830,height:880,title:'书娘守护 · 配置向导',backgroundColor:'#faf5ed',autoHideMenuBar:true,webPreferences:{preload:path.join(__dirname,'wizard-preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true}});wizard.loadFile(path.join(__dirname,'wizard.html'));}
ipcMain.handle('setup:call',async(e,action,data={})=>{
 if(!wizard||e.sender!==wizard.webContents)return {ok:false,message:'未知配置窗口'};
 if(action==='init')return {ok:true,preview,file:verifyWizard?'C:\\Demo\\FlClash\\config.yaml':path.join(app.getPath('appData'),'com.follow','clash','config.yaml')};
 if(setupBusy)return {ok:false,message:'前一步尚未完成，请稍候'};
 setupBusy=true;
 try {
  if(action==='done'){if(data.pet)loadPet();else app.quit();wizard.close();return {ok:true};}
  if(action==='browse'){const r=await dialog.showOpenDialog(wizard,{filters:[{name:'YAML 配置',extensions:['yaml','yml']}],properties:['openFile']});return {ok:true,file:r.filePaths[0]};}
  if(verifyWizard){
   if(action==='scan')return {ok:true,scan:{nodes:[{name:'测试不支持地区',type:'CN'},{name:'测试支持地区',type:'US'}],ready:true}};
   if(action==='apply')return {ok:true,backup:'演示备份（未写文件）'};
   if(action==='validate'){const ok=data.node==='测试支持地区';return {ok:true,summary:{country:ok?'US':'CN',supported:ok,ip:'192.0.2.1'},evidence:{allowed:ok,reason:ok?'通过':'地区不支持',checks:[{ok,message:ok?'模拟地区通过':'模拟不支持地区：锁定'}]}};}
   return {ok:false,message:'测试模式禁止系统安装与 Claude 启动'};
  }
  if(preview)throw Error('演示模式不修改 VPN 或安装保护；请使用配置向导入口');
  const setup=require(path.join(base,'dist/setup.cjs'));
  if(action==='scan'){approvedPolicy=null;scanState=null;scanState=await setup.scanConfig(data.file,data.controller);return {ok:true,scan:setup.publicScan(scanState)};}
  if(action==='apply'){
   approvedPolicy=null;if(!scanState)throw Error('请先读取节点');
   const r=await setup.applyRules(scanState,data.node,path.join(profile,'private-backups'));
   scanState=await setup.scanConfig(scanState.file,scanState.controller);return {ok:true,backup:r.backup};
  }
  if(action==='validate'){
   approvedPolicy=null;if(!scanState)throw Error('请先读取节点');
   scanState=await setup.scanConfig(scanState.file,scanState.controller);const r=await setup.validateSelection(scanState,data.node);
   if(r.evidence.allowed)approvedPolicy=r.policy;return {ok:true,evidence:r.evidence,summary:r.summary};
  }
  if(action==='activate'){
   if(preview||!approvedPolicy)throw Error('必须先通过出口、地区和分流检查');
   const payload=path.resolve(base,'..'),host=path.join(payload,'ShuniangSetupHost.exe');if(!fs.existsSync(host))throw Error('请使用完整 Windows 安装包');
   fs.mkdirSync(profile,{recursive:true});const policyFile=path.join(profile,'pending-policy.json'),resultFile=path.join(profile,'install-result-'+Date.now()+'.json');fs.writeFileSync(policyFile,JSON.stringify(approvedPolicy));
   const code=await new Promise((resolve,reject)=>{const p=spawn(host,['--elevate-install',policyFile,resultFile],{windowsHide:true,stdio:'ignore'});p.once('error',reject);p.once('exit',resolve);});
   const result=fs.existsSync(resultFile)?JSON.parse(fs.readFileSync(resultFile,'utf8').replace(/^\uFEFF/,'')):{message:'管理员确认被取消，系统保护未启用'};
   if(code!==0||result.status!=='PASS')throw Error(result.message||'保护安装失败');
   const link=path.join(app.getPath('desktop'),'Claude（受保护）.lnk');
   if(!fs.existsSync(link))shell.writeShortcutLink(link,{target:'C:\\Program Files\\ShuniangGuard\\ShuniangGuard.exe',args:'--launch',description:'启动前检查网络与地区；安装器不启动 Claude'});
   return {ok:true};
  }
  throw Error('未知配置操作');
 }catch(error){approvedPolicy=null;return {ok:false,message:error.message};}finally{setupBusy=false;}
});
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
  if(action==='setup'){showWizard();return {ok:true};}
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
      {label:'中文配置向导',click:showWizard},
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
      const layout=await panel.webContents.executeJavaScript(`(()=>{const ul=document.querySelector('#checks');while(ul.children.length<15)ul.append(ul.firstElementChild.cloneNode(true));const b=document.querySelector('#launch').getBoundingClientRect();return {checks:ul.children.length,buttonVisible:b.bottom<=innerHeight,checkListScrollable:ul.scrollHeight>ul.clientHeight,bodyFits:document.body.scrollHeight<=innerHeight+1}})()`);
      const calm=await w.webContents.executeJavaScript('(async()=>{const s=sprites[0];const before={...s.pos};s.startThrow(s.pos.x,s.pos.y,5000,-5000);await new Promise(r=>setTimeout(r,600));return {throwDisabled:!s.throwState,autoMoveDisabled:!s.pendingMove,positionStable:s.pos.x===before.x&&s.pos.y===before.y}})()');
      const ok=calm.throwDisabled&&calm.autoMoveDisabled&&calm.positionStable&&after.interaction==='pat'&&panelState.disabled&&launchResult.ok===false&&layout.buttonVisible&&layout.checkListScrollable&&layout.bodyFits;
      fs.writeFileSync(path.join(out,'ui.json'),JSON.stringify({ok,before,after,calm,panelState,launchResult,layout,claudeLaunchAttempted:false},null,2));
      app.exit(ok?0:1);
    }catch(e){fs.writeFileSync(path.join(out,'error.txt'),String(e.stack));app.exit(1);}
  },7000));
}
if(setupOnly)app.whenReady().then(showWizard);else loadPet();
if(setupOnly)app.on('window-all-closed',()=>{if(!petLoaded)app.quit();});
if(verifyWizard)app.whenReady().then(()=>setTimeout(async()=>{
 const out=path.resolve(process.argv[process.argv.indexOf('--verify-wizard')+1]);fs.mkdirSync(out,{recursive:true});
 try {
  const run=s=>wizard.webContents.executeJavaScript(s);
  await run('scan()');await run('validate()');const denied=await run('document.querySelector("#activate").disabled && document.querySelector("#exit").textContent.includes("CN")');
  await run('document.querySelector("#node").selectedIndex=1;validate()');const testBlocked=await run('document.querySelector("#activate").disabled');
  const install=await run('window.setup.call("activate")');const layout=await run('({width:document.body.scrollWidth<=innerWidth,title:document.querySelector("h1").textContent})');
  await run('document.querySelector("#node").selectedIndex=0;validate()');await new Promise(r=>setTimeout(r,500));const shot=await wizard.webContents.capturePage();fs.writeFileSync(path.join(out,'wizard.png'),shot.toPNG());
  await run('document.querySelector("#exit").scrollIntoView({block:"center"})');await new Promise(r=>setTimeout(r,300));fs.writeFileSync(path.join(out,'wizard-region.png'),(await wizard.webContents.capturePage()).toPNG());
  const ok=denied&&testBlocked&&!install.ok&&layout.width;fs.writeFileSync(path.join(out,'wizard.json'),JSON.stringify({ok,denied,testBlocked,install,layout,systemChanged:false,claudeStarted:false},null,2));app.exit(ok?0:1);
 }catch(e){fs.writeFileSync(path.join(out,'error.txt'),e.stack);app.exit(1);}
},2000));
