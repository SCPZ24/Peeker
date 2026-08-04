import CoreGraphics
import Foundation
import PeekerCore

struct PusherDragEnvelope: Equatable, Sendable {
    private static let prefix = "peeker-pusher-drag"
    private static let version = "v1"

    let sessionNonce: UUID
    let businessDayStart: Int64
    let taskID: UUID

    var rawValue: String {
        [
            Self.prefix,
            Self.version,
            sessionNonce.uuidString,
            String(businessDayStart),
            taskID.uuidString,
        ].joined(separator: ":")
    }

    init(sessionNonce: UUID, businessDayStart: Int64, taskID: UUID) {
        self.sessionNonce = sessionNonce
        self.businessDayStart = businessDayStart
        self.taskID = taskID
    }

    init?(rawValue: String) {
        let components = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 5,
              components[0] == Self.prefix,
              components[1] == Self.version,
              let sessionNonce = UUID(uuidString: String(components[2])),
              let businessDayStart = Int64(components[3]),
              let taskID = UUID(uuidString: String(components[4])) else { return nil }
        self.init(
            sessionNonce: sessionNonce,
            businessDayStart: businessDayStart,
            taskID: taskID
        )
    }

    func taskID(in board: PusherBoard, sessionNonce expectedNonce: UUID) -> UUID? {
        guard sessionNonce == expectedNonce,
              businessDayStart == board.businessDay.id.startAtMilliseconds,
              board.allTasks.contains(where: { $0.id == taskID }) else { return nil }
        return taskID
    }
}

struct PusherMoveTransaction: Identifiable, Sendable {
    let id: UUID
    let before: PusherBoard
    let after: PusherBoard

    init(id: UUID = UUID(), before: PusherBoard, after: PusherBoard) {
        self.id = id
        self.before = before
        self.after = after
    }
}

struct PusherDropRow: Equatable {
    let taskIndex: Int
    let frame: CGRect
}

struct PusherDropColumnGeometry: Equatable {
    let status: PusherStatus
    let frame: CGRect
    let rows: [PusherDropRow]
    let taskCount: Int
}

struct PusherDropTarget: Equatable {
    let status: PusherStatus
    let insertionIndex: Int
    let landingFrame: CGRect
}

enum PusherDropGeometry {
    static let horizontalInset: CGFloat = 10
    static let emptyColumnLandingY: CGFloat = 40
    static let rowSpacing: CGFloat = 7
    static let fallbackCardHeight: CGFloat = 36

    static func target(
        location: CGPoint,
        columns: [PusherDropColumnGeometry],
        draggedCardSize: CGSize?
    ) -> PusherDropTarget? {
        guard let column = columns.first(where: { $0.frame.contains(location) }) else { return nil }
        let localY = location.y - column.frame.minY
        let insertionIndex = PusherDropPlacement.insertionIndex(
            locationY: localY,
            rows: column.rows,
            taskCount: column.taskCount
        )
        let orderedRows = column.rows.sorted { lhs, rhs in
            if lhs.taskIndex != rhs.taskIndex { return lhs.taskIndex < rhs.taskIndex }
            return lhs.frame.minY < rhs.frame.minY
        }
        let landingY: CGFloat
        if orderedRows.isEmpty {
            landingY = column.frame.minY + emptyColumnLandingY
        } else if let nextRow = orderedRows.first(where: { $0.taskIndex >= insertionIndex }) {
            landingY = column.frame.minY + nextRow.frame.minY
        } else {
            landingY = column.frame.minY + (orderedRows.last?.frame.maxY ?? emptyColumnLandingY) + rowSpacing
        }
        let height = draggedCardSize?.height ?? fallbackCardHeight
        return PusherDropTarget(
            status: column.status,
            insertionIndex: insertionIndex,
            landingFrame: CGRect(
                x: column.frame.minX + horizontalInset,
                y: landingY,
                width: max(0, column.frame.width - horizontalInset * 2),
                height: height
            )
        )
    }
}

enum PusherDropPlacement {
    static func insertionIndex(
        locationY: CGFloat,
        rows: [PusherDropRow],
        taskCount: Int
    ) -> Int {
        let upperBound = max(0, taskCount)
        let orderedRows = rows.sorted {
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            return $0.taskIndex < $1.taskIndex
        }

        guard let lastRow = orderedRows.last else { return 0 }
        for row in orderedRows where locationY < row.frame.midY {
            return min(max(row.taskIndex, 0), upperBound)
        }
        return min(max(lastRow.taskIndex + 1, 0), upperBound)
    }
}
