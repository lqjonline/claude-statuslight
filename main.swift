import AppKit
import Foundation
import Network

// MARK: - Configuration
let PORT: UInt16 = 9527
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/ClaudeStatusLight.log")

func log(_ msg: String) {
    let line = "[ClaudeStatusLight] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
    fputs(line, stderr)
}

// MARK: - Kill old instance
func ensurePortFree() {
    let task = Process()
    task.launchPath = "/usr/sbin/lsof"
    task.arguments = ["-t", "-i:\(PORT)"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    guard let data = try? pipe.fileHandleForReading.readToEnd(),
          let pids = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n"),
          !pids.isEmpty else { return }

    let myPid = "\(ProcessInfo.processInfo.processIdentifier)"
    for pidStr in pids where pidStr != myPid {
        if let pid = Int32(pidStr) {
            log("端口被 PID \(pid) 占用，正在 kill...")
            kill(pid, SIGKILL)
        }
    }
    Thread.sleep(forTimeInterval: 0.5)
}

// MARK: - App Delegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var currentStatus = "idle"
    var configPanel: NSPanel?
    var soundEnabled = true
    var soundMenuItem: NSMenuItem!

    let titles: [String: String] = [
        "idle":    "Claude 🟢 空闲",
        "working": "Claude 🟡 执行中",
        "confirm": "Claude 🔴 需确认",
        "offline": "Claude ⚪️ 离线",
    ]

    // 系统音效：idle=完成提示，confirm=需关注提醒
    let soundIdle    = NSSound(named: "Glass")     // 清脆完成声
    let soundConfirm = NSSound(named: "Ping")      // 提醒声

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = titles["idle"]!

        let menu = NSMenu()
        let idleItem    = NSMenuItem(title: "空闲",   action: #selector(setIdle),    keyEquivalent: "")
        let workItem    = NSMenuItem(title: "执行中", action: #selector(setWorking), keyEquivalent: "")
        let confirmItem = NSMenuItem(title: "需确认", action: #selector(setConfirm), keyEquivalent: "")
        let offlineItem = NSMenuItem(title: "离线",   action: #selector(setOffline), keyEquivalent: "")
        soundMenuItem   = NSMenuItem(title: "关闭声音", action: #selector(toggleSound), keyEquivalent: "")
        let helpItem    = NSMenuItem(title: "Claude配置", action: #selector(showHelp), keyEquivalent: "")
        let quitItem    = NSMenuItem(title: "退出",   action: #selector(quitApp),    keyEquivalent: "q")
        idleItem.target = self
        workItem.target = self
        confirmItem.target = self
        offlineItem.target = self
        soundMenuItem?.target = self
        helpItem.target = self
        quitItem.target = self

        menu.addItem(idleItem)
        menu.addItem(workItem)
        menu.addItem(confirmItem)
        menu.addItem(offlineItem)
        menu.addItem(.separator())
        menu.addItem(soundMenuItem!)
        menu.addItem(helpItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        startHTTPServer()
        log("启动完成")
    }

    func applyStatus(_ newStatus: String) {
        let changed = currentStatus != newStatus
        currentStatus = newStatus
        statusItem.button?.title = titles[newStatus]!

        // 声音提示：仅在状态变化时，且仅对绿/红灯发声
        if changed && soundEnabled {
            switch newStatus {
            case "idle":    soundIdle?.play()
            case "confirm": soundConfirm?.play()
            default:        break
            }
        }
    }

    @objc func setIdle()    { applyStatus("idle") }
    @objc func setWorking() { applyStatus("working") }
    @objc func setConfirm() { applyStatus("confirm") }
    @objc func setOffline() { applyStatus("offline") }
    @objc func quitApp()    { NSApp.terminate(nil) }

    @objc func toggleSound() {
        soundEnabled.toggle()
        soundMenuItem.title = soundEnabled ? "关闭声音" : "打开声音"
    }

    @objc func showHelp() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Claude Code 状态灯配置"
        panel.isFloatingPanel = true
        panel.center()

        // Header label
        let header = NSTextField(labelWithString: "Hook → 状态灯 对应关系")
        header.font = NSFont.boldSystemFont(ofSize: 14)
        header.frame = NSRect(x: 20, y: 475, width: 580, height: 20)

        let mapping = NSTextField(labelWithString: """
        🟡 执行中  ←  PreToolUse（工具调用前）/ UserPromptSubmit（提交提示词）
        🔴 需确认  ←  Notification（权限请求通知）
        🟢 空闲    ←  Stop（本轮响应结束）
        ⚪️ 离线    ←  SessionEnd（Claude 退出时）

        将下方 JSON 复制到 .claude/settings.json 的 hooks 字段中即可启用：
        """)
        mapping.font = NSFont.systemFont(ofSize: 12)
        mapping.frame = NSRect(x: 20, y: 430, width: 580, height: 50)
        mapping.lineBreakMode = .byWordWrapping
        mapping.maximumNumberOfLines = 0

        // Scrollable config text
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 60, width: 580, height: 365))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let configText = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"working\\"}'"
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
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"working\\"}'"
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
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"confirm\\"}'"
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
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"idle\\"}'"
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
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"offline\\"}'"
                  }
                ]
              }
            ]
          }
        }
        """

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.string = configText
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 10, height: 10)
        scrollView.documentView = textView

        // Copy button
        let copyBtn = NSButton(frame: NSRect(x: 480, y: 15, width: 120, height: 28))
        copyBtn.title = "复制配置"
        copyBtn.bezelStyle = .rounded
        copyBtn.target = self
        copyBtn.action = #selector(copyConfig)

        panel.contentView?.addSubview(header)
        panel.contentView?.addSubview(mapping)
        panel.contentView?.addSubview(scrollView)
        panel.contentView?.addSubview(copyBtn)

        configPanel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func copyConfig() {
        let config = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "",
                "hooks": [
                  {
                    "type": "command",
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"working\\"}'"
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
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"working\\"}'"
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
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"confirm\\"}'"
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
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"idle\\"}'"
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
                    "command": "curl -s -X POST http://localhost:9527/state -H 'Content-Type: application/json' -d '{\\"state\\":\\"offline\\"}'"
                  }
                ]
              }
            ]
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }
}

// MARK: - Minimal HTTP Server (Network.framework, no dependencies)

extension AppDelegate {
    func startHTTPServer() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: PORT)!)
        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            log("HTTP listener 创建失败: \(error)")
            return
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                log("HTTP 服务已启动 → http://127.0.0.1:\(PORT)/state")
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .utility))
            self?.receive(on: conn, buffer: Data())
        }
        listener.start(queue: .global(qos: .utility))
    }

    func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self = self else { return }
            var buf = buffer
            if let data = data { buf.append(data) }

            // Check if we have a complete HTTP request
            guard let bodyRange = buf.range(of: Data("\r\n\r\n".utf8)) else {
                // Need more data
                self.receive(on: conn, buffer: buf)
                return
            }

            let headerData = buf[..<bodyRange.lowerBound]
            let bodyStart = bodyRange.upperBound

            // Parse Content-Length
            var contentLength = 0
            if let headerStr = String(data: headerData, encoding: .utf8) {
                for line in headerStr.components(separatedBy: "\r\n") {
                    let l = line.lowercased()
                    if l.hasPrefix("content-length:") {
                        contentLength = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
            }

            let bodyEnd = bodyStart + contentLength
            if buf.count < bodyEnd {
                // Need more body data
                self.receive(on: conn, buffer: buf)
                return
            }

            let bodyData = buf[bodyStart..<bodyEnd]
            self.handleRequest(headerData: headerData, body: bodyData, conn: conn)
        }
    }

    func handleRequest(headerData: Data, body: Data, conn: NWConnection) {
        guard let headerStr = String(data: headerData, encoding: .utf8) else {
            respond(conn, 400, #"{"status":"error","message":"bad request"}"#)
            return
        }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first,
              firstLine.hasPrefix("POST /state ") else {
            respond(conn, 404, #"{"status":"error","message":"not found"}"#)
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: String],
              let state = json["state"],
              titles[state] != nil else {
            respond(conn, 400, #"{"status":"error","message":"invalid state"}"#)
            return
        }

        DispatchQueue.main.async {
            self.applyStatus(state)
        }
        respond(conn, 200, #"{"status":"ok","state":"\#(state)"}"#)
    }

    func respond(_ conn: NWConnection, _ code: Int, _ body: String) {
        let reason = code == 200 ? "OK" : (code == 400 ? "Bad Request" : "Not Found")
        let resp = """
        HTTP/1.1 \(code) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        conn.send(content: resp.data(using: .utf8)!,
                  completion: .contentProcessed({ _ in conn.cancel() }))
    }
}

// MARK: - Entry Point
log("正在启动...")
ensurePortFree()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
