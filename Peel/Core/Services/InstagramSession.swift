import WebKit

@MainActor
protocol InstagramSessionServicing {
    func signOut() async
}

@MainActor
struct InstagramSessionService: InstagramSessionServicing {
    /// Pure seam for characterizing the existing website-record selection.
    static func matchesWebsiteDataRecord(_ displayName: String) -> Bool {
        InstagramWebsitePolicy.matchesWebsiteDataRecord(displayName)
    }

    func signOut() async {
        await withCheckedContinuation { continuation in
            signOutOfInstagramWebSession { continuation.resume() }
        }
    }
}

@MainActor
func signOutOfInstagramWebSession(completion: @escaping () -> Void) {
    let store = WKWebsiteDataStore.default()
    store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
        let instagramRecords = records.filter { record in
            InstagramSessionService.matchesWebsiteDataRecord(record.displayName)
        }
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: instagramRecords) {
            Task { @MainActor in completion() }
        }
    }
}
