import AuthenticationServices
import CloudKit
import Combine
import CoreData
import Foundation
import Security

enum LifeMedalsCloud {
    static let containerIdentifier = "iCloud.noorg.LifeMedals"

#if LIFEMEDALS_LOCAL_DEVELOPMENT
    static let isEnabledForCurrentBuild = false
#else
    static let isEnabledForCurrentBuild = true
#endif
}

@MainActor
final class AppleAccountManager: NSObject, ObservableObject {
    enum SessionState: Equatable {
        case checking
        case signedOut
        case signedIn
    }

    @Published private(set) var state: SessionState
    @Published private(set) var displayName: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var requiresReauthentication = false

    private let provider = ASAuthorizationAppleIDProvider()
    private let keychain = AppleUserIdentifierStore()
    private let displayNameKey = "appleAccountDisplayName"

    override init() {
        let hasStoredUser = LifeMedalsCloud.isEnabledForCurrentBuild && keychain.userIdentifier != nil
        state = hasStoredUser ? .checking : .signedOut
        displayName = LifeMedalsCloud.isEnabledForCurrentBuild
            ? UserDefaults.standard.string(forKey: displayNameKey)
            : nil
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(credentialWasRevoked),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
    }

    var isSignedIn: Bool { state == .signedIn }

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        request.requestedScopes = [.fullName]
    }

    @discardableResult
    func complete(_ result: Result<ASAuthorization, Error>) -> Bool {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Apple 登录没有返回可用凭证，请重试。"
                state = .signedOut
                return false
            }

            do {
                try keychain.save(userIdentifier: credential.user)
            } catch {
                errorMessage = "无法安全保存登录状态，请检查钥匙串权限后重试。"
                state = .signedOut
                return false
            }

            if let fullName = credential.fullName {
                let formattedName = PersonNameComponentsFormatter().string(from: fullName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !formattedName.isEmpty {
                    displayName = formattedName
                    UserDefaults.standard.set(formattedName, forKey: displayNameKey)
                }
            }

            errorMessage = nil
            requiresReauthentication = false
            state = .signedIn
            return true

        case .failure(let error):
            let authorizationError = error as? ASAuthorizationError
            if authorizationError?.code != .canceled {
                errorMessage = L10n.text(
                    "Apple 登录未完成：\(error.localizedDescription)",
                    english: "Apple sign-in did not complete: \(error.localizedDescription)"
                )
            }
            state = .signedOut
            return false
        }
    }

    func validateStoredCredential() async {
        guard LifeMedalsCloud.isEnabledForCurrentBuild else {
            state = .signedOut
            return
        }

        guard let userIdentifier = keychain.userIdentifier else {
            state = .signedOut
            return
        }

        state = .checking
        do {
            let credentialState = try await provider.credentialState(forUserID: userIdentifier)
            switch credentialState {
            case .authorized:
                errorMessage = nil
                requiresReauthentication = false
                state = .signedIn
            case .revoked, .notFound:
                signOut(keepingError: false, requiringReauthentication: true)
            case .transferred:
                errorMessage = "Apple 登录凭证需要迁移，请重新登录。"
                signOut(keepingError: true, requiringReauthentication: true)
            @unknown default:
                errorMessage = "暂时无法确认 Apple 登录状态。"
                state = .signedOut
            }
        } catch {
            // A temporary network failure must not erase an otherwise valid local session.
            errorMessage = "暂时无法验证 Apple 登录状态，已保留本机会话。"
            state = .signedIn
        }
    }

    func signOut() {
        signOut(keepingError: false, requiringReauthentication: false)
    }

    @objc private func credentialWasRevoked() {
        errorMessage = "Apple 登录授权已撤销，请重新登录。"
        signOut(keepingError: true, requiringReauthentication: true)
    }

    private func signOut(keepingError: Bool, requiringReauthentication: Bool) {
        keychain.deleteUserIdentifier()
        displayName = nil
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        if !keepingError {
            errorMessage = nil
        }
        requiresReauthentication = requiringReauthentication
        state = .signedOut
    }
}

