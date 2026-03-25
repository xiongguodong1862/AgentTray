# CodexTray 代理说明

## 目的

- 本项目是 `macOS` 菜单栏应用，技术栈为 `Swift + AppKit + SwiftUI`。
- 目标是聚合 `Codex / Claude / Gemini` 等 Agent 的使用数据并展示在轻量面板中。

## 低 Token 原则

- 先看本文件，再行动；不要重复总结仓库背景。
- 回答优先短句，只说和当前任务直接相关的信息。
- 非必要不要给大段方案、长列表、全量文件解读。
- 非必要不要做架构重组、命名清洗、接口调整、代码拆分。
- 优先小改、局部改、就地修。

## 目录速记

- `Sources/CodexTray/main.swift`：入口
- `Sources/CodexTrayFeature/App`：托盘控制与状态
- `Sources/CodexTrayFeature/Models`：数据模型与设置
- `Sources/CodexTrayFeature/Services`：数据读取与聚合
- `Sources/CodexTrayFeature/Views`：界面
- `Tests/CodexTrayFeatureTests`：测试
- `scripts/package_app.sh`：打包脚本

## 常用命令

- 测试：`swift test`
- 打包调试版：`./scripts/package_app.sh debug`
- 打包发布版：`./scripts/package_app.sh release`

## 强约束

- 只修改用户明确要求的内容。
- 新增或修改逻辑必须补测试。
- 不得绕过、删除或弱化失败测试。
- 仅可使用商业友好依赖；如需新增依赖，先征求用户同意。
- 不提交密钥、凭证或私密配置。
- 同一难题连续 3 次有效尝试仍未解决时，停止并明确反馈阻塞点。

## 默认环境

- `macOS 14+`
- `Xcode 16+`
- `Swift 6.2`
- 默认产物：`dist/AgentTray.app`
