import fs from 'node:fs';
import path from 'node:path';
import {parse,parseDocument} from 'yaml';
import {DOMAINS,hash,nodeIdentity,inspectPolicy} from './policy.mjs';
import {apiGet,proxyTrace,collect} from './sensor.mjs';
import {regionAllowed,REGION_REVIEWED,REGION_EXPIRES,REGION_SOURCE} from './regions.mjs';
export const GROUP='SHUNIANG_CLAUDE';
export function proposedRules(text,node){
 const doc=parseDocument(text);if(doc.errors.length)throw Error('配置文件格式有误');
 const original=doc.toJS();if(!original.proxies?.some(p=>p.name===node))throw Error('找不到该节点，请重新扫描');
 const groups=original['proxy-groups']||[];const own=groups.find(g=>g.name===GROUP);
 if(own)throw Error('已存在书娘专属组；请先检查当前配置，不会覆盖已有组');
 const rules=[...DOMAINS.map(d=>`DOMAIN-SUFFIX,${d},${GROUP}`),`DOMAIN,www.cloudflare.com,${GROUP}`];
 doc.set('proxy-groups',[...groups,{name:GROUP,type:'select',proxies:[node]}]);
 doc.set('rules',[...rules,...(original.rules||[])]);
 const updated=doc.toString();const next=parse(updated);
 // Assert that every setting and existing rule/group survives exactly.
 const restored={...next,'proxy-groups':next['proxy-groups'].slice(0,-1),rules:next.rules.slice(5)};
 const normalized={...original,'proxy-groups':original['proxy-groups']||[],rules:original.rules||[]};
 if(hash(restored)!==hash(normalized))throw Error('配置保留校验失败，未写入');
 return updated;
}
export function buildPolicy(scan,node,exit){
 const raw=scan.disk.proxies?.find(p=>p.name===node);
 if(!raw||!exit.chainVerified||!regionAllowed(exit.country))throw Error('节点链路或出口地区未通过');
 const group=(scan.disk['proxy-groups']||[]).find(g=>g.proxies?.length===1&&g.proxies[0]===node&&g.type==='select'&&DOMAINS.every((d,i)=>scan.disk.rules?.[i]===`DOMAIN-SUFFIX,${d},${g.name}`));
 if(!group)throw Error('请先配置 Claude 专属分流');
 return {schema:1,enrolled:true,configPath:scan.file,controller:scan.controller,proxyPort:scan.disk['mixed-port'],node,group:group.name,nodeDigest:nodeIdentity(raw),allowedExitIps:[exit.ip],country:exit.country,regionReviewed:REGION_REVIEWED};
}
export async function scanConfig(file,controller,io={read:f=>fs.readFileSync(f,'utf8'),api:apiGet}){
 if(!/^[a-z]:[\\/]/i.test(file)||!/[.]ya?ml$/i.test(file))throw Error('请选择本机磁盘上的 YAML 配置文件');
 const text=io.read(file);const disk=parse(text);const secret=disk.secret||'';
 const [config,proxies,rules]=await Promise.all(['/configs','/proxies','/rules'].map(p=>io.api(controller,secret,p)));
 const allowedTypes=['Shadowsocks','ShadowsocksR','Snell','Trojan','Vmess','Vless','WireGuard','Hysteria','Hysteria2','Tuic','Socks5','Http','AnyTLS','SSH','Mieru','TrustTunnel'];
 const nodes=(disk.proxies||[]).filter(n=>allowedTypes.includes(proxies.proxies?.[n.name]?.type)).map(n=>({name:n.name,type:proxies.proxies[n.name].type}));
 if(!nodes.length)throw Error('未找到可核验的独立节点；本版不支持只有 provider 引用的配置');
 return {file,controller,text,disk,config,proxies,rules,nodes};
}
export function publicScan(s){return {nodes:s.nodes,mode:s.config.mode,tun:s.config.tun?.enable===true,port:s.disk['mixed-port'],ready:s.config.mode==='rule'&&s.config.tun?.enable===true,regionReviewed:REGION_REVIEWED,regionExpires:REGION_EXPIRES,regionSource:REGION_SOURCE};}
export async function probeSelected(s,node,io={api:apiGet,trace:proxyTrace}){
 return io.trace(s.disk['mixed-port'],async sourcePort=>{
  const all=await io.api(s.controller,s.disk.secret||'','/connections');
  return all.connections?.some(c=>Number(c.metadata?.sourcePort)===sourcePort&&c.metadata?.host==='www.cloudflare.com'&&['127.0.0.1','::ffff:127.0.0.1'].includes(c.metadata?.sourceIP)&&c.chains?.includes(node)&&!c.chains.some(x=>['DIRECT','REJECT'].includes(x)))===true;
 });
}
export async function applyRules(scan,node,backupDir,io){
 const disk=io||{read:f=>fs.readFileSync(f,'utf8'),write:(f,s)=>fs.writeFileSync(f,s),replace:(tmp,file)=>fs.renameSync(tmp,file),backup:(f,s)=>{fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,s,{flag:'wx'});},reload:async()=>{
  const response=await fetch(new URL('/configs',scan.controller),{method:'PUT',redirect:'error',headers:{'Content-Type':'application/json',...(scan.disk.secret?{Authorization:`Bearer ${scan.disk.secret}`}:{})},body:JSON.stringify({path:scan.file}),signal:AbortSignal.timeout(6000)});if(!response.ok)throw Error('核心未接受配置');
 }};
 if(disk.read(scan.file)!==scan.text)throw Error('配置已被其他程序改变，请重新扫描');
 const next=proposedRules(scan.text,node);const backup=path.join(backupDir,`clash-${Date.now()}.yaml`);disk.backup(backup,scan.text);
 const temp=scan.file+'.shuniang.tmp';disk.write(temp,next);disk.replace(temp,scan.file);
 try{await disk.reload();return {backup};}catch{
  if(disk.read(scan.file)!==next)throw Error('应用失败且配置被其他程序修改，未覆盖新内容；原配置备份已保留，请重新扫描');
  disk.write(temp,scan.text);disk.replace(temp,scan.file);try{await disk.reload();}catch{throw Error('文件已回滚，但实时核心状态未能确认；请检查 FlClash，保护不会放行');}
  throw Error('配置应用失败，已保留备份并回滚；请重新扫描');
 }
}
export async function validateSelection(scan,node,io){
 const exit=await probeSelected(scan,node,io);
 if(!regionAllowed(exit.country))return {policy:null,evidence:{allowed:false,reason:'出口地区不在已核验的服务地区范围内，或地区列表已过期',checks:[]},summary:{country:exit.country,ip:exit.ip,supported:false,node}};
 const policy=buildPolicy(scan,node,exit);
 const evidence=await collect(policy);
 return {policy,evidence,summary:{country:exit.country,ip:exit.ip,supported:regionAllowed(exit.country),node}};
}
