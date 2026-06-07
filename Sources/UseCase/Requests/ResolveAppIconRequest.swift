import Foundation

struct ResolveAppIconRequest: UseCaseRequest {
    /// Bundle id of the app a File/Directory entry opens with.
    let bundleIdentifier: String
}
