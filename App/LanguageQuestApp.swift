import SwiftUI
import LQCore

@main
struct LanguageQuestApp: App {
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
            case .world:
                WorldView()
            }
        }
        .lqTheme(model.palette, scale: model.profile?.settings.textScale ?? 1)
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
