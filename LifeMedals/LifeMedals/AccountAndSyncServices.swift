import CloudKit
import CoreData
import Foundation
import Observation

enum LifeMedalsCloud {
    static let containerIdentifier = "iCloud.mofololo.LifeMedals"

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isEnabledForCurrentBuild: Bool { !isRunningTests }
}

private struct CloudKitEventSnapshot: Sendable {
    enum Failure: Sendable {
        case quotaExceeded
        case other(String)
    }

    let identifier: UUID
    let endDate: Date?
    let succeeded: Bool
    let failure: Failure?
    let isExport: Bool
    let isImport: Bool

    init(event: NSPersistentCloudKitContainer.Event) {
        identifier = event.identifier
        endDate = event.endDate
        succeeded = event.succeeded
        if let error = event.error {
            failure = Self.containsQuotaExceeded(error)
                ? .quotaExceeded
                : .other(error.localizedDescription)
        } else {
            failure = nil
        }
        isExport = event.type == .export
        isImport = event.type == .import
    }

    private static func containsQuotaExceeded(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        if cloudError.code == .quotaExceeded { return true }
        return cloudError.partialErrorsByItemID?.values.contains { partialError in
            containsQuotaExceeded(partialError)
        } ?? false
    }
}

@Observable
@MainActor
final class CloudSyncMonitor {
    private(set) var accountStatus: CKAccountStatus?
    private(set) var isCheckingAccount = true
    private(set) var isSyncing = false
    private(set) var lastSuccessfulSync: Date?
    private(set) var lastSuccessfulExport: Date?
    private(set) var lastSuccessfulImport: Date?
    private var accountErrorMessage: String?
    private var syncErrorMessage: String?

    @ObservationIgnored private let container: CKContainer?
    @ObservationIgnored private var notificationObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var activeEventIdentifiers: Set<UUID> = []

    init() {
        container = LifeMedalsCloud.isEnabledForCurrentBuild
            ? CKContainer(identifier: LifeMedalsCloud.containerIdentifier)
            : nil

        guard LifeMedalsCloud.isEnabledForCurrentBuild else {
            isCheckingAccount = false
            return
        }

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: .CKAccountChanged,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshAccountStatus()
                }
            }
        )

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard
                    let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event
                else { return }

                let snapshot = CloudKitEventSnapshot(event: event)
                Task { @MainActor [weak self] in
                    self?.applyCloudKitEvent(snapshot)
                }
            }
        )
    }

    var isAvailable: Bool { accountStatus == .available }
    var errorMessage: String? { accountErrorMessage ?? syncErrorMessage }

    var shortTitle: String {
        if !LifeMedalsCloud.isEnabledForCurrentBuild { return L10n.text("本地开发模式") }
        if isCheckingAccount { return L10n.text("检查 iCloud") }
        if isSyncing { return L10n.text("正在同步") }
        if errorMessage != nil { return L10n.text("同步需处理") }
        if isAvailable, lastSuccessfulSync != nil { return L10n.text("iCloud 已同步") }
        if isAvailable { return L10n.text("等待首次同步") }
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

    private func applyCloudKitEvent(_ event: CloudKitEventSnapshot) {
        if event.endDate == nil {
            activeEventIdentifiers.insert(event.identifier)
            isSyncing = !activeEventIdentifiers.isEmpty
            return
        }

        activeEventIdentifiers.remove(event.identifier)
        isSyncing = !activeEventIdentifiers.isEmpty
        if event.succeeded {
            lastSuccessfulSync = event.endDate
            if event.isExport {
                lastSuccessfulExport = event.endDate
            }
            if event.isImport {
                lastSuccessfulImport = event.endDate
            }
            syncErrorMessage = nil
        } else if let failure = event.failure {
            switch failure {
            case .quotaExceeded:
                syncErrorMessage = L10n.text(
                    "iCloud 储存空间不足，无法同步。请在系统设置中释放或升级 iCloud 空间后等待自动重试。",
                    english: "There is not enough iCloud storage to sync. Free up or upgrade iCloud storage in Settings, then wait for an automatic retry."
                )
            case .other(let errorDescription):
                syncErrorMessage = L10n.text(
                    "iCloud 同步失败：\(errorDescription)",
                    english: "iCloud sync failed: \(errorDescription)"
                )
            }
        }
    }
}
