import AppKit

@main
enum DybysApp {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MixerModel()
    private var statusItem: NSStatusItem?
    private var panel: PanelController?
    private var selfTest: SelfTest?
    private var dumpSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            PanelSnapshot.run(directory: arguments[index + 1])
            return
        }
        if let index = arguments.firstIndex(of: "--capture"), index + 1 < arguments.count {
            PanelCapture.run(directory: arguments[index + 1])
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: AppName.display)
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.toolTip = AppName.display
        }
        statusItem = item
        panel = PanelController(model: model, statusItem: item)
        model.start()

        signal(SIGUSR1, SIG_IGN)
        let dump = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        dump.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.model.writeStateDump() }
        }
        dump.resume()
        dumpSignal = dump

        if let index = arguments.firstIndex(of: "--selftest") {
            let test = SelfTest(model: model, arguments: Array(arguments[(index + 1)...]))
            selfTest = test
            test.run()
        }
        if arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                MainActor.assumeIsolated { self?.panel?.open() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            panel?.toggle()
        }
    }

    private func showMenu() {
        panel?.close()
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()
        let login = NSMenuItem(title: "Открывать при входе в систему", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)
        if model.hasAdjustments {
            let reset = NSMenuItem(title: "Вернуть всем 100%", action: #selector(resetAll), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLogin)
    }

    @objc private func resetAll() {
        model.resetAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
