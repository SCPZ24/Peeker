# Peeker Settings Placement and Timer Progress Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 SwiftUI 设置窗口稳定定位到当前屏幕可见区域自底部起 40% 的中心高度，并把 Timer 单任务进度条移到收敛态和展开态的指定行内位置。

**Architecture:** `MacPlatform` 新增无 AppKit 状态的设置窗口 frame 几何函数，由 `PeekerApp` 中一个窄 `NSViewRepresentable` 获取真实 Settings `NSWindow` 并交给定位器；Timer 继续复用既有实时进度模型与进度条视图，只重排 `TimerViews` 内部布局。设置窗口行为以纯几何测试驱动，SwiftUI 视觉重排通过目标构建和实际应用检查验证。

**Tech Stack:** macOS 26、Swift 6.2、SwiftUI、AppKit、SwiftPM、XCTest。

## Global Constraints

- 设置窗口中心固定在窗口所在屏幕 `visibleFrame` 自底部起 `40%` 的高度，水平中心固定为 `visibleFrame.midX`。
- 不依赖 SwiftUI 私有窗口 identifier、窗口标题或私有 selector。
- 不修改设置窗口大小、层级、样式、Scene 生命周期或持久化规则。
- 不修改 Timer 计时状态、进度计算、数据库结构、偏好设置、功能卡尺寸或灵动岛窗口动画。
- Timer 收敛尺寸保持 `340×38`，展开尺寸保持 `760×420`。
- 继续复用 `TimerTaskProgressBar` 的颜色、实时比例和 VoiceOver 百分比。
- 保留当前分支已有提交和用户改动，不回退无关文件。

---

## File Map

- Create `Sources/MacPlatform/SettingsWindowGeometry.swift`: 只负责从窗口尺寸和屏幕可见 frame 计算目标 frame。
- Create `Tests/MacPlatformTests/SettingsWindowGeometryTests.swift`: 覆盖 40% 锚点、外接屏幕坐标和边界约束。
- Create `Sources/PeekerApp/SettingsWindowPositioner.swift`: 保存设置窗口弱引用、选择目标屏幕并应用纯几何结果。
- Modify `Sources/PeekerApp/SettingsRootView.swift`: 用窄 `NSViewRepresentable` 取得当前 Settings Scene 的真实 `NSWindow`。
- Modify `Sources/PeekerApp/AppRuntime.swift`: 注册设置窗口，并在标准设置命令执行后重新定位和置前。
- Modify `Sources/TimerFeature/TimerViews.swift`: 将 compact/expanded 进度条移动到行内。

---

### Task 1: 设置窗口目标 frame 几何

**Files:**
- Create: `Sources/MacPlatform/SettingsWindowGeometry.swift`
- Test: `Tests/MacPlatformTests/SettingsWindowGeometryTests.swift`

**Interfaces:**
- Consumes: `CGSize windowSize`、`CGRect visibleFrame`。
- Produces: `SettingsWindowGeometry.frame(windowSize:visibleFrame:) -> CGRect`。

- [ ] **Step 1: 编写失败测试**

创建测试覆盖：

```swift
func testFrameCentersAtFortyPercentOfVisibleScreenHeight() {
    let frame = SettingsWindowGeometry.frame(
        windowSize: CGSize(width: 600, height: 500),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )
    XCTAssertEqual(frame.midX, 720)
    XCTAssertEqual(frame.midY, 360)
    XCTAssertEqual(frame.size, CGSize(width: 600, height: 500))
}

func testFrameUsesVisibleFrameOriginOnExternalScreen() {
    let frame = SettingsWindowGeometry.frame(
        windowSize: CGSize(width: 500, height: 400),
        visibleFrame: CGRect(x: -1_920, y: 40, width: 1_920, height: 1_000)
    )
    XCTAssertEqual(frame.midX, -960)
    XCTAssertEqual(frame.midY, 440)
}
```

并增加：40% 锚点导致底部越界时贴齐 `visibleFrame.minY`；窗口大于可见区域时保持原尺寸并贴齐可见区域原点。

- [ ] **Step 2: 运行测试确认 RED**

Run:

```bash
swift test --filter SettingsWindowGeometryTests --disable-sandbox --disable-automatic-resolution
```

Expected: 编译失败，提示找不到 `SettingsWindowGeometry`。

- [ ] **Step 3: 实现最小纯几何函数**

```swift
public enum SettingsWindowGeometry {
    public static func frame(windowSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let desiredOrigin = CGPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.40 - windowSize.height / 2
        )
        return CGRect(
            origin: CGPoint(
                x: clampedOrigin(desiredOrigin.x, extent: windowSize.width, range: visibleFrame.minX...visibleFrame.maxX),
                y: clampedOrigin(desiredOrigin.y, extent: windowSize.height, range: visibleFrame.minY...visibleFrame.maxY)
            ),
            size: windowSize
        )
    }

    private static func clampedOrigin(
        _ desired: CGFloat,
        extent: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> CGFloat {
        let maximum = range.upperBound - extent
        guard maximum >= range.lowerBound else { return range.lowerBound }
        return min(max(desired, range.lowerBound), maximum)
    }
}
```

- [ ] **Step 4: 再次运行目标测试**

Expected: 4 项 `SettingsWindowGeometryTests` 全部通过。

---

### Task 2: 将真实 Settings 窗口接入定位器

**Files:**
- Create: `Sources/PeekerApp/SettingsWindowPositioner.swift`
- Modify: `Sources/PeekerApp/SettingsRootView.swift`
- Modify: `Sources/PeekerApp/AppRuntime.swift`

