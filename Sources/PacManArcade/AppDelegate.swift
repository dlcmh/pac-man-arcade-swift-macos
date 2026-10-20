import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var gameView: GameView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        createWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        gameView?.saveHighScore()
    }

    func windowWillClose(_ notification: Notification) {
        gameView?.saveHighScore()
    }

    private func createWindow() {
        let initialSize = NSSize(width: 760, height: 926)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PAC-MAN  —  METAL ARCADE"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 560, height: 683)
        window.contentAspectRatio = NSSize(width: Renderer.designWidth, height: Renderer.designHeight)
        window.setContentSize(initialSize)
        window.center()
        window.delegate = self

        do {
            let gameView = try GameView(arcadeFrame: NSRect(origin: .zero, size: initialSize))
            window.contentView = gameView
            self.gameView = gameView
            self.window = window
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(gameView)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "PAC-MAN could not start"
            alert.informativeText = "Metal initialization failed: \(error)"
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "PAC-MAN")
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About PAC-MAN",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PAC-MAN",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PAC-MAN",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let gameMenuItem = NSMenuItem()
        mainMenu.addItem(gameMenuItem)
        let gameMenu = NSMenu(title: "Game")
        gameMenuItem.submenu = gameMenu

        let newGame = NSMenuItem(title: "New Game", action: #selector(newGame(_:)), keyEquivalent: "n")
        newGame.target = self
        gameMenu.addItem(newGame)

        let pause = NSMenuItem(title: "Pause / Resume", action: #selector(togglePause(_:)), keyEquivalent: "p")
        pause.target = self
        pause.keyEquivalentModifierMask = [.command]
        gameMenu.addItem(pause)

        let mute = NSMenuItem(title: "Toggle Sound", action: #selector(toggleSound(_:)), keyEquivalent: "m")
        mute.target = self
        mute.keyEquivalentModifierMask = [.command]
        gameMenu.addItem(mute)

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        let fullScreen = NSMenuItem(title: "Enter Full Screen",
                                    action: #selector(NSWindow.toggleFullScreen(_:)),
                                    keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreen)

        NSApp.mainMenu = mainMenu
    }

    @objc private func newGame(_ sender: Any?) {
        gameView?.game.startNewGame()
        window?.makeFirstResponder(gameView)
    }

    @objc private func togglePause(_ sender: Any?) {
        gameView?.game.togglePause()
        window?.makeFirstResponder(gameView)
    }

    @objc private func toggleSound(_ sender: Any?) {
        gameView?.toggleMute()
        window?.makeFirstResponder(gameView)
    }
}
