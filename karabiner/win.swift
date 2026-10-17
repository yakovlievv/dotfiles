// Resize the frontmost window on the screen it's on. Called from gen.py binds.
//   win maximize   cover the whole screen (minus menu bar and Dock)
//   win almost     90% of the screen, centered, floating
// Talks to the Accessibility API directly, so it's instant (the old win.js
// went through System Events and took ~0.3s).
// Build: swiftc -O ~/dotfiles/karabiner/win.swift -o ~/dotfiles/karabiner/bin/win
import AppKit
import ApplicationServices

let almost: CGFloat = 0.9

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
}

func set(_ el: AXUIElement, _ name: String, _ value: CFTypeRef) {
    AXUIElementSetAttributeValue(el, name as CFString, value)
}

let mode = CommandLine.arguments.dropFirst().first ?? ""
guard mode == "almost" || mode == "maximize" else { fail("usage: win almost|maximize") }

guard AXIsProcessTrusted() else { fail("not allowed Accessibility access") }
// the system-wide AXFocusedApplication is unreliable from background processes
guard let front = NSWorkspace.shared.frontmostApplication else { fail("no frontmost app") }
var pid = front.processIdentifier
// Apps started through a launcher script (Emacs.app execs Emacs-arm64-11) report
// pid -1 here; fall back to the owner of the frontmost on-screen window.
if pid <= 0 {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
    let top = windows.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
    guard let owner = top?[kCGWindowOwnerPID as String] as? pid_t else { fail("no frontmost window") }
    pid = owner
}
let app = AXUIElementCreateApplication(pid)
guard let winRef = attr(app, kAXFocusedWindowAttribute) ?? attr(app, kAXMainWindowAttribute) else {
    fail("no focused window")
}
let win = winRef as! AXUIElement

var pos = CGPoint.zero
var size = CGSize.zero
if let v = attr(win, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &pos) }
if let v = attr(win, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &size) }

// NSScreen frames start at the bottom-left of the primary screen,
// AX positions at its top-left.
let screens = NSScreen.screens
guard let primary = screens.first else { fail("no screens") }
let primaryH = primary.frame.height
let center = CGPoint(x: pos.x + size.width / 2, y: primaryH - (pos.y + size.height / 2))
let vis = (screens.first { $0.frame.contains(center) } ?? primary).visibleFrame

var frame = CGRect(x: vis.minX, y: primaryH - vis.maxY, width: vis.width, height: vis.height)
if mode == "almost" {
    frame = frame.insetBy(dx: frame.width * (1 - almost) / 2, dy: frame.height * (1 - almost) / 2)
}

// Chrome/Electron apps animate AX resizes while AXEnhancedUserInterface is on.
let enhanced = "AXEnhancedUserInterface"
let wasEnhanced = (attr(app, enhanced) as? Bool) ?? false
if wasEnhanced { set(app, enhanced, kCFBooleanFalse) }

var newSize = frame.size
var newPos = frame.origin
let sizeValue = AXValueCreate(.cgSize, &newSize)!
// size, move, size again: some apps clamp the size to the old position
set(win, kAXSizeAttribute, sizeValue)
set(win, kAXPositionAttribute, AXValueCreate(.cgPoint, &newPos)!)
set(win, kAXSizeAttribute, sizeValue)

if wasEnhanced { set(app, enhanced, kCFBooleanTrue) }
