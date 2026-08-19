import FeatureRuntimeKit
import PusherModule
import SchedulerModule
import TimerModule

@MainActor
enum BuiltInFeatureModules {
    static var all: [any FunctionCardModule] {
        [TimerModule(), PusherModule(), SchedulerModule()]
    }
}
