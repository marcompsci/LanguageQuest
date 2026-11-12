import SwiftUI
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
