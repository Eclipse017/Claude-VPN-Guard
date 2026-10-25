# Claude 网络保护实机验收

验收日期：2026-10-25。结果：**PASS（下述范围）**。未启动 Claude，未停止或切换正在使用的 VPN。使用独立 `ClaudeNetworkProbe.exe`，探针规则与生产规则使用不同的 provider 和 sublayer。

## 已安装状态

- Windows 原生服务 `ClaudeNetworkGuard` 正常运行，自动启动，依赖 BFE。
- 36 条持久化 WFP BLOCK 规则：当前 Claude 包内 8 个 EXE 路径和一个包身份，各覆盖 IPv4 / IPv6 的非批准接口及未知接口；无禁用规则。
- provider 关联自动启动服务。停止网络规则管理服务后，36 条规则仍保留且未禁用；之后服务已恢复运行。这不等同于 Windows 重启测试。
- ShuniangGuard 启动门禁已接入网络层状态，实机读回 14 项检查全部通过。
- 安装前后的 721 条既有 Defender 防火墙规则快照一致。FlClash 配置哈希、FlClash / 核心 / 其他应用保护进程 PID 保持一致。
- 30 份备份文件的 SHA-256 复核一致。并行授权的书娘程序更新已单独对齐基线，未把该更新错误回退。

## 探针证据

| 场景 | 观测结果 |
| --- | --- |
| 对照：正常 TUN TCP / 指定物理接口 TCP | 均可连接中立测试目标 |
| 规则生效：正常 TUN TCP | 可连接 |
| 规则生效：本地代理 CONNECT + HTTPS | TLS 1.2 证书校验及中立 HTTP 请求成功 |
| 规则生效：指定物理接口 TCP | WSAEACCES 10013，拒绝连接 |
| 规则生效：指定物理接口 IPv4 UDP | 本轮规则的 WFP CLASSIFY_DROP / BLOCK 证据匹配 |
| 规则生效：IPv6 链路本地 UDP | 本轮规则的 WFP CLASSIFY_DROP / BLOCK 证据匹配 |
| 仅探针使用不存在的批准接口 | 非 loopback TCP 拒绝；本地代理 HTTPS 仍成功 |
| 重复应用相同探针策略 | Changed=false，未重复创建规则 |
| 移除探针规则 | 所有探针规则移除，TCP 恢复 |

UDP 对照及受保护 socket 均可能返回 SEND_ACCEPTED；验收使用内核阻止事件及本轮 filterId，不以发送返回值或超时推断实际放行。探针记录含 14 项对照、连接及内核事件结果。

## 交付复核

安装的网络保护程序 SHA-256：

`669B00419F69C26446C0FADB2D5CB771387D3C3C7DE4497B379DF1A93EED01A6`

独立探针 SHA-256：

`82ED6EEDCD2ACBB6DDACB5B262B1C80ECC187D09225A003C15AB7246B92997F8`

回滚脚本已同步到安装目录，并验证哈希。它先将网络状态改为非 PASS，再移除本组件，避免启动门禁暂用旧的通过状态。生产回滚未执行。

原始备份、系统配置、WFP 导出及验收日志保存在本机忽略目录，不纳入公开发布。早期失败尝试与最终通过记录同时保留；最终汇总修正了 netsh WFP 导出含多个顶层元素导致的报告解析错误，原始导出未改写。

## NOT_RUN 与范围限制

真实 Claude 会话、真实 VPN 中断、Windows 重启、Cowork 虚拟机转发、公网 IPv6 端到端和生产回滚执行均未测试。IPv6 链路本地内核阻断证据不能代替公网 IPv6 验证。

本组件保留 loopback，本地代理核心的后续分流仍由 FlClash 和启动门禁检查负责。Claude 直接经物理接口或 Tailscale 访问局域网也会被阻止；其他应用不受这些应用范围规则影响。完整保护范围及安装步骤见 [组件说明](CLAUDE-NETWORK-GUARD.md)。
