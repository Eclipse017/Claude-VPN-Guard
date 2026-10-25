import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import http from 'node:http';
import tls from 'node:tls';
import { parse } from 'yaml';
import { inspectPolicy, hash } from './policy.mjs';
import {regionAllowed} from './regions.mjs';

const PROBE_HOST = 'www.cloudflare.com';
const PROBE_PATH = '/cdn-cgi/trace';
export async function apiGet(controller, secret, path) {
  const base = new URL(controller);
  if (base.protocol !== 'http:' || base.hostname !== '127.0.0.1' || base.username || base.password || base.pathname !== '/')
    throw new Error('控制接口必须为本机 127.0.0.1 HTTP 地址');
  const res = await fetch(new URL(path, base), {headers: secret ? {Authorization: `Bearer ${secret}`} : {},
    redirect: 'error', signal: AbortSignal.timeout(2200)});
  if (!res.ok) throw new Error('控制接口未就绪');
  const text = await res.text();
  if (text.length > 4_000_000) throw new Error('控制接口响应过大');
  return JSON.parse(text);
}
// Only this neutral, hard-coded HTTPS destination is permitted. Never contacts Anthropic/Claude.
export function proxyTrace(port, verifyChain = async () => false) {
  return new Promise((resolvePromise, reject) => {
    let conn, secure, done = false;
    const finish = (err, result) => { if (done) return; done = true; clearTimeout(timer); req.destroy(); secure?.destroy(); conn?.destroy(); err ? reject(err) : resolvePromise(result); };
    const timer = setTimeout(() => finish(new Error('中立站点出口检查超时')), 5500);
    const req = http.request({host:'127.0.0.1', port, method:'CONNECT', path:`${PROBE_HOST}:443`});
    req.on('error', () => finish(new Error('本机代理连接失败')));
    req.on('connect', (res, socket, head) => {
      conn = socket;
      if (res.statusCode !== 200 || head.length) return finish(new Error('代理隧道失败'));
      secure = tls.connect({socket, servername:PROBE_HOST, rejectUnauthorized:true}, async () => {
        try {
          if (!await verifyChain(socket.localPort)) return finish(new Error('中立探针未经过批准的代理节点'));
          if (!done) secure.write(`GET ${PROBE_PATH} HTTP/1.1\r\nHost: ${PROBE_HOST}\r\nConnection: close\r\nAccept-Encoding: identity\r\n\r\n`);
        } catch { finish(new Error('无法验证探针流量链')); }
      });
      let text = '';
      secure.on('data', b => { text += b.toString('utf8'); if (text.length > 32768) finish(new Error('出口响应过大')); });
      secure.on('error', () => finish(new Error('出口 TLS 校验失败')));
      secure.on('end', () => {
        if (!/^HTTP\/1\.[01] 200\b/.test(text)) return finish(new Error('出口响应无效'));
        const ip = text.match(/(?:^|\n)ip=([^\r\n]+)/)?.[1];
        const country = text.match(/(?:^|\n)loc=([A-Z]{2})/)?.[1];
        if (!ip || !country) return finish(new Error('缺少出口证据'));
        finish(null, {ip, country, chainVerified:true});
      });
    });
    req.end();
  });
}
export async function collect(policy, io = {apiGet, proxyTrace, readFileSync}) {
  const start = Date.now();
  let checks = [];
  try {
    const diskText = io.readFileSync(policy.configPath, 'utf8');
    const disk = parse(diskText);
    const controller = policy.controller;
    const secret = disk.secret || '';
    const [config, proxies, rules] = await Promise.all(['/configs','/proxies','/rules'].map(p => io.apiGet(controller, secret, p)));
    const snapshot = {config, proxies, rules, disk};
    const inspected = inspectPolicy(policy, snapshot);
    checks = inspected.checks;
    if (!inspected.allowed) return result(false, checks, start);
    const exit = await io.proxyTrace(policy.proxyPort, async sourcePort => {
      const all = await io.apiGet(controller, secret, '/connections');
      const c = all.connections?.find(c => Number(c.metadata?.sourcePort) === sourcePort &&
        c.metadata?.host === PROBE_HOST && ['127.0.0.1','::ffff:127.0.0.1'].includes(c.metadata?.sourceIP));
      return !!c && c.chains?.includes(policy.node) && !c.chains.some(p => ['DIRECT','REJECT'].includes(p));
    });
    const exitMatches = exit.chainVerified === true && policy.allowedExitIps.includes(exit.ip) && exit.country === policy.country;
    checks.push({id:'exit', ok: exitMatches,
      message: exitMatches ? '中立 HTTPS 站点出口符合批准基线' : '出口或代理链与批准基线不一致'});
    checks.push({id:'service-region',ok:regionAllowed(exit.country),message:regionAllowed(exit.country)?'出口地区在已核验的服务地区列表内':'出口地区不支持、无法识别或地区列表已过期'});
    // Check the active state a second time, closing the profile-switch race during a slow probe.
    const [afterConfig, afterProxies, afterRules] = await Promise.all(['/configs','/proxies','/rules'].map(p => io.apiGet(controller, secret, p)));
    const afterDisk = io.readFileSync(policy.configPath, 'utf8');
    const stable = diskText === afterDisk &&
      inspectPolicy(policy, {config:afterConfig, proxies:afterProxies, rules:afterRules, disk:parse(afterDisk)}).allowed &&
      hash(proxies.proxies[policy.node]) === hash(afterProxies.proxies[policy.node]);
    checks.push({id:'stable', ok:stable, message:'检查期间节点和分流配置未发生变化'});
    return result(checks.every(c=>c.ok), checks, start);
  } catch {
    checks.push({id:'unavailable', ok:false, message:'无法验证实时节点／分流：请开启本机控制接口并检查配置'});
    return result(false, checks, start);
  }
}
function result(allowed, checks, start) {
  return {schema:1, allowed, checkedAt:new Date().toISOString(), durationMs:Date.now()-start,
    reason:allowed?'节点、分流和出口检查通过':checks.find(c=>!c.ok)?.message || '检查失败', checks};
}
export function publish(file, value) {
  mkdirSync(dirname(file), {recursive:true});
  const tmp = `${file}.${process.pid}.tmp`;
  writeFileSync(tmp, JSON.stringify(value));
  renameSync(tmp, file);
}
async function main() {
  const args = process.argv.slice(2);
  const get = key => args[args.indexOf(key)+1];
  const policyPath = get('--policy');
  if (!args.includes('--policy') || !policyPath) throw new Error('必须指定本机策略文件');
  const once = args.includes('--once');
  do {
    let value;
    try { value = await collect(JSON.parse(readFileSync(policyPath,'utf8'))); }
    catch { value = result(false,[{id:'policy',ok:false,message:'本机策略不可读取'}],Date.now()); }
    if (args.includes('--output')) publish(get('--output'), value);
    if (once) { process.stdout.write(JSON.stringify(value)); process.exitCode = value.allowed?0:2; break; }
    await new Promise(r=>setTimeout(r,2000));
  } while (true);
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main().catch(()=>{process.exitCode=2;});
