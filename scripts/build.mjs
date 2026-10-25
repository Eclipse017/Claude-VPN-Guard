import {build} from 'esbuild';
import {readFileSync,writeFileSync,mkdirSync,copyFileSync,existsSync} from 'node:fs';
import {resolve,join} from 'node:path';
const root=resolve('.'),vendor=join(root,'vendor/dsh-pet');
const read=p=>readFileSync(join(vendor,p),'utf8');
const write=(p,s)=>writeFileSync(join(vendor,p),s);
const helper='runtime/electron-helper/';
// Deterministic, idempotent changes on the fixed upstream snapshot.
let main=read(helper+'main.js').replace("app.setName('dsh-pet-electron-helper')","app.setName('书娘守护')")
 .replace("path.join(app.getPath('appData'), 'dsh-pet')","process.env.BOOK_GUARD_PROFILE || path.join(app.getPath('appData'), 'ShuniangGuardPet')")
 .replace("'com.dsh.pet.app'","'local.shuniang.guard.pet'").replace("tray.setToolTip('dsh-pet 桌面宠物')","tray.setToolTip('书娘守护 · 退出桌宠不解除保护')");
write(helper+'main.js',main);
let preload=read(helper+'preload.js');
if(!preload.includes("exposeInMainWorld('petGuard'"))preload+="\ncontextBridge.exposeInMainWorld('petGuard',{status:()=>ipcRenderer.invoke('book:status'),action:a=>ipcRenderer.invoke('book:action',a),onPet:cb=>ipcRenderer.on('book:pet',(_e,a)=>cb(a))});\n";
write(helper+'preload.js',preload);
let html=read(helper+'index.html');if(!html.includes('book-skin.js'))html=html.replace('<script src="./renderer.js">','<script src="./book-skin.js"></script>\n    <script src="./renderer.js">');write(helper+'index.html',html);
copyFileSync(join(root,'src/skin.js'),join(vendor,helper,'book-skin.js'));
copyFileSync(join(root,'assets/shuniang-atlas.png'),join(vendor,helper,'shuniang-atlas.png'));
const config={notificationsEnabled:false,clickSoundEnabled:false,chatMemoryRounds:0,whisperImageEnabled:false,chatImageEnabled:false,
 pets:[{id:'main',name:'书娘',size:390,display:'desktop',balanceEnabled:false,whisperEnabled:false,workStatusEnabled:false,fixedEnabled:true,trayEnabled:true,position:{corner:'bottom-right',marginX:45,marginY:65}}],
 font:{family:'yahei',size:16},animations:{idle:['idle'],turn:[],drag:['wave'],clicks:['wave'],moves:{default:{minDist:80,maxDist:150,margin:20,leadSec:2,tailSec:2},actions:[]},categories:[],events:{balance:[],whisper:[],workStatus:[]}},animationWeights:{idle:100,turn:0,move:0},eventsRefreshSec:{balance:86400,whisper:86400}};
write('assets/config.jsonc',JSON.stringify(config,null,2));
mkdirSync(join(vendor,'lib'),{recursive:true});
const alias={'@deepseek-ai/dsh-home-paths':join(vendor,'src/standalone/shims/dsh-home-paths.ts'),'@deepseek-ai/dsh-credentials':join(vendor,'src/standalone/shims/dsh-credentials.ts'),'@deepseek-ai/dsh-llm':join(vendor,'src/standalone/shims/dsh-llm.ts')};
const offline={name:'offline-ai',setup(b){b.onResolve({filter:/ai-transport$/},()=>({path:join(root,'src/offline-ai.ts')}));}};
await build({entryPoints:[join(vendor,'src/app/main.ts')],bundle:true,platform:'node',format:'esm',target:'node22',outfile:join(vendor,'lib/app.mjs'),external:['electron','@electron/get','@electron-internal/extract-zip'],alias,plugins:[offline]});
await build({entryPoints:[join(vendor,'src/shared/index.ts')],bundle:true,platform:'browser',format:'iife',globalName:'PetShared',target:'chrome130',outfile:join(vendor,helper,'shared-core.js')});
mkdirSync('dist/guard',{recursive:true});
await build({entryPoints:['src/sensor.mjs'],bundle:true,platform:'node',format:'cjs',target:'node22',outfile:'dist/guard/sensor.cjs'});
await build({entryPoints:['src/setup.mjs'],bundle:true,platform:'node',format:'cjs',target:'node22',outfile:'dist/setup.cjs'});
// Bundling changes import.meta.url; an explicit generated entry is required for the executable sensor.
let sensor=readFileSync('dist/guard/sensor.cjs','utf8');sensor+='\nmain().catch(()=>{process.exitCode=2;});\n';writeFileSync('dist/guard/sensor.cjs',sensor);
console.log('Built dsh-pet standalone app, original sprite renderer and offline model stub.');
