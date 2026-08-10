import FeatureRuntimeKit
import PusherModule
import TimerModule

@MainActor
enum BuiltInFeatureModules {
    static var all: [any FunctionCardModule] {
        [TimerModule(), PusherModule()]
    }
}
