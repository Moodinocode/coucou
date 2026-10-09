import Foundation
import SwiftUI
import Combine


@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Island state
    @Published var mode: IslandMode = .hidden
    @Published var view: IslandView = .overview

    // Tasks
    @Published var tasks: [AgentTask] = []
    @Published var focusId: String? = nil

    // Bot state override
    @Published var stateOverride: BotState? = nil

    // Real notch dimensions (set by IslandWindowController on launch)
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight
    var hasNotch = true

    // Last app active before NotchBuddy (for window context capture)
    var lastExternalApp: NSRunningApplication? = nil

    // Bot drag-attach state (hides original bot while ghost follows cursor)
    @Published var isDraggingBot: Bool = false

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var lastMouseMove: Date = .now
    var lastActivity: Date = .now
    var isPresent: Bool = true

    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false

    // Upload progress (0-1) — set to 1.0 only at completion; animation is time-based
    @Published var uploadProgress: Double = 0

    // Upload animation timing (non-published — TimelineViews read these directly)
    var uploadStartTime: Date?
    var uploadDuration: Double = 2.4

    // File drag-over state (mailbox morph glow + mouth spring)
    @Published var fileDragOver: Bool = false

    // Sound enabled — persisted
    @Published var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    // Claude model used by the chat and the search — persisted
    static let defaultClaudeModel = "claude-sonnet-4-6"
    @Published var claudeModel: String = AppState.defaultClaudeModel {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    // In-chat provider + model — picked via the model selector in the prompt view
    @Published var chatProvider: ChatProvider = .anthropic {
        didSet { UserDefaults.standard.set(chatProvider.rawValue, forKey: "chatProvider") }
    }
    @Published var googleChatModel: String = ChatProvider.google.defaultModel {
        didSet { UserDefaults.standard.set(googleChatModel, forKey: "googleChatModel") }
    }
    @Published var openAIChatModel: String = ChatProvider.openai.defaultModel {
        didSet { UserDefaults.standard.set(openAIChatModel, forKey: "openAIChatModel") }
    }

    // The always-on workspace pill (default: VS Code). Persisted.
    @Published var mainPillId: String = PillCatalog.defaultMainPillId {
        didSet {
            UserDefaults.standard.set(mainPillId, forKey: "mainPill")
            writeThroughToCurrentMode()
        }
    }

    // Dynamically fetched model lists for the in-chat picker (keyed by provider)
    @Published var fetchedProviderModels: [ChatProvider: [(id: String, label: String)]] = [:]
    @Published var providerModelFetchError: [ChatProvider: String] = [:]
    @Published var loadingProviderModels: Set<ChatProvider> = []

    /// Fetches models for `provider` if not already loaded or loading.
    /// Sets `providerModelFetchError` if the key is absent or the request fails.
    func fetchModelsIfNeeded(for provider: ChatProvider) {
        guard !loadingProviderModels.contains(provider),
              fetchedProviderModels[provider] == nil else { return }
        guard let apiKey = KeychainStore.shared.get(provider.keychainKey), !apiKey.isEmpty else {
            providerModelFetchError[provider] = "No API key — add it in Settings."
            return
        }
        loadingProviderModels.insert(provider)
        providerModelFetchError.removeValue(forKey: provider)
        Task {
            let models: [(id: String, label: String)]
            switch provider {
            case .anthropic: models = await ClaudeService.fetchModels(apiKey: apiKey)
            case .google:    models = await ClaudeService.fetchGoogleModels(apiKey: apiKey)
            case .openai:    models = await ClaudeService.fetchOpenAIModels(apiKey: apiKey)
            }
            loadingProviderModels.remove(provider)
            if models.isEmpty {
                providerModelFetchError[provider] = "Failed to load models. Check your API key."
            } else {
                fetchedProviderModels[provider] = models
                // If the saved model isn't in the fetched list, pick a sensible default:
                // prefer "sonnet" (Anthropic), "flash" (Google), "mini" (OpenAI); else first.
                switch provider {
                case .anthropic:
                    if !models.contains(where: { $0.id == claudeModel }) {
                        claudeModel = models.first(where: { $0.id.contains("sonnet") })?.id ?? models.first!.id
                    }
                case .google:
                    if !models.contains(where: { $0.id == googleChatModel }) {
                        googleChatModel = models.first(where: { $0.id.contains("flash") })?.id ?? models.first!.id
                    }
                case .openai:
                    if !models.contains(where: { $0.id == openAIChatModel }) {
                        openAIChatModel = models.first(where: { $0.id.contains("mini") })?.id ?? models.first!.id
                    }
                }
            }
        }
    }

    /// The model currently active for chat (provider-aware).
    var activeChatModel: String {
        switch chatProvider {
        case .anthropic: return claudeModel
        case .google:    return googleChatModel
        case .openai:    return openAIChatModel
        }
    }

    // Sound volume (0–0.2) — persisted, synced to SoundEngine
    @Published var soundVolume: Double = 0.12 {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
            SoundEngine.shared.volume = Float(soundVolume)
        }
    }

    // Context for prompt (window attach / file)
    @Published var promptContext: PromptContext? = nil

    // Dropped file (set during upload flow)
    @Published var droppedFile: DroppedFile? = nil

    // Short note message (shown in NoteView)
    @Published var noteMessage: String? = nil

    // Auto-close delay — persisted
    @Published var autoCloseInterval: TimeInterval = 15 {
        didSet { UserDefaults.standard.set(autoCloseInterval, forKey: "autoCloseInterval") }
    }

    // Absence interval — persisted
    var absenceInterval: TimeInterval = 3 * 60 {
        didSet { UserDefaults.standard.set(absenceInterval, forKey: "absenceInterval") }
    }

    // Greeting threshold — how long hidden before greeting on reappear (default 2 min)
    var greetThresholdSeconds: TimeInterval = 120 {
        didSet { UserDefaults.standard.set(greetThresholdSeconds, forKey: "greetThreshold") }
    }

    // Hotkey to show island (e.g. ⌘⇧N)
    @Published var hotkeyEnabled: Bool = false {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    var hotkeyFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue {
        didSet { UserDefaults.standard.set(Int(hotkeyFlags), forKey: "hotkeyFlags") }
    }
    var hotkeyCode: UInt16 = 45 {  // 'n'
        didSet { UserDefaults.standard.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }

    // Hotkey to cycle pill modes (default ⌃⌥M)
    @Published var modeHotkeyEnabled: Bool = false {
        didSet { UserDefaults.standard.set(modeHotkeyEnabled, forKey: "modeHotkeyEnabled") }
    }
    var modeHotkeyFlags: UInt = NSEvent.ModifierFlags([.control, .option]).rawValue {
        didSet { UserDefaults.standard.set(Int(modeHotkeyFlags), forKey: "modeHotkeyFlags") }
    }
    var modeHotkeyCode: UInt16 = 46 {  // 'm'
        didSet { UserDefaults.standard.set(Int(modeHotkeyCode), forKey: "modeHotkeyCode") }
    }

    // Vercel project filter — empty = watch all projects
    @Published var vercelProjectFilter: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(vercelProjectFilter)) {
                UserDefaults.standard.set(data, forKey: "vercelProjectFilter")
            }
        }
    }

    // n8n workflow filter — empty = watch all workflows
    @Published var n8nWorkflowFilter: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(n8nWorkflowFilter)) {
                UserDefaults.standard.set(data, forKey: "n8nWorkflowFilter")
            }
        }
    }

    // Active integration pills (main workspace pill excluded). Max 4.
    @Published var activeIntegrations: Set<String> = ["integration_resend", "integration_n8n", "integration_vercel", "integration_github"] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(activeIntegrations)) {
                UserDefaults.standard.set(data, forKey: "activeIntegrations")
            }
            writeThroughToCurrentMode()
        }
    }

    // User-defined pills (IntelliJ projects, links)
    @Published var customPills: [CustomPill] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(customPills) {
                UserDefaults.standard.set(data, forKey: "customPills")
            }
            syncCustomPillTasks()
        }
    }

    // Pill modes: named presets of active pills + main pill. The live properties mirror the current one.
    @Published var pillModes: [PillMode] = [] {
        didSet { savePillModes() }
    }
    @Published var currentPillModeId: String = "" {
        didSet { UserDefaults.standard.set(currentPillModeId, forKey: "currentModeId") }
    }
    private var isApplyingPillMode = false

    // Pending API result
    @Published var searchResult: SearchResult? = nil

    // Vercel deployments (populated by VercelPoller)
    @Published var vercelDeployments: [VercelDeployment] = []

    // Resend emails (populated by ResendPoller)
    @Published var resendEmails: [ResendEmail] = []
    @Published var resendTotal: Int? = nil

    // GitHub stats (populated by GithubPoller)
    @Published var githubStats: GitHubStats? = nil

    // Stripe (populated by StripePoller)
    @Published var stripePayments: [StripePayment] = []
    @Published var stripeBalance: Int = 0           // raw balance in cents
    @Published var stripeDisplayBalance: Int = 0    // animated balance target
    @Published var stripeCurrency: String = "eur"
    @Published var stripeLoaded: Bool = false       // true after first successful poll
    @Published var stripeError: String? = nil      // last API error (nil = ok)

    // Cal.com (populated by CalcomPoller)
    @Published var calcomBookings: [CalcomBooking] = []
    @Published var calcomLoaded: Bool = false
    @Published var calcomError: String? = nil

    // Notion (populated by NotionPoller)
    @Published var notionPages: [NotionPage] = []
    @Published var notionLoaded: Bool = false
    @Published var notionError: String? = nil

    // Chat conversation history
    @Published var chatHistory: [ChatMessage] = []

    // Pending approval request from Claude Code hook
    @Published var pendingApproval: ApprovalInfo? = nil

    // MARK: - Init (loads persisted settings)

    private init() {
        let ud = UserDefaults.standard

        if let v = ud.object(forKey: "soundEnabled") as? Bool   { soundEnabled = v }
        if let v = ud.object(forKey: "soundVolume")  as? Double { soundVolume  = v }
        if let v = ud.string(forKey: "claudeModel"),
           !v.trimmingCharacters(in: .whitespaces).isEmpty { claudeModel = v }
        if let v = ud.string(forKey: "chatProvider"), let p = ChatProvider(rawValue: v) { chatProvider = p }
        if let v = ud.string(forKey: "googleChatModel"), !v.isEmpty { googleChatModel = v }
        if let v = ud.string(forKey: "openAIChatModel"), !v.isEmpty { openAIChatModel = v }
        // Migrate old 60s default → 15s
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
            autoCloseInterval = (v == 60) ? 15 : v
        }
        if let v = ud.object(forKey: "absenceInterval")   as? Double { absenceInterval   = v }
        if let v = ud.object(forKey: "greetThreshold")    as? Double { greetThresholdSeconds = v }
        if let v = ud.object(forKey: "hotkeyEnabled") as? Bool  { hotkeyEnabled = v }
        if let v = ud.object(forKey: "hotkeyFlags")   as? Int   { hotkeyFlags = UInt(v) }
        if let v = ud.object(forKey: "hotkeyCode")    as? Int   { hotkeyCode = UInt16(v) }
        if let v = ud.object(forKey: "modeHotkeyEnabled") as? Bool { modeHotkeyEnabled = v }
        if let v = ud.object(forKey: "modeHotkeyFlags")   as? Int  { modeHotkeyFlags = UInt(v) }
        if let v = ud.object(forKey: "modeHotkeyCode")    as? Int  { modeHotkeyCode = UInt16(v) }
        if let d = ud.data(forKey: "vercelProjectFilter"),
           let a = try? JSONDecoder().decode([String].self, from: d) { vercelProjectFilter = Set(a) }
        if let d = ud.data(forKey: "n8nWorkflowFilter"),
           let a = try? JSONDecoder().decode([String].self, from: d) { n8nWorkflowFilter = Set(a) }
        if let d = ud.data(forKey: "activeIntegrations"),
           let a = try? JSONDecoder().decode([String].self, from: d) { activeIntegrations = Set(a) }
        // Custom pills first: the saved main pill may be one of them.
        if let d = ud.data(forKey: "customPills"),
           let a = try? JSONDecoder().decode([CustomPill].self, from: d) { customPills = a }
        if let v = ud.string(forKey: "mainPill"), !v.isEmpty, isValidMainPill(v) {
            mainPillId = v
        }
        loadOrMigratePillModes()

        // Sync SoundEngine volume on launch
        SoundEngine.shared.volume = Float(soundVolume)

        // Always load integration pills
        loadIntegrationTasks()
    }

    // MARK: - Computed

    var focusTask: AgentTask? {
        tasks.first { $0.id == focusId } ?? tasks.first
    }

    var effectiveState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

    // MARK: - Task management

    func addTask(_ task: AgentTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        if focusId == nil { focusId = task.id }
        syncMode()
        syncView()
    }

    func removeTask(id: String) {
        // mainPillId: always reset, never remove (the active workspace tool)
        // activeIntegrations: also reset (user declared it active, keep it as idle)
        let isProtected = id == mainPillId
        let isActiveDecl = pillDefinition(for: id) != nil && activeIntegrations.contains(id)
        if isProtected || isActiveDecl {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                let catalogName = pillDefinition(for: id)?.name
                tasks[idx].state      = .idle
                tasks[idx].steps      = []
                tasks[idx].stepIndex  = 0
                tasks[idx].pillBadge  = nil
                if let n = catalogName { tasks[idx].name = n }
            }
            return
        }
        // Undeclared or declared-but-not-active: remove
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = mainPillId }
        syncMode()
        syncView()
    }

    func updateTask(id: String, state: BotState) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].state = state
    }

    func setFocus(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        focusId = id
        tasks[idx].pillBadge = nil  // clear badge when user brings task to focus
    }

    func syncMode() {
        // If no tasks and not expanded/peek, go hidden
        if tasks.isEmpty && mode == .compact {
            mode = .hidden
        } else if !tasks.isEmpty && mode == .hidden && isPresent {
            mode = .compact
        }
    }

    func syncView() {
        guard mode == .expanded else { return }
        if view == .empty && !tasks.isEmpty { view = .overview }
        else if view == .overview && tasks.isEmpty { view = .empty }
    }

    /// Load catalog pills into tasks, respecting activeIntegrations. Safe to call multiple times.
    func loadIntegrationTasks() {
        let catalog = availablePills
        // Sanitize: remove saved IDs not in catalog
        let catalogIds = Set(catalog.map { $0.id })
        activeIntegrations = activeIntegrations.filter { catalogIds.contains($0) }
        // Validate mainPillId: must be a non-comingSoon workspace pill in the catalog
        if !isValidMainPill(mainPillId) {
            mainPillId = PillCatalog.defaultMainPillId
        }
        // mainPillId must never be in activeIntegrations (migration + invariant)
        activeIntegrations.remove(mainPillId)
        for def in catalog {
            // mainPillId always loads; activeIntegrations load
            let shouldLoad = def.id == mainPillId || activeIntegrations.contains(def.id)
            let loaded = tasks.contains(where: { $0.id == def.id })
            if shouldLoad && !loaded {
                let task = AgentTask(id: def.id, name: def.name, color: def.color,
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
            }
            if !shouldLoad && loaded {
                tasks.removeAll { $0.id == def.id }
            }
        }
        sortTasksByCatalog()
        if focusId == nil { focusId = mainPillId }
        syncMode()
    }

    /// Toggle a catalog pill on/off.
    /// mainPillId: never toggleable (change via the Main picker first).
    /// Max 4 non-main pills active at once.
    func toggleIntegration(_ id: String) {
        guard id != mainPillId else { return }
        guard availablePills.contains(where: { $0.id == id }) else { return }
        if activeIntegrations.contains(id) {
            activeIntegrations.remove(id)
            tasks.removeAll { $0.id == id }
            if focusId == id { focusId = mainPillId }
        } else {
            guard activeIntegrations.count < 4 else { return }
            activeIntegrations.insert(id)
            if let def = availablePills.first(where: { $0.id == id }),
               !tasks.contains(where: { $0.id == id }) {
                let task = AgentTask(id: def.id, name: def.name, color: def.color,
                                     state: .idle, steps: [], source: def.source, isIntegration: true)
                tasks.append(task)
                sortTasksByCatalog()
            }
        }
        syncMode()
    }

    /// Sort tasks so catalog pills are in catalog order, undeclared pills sit right after
    /// integration_claude (matching HookServer insertion behaviour), and the rest follows.
    private func sortTasksByCatalog() {
        let order = availablePills.enumerated()
            .reduce(into: [String: Int]()) { $0[$1.element.id] = $1.offset }
        let catalogPills    = tasks.filter { order[$0.id] != nil }
        let undeclaredPills = tasks.filter { order[$0.id] == nil }
        let sortedCatalog   = catalogPills.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        if let claudeIdx = sortedCatalog.firstIndex(where: { $0.id == "integration_claude" }) {
            var result: [AgentTask] = Array(sortedCatalog[...claudeIdx])
            result.append(contentsOf: undeclaredPills)
            if claudeIdx + 1 < sortedCatalog.count {
                result.append(contentsOf: sortedCatalog[(claudeIdx + 1)...])
            }
            tasks = result
        } else {
            tasks = undeclaredPills + sortedCatalog
        }
    }

    /// Pills that can be the main pill: shipping workspace tools, then the user's custom pills for this build.
    var mainPillCandidates: [PillDefinition] {
        PillCatalog.available.filter { $0.category == .workspace && !$0.comingSoon } + customPillDefinitions
    }

    func isValidMainPill(_ id: String) -> Bool {
        mainPillCandidates.contains(where: { $0.id == id })
    }

    // MARK: - Custom pills

    var customPillDefinitions: [PillDefinition] {
        let kinds = CustomPillKind.availableInBuild
        return customPills.filter { kinds.contains($0.kind) }.map(\.definition)
    }

    /// Catalog pills followed by the user's custom pills.
    var availablePills: [PillDefinition] {
        PillCatalog.available + customPillDefinitions
    }

    func pillDefinition(for id: String) -> PillDefinition? {
        if id.hasPrefix(CustomPill.idPrefix) { return customPill(id: id)?.definition }
        return PillCatalog.definition(for: id)
    }

    func customPill(id: String) -> CustomPill? {
        customPills.first { $0.id == id }
    }

    func addCustomPill(_ pill: CustomPill) {
        guard !customPills.contains(where: { $0.id == pill.id }) else { return }
        customPills.append(pill)
    }

    func deleteCustomPill(id: String) {
        customPills.removeAll { $0.id == id }
    }

    /// Keeps tasks, active pills and every mode consistent with `customPills`. Never writes `customPills`.
    func syncCustomPillTasks() {
        let prefix = CustomPill.idPrefix
        let defs = customPillDefinitions
        let availableIds = Set(defs.map(\.id))

        if mainPillId.hasPrefix(prefix) && !availableIds.contains(mainPillId) {
            mainPillId = PillCatalog.defaultMainPillId
            loadIntegrationTasks()
        }

        let stale = activeIntegrations.filter { $0.hasPrefix(prefix) && !availableIds.contains($0) }
        if !stale.isEmpty { activeIntegrations.subtract(stale) }

        var updated = tasks.filter { !$0.id.hasPrefix(prefix) || availableIds.contains($0.id) }
        for def in defs {
            if let i = updated.firstIndex(where: { $0.id == def.id }) {
                updated[i].name  = def.name
                updated[i].color = def.color
            }
        }
        let tasksChanged = updated != tasks
        if tasksChanged { tasks = updated }
        if let f = focusId, f.hasPrefix(prefix), !tasks.contains(where: { $0.id == f }) {
            focusId = mainPillId
        }

        let allIds = Set(customPills.map(\.id))
        var modes = pillModes
        for i in modes.indices {
            modes[i].activePills.removeAll { $0.hasPrefix(prefix) && !allIds.contains($0) }
            if modes[i].mainPillId.hasPrefix(prefix) && !allIds.contains(modes[i].mainPillId) {
                modes[i].mainPillId = PillCatalog.defaultMainPillId
            }
        }
        if modes != pillModes { pillModes = modes }

        if tasksChanged {
            syncMode()
            syncView()
        }
    }

    // MARK: - Pill modes

    var currentPillMode: PillMode? {
        pillModes.first { $0.id == currentPillModeId }
    }

    func savePillModes() {
        if let data = try? JSONEncoder().encode(pillModes) {
            UserDefaults.standard.set(data, forKey: "modes")
        }
    }

    /// Loads saved modes and applies the current one, or creates "Default" from today's pills.
    private func loadOrMigratePillModes() {
        let ud = UserDefaults.standard
        isApplyingPillMode = true
        defer { isApplyingPillMode = false }
        if let d = ud.data(forKey: "modes"),
           let modes = try? JSONDecoder().decode([PillMode].self, from: d), !modes.isEmpty {
            let savedId = ud.string(forKey: "currentModeId")
            let current = modes.first { $0.id == savedId } ?? modes[0]
            pillModes = modes
            currentPillModeId = current.id
            if isValidMainPill(current.mainPillId) { mainPillId = current.mainPillId }
            activeIntegrations = Set(current.activePills.filter { $0 != mainPillId }.prefix(PillMode.maxActive))
        } else {
            let mode = PillMode(id: PillMode.newID(), name: "Default",
                                activePills: activeIntegrations.subtracting([mainPillId]).sorted(),
                                mainPillId: mainPillId)
            pillModes = [mode]
            currentPillModeId = mode.id
        }
        savePillModes()
        ud.set(currentPillModeId, forKey: "currentModeId")
    }

    /// Saves the live active pills and main pill into the current mode (only when they differ).
    private func writeThroughToCurrentMode() {
        guard !isApplyingPillMode,
              let idx = pillModes.firstIndex(where: { $0.id == currentPillModeId }) else { return }
        var mode = pillModes[idx]
        mode.activePills = activeIntegrations.subtracting([mainPillId]).sorted()
        mode.mainPillId  = mainPillId
        if mode != pillModes[idx] { pillModes[idx] = mode }
    }

    /// Applies a mode. Refused while a permission card is waiting for an answer.
    @discardableResult
    func switchPillMode(to id: String) -> Bool {
        guard pendingApproval == nil, let mode = pillModes.first(where: { $0.id == id }) else { return false }
        guard id != currentPillModeId else { return true }
        isApplyingPillMode = true
        currentPillModeId = id
        if isValidMainPill(mode.mainPillId) { mainPillId = mode.mainPillId }
        activeIntegrations = Set(mode.activePills.filter { $0 != mainPillId }.prefix(PillMode.maxActive))
        isApplyingPillMode = false
        loadIntegrationTasks()
        if let f = focusId, !tasks.contains(where: { $0.id == f }) { focusId = mainPillId }
        return true
    }

    /// Switches to the next mode (wrapping). Returns the new mode, or nil if refused or there's only one.
    @discardableResult
    func cycleToNextPillMode() -> PillMode? {
        guard pillModes.count > 1 else { return nil }
        let idx = pillModes.firstIndex(where: { $0.id == currentPillModeId }) ?? -1
        let next = pillModes[(idx + 1) % pillModes.count]
        return switchPillMode(to: next.id) ? next : nil
    }

    @discardableResult
    func addPillMode(name: String) -> PillMode {
        let mode = PillMode(id: PillMode.newID(), name: name, activePills: [], mainPillId: mainPillId)
        pillModes.append(mode)
        switchPillMode(to: mode.id)
        return mode
    }

    @discardableResult
    func duplicatePillMode(id: String) -> PillMode? {
        guard let source = pillModes.first(where: { $0.id == id }) else { return nil }
        let copy = PillMode(id: PillMode.newID(), name: "\(source.displayName) copy",
                            activePills: source.activePills, mainPillId: source.mainPillId)
        pillModes.append(copy)
        switchPillMode(to: copy.id)
        return copy
    }

    func renamePillMode(id: String, name: String) {
        guard let idx = pillModes.firstIndex(where: { $0.id == id }), pillModes[idx].name != name else { return }
        pillModes[idx].name = name
    }

    /// The last mode can't be deleted. Deleting the current mode switches to a neighbour first.
    func deletePillMode(id: String) {
        guard pillModes.count > 1, let idx = pillModes.firstIndex(where: { $0.id == id }) else { return }
        if id == currentPillModeId {
            let neighbour = pillModes[idx + 1 < pillModes.count ? idx + 1 : idx - 1]
            guard switchPillMode(to: neighbour.id) else { return }
        }
        pillModes.removeAll { $0.id == id }
    }

}

