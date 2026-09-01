import AgentorModule
import FeatureRuntimeKit
import PusherModule
import SchedulerModule
import TargetorModule
import TimerModule

@MainActor
enum BuiltInFeatureModules {
    static var all: [any FunctionCardModule] {
        [TimerModule(), PusherModule(), SchedulerModule(), AgentorModule(), TargetorModule()]
    }
}
