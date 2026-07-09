import SwiftUI

@main
struct CarouselStudioApp: App {
    @State private var services = AppServices()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TemplateListView()
                .environment(services)
                .preferredColorScheme(.dark)
                .task {
                    let status = await services.photoSource.requestAccess()
                    if status == .full || status == .limited {
                        await services.activateQuestEngine()
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                switch newPhase {
                case .background:
                    await services.deactivateQuestEngine()
                case .active:
                    let status = await services.photoSource.requestAccess()
                    if status == .full || status == .limited {
                        await services.activateQuestEngine()
                    }
                default:
                    break
                }
            }
        }
    }
}
