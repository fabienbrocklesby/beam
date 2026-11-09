import AppKit
import BeamCore
import UserNotifications
import os

/// Tells the user an agent needs them while Beam is in the background. Each
/// pane has at most one notification: a newer one replaces the older, and it
/// goes once the pane no longer needs the user.
final class AgentNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the pane whose notification the user clicked. A click that
    /// launched Beam waits until this is set, when the window is ready for it.
    var onOpen: ((Pane.ID) -> Void)? {
        didSet {
            guard let pane = pendingOpen, let onOpen else { return }
            pendingOpen = nil
            onOpen(pane)
        }
    }
    private var pendingOpen: Pane.ID?
    /// Panes whose notification may still be showing, each with the post that
    /// is current for it.
    private var posted: [Pane.ID: UUID] = [:]
    /// Asking the user for permission, once. Every notification waits for
    /// the answer: one posted while the prompt is still up is refused.
    private var permission: Task<Void, Never>?

    /// Becomes the notification centre's delegate, which has to happen before
    /// the app finishes launching for a click that launches it to arrive.
    /// Clears what an earlier run delivered: Beam does not know which
    /// notifications that run posted, so it could never withdraw them.
    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.removeAllDeliveredNotifications()
    }

    /// Tells the user that `agent`, in `pane` of `workspace`, has reached
    /// `state`. Permission is asked for the first time, so a user who never
    /// leaves an agent working in the background is never asked.
    func post(_ state: AgentState, from agent: Agent, in pane: Pane.ID, of workspace: Workspace) {
        let title: String
        let body: String
        switch state {
        case .working:
            return
        case .waiting(let message):
            title = "\(agent.name) needs you"
            body = message
        case .done(let message):
            title = "\(agent.name) is done"
            body = message ?? ""
        }
        let token = UUID()
        posted[pane] = token
        let permission = self.permission ?? Task.detached { await Self.askPermission() }
        self.permission = permission
        let subtitle = workspace.name
        let thread = workspace.id.description
        Task {
            await permission.value
            // While the user was deciding, they may have looked at the pane,
            // or it may have posted again.
            guard await Self.isAllowed(), posted[pane] == token else { return }
            await Self.add(identifier: pane.description, title: title, subtitle: subtitle, body: body, thread: thread)
        }
    }

    /// Takes back the notifications of panes `needsUser` says no longer need
    /// the user.
    func withdraw(unless needsUser: (Pane.ID) -> Bool) {
        let stale = posted.keys.filter { !needsUser($0) }
        guard !stale.isEmpty else { return }
        for pane in stale { posted[pane] = nil }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: stale.map(\.description))
    }

    private nonisolated static func askPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch UNError.notificationsNotAllowed {
            // The user said no.
        } catch {
            Logger.app.error("could not ask to post notifications: \(error, privacy: .public)")
        }
    }

    /// Read afresh each time: the user can change it in System Settings.
    private nonisolated static func isAllowed() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Built here from plain values, so nothing the main actor holds crosses
    /// to the notification centre.
    private nonisolated static func add(
        identifier: String, title: String, subtitle: String, body: String, thread: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.threadIdentifier = thread
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger.app.error("could not post a notification: \(error, privacy: .public)")
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run { open(identifier) }
    }

    private func open(_ identifier: String) {
        guard let uuid = UUID(uuidString: identifier) else { return }
        let pane = Pane.ID(uuid: uuid)
        posted[pane] = nil
        if let onOpen {
            onOpen(pane)
        } else {
            pendingOpen = pane
        }
    }
}
