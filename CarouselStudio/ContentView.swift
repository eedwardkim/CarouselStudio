import CoreModels
import SwiftUI

/// Placeholder shell. Real navigation lands with Phase 1 (template list →
/// match results → draft assembly). See ARCHITECTURE.md.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Subsystems") {
                    Label("Template Engine", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    Label("Matching Engine", systemImage: "photo.stack")
                    Label("Music Matching", systemImage: "music.note")
                    Label("Quest Engine", systemImage: "flag.checkered")
                }
                Section("Formats") {
                    ForEach(PostFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.capitalized)
                    }
                }
            }
            .navigationTitle("CarouselStudio")
        }
    }
}

#Preview {
    ContentView()
}
