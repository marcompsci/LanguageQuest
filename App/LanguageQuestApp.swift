import SwiftUI
import UserNotifications
import LQCore

@main
struct LanguageQuestApp: App {
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientationDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.store.listenForTransactions { await model.refreshEntitlements() } }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.sessionBegan()
            case .background, .inactive: model.sessionEnded()
            @unknown default: break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var limitTick = 0

    var body: some View {
        Group {
            switch model.route {
            case .loading:
                ProgressView()
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(message).multilineTextAlignment(.center).padding()
                }
            case .onboarding:
                OnboardingView()
            case .menu:
                MenuView()
            case .hub:
                LanguageHubView()
            case .world:
                WorldView()
            }
        }
        // One sheet presenter for the menu and the village.
        .sheet(item: $model.sheet) { sheet in
            SheetRouter(sheet: sheet)
                .lqTheme(model.palette, scale: model.profile?.settings.textScale ?? 1, easyRead: model.profile?.settings.easyReadOn ?? false)
                .environmentObject(model)
        }
        .onChange(of: model.sheet) { _, _ in model.syncMusic() }
        .onChange(of: model.route) { _, _ in model.syncMusic() }
        .lqTheme(model.palette, scale: model.profile?.settings.textScale ?? 1, easyRead: model.profile?.settings.easyReadOn ?? false)
        .overlay {
            // v1.2: the parent's daily playtime limit (checked every minute).
            if limitTick >= 0 && (model.timeLimitReached || model.bedtimeReached) { TimeLimitOverlay(bedtime: !model.timeLimitReached) }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            limitTick += 1
            if (model.timeLimitReached || model.bedtimeReached) && model.sheet != nil { model.sheet = nil }   // the stop screen sits over everything
        }
        .overlay {
            if let c = model.celebration {
                CelebrationOverlay(celebration: c, reducedMotion: model.profile?.settings.reducedMotion ?? false) { model.dismissCelebration() }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let t = model.toast {
                Text(t)
                    .font(.callout)
                    .padding(12)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .onTapGesture { model.toast = nil }
                    .task { try? await Task.sleep(nanoseconds: 3_500_000_000); model.toast = nil }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }
}

/// The app stays portrait except while writing (Write Out), where landscape gives a bigger canvas.
final class OrientationDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = ReminderTapDelegate.shared
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // iPad apps support every orientation (multitasking and resizable windows); the portrait lock is iPhone only.
        UIDevice.current.userInterfaceIdiom == .pad ? .all : OrientationDelegate.mask
    }

    /// Allows (and optionally turns to) landscape; `nil` returns to portrait only.
    @MainActor static func allowLandscape(_ on: Bool, rotateNow: Bool = false) {
        mask = on ? .allButUpsideDown : .portrait
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.keyWindow?.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if !on {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        } else if rotateNow {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
    }
}
