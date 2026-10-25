const $=s=>document.querySelector(s);let ready=false,preview=false,busy=false;
function message(s){$('#message').textContent=s;}
function controls(){for(const id of ['browse','scan'])$('#'+id).disabled=busy;$('#node').disabled=busy||!$('#node').value;$('#apply').disabled=busy||!$('#node').value;$('#validate').disabled=busy||!$('#node').value;$('#activate').disabled=busy||!ready||preview;}
function invalidate(){ready=false;$('#exit').textContent='配置已改变，请重新检查';$('#checks').replaceChildren();controls();}
async function call(action,data){if(busy)return;busy=true;controls();try{const r=await window.setup.call(action,data);if(!r.ok)throw Error(r.message);return r;}catch(e){ready=false;message(e.message);return null;}finally{busy=false;controls();}}
async function scan(){invalidate();const r=await call('scan',{file:$('#config').value,controller:$('#controller').value});if(!r)return;$('#node').replaceChildren();for(const n of r.scan.nodes){const o=document.createElement('option');o.value=n.name;o.textContent=n.name+' · '+n.type;$('#node').append(o);}message('节点已读取。'+(r.scan.ready?'请选择专属节点，再配置分流或检查已有配置。':'请先在 FlClash 开启规则模式与 TUN，再重新读取。'));controls();}
async function validate(){invalidate();message('正在通过选定链路核验出口与地区…');const r=await call('validate',{node:$('#node').value});if(!r)return;$('#exit').textContent=`出口地区：${r.summary.country||'未知'} · ${r.summary.supported?'在已核验名单内':'不支持或无法核验'}\n出口 IP：${r.summary.ip||'未知'}`;$('#exit').className=r.evidence.allowed?'ok':'bad';$('#checks').replaceChildren();for(const c of r.evidence.checks){const li=document.createElement('li');li.textContent=(c.ok?'✓ ':'× ')+c.message;li.className=c.ok?'ok':'bad';$('#checks').append(li);}ready=r.evidence.allowed;message(preview?'测试模式：系统安装与 Claude 启动均被禁用。':ready?'出口、地区与分流已通过。点击启用保护后确认 Windows 管理员提示。':r.evidence.reason);controls();}
$('#browse').onclick=async()=>{const r=await call('browse');if(r?.file){$('#config').value=r.file;invalidate();}};
$('#scan').onclick=scan;$('#node').onchange=invalidate;$('#config').oninput=invalidate;$('#controller').oninput=invalidate;
$('#apply').onclick=async()=>{ready=false;const node=$('#node').value;message('正在备份并应用专属规则…');const r=await call('apply',{node});if(r){message('原配置已备份到：'+r.backup+'\n请点击「检查已有配置 / 重新检查」核验出口。');}controls();};
$('#validate').onclick=validate;
$('#activate').onclick=async()=>{message('等待管理员确认与后台检查，可能需要约一分钟…');const r=await call('activate');if(r){message('系统保护已启用；已创建「Claude（受保护）」快捷方式。Claude 没有启动。');$('#finish').style.display='block';ready=false;controls();}};
$('#done').onclick=()=>window.setup.call('done',{pet:$('#pet').checked});
window.setup.call('init').then(r=>{$('#config').value=r.file;preview=r.preview;if(preview)message('配置向导测试模式：不写 VPN，不安装保护，不启动 Claude。');controls();});
