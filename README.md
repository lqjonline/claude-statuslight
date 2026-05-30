# Claude StatusLight

macOS 菜单栏状态灯，实时显示 [Claude Code](https://claude.ai/code) 的工作状态。

<p align="center">
  🟢 空闲 &nbsp;—&nbsp; 🟡 执行中 &nbsp;—&nbsp; 🔴 需确认 &nbsp;—&nbsp; ⚪️ 离线
</p>

通过 Claude Code 的 **hooks** 机制自动切换：Claude 启动 → 绿灯，开始调用工具 → 黄灯，请求权限 → 红灯，任务完成 → 绿灯，Claude 退出 → 灰灯。看一眼菜单栏就知道 Claude 在干嘛，无需切窗口。

## 效果

| 菜单栏显示 | 状态 | 何时触发 |
|-----------|------|---------|
| `Claude 🟢 空闲` | 空闲 | Claude 启动（SessionStart）/ 本轮响应结束（Stop） |
| `Claude 🟡 执行中` | 工作中 | 工具调用前、提交提示词 |
| `Claude 🔴 需确认` | 等待中 | 权限请求通知弹出 |
| `Claude ⚪️ 离线` | 离线 | Claude 进程退出（SessionEnd） |

## 安装

### 方式一：直接下载（推荐）

[⬇ 下载 ClaudeStatusLight.app.zip](releases/ClaudeStatusLight.app.zip)

解压后双击 `ClaudeStatusLight.app` 即可运行。

> 也可在 [GitHub Releases](https://github.com/lqjonline/claude-statuslight/releases) 页面下载。

### 方式二：从源码编译

```bash
git clone https://github.com/lqjonline/claude-statuslight.git
cd claude-statuslight
./build.sh
open ClaudeStatusLight.app
```

依赖：macOS + Xcode Command Line Tools（`swiftc`），145KB 独立二进制，无任何第三方依赖。

## 配置 Claude Code

启动 StatusLight 后，在 Claude Code 项目的 `.claude/settings.json` 中添加 hooks：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\"state\":\"idle\"}'"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\"state\":\"working\"}'"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\"state\":\"working\"}'"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\"state\":\"confirm\"}'"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\"state\":\"idle\"}'"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\"state\":\"offline\"}'"
          }
        ]
      }
    ]
  }
}
```

> 💡 点击菜单栏图标 → **Claude配置** 可随时查看配置说明并一键复制。

## 工作流程

```
Claude Code hooks (curl)  →  HTTP :9527  →  菜单栏标题实时更新
─────────────────────────────────────────────────────────────
  SessionStart     ──────────  🟢 空闲
  PreToolUse       ──────────  🟡 执行中
  UserPromptSubmit ──────────  🟡 执行中
  Notification     ──────────  🔴 需确认
  Stop             ──────────  🟢 空闲
  SessionEnd       ──────────  ⚪️ 离线
```

## 特性

- **零依赖** — 纯 Swift 实现，仅使用 macOS 系统框架（Network、AppKit）
- **极速启动** — 145KB 二进制，启动 < 0.1 秒
- **自动恢复** — 启动时自动清理残留进程，确保端口可用
- **手动切换** — 菜单栏支持手动切换状态
- **原生体验** — 基于 NSStatusBar，无 Dock 图标，纯菜单栏应用

## 技术栈

| 组件 | 技术 |
|------|------|
| 菜单栏 UI | AppKit (`NSStatusBar`) |
| HTTP 服务 | Network.framework (`NWListener`) |
| 语言 | Swift 5+ |
| 最低系统 | macOS 14+ |

## License

MIT © [lqjonline](https://github.com/lqjonline)
