import {test} from 'node:test';
import assert from 'node:assert/strict';
import {inspectPolicy,nodeIdentity,DOMAINS,validEvidence} from '../src/policy.mjs';
import {collect,apiGet} from '../src/sensor.mjs';
function fixture(){
 const node={name:'approved',type:'ss',server:'example.invalid',port:443,password:'test-only'};
 const p={schema:1,enrolled:true,node:'approved',group:'CLAUDE',nodeDigest:nodeIdentity(node),proxyPort:7890,allowedExitIps:['192.0.2.1'],country:'TW',controller:'http://127.0.0.1:9090',configPath:'fixture'};
 const s={config:{mode:'rule',ipv6:false,'mixed-port':7890,tun:{enable:true}},proxies:{proxies:{CLAUDE:{now:'approved',all:['approved'],type:'Selector'},approved:{type:'Shadowsocks'}}},rules:{rules:DOMAINS.map(d=>({type:'DomainSuffix',payload:d,proxy:'CLAUDE'}))},disk:{mode:'rule',ipv6:false,'mixed-port':7890,dns:{enable:true,ipv6:false,'enhanced-mode':'fake-ip'},tun:{enable:true,'dns-hijack':['any:53','tcp://any:53']},proxies:[node],'proxy-groups':[{name:'CLAUDE',type:'select',proxies:['approved']}],rules:DOMAINS.map(d=>`DOMAIN-SUFFIX,${d},CLAUDE`)}};
 return {p,s};
}
test('complete approved configuration permits a neutral endpoint check',()=>{const {p,s}=fixture();assert.equal(inspectPolicy(p,s).allowed,true);});
const mutations={
 'not enrolled':(p,s)=>p.enrolled=false,
 'unknown runtime node type':(p,s)=>delete s.proxies.proxies.approved.type,
 'unknown runtime group type':(p,s)=>delete s.proxies.proxies.CLAUDE.type,
 'unapproved IP baseline':p=>p.allowedExitIps=[],
 'core direct mode':(p,s)=>s.config.mode='direct',
 'disk global mode':(p,s)=>s.disk.mode='global',
 'TUN off':(p,s)=>s.config.tun.enable=false,
 'IPv6 enabled':(p,s)=>s.config.ipv6=true,
 'DNS IPv6 unknown':(p,s)=>delete s.disk.dns.ipv6,
 'proxy port mismatch':(p,s)=>s.config['mixed-port']=8080,
 'node credentials changed':(p,s)=>s.disk.proxies[0].password='changed',
 'node server changed':(p,s)=>s.disk.proxies[0].server='changed.invalid',
 'wrong selected node':(p,s)=>s.proxies.proxies.CLAUDE.now='DIRECT',
 'fallback added':(p,s)=>s.proxies.proxies.CLAUDE.all.push('DIRECT'),
 'node is another selector':(p,s)=>s.proxies.proxies.approved.type='Selector',
 'subscription fallback':(p,s)=>s.disk['proxy-groups'][0].use=['unapproved'],
 'process DIRECT before domain':(p,s)=>s.disk.rules.unshift('PROCESS-NAME,Claude.exe,DIRECT'),
 'runtime DIRECT override':(p,s)=>s.rules.rules.unshift({type:'ProcessName',payload:'Claude.exe',proxy:'DIRECT'}),
 'disabled live rule':(p,s)=>s.rules.rules[0].extra={disabled:true},
 'missing domain':(p,s)=>s.rules.rules.pop(),
 'TCP DNS hijack absent':(p,s)=>s.disk.tun['dns-hijack'].pop(),
 'Fake-IP disabled':(p,s)=>s.disk.dns['enhanced-mode']='redir-host',
 'unknown live response':(p,s)=>s.config={},
};
for(const [name,mutate] of Object.entries(mutations))test('blocks '+name,()=>{const {p,s}=fixture();mutate(p,s);assert.equal(inspectPolicy(p,s).allowed,false);});
function ioFor(s,extras={}){return {readFileSync:()=>JSON.stringify(s.disk),apiGet:async(c,secret,path)=>({'/configs':s.config,'/rules':s.rules,'/proxies':s.proxies}[path]),proxyTrace:async()=>({ip:'192.0.2.1',country:'TW',chainVerified:true}),...extras};}
test('full collection passes only with approved egress',async()=>{const {p,s}=fixture();const v=await collect(p,ioFor(s));assert.equal(validEvidence(v),true);});
test('unreachable controller is fail closed',async()=>{const {p,s}=fixture();const v=await collect(p,ioFor(s,{apiGet:async()=>{throw Error('secret must not leak');}}));assert.equal(v.allowed,false);assert.ok(!JSON.stringify(v).includes('secret'));});
test('wrong exit blocks',async()=>{const {p,s}=fixture();assert.equal((await collect(p,ioFor(s,{proxyTrace:async()=>({ip:'192.0.2.2',country:'TW',chainVerified:true})}))).allowed,false);});
test('wrong country blocks',async()=>{const {p,s}=fixture();assert.equal((await collect(p,ioFor(s,{proxyTrace:async()=>({ip:'192.0.2.1',country:'XX',chainVerified:true})}))).allowed,false);});
test('approved baseline in an unsupported region still cannot pass',async()=>{const {p,s}=fixture();p.country='CN';const result=await collect(p,ioFor(s,{proxyTrace:async()=>({ip:'192.0.2.1',country:'CN',chainVerified:true})}));assert.equal(result.checks.find(c=>c.id==='exit').ok,true);assert.equal(result.checks.find(c=>c.id==='service-region').ok,false);assert.equal(result.allowed,false);});
test('unverified probe chain blocks even with correct IP',async()=>{const {p,s}=fixture();assert.equal((await collect(p,ioFor(s,{proxyTrace:async()=>({ip:'192.0.2.1',country:'TW',chainVerified:false})}))).allowed,false);});
test('probe connection must match source port, host and approved chain',async()=>{const {p,s}=fixture();const io=ioFor(s);const api=io.apiGet;io.apiGet=async(c,k,path)=>path==='/connections'?{connections:[{metadata:{sourcePort:'12345',sourceIP:'127.0.0.1',host:'www.cloudflare.com'},chains:['approved','ROUTE']}]}:api(c,k,path);io.proxyTrace=async(port,verify)=>{assert.equal(await verify(12345),true);assert.equal(await verify(11111),false);return {ip:'192.0.2.1',country:'TW',chainVerified:true};};assert.equal((await collect(p,io)).allowed,true);});
test('configuration changed during probe blocks',async()=>{const {p,s}=fixture();assert.equal((await collect(p,ioFor(s,{proxyTrace:async()=>{s.rules.rules[0].proxy='DIRECT';return {ip:'192.0.2.1',country:'TW',chainVerified:true};}}))).allowed,false);});
test('invalid configuration never calls the neutral probe',async()=>{const {p,s}=fixture();s.config.mode='direct';let called=false;await collect(p,ioFor(s,{proxyTrace:async()=>{called=true;}}));assert.equal(called,false);});
test('state freshness and completeness',async()=>{const {p,s}=fixture();const v=await collect(p,ioFor(s));for(const delta of [-13000,1000])assert.equal(validEvidence({...v,checkedAt:new Date(Date.now()+delta).toISOString()}),false);assert.equal(validEvidence({...v,checks:[]}),false);assert.equal(validEvidence({...v,checks:v.checks.map(()=>v.checks[0])}),false);assert.equal(validEvidence({allowed:true,checkedAt:new Date().toISOString()}),false);});
test('controller cannot send credentials to another host',async()=>{await assert.rejects(apiGet('http://example.invalid:9090','not-a-secret','/configs'));await assert.rejects(apiGet('https://127.0.0.1:9090','not-a-secret','/configs'));});
