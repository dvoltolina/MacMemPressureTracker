import AppKit
import Darwin

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  static func main() {
    let parsed = AppArguments.parse(CommandLine.arguments)
    let app = NSApplication.shared
    if parsed.alertKind != nil {
      let delegate = AlertController(arguments: parsed)
      app.delegate = delegate
      app.run()
    } else {
      let delegate = AppDelegate()
      app.delegate = delegate
      app.run()
    }
  }

  private var window: NSWindow!
  private let statusLabel = NSTextField(labelWithString: "Checking status...")
  private let heartbeatLabel = NSTextField(labelWithString: "")
  private let detailsView = NSTextView()
  private let chartView = PressureChartView()
  private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
  private let installButton = NSButton(title: "Install / Reload", target: nil, action: nil)
  private let uninstallButton = NSButton(title: "Uninstall", target: nil, action: nil)
  private let testButton = NSButton(title: "Test Notification", target: nil, action: nil)
  private let revealLogButton = NSButton(title: "Reveal Log", target: nil, action: nil)
  private var currentLogPath: String?
  private var chartTimer: Timer?
  private var heartbeatTimer: Timer?
  private var lastSampleAt: Date?

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
    startChartTimer()
    startHeartbeatTimer()
  }

  private func startChartTimer() {
    chartTimer?.invalidate()
    let timer = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
      self?.refreshChart()
    }
    RunLoop.main.add(timer, forMode: .common)
    chartTimer = timer
  }

  private func startHeartbeatTimer() {
    heartbeatTimer?.invalidate()
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateHeartbeat()
    }
    RunLoop.main.add(timer, forMode: .common)
    heartbeatTimer = timer
    updateHeartbeat()
  }

  private func updateHeartbeat() {
    guard let last = lastSampleAt else {
      heartbeatLabel.stringValue = "Waiting for first sample..."
      heartbeatLabel.textColor = .secondaryLabelColor
      return
    }
    let elapsed = Int(Date().timeIntervalSince(last))
    let staleThreshold = 150
    let formatted: String
    if elapsed < 60 {
      formatted = "Last sample \(elapsed)s ago"
    } else {
      let mins = elapsed / 60
      let secs = elapsed % 60
      formatted = "Last sample \(mins)m \(secs)s ago"
    }
    heartbeatLabel.stringValue = formatted
    heartbeatLabel.textColor = elapsed > staleThreshold ? .systemRed : .secondaryLabelColor
  }

  private func refreshChart() {
    guard let path = currentLogPath, !path.isEmpty else { return }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let samples = PressureLogReader.recentSamples(logPath: path, maxCount: 240)
      DispatchQueue.main.async {
        self?.chartView.setSamples(samples)
      }
    }
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
    window.minSize = NSSize(width: 560, height: 520)
    window.setContentSize(NSSize(width: 680, height: 600))

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

    heartbeatLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    heartbeatLabel.textColor = .secondaryLabelColor

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

    chartView.translatesAutoresizingMaskIntoConstraints = false

    root.addArrangedSubview(title)
    root.addArrangedSubview(statusLabel)
    root.addArrangedSubview(heartbeatLabel)
    root.addArrangedSubview(buttonRow)
    root.addArrangedSubview(chartView)
    root.addArrangedSubview(scroll)

    window.contentView = NSView()
    window.contentView?.addSubview(root)

    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
      root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
      chartView.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
      chartView.heightAnchor.constraint(equalToConstant: 160),
      scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
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
    lastSampleAt = parseSampleTimestamp(from: lastSample)
    updateHeartbeat()
    refreshChart()

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

  private func parseSampleTimestamp(from line: String) -> Date? {
    guard !line.isEmpty,
      let data = line.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let ts = json["ts"] as? String
    else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: ts)
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

struct PressureSample {
  let timestamp: Date
  let freePct: Double
  let zone: String
  let swapMiB: Double
}

