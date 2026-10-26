import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Model

struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
    var pinned = false
}

// MARK: - Store (watches the clipboard, persists history)

final class ClipStore: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var paused = false

    private let maxUnpinned = 200
    private let fileURL: URL
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if paused { return }

        // Skip things password managers mark as secret/temporary.
        let types = pb.types?.map { $0.rawValue } ?? []
        if types.contains("org.nspasteboard.ConcealedType") ||
            types.contains("org.nspasteboard.TransientType") { return }

        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        add(s)
    }

    private func add(_ s: String) {
        if let idx = items.firstIndex(where: { $0.text == s }) {
            var it = items.remove(at: idx)
            it.date = Date()
            items.insert(it, at: 0)
        } else {
            items.insert(ClipItem(text: s), at: 0)
        }
        trim()
        save()
    }

    private func trim() {
        var count = 0
        items = items.filter { item in
            if item.pinned { return true }
            count += 1
            return count <= maxUnpinned
        }
    }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastChange = pb.changeCount
        add(item.text) // moves it to the top
    }

    func togglePin(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear(keepPinned: Bool) {
        items = keepPinned ? items.filter { $0.pinned } : []
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ClipboardBar: save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = decoded
    }
}

// MARK: - Views

struct RowView: View {
    let item: ClipItem
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    private static let relative = RelativeDateTimeFormatter()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(item.text.prefix(300)))
                        .font(.system(size: 12.5))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Self.relative.localizedString(for: item.date, relativeTo: Date()))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 8) {
                Button(action: onPin) {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                        .foregroundColor(item.pinned ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.pinned ? "Unpin" : "Pin")

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hover ? Color.primary.opacity(0.08) : Color.clear)
        .onHover { hover = $0 }
    }
}

struct ContentView: View {
    @ObservedObject var store: ClipStore
    var paste: () -> Void

    @State private var query = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @FocusState private var searchFocused: Bool

    private var shown: [ClipItem] {
        let filtered = query.isEmpty
            ? store.items
            : store.items.filter { $0.text.localizedCaseInsensitiveContains(query) }
        return filtered.filter { $0.pinned } + filtered.filter { !$0.pinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search clipboard history", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            Divider()

            if shown.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard").font(.system(size: 28)).foregroundColor(.secondary)
                    Text(store.items.isEmpty ? "Nothing copied yet" : "No matches")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { item in
                            RowView(
                                item: item,
                                onCopy: { store.copy(item); paste() },
                                onPin: { store.togglePin(item) },
                                onDelete: { store.delete(item) }
                            )
                            Divider()
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()

                Button { store.paused.toggle() } label: {
                    Image(systemName: store.paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.plain)
                .help(store.paused ? "Resume recording" : "Pause recording")

                Menu {
                    Button("Clear unpinned") { store.clear(keepPinned: true) }
                    Button("Clear everything") { store.clear(keepPinned: false) }
                } label: {
                    Image(systemName: "trash")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Clear history")

                Menu {
                    Button(launchAtLogin ? "✓ Launch at login" : "Launch at login") {
                        do {
                            if launchAtLogin { try SMAppService.mainApp.unregister() }
                            else { try SMAppService.mainApp.register() }
                        } catch {
                            NSLog("ClipboardBar: login item change failed: \(error)")
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                    Text("Open shortcut: ⌃⌥V")
                    Divider()
                    Button("Quit ClipboardBar") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 360, height: 480)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipStore()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var hotKeyRef: EventHotKeyRef?
    var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "Clipboard history")
            button.target = self
            button.action = #selector(toggle)
        }

        popover.behavior = .transient   // closes when you click elsewhere or press Esc
        popover.contentSize = NSSize(width: 360, height: 480)

        registerHotKey()
    }

    @objc func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    private func show() {
        guard let button = statusItem.button else { return }

        // Remember which app you were typing in, so we can paste back into it.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        popover.contentViewController = NSHostingController(
            rootView: ContentView(store: store, paste: { [weak self] in
                self?.pasteIntoPreviousApp()
            })
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    // Close the popup, return focus to the previous app, and press Cmd+V for you.
    // Needs the Accessibility permission (macOS asks the first time).
    private func pasteIntoPreviousApp() {
        popover.performClose(nil)

        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            // Text is already on the clipboard; user can press Cmd+V manually.
            return
        }

        previousApp?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.sendCommandV()
        }
    }

    private func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // Global shortcut: Control + Option + V
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let id = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // Menu-bar apps have no Edit menu by default, which breaks Cmd+V in the search box.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem())
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
