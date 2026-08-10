import Foundation
import GRDB
import PeekerCore

public enum AppDatabaseMigrationError: Error, Equatable {
    case duplicateIdentifier(String)
}

public struct AppDatabaseMigration: Sendable {
    public let id: String
    private let action: @Sendable (Database) throws -> Void

    public init(
        id: String,
        migrate: @escaping @Sendable (Database) throws -> Void
    ) {
        self.id = id
        self.action = migrate
    }

    fileprivate func run(in database: Database) throws {
        try action(database)
    }
}

public final class AppDatabase: @unchecked Sendable {
    public let queue: DatabaseQueue
    private let featureMigrations: [AppDatabaseMigration]

    public init(
        path: String,
        featureMigrations: [AppDatabaseMigration] = []
    ) throws {
        try Self.validate(featureMigrations: featureMigrations)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.featureMigrations = featureMigrations
        queue = try DatabaseQueue(path: path, configuration: Self.configuration)
        try migrate()
    }

    private init(
        queue: DatabaseQueue,
        featureMigrations: [AppDatabaseMigration]
    ) throws {
        try Self.validate(featureMigrations: featureMigrations)
        self.queue = queue
        self.featureMigrations = featureMigrations
        try migrate()
    }

    public static func inMemory(
        featureMigrations: [AppDatabaseMigration] = []
    ) throws -> AppDatabase {
        try validate(featureMigrations: featureMigrations)
        return try AppDatabase(
            queue: DatabaseQueue(configuration: configuration),
            featureMigrations: featureMigrations
        )
    }

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Peeker", isDirectory: true)
            .appendingPathComponent("Peeker.sqlite", isDirectory: false)
    }

    public func migrate() throws {
        try Self.validate(featureMigrations: featureMigrations)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "business_days") { table in
                table.column("feature_id", .text).notNull()
                table.column("start_at_ms", .integer).notNull()
                table.column("end_at_ms", .integer).notNull()
                table.primaryKey(["feature_id", "start_at_ms"])
            }
        }
        migrator.registerMigration("v2-feature-runtime-state") { db in
            try db.create(table: "feature_runtime_state") { table in
                table.column("feature_id", .text).primaryKey()
                table.column("current_day_start_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.foreignKey(
                    ["feature_id", "current_day_start_at_ms"],
                    references: "business_days",
                    columns: ["feature_id", "start_at_ms"]
                )
            }
        }
        for migration in featureMigrations {
            migrator.registerMigration(migration.id) { database in
                try migration.run(in: database)
            }
        }
        try migrator.migrate(queue)
    }

    private static func validate(
        featureMigrations: [AppDatabaseMigration]
    ) throws {
        var identifiers = Set(["v1", "v2-feature-runtime-state"])
        for migration in featureMigrations {
            guard identifiers.insert(migration.id).inserted else {
                throw AppDatabaseMigrationError.duplicateIdentifier(migration.id)
            }
        }
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }
}

public func persistBusinessDay(_ day: BusinessDay, in db: Database) throws {
    try db.execute(
        sql: """
        INSERT INTO business_days (feature_id, start_at_ms, end_at_ms)
        VALUES (?, ?, ?)
        ON CONFLICT(feature_id, start_at_ms) DO UPDATE SET end_at_ms = excluded.end_at_ms
        """,
        arguments: [day.id.featureID.rawValue, day.id.startAtMilliseconds, day.end.millisecondsSince1970]
    )
}
