# 来源与素材

本项目基于 [PC2005-cloud/dsh-pet](https://github.com/PC2005-cloud/dsh-pet) 的独立应用模式开发。
固定上游版本：`dfc03961bdb4d26898838cb72c9c2ac09699b1e2`（包源码版本 0.3.8）。
上游代码的 MIT 声明保存在 `vendor/dsh-pet/LICENSE`。独立宿主、透明窗口、拖拽/抛掷物理、显示器适配和配置代码来自该项目；本项目加入独立数据目录、本地 PNG 表情渲染器、保护面板和 Claude 专用门禁。

不分发上游鲸鱼娘视频、人物图像、音效或字体。`assets/shuniang-atlas.png` 为本项目用内置 imagegen 生成的原创角色六表情图集，未经人工逐帧手绘；制作提示词保存在 `assets/generation.json`。运行时 Canvas 选择图集单元并叠加轻微呼吸位移，不声称是 Live2D 或完整逐帧动画。

项目作者提供的代码和本项目生成的素材按根目录 MIT License 分发；第三方代码保留各自许可。第三方商标不在许可范围内。书娘是非官方陪伴角色，与 Anthropic、Claude、DeepSeek 无隶属或背书关系。

发布包包含 Electron、Chromium、Node.js 等运行时，随包保留其 LICENSE 与第三方声明。
