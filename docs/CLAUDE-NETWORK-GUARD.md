# Claude 应用级网络保护

本组件独立于启动保护和桌宠。使用 Windows 自带 WFP 的 ALE_AUTH_CONNECT_V4 / V6 层，新增只属于 ClaudeNetworkGuard 的持久化阻止规则。不安装驱动，不更改既有 Defender 规则、系统默认策略、FlClash 分流或其他应用的启动保护。

## 保护范围

- Claude 包身份 `Claude_pzs8sxrjxfjjc`，以及已安装包目录内的原生 EXE 路径。路径规则补充未携带包身份的程序启动方式。
- 保留本机 loopback 通信，包括 `127.0.0.1:7890` 代理和本机 IPC。
- 非 loopback 连接必须使用名称 `FlClash`、描述 `Meta Tunnel` 的已启用网卡所对应的 LUID。其他接口和无法确定接口的连接被阻止。
- IPv4 / IPv6 均覆盖；ALE 规则不按协议放宽，适用于 TCP、UDP 等该层识别的连接。
- 规则在辅助程序退出后保留。WFP provider 关联自动启动的 ClaudeNetworkGuard 服务，确保 BFE 重启时按自动服务身份加载。服务每 30 秒核对一次网卡身份及包目录，原子替换需要更新的规则；没有变化则不改规则。找不到 TUN 时关闭非 loopback 出站，保留本地代理。
- 新网卡不需要逐个加入黑名单。TUN 重建后，直接走 TUN 的 Claude 连接可能在下一次核对前暂时被阻止。

## 保留与限制

- 不修改 Claude / ShuniangGuard 的 IFEO，不停止现有后台，不更改代理策略组或 DNS。
- 本组件阻止应用绕过 TUN 的直接联网；代理核心自身如何分流仍由 FlClash 规则和 ShuniangGuard 检查负责。本地代理不能被当作所有流量出口都正确的证明。
- Claude 直接经以太网、Wi-Fi、Tailscale 访问局域网也会被阻止；其他应用的这些连接不受本组件影响。
- Cowork 虚拟机内转发流量、外部通用解释器、浏览器、独立 CLI 和其他设备不属于完整覆盖保证。包内 cowork-svc.exe 的进程连接受路径规则保护，不等于整个虚拟机网络已被验证。
- 包身份规则为跨版本补充；新版本的真实客户端兼容性和所有进程的包身份继承仍需实际验证。不会为测试而启动 Claude。
- 本地管理员能更改规则；不提供账号安全或绝对零泄漏保证。重启、真实 VPN 中断和真实 Claude 会话未做破坏性验收。

## 安装与回滚

先执行管理员只读审计及备份，使用独立 ClaudeNetworkProbe.exe 验证，再运行 `Install-ClaudeNetworkGuard.ps1 -AuditDirectory <已验收目录>`。安装器拒绝覆盖已有安装。

运行目录：`C:\Program Files\ClaudeNetworkGuard`。
状态：`C:\ProgramData\ClaudeNetworkGuard\status.json`。
服务：`ClaudeNetworkGuard`，LocalSystem，自动启动并依赖 BFE。

回滚请在管理员 PowerShell 7 执行：

```powershell
& 'C:\Program Files\ClaudeNetworkGuard\Remove-ClaudeNetworkGuard.ps1'
```

回滚仅停用并移除本组件服务和它拥有的 WFP provider / sublayer / filters；不导入整机防火墙备份，不改其他规则。保留程序和证据。完整 `.wfw` 备份仅供灾难恢复，不应当作日常回滚方式。

## 可重复验证

探针访问固定中立地址，不使用 Claude 账号或服务。对同一独立探针先做对照、再应用同构 WFP 规则：验证 TUN TCP、本地代理 CONNECT + TLS 1.2 HTTPS、物理接口 TCP / UDP、IPv6 链路本地 UDP。额外仅为探针指定不存在的可用接口，验证拒绝出站；实际 VPN 网卡、路由、核心进程始终保持运行。最后移除探针规则并复测恢复。

UDP 的 socket 接受发送不表示远端收到，Windows 可以在随后异步丢弃。TCP 阻断要求 WSAEACCES (10013)；UDP 阻断要求 WFP CLASSIFY_DROP 事件中包含本轮新建规则的 filterId 和 BLOCK 动作，分别核对 IPv4 / IPv6，不能把发送成功或超时当作放行/阻断证明。IPv6 链路本地测试不等于公网 IPv6 端到端验证。测试只读取已有 WFP 事件缓冲，不改变全局诊断开关。

实现依据：
- [Microsoft：ALE layers](https://learn.microsoft.com/en-us/windows/win32/fwp/ale-layers)
- [Microsoft：filtering conditions](https://learn.microsoft.com/en-us/windows/win32/fwp/filtering-condition-identifiers-)
- [Microsoft：ALE reauthorization](https://learn.microsoft.com/en-us/windows/win32/fwp/ale-re-authorization)
- 结构与常量按本机 Windows SDK 10.0.19041.0 的 fwpmu.h / fwpmtypes.h / fwptypes.h 核对。