enum PressureLogReader {
  // Reads the JSONL log tail and returns up to `maxCount` of the most recent
  // `sample_taken` events, oldest-first.
  static func recentSamples(logPath: String, maxCount: Int) -> [PressureSample] {
    guard let handle = FileHandle(forReadingAtPath: logPath) else { return [] }
    defer { try? handle.close() }

    let readBudget: UInt64 = 256 * 1024
    let totalSize = (try? handle.seekToEnd()) ?? 0
    let offset = totalSize > readBudget ? totalSize - readBudget : 0
    do {
      try handle.seek(toOffset: offset)
    } catch {
      return []
    }
    let data = handle.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return [] }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]

    var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    if offset > 0, !lines.isEmpty {
      lines.removeFirst()
    }

    var samples: [PressureSample] = []
    for line in lines {
      guard
        let lineData = line.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
      else { continue }
      guard (json["event"] as? String) == "sample_taken" else { continue }

      let ts = (json["ts"] as? String).flatMap(formatter.date(from:)) ?? Date()
      let freePct: Double
      if let n = json["free_pct"] as? NSNumber { freePct = n.doubleValue }
      else if let s = json["free_pct"] as? String, let n = Double(s) { freePct = n }
      else { continue }
      let zone = (json["zone"] as? String) ?? "unknown"
      let swap: Double
      if let n = json["swap_used_mib"] as? NSNumber { swap = n.doubleValue }
      else { swap = 0 }

      samples.append(PressureSample(timestamp: ts, freePct: freePct, zone: zone, swapMiB: swap))
    }

    if samples.count > maxCount {
      samples = Array(samples.suffix(maxCount))
    }
    return samples
  }
}

final class PressureChartView: NSView {
  private var samples: [PressureSample] = []
  private let placeholder = NSTextField(labelWithString: "Waiting for samples...")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    layer?.cornerRadius = 6
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.cgColor

    placeholder.translatesAutoresizingMaskIntoConstraints = false
    placeholder.textColor = .secondaryLabelColor
    addSubview(placeholder)
    NSLayoutConstraint.activate([
      placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
      placeholder.centerYAnchor.constraint(equalTo: centerYAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  func setSamples(_ samples: [PressureSample]) {
    self.samples = samples
    placeholder.isHidden = !samples.isEmpty
    needsDisplay = true
  }

  override var wantsUpdateLayer: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard samples.count >= 2 else { return }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    let inset = NSEdgeInsets(top: 14, left: 36, bottom: 22, right: 12)
    let plot = NSRect(
      x: bounds.minX + inset.left,
      y: bounds.minY + inset.bottom,
      width: bounds.width - inset.left - inset.right,
      height: bounds.height - inset.top - inset.bottom
    )
    guard plot.width > 4, plot.height > 4 else { return }

    drawAxes(in: plot, ctx: ctx)

    let count = samples.count
    let stepX = plot.width / CGFloat(max(count - 1, 1))
    func point(for index: Int) -> CGPoint {
      let s = samples[index]
      let clamped = max(0, min(100, s.freePct))
      let x = plot.minX + CGFloat(index) * stepX
      let y = plot.minY + plot.height * CGFloat(clamped / 100.0)
      return CGPoint(x: x, y: y)
    }

    // Filled area under the line.
    let areaPath = NSBezierPath()
    areaPath.move(to: CGPoint(x: plot.minX, y: plot.minY))
    for i in 0..<count {
      let p = point(for: i)
      if i == 0 {
        areaPath.line(to: CGPoint(x: p.x, y: plot.minY))
      }
      areaPath.line(to: p)
    }
    areaPath.line(to: CGPoint(x: plot.maxX, y: plot.minY))
    areaPath.close()
    NSColor.systemBlue.withAlphaComponent(0.12).setFill()
    areaPath.fill()

    // Line.
    let linePath = NSBezierPath()
    linePath.lineWidth = 1.5
    linePath.lineJoinStyle = .round
    linePath.move(to: point(for: 0))
    for i in 1..<count {
      linePath.line(to: point(for: i))
    }
    NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
    linePath.stroke()

    // Per-sample dots colored by zone.
    for i in 0..<count {
      let p = point(for: i)
      let radius: CGFloat = 2.5
      let dot = NSBezierPath(ovalIn: NSRect(
        x: p.x - radius, y: p.y - radius,
        width: radius * 2, height: radius * 2
      ))
      zoneColor(samples[i].zone).setFill()
      dot.fill()
    }

    drawLegend(in: bounds, ctx: ctx)
  }

  private func zoneColor(_ zone: String) -> NSColor {
    switch zone {
    case "normal": return .systemGreen
    case "warn": return .systemOrange
    case "critical": return .systemRed
    default: return .systemGray
    }
  }

  private func drawAxes(in plot: NSRect, ctx: CGContext) {
    let gridColor = NSColor.separatorColor.withAlphaComponent(0.5)
    let labelAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 9),
      .foregroundColor: NSColor.secondaryLabelColor
    ]

    for pct in stride(from: 0, through: 100, by: 25) {
      let y = plot.minY + plot.height * CGFloat(Double(pct) / 100.0)
      let path = NSBezierPath()
      path.move(to: CGPoint(x: plot.minX, y: y))
      path.line(to: CGPoint(x: plot.maxX, y: y))
      gridColor.setStroke()
      path.lineWidth = 0.5
      path.stroke()
      let label = NSAttributedString(string: "\(pct)%", attributes: labelAttrs)
      let size = label.size()
      label.draw(at: CGPoint(x: plot.minX - size.width - 4, y: y - size.height / 2))
    }

    let oldest = samples.first?.timestamp
    let newest = samples.last?.timestamp
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    if let oldest = oldest {
      let s = NSAttributedString(string: formatter.string(from: oldest), attributes: labelAttrs)
      s.draw(at: CGPoint(x: plot.minX, y: plot.minY - s.size().height - 4))
    }
    if let newest = newest {
      let s = NSAttributedString(string: formatter.string(from: newest), attributes: labelAttrs)
      let sz = s.size()
      s.draw(at: CGPoint(x: plot.maxX - sz.width, y: plot.minY - sz.height - 4))
    }
  }