@MainActor
final class CloudSyncMonitor: NSObject, ObservableObject {
    @Published private(set) var accountStatus: CKAccountStatus?
    @Published private(set) var isCheckingAccount = true
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private var accountErrorMessage: String?
    @Published private var syncErrorMessage: String?

    private let container: CKContainer?

    override init() {
        container = LifeMedalsCloud.isEnabledForCurrentBuild
            ? CKContainer(identifier: LifeMedalsCloud.containerIdentifier)
            : nil
        super.init()

        guard LifeMedalsCloud.isEnabledForCurrentBuild else {
            isCheckingAccount = false
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudAccountChanged),
            name: .CKAccountChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudKitEventChanged(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil
        )
    }

    var isAvailable: Bool { accountStatus == .available }
    var errorMessage: String? { accountErrorMessage ?? syncErrorMessage }

    var shortTitle: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild { return L10n.text("本地开发模式") }
        if isCheckingAccount { return L10n.text("检查 iCloud") }
        if isSyncing { return L10n.text("正在同步") }
        if errorMessage != nil { return L10n.text("同步需处理") }
        if isAvailable { return L10n.text("iCloud 已连接") }
        return L10n.text("仅本机")
    }

    var iconName: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild { return "internaldrive.fill" }
        if isCheckingAccount || isSyncing { return "arrow.triangle.2.circlepath.icloud" }
        if errorMessage != nil { return "exclamationmark.icloud" }
        if isAvailable { return "checkmark.icloud.fill" }
        return "icloud.slash"
    }

    func refreshAccountStatus() async {
        guard LifeMedalsCloud.isEnabledForCurrentBuild, let container else {
            accountStatus = nil
            accountErrorMessage = nil
            isCheckingAccount = false
            return
        }

        isCheckingAccount = true
        do {
            let status = try await container.accountStatus()
            accountStatus = status
            if status == .available {
                accountErrorMessage = nil
            } else {
                accountErrorMessage = accountMessage(for: status)
            }
        } catch {
            accountStatus = .couldNotDetermine
            accountErrorMessage = L10n.text(
                "暂时无法检查 iCloud 账户：\(error.localizedDescription)",
                english: "Could not check the iCloud account: \(error.localizedDescription)"
            )
        }
        isCheckingAccount = false
    }

    func accountMessage(for status: CKAccountStatus) -> String? {
        switch status {
        case .available:
            nil
        case .noAccount:
            L10n.text("iCloud 账户未登录。请在系统设置中登录 iCloud 后重试。")
        case .restricted:
            L10n.text("这台设备限制了 iCloud 访问，请检查系统或家长控制设置。")
        case .temporarilyUnavailable:
            L10n.text("iCloud 账户暂时不可用，请稍后重试。")
        case .couldNotDetermine:
            L10n.text("暂时无法确定 iCloud 账户状态，请检查网络后重试。")
        @unknown default:
            L10n.text("iCloud 当前不可用，请稍后重试。")
        }
    }

    @objc private func cloudAccountChanged() {
        Task { await refreshAccountStatus() }
    }

    @objc private func cloudKitEventChanged(_ notification: Notification) {
        guard
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else { return }

        if event.endDate == nil {
            isSyncing = true
            return
        }

        isSyncing = false
        if event.succeeded {
            lastSuccessfulSync = event.endDate
            syncErrorMessage = nil
        } else if let error = event.error {
            syncErrorMessage = L10n.text(
                "iCloud 同步失败：\(error.localizedDescription)",
                english: "iCloud sync failed: \(error.localizedDescription)"
            )
        }
    }
}

private struct AppleUserIdentifierStore {
    private let service = "noorg.LifeMedals.apple-account"
    private let account = "current-user"

    var userIdentifier: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(userIdentifier: String) throws {
        guard let data = userIdentifier.data(using: .utf8) else {
            throw KeychainError.invalidValue
        }

        deleteUserIdentifier()
        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    func deleteUserIdentifier() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private enum KeychainError: Error {
        case invalidValue
        case unhandled(OSStatus)
    }
}
