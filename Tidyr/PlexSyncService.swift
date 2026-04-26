import Foundation

struct PlexSyncService {

    enum SyncError: Error {
        case noToken
        case serverUnreachable
        case unexpectedStatus(Int)
    }

    // Triggers a Plex library scan for the given section ID.
    // Plex responds with 200 and starts scanning in background — no need to wait.
    @discardableResult
    static func refresh(sectionId: Int) async -> Bool {
        guard let token = PlexLibraryDetector.localToken else { return false }
        guard let url = URL(string: "http://localhost:32400/library/sections/\(sectionId)/refresh?X-Plex-Token=\(token)") else { return false }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 || status == 204
        } catch {
            return false
        }
    }
}
