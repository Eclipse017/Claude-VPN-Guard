import { createHash } from 'node:crypto';
export const DOMAINS = ['anthropic.com', 'claude.ai', 'claude.com', 'claudeusercontent.com'];
export const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
export function nodeIdentity(node) {
  if (!node || typeof node !== 'object') return '';
  // Includes all transport and credential fields. Only the digest leaves the sensor.
  return hash(node);
}
export function inspectPolicy(policy, snapshot) {
  const checks = [];
  const check = (id, ok, message) => checks.push({id, ok: ok === true, message});
  const {config, proxies, rules, disk} = snapshot;
  check('policy', policy.schema === 1 && policy.enrolled === true &&
    typeof policy.nodeDigest === 'string' && /^[a-f0-9]{64}$/.test(policy.nodeDigest) &&
    Array.isArray(policy.allowedExitIps) && policy.allowedExitIps.length > 0,
    '本机批准的节点与出口基线');
  check('mode', config?.mode === 'rule' && disk?.mode === 'rule', '规则模式必须启用');
  check('tun', config?.tun?.enable === true && disk?.tun?.enable === true, '实时 TUN 必须启用');
  check('ipv6', config?.ipv6 === false && disk?.ipv6 === false && disk?.dns?.ipv6 === false,
    'IPv6 关闭（本版尚未验证 IPv6 分流）');
  check('port', config?.['mixed-port'] === policy.proxyPort && disk?.['mixed-port'] === policy.proxyPort,
    '实时代理端口与检查端口一致');
  const node = disk?.proxies?.find(p => p.name === policy.node);
  check('node-identity', !!node && nodeIdentity(node) === policy.nodeDigest, '节点传输配置与批准基线一致');
  const group = proxies?.proxies?.[policy.group];
  const actual = proxies?.proxies?.[policy.node];
  const leafTypes = ['Shadowsocks','ShadowsocksR','Snell','Trojan','Vmess','Vless','WireGuard','Hysteria','Hysteria2','Tuic','Socks5','Http','AnyTLS','SSH','Mieru','TrustTunnel'];
  check('selection', !!group && group.type === 'Selector' && group.now === policy.node && Array.isArray(group.all) &&
    group.all.length === 1 && group.all[0] === policy.node && !!actual &&
    leafTypes.includes(actual.type),
    'Claude 专用策略组仅包含批准的单一节点');
  const diskGroup = disk?.['proxy-groups']?.find(p => p.name === policy.group);
  check('group', !!diskGroup && diskGroup.type === 'select' && !diskGroup.use?.length &&
    diskGroup.proxies?.length === 1 && diskGroup.proxies[0] === policy.node,
    '专用组禁止自动回落到直连或其他节点');
  // Require these four protective suffix rules at the very top, before ANY process/IP/rule-set override.
  const live = rules?.rules;
  const expected = DOMAINS.map(domain => `DOMAIN-SUFFIX,${domain},${policy.group}`);
  check('disk-rules', Array.isArray(disk?.rules) &&
    expected.every((rule, i) => disk.rules[i] === rule), '四条 Claude 域名保护规则位于配置最前');
  check('live-rules', Array.isArray(live) && DOMAINS.every((domain, i) => {
    const r = live[i];
    return r?.type === 'DomainSuffix' && r.payload === domain && r.proxy === policy.group && r.extra?.disabled !== true;
  }), '核心当前生效的四条规则与保护配置一致');
  check('dns', disk?.dns?.enable === true && disk.dns['enhanced-mode'] === 'fake-ip' &&
    disk.tun?.['dns-hijack']?.includes('any:53') && disk.tun?.['dns-hijack']?.includes('tcp://any:53'),
    'Fake-IP 与 TCP/UDP DNS 劫持启用');
  return {allowed: checks.every(c => c.ok), checks};
}
export function validEvidence(value, now = Date.now(), ttl = 12000) {
  const age = now - Date.parse(value?.checkedAt);
  const ids=['policy','mode','tun','ipv6','port','node-identity','selection','group','disk-rules','live-rules','dns','exit','service-region','stable'];
  return value?.schema === 1 && value?.allowed === true && value?.checks?.length === ids.length &&
    ids.every(id=>value.checks.filter(c=>c.id===id&&c.ok===true).length===1) && Number.isFinite(age) && age >= 0 && age < ttl;
}
