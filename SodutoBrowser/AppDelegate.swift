//
//  AppDelegate.swift
//  SodutoBrowser
//
//  Created by Giedrius on 2017-03-03.
//  Copyright © 2017 Soduto. All rights reserved.
//

import Cocoa
import CleanroomLogger

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, BrowserWindowControllerDelegate {
    
    // MARK: Types
    
    struct MenuItemTags {
        // Go menu
        static let back: Int = 1001
        static let forward: Int = 1002
        static let enclosingFolder: Int = 1003
        
        // View menu
        static let toggleHiddenFiles: Int = 2001
        static let foldersAlwaysFirst: Int = 2101
        
        // File menu
        static let deleteFiles: Int = 3001
        static let newFolder: Int = 3002
        static let newWindow: Int = 3003
        static let closeTabGroup: Int = 3004
        static let close: Int = 3005
        static let newTab: Int = 3006
    }
    
    struct ToolbarItemTags {
        static let backForward: Int = 50001
    }
    
    
    // MARK: Properties

    private(set) var browserWindowControllers: [BrowserWindowController] = []
    
    var keyBrowserWindowController: BrowserWindowController? {
        return NSApp.keyWindow?.windowController as? BrowserWindowController
    }
    
    static let logLevelConfigurationKey = "com.soduto.logLevel"
    
    override init() {
        UserDefaults.standard.register(defaults: [AppDelegate.logLevelConfigurationKey: LogSeverity.info.rawValue])
        
        #if DEBUG
            Log.enable(configuration: XcodeLogConfiguration(minimumSeverity: .debug, logToASL: true))
        #else
            let formatter = FieldBasedLogFormatter(fields: [.severity(.simple), .delimiter(.spacedPipe), .payload])
            let aslRecorder = ASLLogRecorder(formatter: formatter, echoToStdErr: true)
            let severity: LogSeverity = LogSeverity(rawValue: UserDefaults.standard.integer(forKey: AppDelegate.logLevelConfigurationKey)) ?? .info
            Log.enable(configuration: BasicLogConfiguration(minimumSeverity: severity, recorders: [aslRecorder]))
        #endif
    }
    
    
    // MARK: NSApplicationDelegate
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [AppDelegate.logLevelConfigurationKey: LogSeverity.info.rawValue])
        
        #if DEBUG
            Log.enable(configuration: XcodeLogConfiguration(minimumSeverity: .debug, logToASL: false))
        #else
            let formatter = FieldBasedLogFormatter(fields: [.severity(.simple), .delimiter(.spacedPipe), .payload])
            let aslRecorder = ASLLogRecorder(formatter: formatter, echoToStdErr: true)
            let severity: LogSeverity = LogSeverity(rawValue: UserDefaults.standard.integer(forKey: AppDelegate.logLevelConfigurationKey)) ?? .info
            Log.enable(configuration: BasicLogConfiguration(minimumSeverity: severity, recorders: [aslRecorder]))
        #endif
        
        if #available(OSX 10.12, *) {
            NSWindow.allowsAutomaticWindowTabbing = true
        }
        
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
//        let fs = try! SftpFileSystem(name: "SFTP", host: "286840.s.dedikuoti.lt", user: "giedrius", password: "gargantuki", path: "/")
//        newBrowserWindow(with: fs)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    
    // MARK: BrowserWindowControllerDelegate
    
    func browserWindowWillClose(_ controller: BrowserWindowController) {
        guard let index = self.browserWindowControllers.index(of: controller) else { return }
        self.browserWindowControllers.remove(at: index)
    }
    
    
    // MARK: Actions
    
    @IBAction func newWindow(_ sender: Any?) {
        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
        newBrowserWindow(with: controller.fileSystem)
    }
    
    @IBAction func newTab(_ sender: Any?) {
        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
        let newController = newBrowserWindow(with: controller.fileSystem)
        if #available(OSX 10.12, *) {
            if let newWindow = newController.window {
                controller.window?.addTabbedWindow(newWindow, ordered: .above)
            }
        }
    }
    
    @IBAction func closeTabGroup(_ sender: Any?) {
        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
        if #available(OSX 10.12, *) {
            controller.window?.tabbedWindows?.forEach { $0.close() }
        }
        else {
            controller.window?.close()
        }
    }
    
    @IBAction func close(_ sender: Any?) {
        guard let controller = self.keyBrowserWindowController else { NSBeep(); return }
        controller.window?.close()
    }
    
    
    // MARK: Menu
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
        case MenuItemTags.newWindow: return keyBrowserWindowController != nil
        case MenuItemTags.newTab:
            if #available(OSX 10.12, *) {
                menuItem.isHidden = false
            }
            else {
                menuItem.isHidden = true
            }
            return keyBrowserWindowController != nil
        case MenuItemTags.closeTabGroup:
            let available = isWindowTabbed(keyBrowserWindowController?.window)
            menuItem.isHidden = !available
            return available
        case MenuItemTags.close:
            let controller = keyBrowserWindowController
            menuItem.title = isWindowTabbed(controller?.window) ? NSLocalizedString("Close Tab", comment: "menu item") : NSLocalizedString("Close Window", comment: "menu item")
            return keyBrowserWindowController != nil
        default: return false
        }
    }

    
    // MARK: Private
    
    @discardableResult private func newBrowserWindow(with fileSystem: FileSystem) -> BrowserWindowController {
        let windowController = BrowserWindowController(fileSystem: fileSystem)
        windowController.delegate = self
        browserWindowControllers.append(windowController)
        return windowController
    }
    
    private func isWindowTabbed(_ window: NSWindow?) -> Bool {
        if #available(OSX 10.12, *) {
            return (window?.tabbedWindows?.count ?? 0) > 1
        } else {
            return false
        }
    }
    
    @objc func handleGetURLEvent(_ event:NSAppleEventDescriptor, withReplyEvent replyEvent:NSAppleEventDescriptor) {
        guard let directObject = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { Log.info?.message("Failed to read direct object string value from getURL Apple event."); return }
        guard let url = URL(string: directObject) else { Log.info?.message("Failed to initialize URL from string."); return }
        
        let qtnpKeyword = UInt32(0x71746E70)
        if let propertiesData = event.paramDescriptor(forKeyword: qtnpKeyword)?.data {
            do {
                let properties = try PropertyListSerialization.propertyList(from: propertiesData, options: [], format: nil)
                print("\(properties)")
            }
            catch {
                print("\(error)")
            }
        }
        
        open(url)
    }
    
    private func open(_ url: URL) {
        guard let scheme = url.scheme else { Log.info?.message("Input URL expected to contain valid scheme part."); return }
        
        switch scheme {
        case "sftp":
            guard let host = url.host else { Log.info?.message("Input URL expected to contain valid host part."); return }
            guard let user = url.user else { Log.info?.message("Input URL expected to contain valid user part - anonymous not supported."); return }
            guard let password = url.password else { Log.info?.message("Input URL expected to contain valid password part - anonymous not supported."); return }
            let name = url.fragment ?? host
            let port: UInt16? = (url.port != nil) ? UInt16(url.port!) : nil
            let path = url.path
            guard let fs = try? SftpFileSystem(name: name, host: host, port: port, user: user, password: password, path: path) else { Log.info?.message("Failed to connect to SFTP at URL [\(url)]"); return }
            newBrowserWindow(with: fs)
        default:
            Log.info?.message("Unsupported URL scheme: \(scheme)")
        }
    }
}