  private func drawLegend(in rect: NSRect, ctx: CGContext) {
    guard let last = samples.last else { return }
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 10, weight: .medium),
      .foregroundColor: NSColor.labelColor
    ]
    let pctText = String(format: "free %.0f%% • zone %@ • swap %.0f MiB",
      last.freePct, last.zone, last.swapMiB)
    let s = NSAttributedString(string: pctText, attributes: attrs)
    let sz = s.size()
    s.draw(at: CGPoint(x: rect.maxX - sz.width - 10, y: rect.maxY - sz.height - 4))
  }
}

struct AppArguments {
  let alertKind: String?
  let alertTitle: String
  let alertBody: String
  let zone: String?
  let freePct: Int?
  let swapMib: Int?

  static func parse(_ argv: [String]) -> AppArguments {
    var dict: [String: String] = [:]
    var i = 1
    while i < argv.count {
      let key = argv[i]
      if key.hasPrefix("--") {
        // Reject values that look like another flag — protects callers
        // that drop a flag's value, which would otherwise silently
        // misalign the parse and break alert mode.
        if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") {
          dict[key] = argv[i + 1]
          i += 2
        } else {
          i += 1
        }
      } else {
        i += 1
      }
    }
    return AppArguments(
      alertKind: dict["--alert"],
      alertTitle: dict["--title"] ?? "Memory Pressure Monitor",
      alertBody: dict["--body"] ?? "",
      zone: dict["--zone"],
      freePct: dict["--free-pct"].flatMap(Int.init),
      swapMib: dict["--swap-mib"].flatMap(Int.init)
    )
  }
}

struct ProcessRow {
  let pid: Int
  let rssMib: Int
  let command: String
}

enum ProcessLister {
  // Returns the top `limit` processes by RSS, descending.
  static func topByRSS(limit: Int) -> [ProcessRow] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-A", "-o", "pid=,rss=,comm="]
    let outPipe = Pipe()
    let errPipe = Pipe()
    task.standardOutput = outPipe
    task.standardError = errPipe
    do { try task.run() } catch { return [] }
    task.waitUntilExit()
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return [] }

    var rows: [ProcessRow] = []
    for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
      guard parts.count == 3,
        let pid = Int(parts[0]),
        let rssKb = Int(parts[1])
      else { continue }
      let cmd = parts[2].trimmingCharacters(in: .whitespaces)
      let display = cmd.isEmpty ? "(unknown)" : cmd
      rows.append(ProcessRow(pid: pid, rssMib: rssKb / 1024, command: display))
    }
    rows.sort { $0.rssMib > $1.rssMib }
    return Array(rows.prefix(limit))
  }
}

