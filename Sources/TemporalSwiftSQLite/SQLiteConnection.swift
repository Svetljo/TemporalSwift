import Foundation
import CSQLite

// MARK: - SQLite result code helpers

/// Returns `true` when the SQLite result code indicates success.
@inline(__always)
func sqliteOK(_ code: Int32) -> Bool {
    code == SQLITE_OK
}

/// Returns `true` when the result code is SQLITE_ROW (a row is available).
@inline(__always)
func sqliteRow(_ code: Int32) -> Bool {
    code == SQLITE_ROW
}

/// Returns `true` when the result code is SQLITE_DONE (operation finished).
@inline(__always)
func sqliteDone(_ code: Int32) -> Bool {
    code == SQLITE_DONE
}

// MARK: - SQLiteConnection

/// A lightweight, non-Sendable wrapper around a raw `sqlite3` database handle.
///
/// `SQLiteConnection` is **not** `Sendable`. It must only be used from within
/// the actor that owns it (`SQLiteGraphStore`). The actor serializes all access,
/// satisfying SQLite's requirement that a single connection be used from one
/// thread at a time (default serialized threading mode).
final class SQLiteConnection {

    // MARK: - State

    /// The raw SQLite database pointer. Owned exclusively by this object.
    private(set) var db: OpaquePointer?

    // MARK: - Init / deinit

    /// Opens or creates a SQLite database at `path`.
    ///
    /// Passes `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX`
    /// so the handle is opened for read+write, created if missing, and uses the
    /// serialized threading mode.
    ///
    /// - Parameter path: File system path, or `":memory:"` for an in-memory database.
    /// - Throws: A descriptive `RuntimeError` if the database cannot be opened.
    init(path: String) throws {
        let flags: Int32 = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard sqliteOK(rc), db != nil else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw SQLiteError.cannotOpen(path: path, reason: message)
        }
        // Enable foreign key support
        try exec("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Raw execution

    /// Executes one or more SQL statements that produce no result rows.
    ///
    /// Use for DDL (`CREATE TABLE`, `CREATE INDEX`) and simple DML that does
    /// not return rows.
    ///
    /// - Parameter sql: A null-terminated SQL string (may contain multiple
    ///   statements separated by semicolons).
    /// - Throws: ``SQLiteError/execFailed(_:_:)`` if any statement fails.
    func exec(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>? = nil
        let rc = sqlite3_exec(db, sql, nil, nil, &errmsg)
        if !sqliteOK(rc) {
            let message = errmsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errmsg)
            throw SQLiteError.execFailed(sql: sql, reason: message)
        }
    }

    // MARK: - Transaction management

    /// Begins an `IMMEDIATE` transaction.
    ///
    /// `BEGIN IMMEDIATE` acquires the write lock at the start, preventing
    /// `SQLITE_BUSY` errors that can occur with deferred transactions.
    func beginTransaction() throws {
        try exec("BEGIN IMMEDIATE;")
    }

    /// Commits the current transaction.
    func commit() throws {
        try exec("COMMIT;")
    }

    /// Rolls back the current transaction.
    func rollback() {
        try? exec("ROLLBACK;")
    }

    // MARK: - Prepared statements

    /// Prepares a SQL statement for repeated execution.
    ///
    /// - Parameter sql: The SQL text to prepare.
    /// - Returns: A ``SQLiteStatement`` wrapping the compiled statement.
    /// - Throws: ``SQLiteError/prepareFailed(_:_:)`` if compilation fails.
    func prepare(_ sql: String) throws -> SQLiteStatement {
        var stmt: OpaquePointer? = nil
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard sqliteOK(rc), let handle = stmt else {
            let reason = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.prepareFailed(sql: sql, reason: reason)
        }
        return SQLiteStatement(handle: handle)
    }

    // MARK: - Convenience: last insert rowid

    /// The rowid of the most recent successful INSERT on this connection.
    var lastInsertRowid: Int64 {
        sqlite3_last_insert_rowid(db)
    }
}

// MARK: - SQLiteError

/// Errors thrown by ``SQLiteConnection`` and ``SQLiteStatement``.
enum SQLiteError: Error {
    case cannotOpen(path: String, reason: String)
    case execFailed(sql: String, reason: String)
    case prepareFailed(sql: String, reason: String)
    case bindFailed(column: Int, reason: String)
    case stepFailed(reason: String)
}
