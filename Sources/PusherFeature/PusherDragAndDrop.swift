import CoreGraphics
import CoreTransferable
import Foundation
import PeekerCore
import UniformTypeIdentifiers

extension UTType {
    static let peekerPusherTask = UTType(exportedAs: "com.scpz24.peeker.pusher-task")
}

struct PusherDragPayload: Codable, Equatable, Sendable, Transferable {
    let taskID: UUID
    let businessDayID: BusinessDayID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .peekerPusherTask)
    }

    func taskID(in board: PusherBoard) -> UUID? {
        guard businessDayID == board.businessDay.id,
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