final class AlertController: NSObject, NSApplicationDelegate {
  private let args: AppArguments
  private let autoDismissSeconds: TimeInterval = 90
  private var dismissTimer: Timer?

  init(arguments: AppArguments) {
    self.args = arguments
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    if geteuid() == 0 {
      NSApp.terminate(nil)
      return
    }

    configureMenu()
    NSApp.activate(ignoringOtherApps: true)
    presentAlert()
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

  private func presentAlert() {
    let alert = NSAlert()
    alert.messageText = args.alertTitle
    alert.informativeText = composeBody()
    alert.alertStyle = alertStyle(for: args.alertKind)
    alert.accessoryView = buildProcessTable()
    alert.addButton(withTitle: "Open Activity Monitor")
    alert.addButton(withTitle: "Dismiss")
    alert.window.level = .floating
    alert.window.collectionBehavior = [.canJoinAllSpaces, .moveToActiveSpace]

    let timer = Timer(timeInterval: autoDismissSeconds, repeats: false) { _ in
      // abortModal stops runModal and returns NSApplication.ModalResponse.abort
      NSApp.abortModal()
    }
    RunLoop.main.add(timer, forMode: .common)
    dismissTimer = timer

    let response = alert.runModal()
    timer.invalidate()
    dismissTimer = nil

    if response == .alertFirstButtonReturn {
      openActivityMonitor()
    }
    NSApp.terminate(nil)
  }

  private func composeBody() -> String {
    var lines: [String] = []
    if !args.alertBody.isEmpty { lines.append(args.alertBody) }
    var ctx: [String] = []
    if let z = args.zone, !z.isEmpty { ctx.append("zone \(z)") }
    if let f = args.freePct { ctx.append("free \(f)%") }
    if let s = args.swapMib { ctx.append("swap \(s) MiB") }
    if !ctx.isEmpty {
      lines.append(ctx.joined(separator: " · "))
    }
    return lines.joined(separator: "\n")
  }

  private func alertStyle(for kind: String?) -> NSAlert.Style {
    switch kind {
    case "red_pressure": return .critical
    case "warn_pressure", "swap_in_use": return .warning
    default: return .informational
    }
  }

  private func buildProcessTable() -> NSView {
    let processes = ProcessLister.topByRSS(limit: 8)
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 3

    let header = NSTextField(labelWithString: "Top processes by memory (RSS):")
    header.font = .boldSystemFont(ofSize: 11)
    stack.addArrangedSubview(header)

    if processes.isEmpty {
      let none = NSTextField(labelWithString: "(could not enumerate processes)")
      none.font = .systemFont(ofSize: 11)
      none.textColor = .secondaryLabelColor
      stack.addArrangedSubview(none)
    } else {
      let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
      let columnHeader = NSTextField(labelWithString: "   PID    RSS  Process")
      columnHeader.font = mono
      columnHeader.textColor = .secondaryLabelColor
      stack.addArrangedSubview(columnHeader)
      for p in processes {
        let row = NSTextField(labelWithString:
          String(format: "%6d  %4d MiB  %@", p.pid, p.rssMib, p.command))
        row.font = mono
        stack.addArrangedSubview(row)
      }
    }

    let advisory = NSTextField(labelWithString:
      "To free memory: open Activity Monitor and Quit the largest process you don't need.")
    advisory.font = .systemFont(ofSize: 11, weight: .medium)
    advisory.textColor = .labelColor
    stack.addArrangedSubview(advisory)

    let size = stack.fittingSize
    stack.frame = NSRect(x: 0, y: 0, width: max(size.width, 460), height: size.height)
    return stack
  }

  private func openActivityMonitor() {
    let candidates = [
      "/System/Applications/Utilities/Activity Monitor.app",
      "/Applications/Utilities/Activity Monitor.app"
    ]
    for path in candidates {
      if FileManager.default.fileExists(atPath: path) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        return
      }
    }
    NSLog("Memory Pressure Monitor: Activity Monitor not found at known paths")
    let alert = NSAlert()
    alert.messageText = "Activity Monitor not found"
    alert.informativeText = "Could not locate Activity Monitor at the standard system or /Applications path."
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
