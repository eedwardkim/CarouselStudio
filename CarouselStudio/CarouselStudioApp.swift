import SwiftUI

@main
struct CarouselStudioApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            TemplateListView()
                .environment(services)
                .preferredColorScheme(.dark)
        }
    }
}
