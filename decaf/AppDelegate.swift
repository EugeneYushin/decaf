import Cocoa
import IOKit.pwr_mgt

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var assertionID: IOPMAssertionID = 0
    var isCaffeinated = false
    var timeoutTimer: Timer?
    var timeoutDuration: TimeInterval? = nil
    var timeoutEndDate: Date? = nil
    let ENABLE_TAG: Int = 100
    // var currentIconName: String? = nil

    var useScreenAssertion = true

    var currentAssertionType: CFString {
        (useScreenAssertion ? kIOPMAssertionTypeNoDisplaySleep : kIOPMAssertionTypePreventSystemSleep) as CFString
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenu()
        updateStatusIcon()
    }

    func setupMenu() {
        let menu = NSMenu()

        let enableItem = NSMenuItem(title: "Enable", action: #selector(toggleCaffeinate), keyEquivalent: "e")
        enableItem.target = self
        enableItem.tag = ENABLE_TAG
        menu.addItem(enableItem)

        let enable60Item = NSMenuItem(title: "Enable for next hour", action: #selector(enable60Minutes), keyEquivalent: "")
        enable60Item.target = self
        menu.addItem(enable60Item)

        let customItem = NSMenuItem(title: "Custom", action: #selector(enableCustomTimer), keyEquivalent: "")
        customItem.target = self
        menu.addItem(customItem)

        menu.addItem(NSMenuItem.separator())

        let toggleScreenItem = NSMenuItem(title: "Keep screen awake", action: #selector(toggleScreenAssertion), keyEquivalent: "")
        toggleScreenItem.target = self
        toggleScreenItem.image = circularImage(named: "display", isActive: useScreenAssertion)
        menu.addItem(toggleScreenItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }
    
@objc func toggleCaffeinate() {
        if isCaffeinated {
            // disable assertion here
            stopAssertion()
            updateStatusIcon()
        } else {
            // enable assertion here
            enableNoTimer()
        }
    }

    func circularImage(named systemName: String, isActive: Bool, size: NSSize = NSSize(width: 24, height: 24)) -> NSImage? {
        // draw circle + background
        let image = NSImage(size: size)
        image.lockFocus()
        
        let bounds = NSRect(origin: .zero, size: size)
        
        // Background circle
        if isActive {
            NSColor.systemBlue.setFill()
        } else {
            NSColor(calibratedWhite: 0.75, alpha: 1).setFill()
        }
        NSBezierPath(ovalIn: bounds).fill()
        
        let symbolRect = bounds.insetBy(dx: 6, dy: 6)
        
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .heavy)
        if let symbolImage = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) {

            // Tint the image white
            let tintImage = symbolImage.copy() as! NSImage
            tintImage.isTemplate = false  // Required to respect tint color
            tintImage.lockFocus()
            if isActive {
                NSColor.white.set()
            } else {
                NSColor.darkGray.set()
            }
            
            let imageRect = NSRect(origin: .zero, size: tintImage.size)
            imageRect.fill(using: .sourceAtop)
            tintImage.unlockFocus()

            // Set the tinted image
            tintImage.draw(in: symbolRect, from: .zero, operation: .sourceAtop, fraction: 1)
        }
        
        image.unlockFocus()
        image.isTemplate = false
        
        return image
    }

    @objc func enableNoTimer() {
        timeoutDuration = nil
        startAssertion()
    }

    @objc func enable60Minutes() {
        timeoutDuration = 60 * 60
        startAssertion()
    }

    @objc func enableCustomTimer() {
        let alert = NSAlert()
        alert.messageText = "Set Timeout (in minutes)"
        alert.informativeText = "Enter how many minutes to stay awake:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputField.placeholderString = "60"
        alert.accessoryView = inputField

        if alert.runModal() == .alertFirstButtonReturn {
            if let minutes = Double(inputField.stringValue), minutes > 0 {
                timeoutDuration = minutes * 60
                startAssertion()
            }
        }
    }

    @objc func toggleScreenAssertion(_ sender: NSMenuItem) {
        useScreenAssertion.toggle()
        sender.image = circularImage(named: "display", isActive: useScreenAssertion)

        if isCaffeinated {
            restartAssertionKeepingTimer()
        }
        // updateStatusIcon()
    }

    func startAssertion() {
        stopAssertion()

        let result = IOPMAssertionCreateWithName(
            currentAssertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "eyushin - Prevent sleep from decaf" as CFString,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isCaffeinated = true
            if let timeout = timeoutDuration {
                timeoutEndDate = Date().addingTimeInterval(timeout)
                timeoutTimer = Timer.scheduledTimer(timeInterval: timeout,
                                                    target: self,
                                                    selector: #selector(timeoutReached),
                                                    userInfo: nil,
                                                    repeats: false)
            } else {
                timeoutEndDate = nil
                timeoutTimer?.invalidate()
                timeoutTimer = nil
            }
        }

        updateStatusIcon()
    }

    func stopAssertion() {
        if isCaffeinated {
            IOPMAssertionRelease(assertionID)
            isCaffeinated = false
        }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        timeoutEndDate = nil
    }

    func restartAssertionKeepingTimer() {
        guard isCaffeinated else {
            startAssertion()
            return
        }
        IOPMAssertionRelease(assertionID)

        let result = IOPMAssertionCreateWithName(
            currentAssertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Prevent sleep" as CFString,
            &assertionID
        )
        if result != kIOReturnSuccess {
            isCaffeinated = false
            timeoutTimer?.invalidate()
            timeoutTimer = nil
            timeoutEndDate = nil
            return
        }
    }

    @objc func timeoutReached() {
        stopAssertion()
        updateStatusIcon()
    }

    func updateStatusIcon() {
        if let menuItem = statusItem.menu?.item(withTag: ENABLE_TAG) {
            menuItem.title = isCaffeinated ? "Disable" : "Enable"
        }

        let iconName = isCaffeinated ? "cup.and.heat.waves" : "cup.and.saucer"
        
        animateStatusBarIconChange(to: iconName)
    }
    
    @objc func quitApp() {
        // Remove assertions or cleanup here if needed
        stopAssertion()
        NSApplication.shared.terminate(nil)
    }
    
    func animateStatusBarIconChange(to iconName: String) {
        guard let button = statusItem.button else { return }
        // return if new image equals to the current one
        // if currentIconName == iconName { return }
        // currentIconName = iconName
        
        guard let newImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) else { return }
        newImage.isTemplate = true
        
        // Create a fade transition
        let transition = CATransition()
        transition.type = .moveIn
        transition.duration = 0.3
        
        // Add the transition animation to the button's layer
        button.wantsLayer = true
        button.layer?.add(transition, forKey: "fadeTransition")
        
        // Swap the image
        button.image = newImage
    }

}
