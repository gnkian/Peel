import SwiftUI

@MainActor final class PeelModel: ObservableObject {
    @Published var demoRestrictionRequested = false
    @Published private(set) var hasImportedSample = false
    let isDemo: Bool
    @Published var queue = QueueState() { didSet { persist() } }
    @Published var followingNames: [String] = []
    @Published var followerNames: [String] = []
    @Published var message = ""
    @Published private(set) var isRestoring = true
    @Published var instagramLoginConfirmed: Bool {
        didSet { if !isDemo { defaults.set(instagramLoginConfirmed, forKey: "peel-instagram-login-confirmed") } }
    }
    @Published var instagramUser: String?
    @Published var excluded: Set<String> = [] { didSet { persistPreferences() } }
    @Published var nonMutualReviewed: Set<String> = [] { didSet { persistPreferences() } }
    @Published var mutualReviewed: Set<String> = [] { didSet { persistPreferences() } }
    @Published var browserMode: ReviewMode = .unfollow
    @Published var browserUsers: [String] = []
    @Published var browserHistory: [String] = []
    @Published var browserIndex = 0
    @Published private(set) var browserRequestID = UUID()
    // Do not decode large Instagram exports synchronously during app launch.
    // Keep saved data untouched until restoration has completed.
    private var restoring = true
    private let defaults: UserDefaults
    private let progressStore: any ProgressStore
    private let session: any InstagramSessionServicing
    private let importer: any ImportServicing
    private let temporaryExports: TemporaryExportStore
    private let writeExport: (Data, URL) throws -> Void
    private var committed = SavedSnapshot.empty
    private var savingBlocked = false
    private var startupID = UUID()
    private var pendingSave: SavedSnapshot?
    private var operationID: UUID?
    private var operationTask: Task<Void, Never>?
    @Published var failure: OperationFailure?
    @Published private(set) var operationState: OperationState = .idle
    private var retryOperation: FileOperation?

    init(demo: Bool = false, defaults: UserDefaults = .standard,
         progressStore: (any ProgressStore)? = nil,
         importer: any ImportServicing = ImportService(),
         session: (any InstagramSessionServicing)? = nil,
         temporaryExports: TemporaryExportStore? = nil,
         writeExport: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.defaults = defaults
        self.progressStore = progressStore ?? DefaultsProgressStore(defaults: defaults)
        self.importer = importer
        self.session = session ?? InstagramSessionService()
        self.writeExport = writeExport
        self.temporaryExports = temporaryExports ?? .shared
        isDemo = demo
        instagramLoginConfirmed = defaults.bool(forKey: "peel-instagram-login-confirmed")
        if demo {
            // Fictional usernames only. No real credentials, exports or user data.
            let unfollow = (1...18).map { "peeldemo_unfollow\($0)" }
            let followers = (1...12).map { "peeldemo_follower\($0)" }
            let mutual = (1...10).map { "peeldemo_mutual\($0)" }
            followingNames = unfollow + mutual
            followerNames = followers + mutual
            queue = QueueState(users: unfollow, following: followingNames.count,
                               followers: followerNames.count, done: Array(unfollow.prefix(7)),
                               mode: "comparison")
            nonMutualReviewed = Set(followers.prefix(4))
            mutualReviewed = Set(mutual.prefix(6))
            excluded = Set(unfollow.suffix(2))
            instagramLoginConfirmed = true
            restoring = false
            isRestoring = false
            committed = snapshot
            return
        }
        reloadSavedData()
    }

    var snapshot: SavedSnapshot {
        SavedSnapshot(queue: queue, preferences: PeelPreferences(
            excluded: excluded.sorted(), nonMutualReviewed: nonMutualReviewed.sorted(),
            mutualReviewed: mutualReviewed.sorted(), followers: followerNames, following: followingNames))
    }