**Interfaces:**
- Consumes: `SettingsWindowGeometry.frame(windowSize:visibleFrame:)`、`NSWindow.screen`、`NSEvent.mouseLocation`。
- Produces: `SettingsWindowPositioner.register(_:)`、`repositionAndBringForward()`；Settings 根视图报告实际 `NSWindow`。

- [ ] **Step 1: 实现定位器**

```swift
@MainActor
final class SettingsWindowPositioner {
    private weak var window: NSWindow?

    func register(_ window: NSWindow) {
        self.window = window
        position(window)
    }

    func repositionAndBringForward() {
        guard let window else { return }
        position(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func position(_ window: NSWindow) {
        guard let screen = window.screen ?? screenContainingMouse() ?? NSScreen.main else { return }
        window.setFrame(
            SettingsWindowGeometry.frame(windowSize: window.frame.size, visibleFrame: screen.visibleFrame),
            display: true
        )
    }
}
```

`screenContainingMouse()` 遍历 `NSScreen.screens` 并用 `NSMouseInRect(NSEvent.mouseLocation, screen.frame, false)` 选择首次创建时的回退屏幕。

- [ ] **Step 2: 在 SettingsRootView 接入窗口 accessor**

新增 `SettingsWindowAccessor: NSViewRepresentable` 和 `WindowReportingView: NSView`。后者在 `viewDidMoveToWindow()` 中把真实窗口延迟到下一主运行循环报告给：

```swift
runtime.registerSettingsWindow(window)
```

根视图通过 `.background { SettingsWindowAccessor(...) }` 附着 accessor；不搜索窗口标题或 identifier。

- [ ] **Step 3: AppRuntime 注册并在设置命令后复位**

新增私有 `SettingsWindowPositioner`，公开 target 内部方法：

```swift
func registerSettingsWindow(_ window: NSWindow) {
    settingsWindowPositioner.register(window)
}
```

在 `applicationMenu.performActionForItem(at:)` 后执行：

```swift
DispatchQueue.main.async { [weak self] in
    self?.settingsWindowPositioner.repositionAndBringForward()
}
```

- [ ] **Step 4: 构建 PeekerApp**

Run:

```bash
swift build --target PeekerApp --disable-sandbox --disable-automatic-resolution
```

Expected: 编译成功，无 Swift 6 actor isolation 或 representable 类型错误。

---

### Task 3: Timer 两种状态的行内进度条

**Files:**
- Modify: `Sources/TimerFeature/TimerViews.swift`

**Interfaces:**
- Consumes: 既有 `TimerProgressSnapshot`、`TimerTaskProgressBar`、`TimerStore.remainingSeconds(for:at:)`。
- Produces: 相同 compact/expanded 业务视图与辅助功能值，仅改变进度条视觉顺序和尺寸约束。

- [ ] **Step 1: compact 改为单行四段布局**

元素顺序固定为颜色、标题、进度、剩余信息：

```swift
HStack(spacing: 8) {
    Circle().fill(Color(hex: task.colorHex)).frame(width: 8, height: 8)
    Text(task.name)
        .lineLimit(1)
        .truncationMode(.tail)
        .layoutPriority(1)
    TimerTaskProgressBar(ratio: progress.ratio, color: Color(hex: task.colorHex))
        .frame(minWidth: 56, idealWidth: 92, maxWidth: 112)
        .frame(height: 4)
    // 保留完成图标或固定宽度剩余时间分支
}
```

删除原底部进度条和额外 `Spacer`，剩余时间添加 `.fixedSize(horizontal: true, vertical: false)`。

- [ ] **Step 2: expanded 改为单行四段布局**

保留颜色条和标题/剩余时间垂直文字组，将文字组限制为稳定宽度 `170`，随后放置：

```swift
TimerTaskProgressBar(ratio: progress.ratio, color: Color(hex: task.colorHex))
    .frame(minWidth: 80, maxWidth: .infinity)
    .frame(height: 4)
```

最后保留现有开始、暂停、完成控制分支。删除任务卡底部进度条。

- [ ] **Step 3: 构建 TimerFeature**

Run:

```bash
swift build --target TimerFeature --disable-sandbox --disable-automatic-resolution
```

Expected: 编译成功，compact/expanded metrics 未变化。

---

### Task 4: 完整验证和真实界面检查

**Files:**
- Verify only；若发现回归，只修复上述文件映射中的实现。

**Interfaces:**
- Consumes: 完整 SwiftPM package、`script/build_and_run.sh`。
- Produces: 测试、格式、应用构建与真实 UI 验收证据。

- [ ] **Step 1: 运行完整自动化验证**

```bash
swift test --disable-sandbox --disable-automatic-resolution
git diff --check
./script/build_and_run.sh --verify
```

Expected: 全部测试通过、diff 检查无输出、应用生成并成功启动。

- [ ] **Step 2: 实际检查设置窗口**

展开灵动岛后点击齿轮；确认设置窗口水平居中、垂直中心为可见区域 40%（边界约束除外）、不被岛遮挡；再次点击齿轮复用同一窗口并重新应用位置。

- [ ] **Step 3: 实际检查 Timer**

确认 compact 为“标题—进度条—剩余时间”，expanded 为“文字—进度条—控制按钮”；长标题不会挤掉时间或按钮，进度条无裁剪或越界。

- [ ] **Step 4: 审查最终差异**

```bash
git status --short
git diff --stat
git diff -- Sources/MacPlatform Sources/PeekerApp Sources/TimerFeature Tests/MacPlatformTests
```

Expected: 只包含本计划文件映射内的实现与测试修改，没有业务模型、数据库或无关文件变化。

