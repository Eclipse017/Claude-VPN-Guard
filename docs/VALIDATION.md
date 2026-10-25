# 验证记录 · 2026-10-25

本记录不包含用户节点、出口 IP、订阅、凭据或聊天数据。

| 项目 | 状态 | 证据 |
|---|---|---|
| 节点/分流策略与未知状态拒绝 | PASS | Node 内置测试框架 34 项；正例及错误节点、未知类型、DIRECT 覆盖、规则缺失、DNS/IPv6、出口不符、超时、切换竞态、过期状态等反例 |
| Windows 原生调试启动与脱离 | PASS | 只运行 ShuniangGuardProbe.exe，生成离线标记文件 |
| Windows IFEO 系统拦截与放行 | PASS | 管理员安装器针对离线替身分别验证拒绝和调试脱离，真实 Claude 未启动 |
| 本机实时节点、分流、出口 | PASS | 仅本机控制接口开启后，13 项检查全部通过；中立 HTTPS 探针代理链与批准基线匹配 |
| 其他应用的 VPN 保护 | PASS | 安装前后 AIAppVpnGuard 文件哈希、任务 XML、进程 PID 一致 |
| 透明桌宠、表情与面板 | PASS | Electron 实际窗口渲染、Canvas 像素截图、摸头状态切换 |
| 演示模式启动禁用 | PASS | 按钮禁用，IPC launch 请求返回拒绝 |
| 真实 Claude 客户端启动 | NOT_RUN | 用户明确禁止，未启动、未请求其服务 |
| 实际中断 VPN 测试 | NOT_RUN | 为保持其他受保护应用运行，不切断 TUN，不切换节点 |
| 目标域名实际连接 | NOT_RUN | 仅检查规则与中立 HTTPS 探针，不访问 Claude |

系统级 IFEO 迁移结果保存在安装机器的本地备份目录；只有 `install-result.json` 中 `status:PASS` 才表示安装与操作系统探针通过。没有该文件，不能宣称已安装。

这些验证不构成网络零泄漏、账号安全或所有 Windows/Claude 版本兼容性的保证。