// MARK: - Supporting types

enum PromptContext {
    case window(appName: String, title: String, url: String?)
    case file(name: String, fileURL: URL?)
}

struct DroppedFile {
    var url: URL
    var name: String
}

struct SearchResult {
    var title: String
    var items: [ResultItem]
    var note: String?
}

struct ResultItem {
    var label: String
    var detail: String
    var url: String?
}

// MARK: - Vercel

struct VercelDeployment: Identifiable {
    let id: String
    let projectName: String
    let url: String
    let state: String        // "READY", "ERROR", "CANCELED"
    let createdAt: Date
    let commitMessage: String?
    let branch: String?

    var isSuccess: Bool { state == "READY" }
    var statusLabel: String { isSuccess ? "Ready" : (state == "CANCELED" ? "Canceled" : "Error") }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Resend

struct ResendEmail: Identifiable {
    let id: String
    let to: [String]
    let subject: String
    let createdAt: Date
    let lastEvent: String   // "delivered", "bounced", "complained", "opened", etc.

    var recipientShort: String {
        guard let first = to.first else { return "?" }
        return first.components(separatedBy: "@").first ?? first
    }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
    var isDelivered: Bool { lastEvent == "delivered" }
}

// MARK: - GitHub

struct GitHubStats {
    let totalRepos: Int
    let totalStars: Int
}

// MARK: - Stripe

struct StripePayment: Identifiable, Equatable {
    let id: String
    let amount: Int         // in cents/smallest unit
    let currency: String
    let description: String?
    let createdAt: Date
    let status: String      // "succeeded", "pending", "failed"

    var amountFormatted: String { String(format: "%.2f", Double(amount) / 100.0) }
    var isSuccess: Bool { status == "succeeded" }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Cal.com

struct CalcomBooking: Identifiable, Equatable {
    let id: Int
    let title: String
    let startTime: Date
    let endTime: Date
    let status: String
    let attendeeName: String?
    let attendeeEmail: String?
    let attendeeNotes: String?

    var isActive: Bool { status == "ACCEPTED" || status == "PENDING" }
    var timeLabel: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: startTime)
    }
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: startTime)
        return "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
    }
}

// MARK: - Notion

struct NotionPage: Identifiable {
    let id: String
    let title: String
    let emoji: String?
    let lastEditedAt: Date
    let url: String

    var timeAgo: String {
        let diff = Date().timeIntervalSince(lastEditedAt)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Chat

enum ChatRole { case user, assistant }

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
}
