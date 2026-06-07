import Foundation

struct ReadLaunchAtLoginRequest: UseCaseRequest {}

struct SetLaunchAtLoginRequest: UseCaseRequest {
    let enabled: Bool
}
