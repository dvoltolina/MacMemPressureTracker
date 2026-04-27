import AppKit
import Darwin

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private let statusLabel = NSTextField(labelWithString: "Checking status...")
  private let detailsView = NSTextView()
  private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
  private let installButton = NSButton(title: "Install / Reload", target: nil, action: nil)
  private let uninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
  private let testButton = NSButton(title: "Test Notification", target: nil, action: nil)
  private let revealLogButton = NSButton(title: "Reveal Log", target: nil, action: nil)
  private var currentLogPath: String?

  private lazy var repoRoot: URL = {
    if let path = Bundle.main.object(forInfoDictionaryKey: "MPMRepoRoot") as? String, !path.isEmpty {
      return URL(fileURLWithPath: path).standardizedFileURL
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
  }()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    if geteuid() == 0 {
      showFatalError("Do not run this app with sudo or as root. Open it as the logged-in user.")
      return
    }
    configureMenu()
    configureWindow()
    refreshStatus()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func configureMenu() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
      NSMenuItem(
        title: "Quit Memory Pressure Monitor",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
      )
    )
    appItem.submenu = appMenu
    menu.addItem(appItem)
    NSApp.mainMenu = menu
  }

  private func configureWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Memory Pressure Monitor"
    window.center()
    window.minSize = NSSize(width: 520, height: 380)

    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 14
    root.translatesAutoresizingMaskIntoConstraints = false
    root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

    let title = NSTextField(labelWithString: "Memory Pressure Monitor")
    title.font = .systemFont(ofSize: 22, weight: .semibold)

    statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
    statusLabel.textColor = .secondaryLabelColor

    let buttonRow = NSStackView()
    buttonRow.orientation = .horizontal
    buttonRow.alignment = .centerY
    buttonRow.spacing = 8

    for button in [refreshButton, installButton, testButton, revealLogButton, uninstallButton] {
      button.bezelStyle = .rounded
      button.setButtonType(.momentaryPushIn)
      button.target = self
      buttonRow.addArrangedSubview(button)
    }

    refreshButton.action = #selector(refreshClicked)
    installButton.action = #selector(installClicked)
    uninstallButton.action = #selector(uninstallClicked)
    testButton.action = #selector(testNotificationClicked)
    revealLogButton.action = #selector(revealLogClicked)

    detailsView.isEditable = false
    detailsView.isSelectable = true
    detailsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    detailsView.textColor = .labelColor
    detailsView.backgroundColor = .textBackgroundColor
    detailsView.textContainerInset = NSSize(width: 10, height: 10)

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.documentView = detailsView
    scroll.translatesAutoresizingMaskIntoConstraints = false

    root.addArrangedSubview(title)
    root.addArrangedSubview(statusLabel)
    root.addArrangedSubview(buttonRow)
    root.addArrangedSubview(scroll)

    window.contentView = NSView()
    window.contentView?.addSubview(root)

    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
      root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
      scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 230)
    ])

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showFatalError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Memory Pressure Monitor cannot run"
    alert.informativeText = message
    alert.addButton(withTitle: "Quit")
    alert.runModal()
    NSApp.terminate(nil)
  }

  @objc private func refreshClicked() {
    refreshStatus()
  }

  @objc private func installClicked() {
    setControls(enabled: false)
    detailsView.string = "Running install / reload..."
    runRepoScript("install.sh", arguments: ["--force"]) { [weak self] result in
      self?.showCommandResult(title: "Install / Reload", result: result)
      self?.refreshStatus()
    }
  }

  @objc private func uninstallClicked() {
    let alert = NSAlert()
    alert.messageText = "Uninstall the launchd agent?"
    alert.informativeText = "This stops the background monitor but keeps logs and state."
    alert.addButton(withTitle: "Uninstall")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else {
      return
    }

    setControls(enabled: false)
    detailsView.string = "Running uninstall..."
    runRepoScript("uninstall.sh", arguments: []) { [weak self] result in
      self?.showCommandResult(title: "Uninstall", result: result)
      self?.refreshStatus()
    }
  }

  @objc private func testNotificationClicked() {
    setControls(enabled: false)
    detailsView.string = "Sending test notification..."
    runExecutable(
      "/usr/bin/osascript",
      arguments: [
        "-e",
        "display notification \"Notifications are enabled.\" with title \"Memory Pressure Monitor test\""
      ]
    ) { [weak self] result in
      self?.showCommandResult(
        title: "Test Notification",
        result: result,
        successMessage: "The test command completed. If no banner appeared, check macOS notification settings for Script Editor or osascript."
      )
      self?.refreshStatus()
    }
  }

  @objc private func revealLogClicked() {
    let path = currentLogPath ?? "\(NSHomeDirectory())/Library/Logs/memory-pressure-monitor.log"
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
    }
  }

  private func refreshStatus() {
    setControls(enabled: false)
    statusLabel.stringValue = "Checking status..."
    detailsView.string = "Refreshing..."

    runRepoScript("status.sh", arguments: ["--json"]) { [weak self] result in
      guard let self = self else { return }
      self.setControls(enabled: true)

      guard result.status == 0 else {
        self.statusLabel.stringValue = "Status check failed"
        self.detailsView.string = result.output
        return
      }

      self.applyStatusJSON(result.output)
    }
  }

  private func applyStatusJSON(_ text: String) {
    guard let data = text.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      statusLabel.stringValue = "Status output could not be parsed"
      detailsView.string = text
      return
    }

    let loaded = json["loaded"] as? Bool ?? false
    let installed = json["installed"] as? Bool ?? false
    let health = json["health"] as? String ?? "unknown"
    let healthLabel = json["health_label"] as? String ?? "Unknown"
    let configStatus = json["config_status"] as? String ?? "unknown"
    let logExists = json["log_exists"] as? Bool ?? false
    let stateExists = json["state_exists"] as? Bool ?? false
    let service = json["service"] as? String ?? ""
    let plistPath = json["plist_path"] as? String ?? ""
    let logPath = json["log_path"] as? String ?? ""
    let statePath = json["state_path"] as? String ?? ""
    let lastLog = json["last_log"] as? String ?? ""
    let lastSample = json["last_sample"] as? String ?? ""
    let configError = json["config_error"] as? String ?? ""
    let launchdStdoutPath = json["launchd_stdout_path"] as? String ?? ""
    let launchdStderrPath = json["launchd_stderr_path"] as? String ?? ""
    let lastLaunchdStderr = json["last_launchd_stderr"] as? String ?? ""

    currentLogPath = logPath

    statusLabel.stringValue = healthLabel
    if health == "running" {
      statusLabel.textColor = .systemGreen
    } else if health == "loaded_no_sample" || health == "installed_not_loaded" {
      statusLabel.textColor = .systemOrange
    } else {
      statusLabel.textColor = .systemRed
    }

    var lines: [String] = []
    lines.append("Status:          \(healthLabel)")
    lines.append("Launchd loaded:  \(loaded ? "yes" : "no")")
    lines.append("Plist installed: \(installed ? "yes" : "no")")
    lines.append("Service:         \(service)")
    lines.append("Plist:           \(plistPath)")
    lines.append("")
    lines.append("Config:          \(configStatus)")
    lines.append("Log file:        \(logExists ? "yes" : "no") (\(logPath))")
    lines.append("State file:      \(stateExists ? "yes" : "no") (\(statePath))")
    lines.append("Launchd stdout:  \(launchdStdoutPath)")
    lines.append("Launchd stderr:  \(launchdStderrPath)")

    if !configError.isEmpty {
      lines.append("")
      lines.append("Config error:")
      lines.append(configError)
    }

    lines.append("")
    lines.append("Last sample:")
    lines.append(lastSample.isEmpty ? "(none yet)" : lastSample)
    lines.append("")
    lines.append("Last log line:")
    lines.append(lastLog.isEmpty ? "(none yet)" : lastLog)

    if !lastLaunchdStderr.isEmpty {
      lines.append("")
      lines.append("Last launchd error line:")
      lines.append(lastLaunchdStderr)
    }

    detailsView.string = lines.joined(separator: "\n")
  }

  private func setControls(enabled: Bool) {
    for button in [refreshButton, installButton, uninstallButton, testButton, revealLogButton] {
      button.isEnabled = enabled
    }
  }

  private func runRepoScript(
    _ scriptName: String,
    arguments: [String],
    completion: @escaping (CommandResult) -> Void
  ) {
    guard let scriptURL = validatedScriptURL(named: scriptName) else {
      completion(CommandResult(status: 126, output: "Refusing to run untrusted or missing repo script: \(scriptName)"))
      return
    }

    runExecutable(
      scriptURL.path,
      arguments: arguments,
      completion: completion
    )
  }

  private func validatedScriptURL(named scriptName: String) -> URL? {
    let allowed = ["status.sh", "install.sh", "uninstall.sh"]
    guard allowed.contains(scriptName) else {
      return nil
    }

    let repo = repoRoot.resolvingSymlinksInPath()
    let script = repo
      .appendingPathComponent("scripts", isDirectory: true)
      .appendingPathComponent(scriptName)
      .resolvingSymlinksInPath()

    guard script.path.hasPrefix(repo.path + "/scripts/") else {
      return nil
    }

    do {
      let repoValues = try repo.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard repoValues.isDirectory == true, repoValues.isSymbolicLink != true else {
        return nil
      }

      let scriptValues = try script.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard scriptValues.isRegularFile == true, scriptValues.isSymbolicLink != true else {
        return nil
      }
    } catch {
      return nil
    }

    let fileManager = FileManager.default
    guard fileManager.isExecutableFile(atPath: script.path) else {
      return nil
    }

    do {
      let attrs = try fileManager.attributesOfItem(atPath: script.path)
      let owner = attrs[.ownerAccountID] as? NSNumber
      let permissions = attrs[.posixPermissions] as? NSNumber
      guard owner?.uint32Value == getuid() else {
        return nil
      }
      guard let mode = permissions?.uint16Value, mode & 0o022 == 0 else {
        return nil
      }
    } catch {
      return nil
    }

    return script
  }

  private func runExecutable(
    _ path: String,
    arguments: [String],
    completion: @escaping (CommandResult) -> Void
  ) {
    if geteuid() == 0 {
      completion(CommandResult(status: 126, output: "Refusing to run commands as root."))
      return
    }

    let process = Process()
    let pipe = Pipe()
    let outputQueue = DispatchQueue(label: "MemoryPressureMonitor.commandOutput")
    var outputData = Data()
    let maxOutputBytes = 256 * 1024

    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        return
      }
      outputQueue.sync {
        if outputData.count < maxOutputBytes {
          outputData.append(contentsOf: data.prefix(maxOutputBytes - outputData.count))
        }
      }
    }

    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.currentDirectoryURL = repoRoot
    process.environment = [
      "HOME": NSHomeDirectory(),
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
    ]
    process.standardOutput = pipe
    process.standardError = pipe
    process.terminationHandler = { process in
      pipe.fileHandleForReading.readabilityHandler = nil
      let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
      outputQueue.sync {
        if outputData.count < maxOutputBytes {
          outputData.append(contentsOf: remaining.prefix(maxOutputBytes - outputData.count))
        }
      }
      let captured = outputQueue.sync { outputData }
      var output = String(data: captured, encoding: .utf8) ?? ""
      if captured.count >= maxOutputBytes {
        output += "\n[output truncated]"
      }
      DispatchQueue.main.async {
        completion(CommandResult(status: process.terminationStatus, output: output))
      }
    }

    do {
      try process.run()
    } catch {
      completion(CommandResult(status: 127, output: error.localizedDescription))
    }
  }

  private func showCommandResult(
    title: String,
    result: CommandResult,
    successMessage: String? = nil
  ) {
    let alert = NSAlert()
    alert.messageText = result.status == 0 ? "\(title) completed" : "\(title) failed"
    if result.status == 0, let successMessage = successMessage {
      alert.informativeText = result.output.isEmpty ? successMessage : "\(successMessage)\n\n\(result.output)"
    } else {
      alert.informativeText = result.output.isEmpty ? "Exit status: \(result.status)" : result.output
    }
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}

struct CommandResult {
  let status: Int32
  let output: String
}
