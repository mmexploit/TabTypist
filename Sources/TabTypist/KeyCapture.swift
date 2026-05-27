import ApplicationServices
import AppKit
import Carbon.HIToolbox
import Foundation

// CGEventTap for Tab and Escape.  Tab accepts the current completion; Escape dismisses it.
final class KeyCapture: @unchecked Sendable {
    static let shared = KeyCapture()

    private var eventTap: CFMachPort?
    private(set) var completionIsVisible: Bool = false
    private var pendingCompletionText: String = ""

    func setCompletion(_ text: String) {
        pendingCompletionText = text
        completionIsVisible = !text.isEmpty
    }

    func clearCompletion() {
        pendingCompletionText = ""
        completionIsVisible = false
    }

    func start() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let capture = Unmanaged<KeyCapture>.fromOpaque(refcon).takeUnretainedValue()
                return capture.handleEvent(event)
            },
            userInfo: selfPtr
        )

        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            fputs("TabTypistSidecar: failed to create CGEventTap — Input Monitoring permission needed\n", stderr)
        }
    }

    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case Int64(kVK_Tab):
            if completionIsVisible {
                let text = pendingCompletionText
                clearCompletion()
                insertCompletion(text)
                IPCBridge.shared.notify(method: "acceptCompletion", params: [:])
                return nil // consume the event
            }
            return Unmanaged.passRetained(event) // pass through when no completion

        case Int64(kVK_Escape):
            if completionIsVisible {
                clearCompletion()
                IPCBridge.shared.notify(method: "dismissCompletion", params: [:])
            }
            return Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }

    // Insert completion text into the focused field via AX setValue.
    private func insertCompletion(_ text: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appRef, kAXFocusedUIElementAttribute as CFString, &focusedElement
        ) == .success else { return }
        let element = focusedElement as! AXUIElement

        // Get current value
        var currentValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue) == .success,
              let current = currentValue as? String
        else { return }

        // Get caret position
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success,
              let rv = rangeValue
        else { return }

        var cfRange = CFRange()
        guard AXValueGetValue(rv as! AXValue, .cfRange, &cfRange) else { return }

        let caretPos = cfRange.location
        let newText = String(current.prefix(caretPos)) + text + String(current.dropFirst(caretPos))
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newText as CFTypeRef)

        // Move caret to end of inserted text
        let newPos = caretPos + text.count
        var newRange = CFRangeMake(newPos, 0)
        if let axRange = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, axRange
            )
        }
    }
}
