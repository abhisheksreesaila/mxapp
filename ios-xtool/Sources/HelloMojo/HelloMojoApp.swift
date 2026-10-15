import SwiftUI
import MojoBridge

@main
struct HelloMojoApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Thin Swift wrapper: all state and logic live in Mojo.
@MainActor
final class MojoCore: ObservableObject {
    private let app: Int64
    @Published var greeting = "Tap Greet"

    init() { app = mojo_app_init() }
    deinit { mojo_app_quit(app) }

    func greet() {
        _ = mojo_app_event(app, 1)   // 1 = "Greet" clicked
        let len = Int(mui_last_text_len())
        if let ptr = mui_last_text(), len > 0 {
            greeting = String(decoding: UnsafeBufferPointer(start: ptr, count: len), as: UTF8.self)
        }
    }
}

struct ContentView: View {
    @StateObject private var core = MojoCore()

    var body: some View {
        VStack(spacing: 24) {
            Text("mojo-ui · hello")
                .font(.title2.bold())
            Text(core.greeting)
                .font(.title3)
            Button("Greet") { core.greet() }
                .buttonStyle(.borderedProminent)
            Text("This greeting is computed in Mojo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