    private func apply(_ state: SavedSnapshot) {
        let wasRestoring = restoring
        restoring = true
        queue = state.queue
        excluded = Set(state.preferences.excluded)
        nonMutualReviewed = Set(state.preferences.nonMutualReviewed)
        mutualReviewed = Set(state.preferences.mutualReviewed ?? [])
        followingNames = state.preferences.following
        followerNames = state.preferences.followers
        restoring = wasRestoring
    }

    @discardableResult
    func reloadSavedData() -> Task<Void, Never> {
        cancelOperation()
        let id = UUID()
        startupID = id
        isRestoring = true
        restoring = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.startupID == id { self.isRestoring = false; self.restoring = false }
            }
            do {
                let bytes = try self.progressStore.read()
                let state = try await Task.detached(priority: .utility) {
                    try DefaultsProgressStore.decode(bytes)
                }.value
                guard self.startupID == id else { return }
                self.apply(state)
                self.committed = state
                self.savingBlocked = false
                self.failure = nil
            } catch {
                guard self.startupID == id else { return }
                self.savingBlocked = true
                self.report(PeelError.corruptSavedData, operation: .startup)
            }
        }
        return task
    }

    private func commit(_ state: SavedSnapshot, recovering: Bool = false) throws {
        guard !savingBlocked || recovering else { throw PeelError.corruptSavedData }
        try SavedStateValidator.validate(state)
        if !isDemo {
            do { try progressStore.save(state) }
            catch { throw PeelError.persistence }
        }
        apply(state)
        committed = state
        savingBlocked = false
        pendingSave = nil
    }

    func report(_ error: Error, operation: FileOperation) {
        guard !(error is CancellationError), (error as? URLError)?.code != .cancelled,
              (error as? CocoaError)?.code != .userCancelled else { return }
        let typed = PeelError.map(error)
        retryOperation = operation
        failure = OperationFailure(error: typed, operation: operation)
        operationState = .failed
    }

    func cancelOperation() {
        startupID = UUID()
        operationID = nil
        operationTask?.cancel()
        operationTask = nil
        if operationState.isRunning { operationState = .idle }
    }

    func retryLastOperation() {
        guard let operation = retryOperation else { return }
        if let date = failure?.error.retryAfter, date > Date() { return }
        failure = nil
        switch operation {
        case .zip(let url):
            if isDemo { importSampleArchive() } else { importZIP(url) }
        case .list(let urls, let kind): importList(urls, kind: kind)
        case .restore(let url): restore(url)
        case .startup: reloadSavedData()
        case .save:
            do { try commit(pendingSave ?? snapshot); operationState = .completed }
            catch { report(error, operation: .save) }
        case .cleanupExports: retryExportCleanup()
        case .chooseZIP, .chooseRestore, .export: break // The presenting screen retries so it can share the returned URL.
        }
    }

    private func perform(_ operation: FileOperation,
                         work: @escaping @MainActor () async throws -> SavedSnapshot) -> Task<Void, Never> {
        cancelOperation()
        let id = UUID()
        operationID = id
        operationState = .running(id)
        failure = nil
        let task = Task { [weak self] in
            do {
                let state = try await work()
                try Task.checkCancellation()
                guard let self, self.operationID == id else { return }
                try self.commit(state, recovering: {
                    if case .restore = operation { return true }
                    return false
                }())
                if self.isDemo, case .zip = operation { self.hasImportedSample = true }
                self.operationState = .completed
                self.operationID = nil
                self.operationTask = nil
                self.message = String(localized: "Operation completed.")
            } catch {
                guard let self, self.operationID == id else { return }
                self.operationID = nil
                self.operationTask = nil
                if error is CancellationError { self.operationState = .idle; return }
                switch operation {
                case .zip: self.message = String(localized: "ZIP import failed: \(error.localizedDescription)")
                case .restore: self.message = String(localized: "Restore failed: \(error.localizedDescription)")
                default: self.message = String(localized: "Import failed: \(error.localizedDescription)")
                }
                self.report(error, operation: operation)
            }
        }
        operationTask = task
        return task
    }
    /// Imports and restores own the list snapshot until they finish or are explicitly cancelled.
    var canEditLists: Bool { !isRestoring && !operationState.isRunning }

    /// Keep number columns aligned across tabs, filters and queue trimming.
    var accountNumberColumnCount: Int { max(queue.users.count, followingNames.count, followerNames.count) }

    var doneSet: Set<String> { Set(queue.done) }
    var remaining: Int {
        let done = doneSet
        return queue.users.filter { !done.contains($0) && !excluded.contains($0) }.count
    }
    /// Exclusions skip automatic review traversal in every relationship list.
    func remainingCount(_ mode: ReviewMode) -> Int {
        switch mode {
        case .unfollow: remaining
        case .followers: reverseUsers.filter { !nonMutualReviewed.contains($0) && !excluded.contains($0) }.count
        case .mutual: mutualUsers.filter { !mutualReviewed.contains($0) && !excluded.contains($0) }.count
        }
    }
    var reverseUsers: [String] { let following = Set(followingNames); return followerNames.filter { !following.contains($0) } }
    var mutualUsers: [String] { let following = Set(followingNames); return followerNames.filter { following.contains($0) } }
    func reviewed(_ mode: ReviewMode) -> Set<String> {
        switch mode { case .unfollow: return doneSet; case .followers: return nonMutualReviewed; case .mutual: return mutualReviewed }
    }
    func markReviewed(_ user: String, mode: ReviewMode) {
        guard canEditLists else { return }
        switch mode {
        case .unfollow: recordReviewed(user)
        case .followers: nonMutualReviewed.insert(user)
        case .mutual: mutualReviewed.insert(user)
        }
    }
    var browserRemaining: Int {
        let done = reviewed(browserMode)
        return browserUsers.filter { !done.contains($0) && !excluded.contains($0) }.count
    }
    var browserReviewedCount: Int {
        let done = reviewed(browserMode)
        return browserUsers.filter { done.contains($0) }.count
    }
    func startBrowser(mode: ReviewMode, at user: String? = nil) {
        guard requireLiveMode(), canEditLists else { return }
        browserMode = mode
        switch mode {
        case .unfollow: browserUsers = queue.users
        case .followers: browserUsers = reverseUsers
        case .mutual: browserUsers = mutualUsers
        }
        browserHistory = []; browserIndex = 0
        let done = reviewed(mode)
        let target = user ?? browserUsers.first(where: { !done.contains($0) && !excluded.contains($0) })
        if let target { browserHistory = [target]; showBrowserUser(target) }
    }
    func showBrowserUser(_ user: String) {
        browserRequestID = UUID()
        instagramUser = user
    }

    func profileDidLoad(_ user: String, requestID: UUID) {
        guard requestID == browserRequestID, instagramUser == user, !isDemo else { return }
        markReviewed(user, mode: browserMode)
    }
    func persistPreferences() { persist() }
    func toggleExclude(_ user: String) {
        guard canEditLists else { return }
        if excluded.contains(user) { excluded.remove(user) } else { excluded.insert(user) }
    }
    func openInBrowser(_ user: String) { guard requireLiveMode() else { return }; startBrowser(mode: .unfollow, at: user) }
    func previousInBrowser() {
        guard canEditLists else { return }
        guard browserIndex > 0, browserHistory.indices.contains(browserIndex - 1) else { return }
        browserIndex -= 1
        showBrowserUser(browserHistory[browserIndex])
    }
    @discardableResult func nextInBrowser() -> Bool {
        guard canEditLists else { return false }
        if browserIndex >= 0, browserIndex < browserHistory.count - 1 {
            browserIndex += 1
            showBrowserUser(browserHistory[browserIndex])
            return true
        }
        let done = reviewed(browserMode)
        guard let user = browserUsers.first(where: { !done.contains($0) && !excluded.contains($0) }) else { return false }
        browserHistory.append(user)
        browserIndex = browserHistory.count - 1
        showBrowserUser(user)
        return true
    }
    func persist() {
        guard !restoring && !isDemo else { return }
        if operationState.isRunning { cancelOperation() }
        let candidate = snapshot
        do { try commit(candidate) }
        catch {
            pendingSave = candidate
            apply(committed)
            report(error, operation: .save)
        }
    }
    func compare() {
        guard canEditLists else { return }
        let followerSet = Set(followerNames)
        let users = followingNames.filter { !followerSet.contains($0) }
        let oldDone = doneSet
        queue = QueueState(users: users, following: followingNames.count, followers: followerNames.count, done: users.filter { oldDone.contains($0) }, mode: "comparison")
        message = users.isEmpty ? String(localized: "Comparison complete: everyone you follow follows you back.") : String(localized: "Found \(users.count) accounts not following back.")
    }
    private func recordReviewed(_ user: String) {
        guard let index = queue.users.firstIndex(of: user) else { return }
        var updated = queue
        if !updated.done.contains(user) { updated.done.append(user) }
        updated.lastOpened = user
        updated.cursor = updated.users.isEmpty ? 0 : (index + 1) % updated.users.count
        queue = updated
    }
    @discardableResult func openNext() -> Bool {
        guard canEditLists, !queue.users.isEmpty else { return false }
        let done = doneSet
        let cursor = queue.users.indices.contains(queue.cursor) ? queue.cursor : 0
        for offset in 0..<queue.users.count {
            let index = offset < queue.users.count - cursor ? cursor + offset : offset - (queue.users.count - cursor)
            let user = queue.users[index]
            if !done.contains(user) && !excluded.contains(user) { startBrowser(mode: .unfollow, at: user); return true }
        }
        return false
    }
    func start(at user: String) {
        guard canEditLists else { return }
        guard let index = queue.users.firstIndex(of: user) else { return }
        var updated = queue
        updated.users = Array(updated.users[index...])
        let kept = Set(updated.users)
        updated.done = updated.done.filter { kept.contains($0) }
        updated.cursor = 0
        updated.lastOpened = nil
        queue = updated
    }
    func signOut() async {
        guard !isDemo else { return }
        await session.signOut()
        instagramLoginConfirmed = false
    }

    func resetLists() {
        cancelOperation()
        restoring = false
        isRestoring = false
        do {
            try commit(.empty, recovering: true)
            hasImportedSample = false
            browserUsers = []
            browserHistory = []
            browserIndex = 0
            instagramUser = nil
            failure = nil
            message = String(localized: "Imported lists and review progress cleared.")
        } catch { pendingSave = .empty; report(error, operation: .save) }
    }

    @discardableResult
    func importZIP(_ url: URL) -> Task<Void, Never> {
        guard !isDemo else { return Task {} }
        return importArchive(url, current: snapshot)
    }

    /// Restricted actions explain how to leave Demo Mode without starting network work.
    func requireLiveMode() -> Bool {
        guard isDemo else { return true }
        demoRestrictionRequested = true
        return false
    }

    /// An empty workspace is required, even after confirmation, so personal data is never replaced.
    var canReceiveSampleLists: Bool {
        guard !isDemo, canEditLists, !savingBlocked, pendingSave == nil else { return false }
        let state = snapshot
        return state.queue.users.isEmpty && state.queue.done.isEmpty && state.queue.mode == "none"
            && state.queue.lastOpened == nil && state.queue.cursor == 0
            && state.queue.following == nil && state.queue.followers == nil
            && state.preferences.following.isEmpty && state.preferences.followers.isEmpty
            && state.preferences.excluded.isEmpty && state.preferences.nonMutualReviewed.isEmpty
            && (state.preferences.mutualReviewed ?? []).isEmpty
    }

    func retainSampleLists(from demo: PeelModel) throws {
        guard canReceiveSampleLists, demo.isDemo, demo.hasImportedSample, demo.canEditLists,
              demo.failure == nil else { throw PeelError.invalidBackup }
        // Commit validates and saves before publishing; a failed write leaves both models intact.
        try commit(demo.snapshot)
        failure = nil
        operationState = .completed
        instagramUser = nil
        browserUsers = []
        browserHistory = []
        browserIndex = 0
        // The demo login flag is intentionally not copied. Live login remains user-confirmed.
    }

    /// Only the isolated demo model can import the bundled fictional archive.
    @discardableResult
    func importSampleArchive() -> Task<Void, Never> {
        guard isDemo else { return Task {} }
        let url = Bundle.main.url(forResource: "Peel-Sample-Archive", withExtension: "zip")
            ?? Bundle.main.bundleURL.appendingPathComponent("Peel-Sample-Archive.zip")
        return importArchive(url, current: .empty)
    }

    private func importArchive(_ url: URL, current: SavedSnapshot) -> Task<Void, Never> {
        let importer = importer
        return perform(.zip(url)) {
            let result = try await importer.importZIP(url)
            let oldDone = Set(current.queue.done)
            let followers = Set(result.followers)
            let users = result.following.filter { !followers.contains($0) }
            return SavedSnapshot(queue: QueueState(users: users, following: result.following.count,
                followers: result.followers.count, done: users.filter { oldDone.contains($0) },
                mode: "comparison"), preferences: PeelPreferences(
                excluded: current.preferences.excluded, nonMutualReviewed: current.preferences.nonMutualReviewed,
                mutualReviewed: current.preferences.mutualReviewed,
                followers: result.followers, following: result.following))
        }
    }

    @discardableResult
    func importList(_ urls: [URL], kind: ListKind) -> Task<Void, Never> {
        guard !isDemo else { return Task {} }
        let current = snapshot
        let importer = importer
        return perform(.list(urls, kind)) {
            let names = try await importer.importList(urls, kind: kind)
            var state = current
            if kind == .following { state.preferences.following = names }
            else { state.preferences.followers = names }
            return state
        }
    }

    @discardableResult
    func restore(_ url: URL) -> Task<Void, Never> {
        guard !isDemo else { return Task {} }
        let current = snapshot
        let importer = importer
        return perform(.restore(url)) { try await importer.restore(url, current: current) }
    }

    /// The returned callback owns this consumer until UIKit reports activity completion.
    func beginExportSharing(_ url: URL) -> @MainActor () -> Void {
        guard let token = temporaryExports.beginSharing(url) else { return {} }
        return { [self] in
            do { try temporaryExports.finishSharing(url, token: token) }
            catch { report(PeelError.exportCleanupFailed, operation: .cleanupExports) }
        }
    }

    func discardUnsharedExport(_ url: URL) {
        do { try temporaryExports.discardUnshared(url) }
        catch { report(PeelError.exportCleanupFailed, operation: .cleanupExports) }
    }

    private func retryExportCleanup() {
        do { try temporaryExports.retryCleanup(); operationState = .completed }
        catch { report(PeelError.exportCleanupFailed, operation: .cleanupExports) }
    }

    func exportFile() -> URL? {
        guard !savingBlocked else {
            report(PeelError.corruptSavedData, operation: .export)
            return nil
        }
        let file = ProgressFile(exportedAt: ISO8601DateFormatter().string(from: Date()), state: queue,
            excluded: excluded.sorted(), nonMutualReviewed: nonMutualReviewed.sorted(),
            mutualReviewed: mutualReviewed.sorted(), importedFollowing: followingNames, importedFollowers: followerNames)
        do {
            return try temporaryExports.create(JSONEncoder().encode(file), write: writeExport)
        } catch {
            do { try temporaryExports.retryCleanup(); report(PeelError.exportFailed, operation: .export) }
            catch { report(PeelError.exportCleanupFailed, operation: .cleanupExports) }
            return nil
        }
    }
}
