import Foundation
import CSQLite

// SQLITE_TRANSIENT is a C macro that expands to `(sqlite3_destructor_type)(-1)`.
// It is not exported through the module map, so we define it manually.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - SQLiteStatement

/// A wrapper around a compiled SQLite prepared statement (`sqlite3_stmt`).
///
/// Provides typed bind and column accessor methods. The statement is
/// automatically finalized when the object is deallocated.
///
/// - Important: Not `Sendable`. Use only from the actor that owns the connection.
final class SQLiteStatement {

    // MARK: - State

    private let handle: OpaquePointer

    // MARK: - Init / deinit

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_finalize(handle)
    }

    // MARK: - Execution

    /// Advances the statement to the next result row.
    ///
    /// - Returns: `true` if a row is available; `false` if the statement is done.
    /// - Throws: ``SQLiteError/stepFailed(_:)`` on error.
    @discardableResult
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW:  return true
        case SQLITE_DONE: return false
        default:
            let reason = String(cString: sqlite3_errmsg(sqlite3_db_handle(handle)))
            throw SQLiteError.stepFailed(reason: reason)
        }
    }

    /// Resets the statement so it can be re-executed with new bindings.
    func reset() {
        sqlite3_reset(handle)
    }

    // MARK: - Binding (1-indexed)

    /// Binds a `TEXT` value at the given 1-based parameter index.
    func bindText(_ value: String, at index: Int32) throws {
        let rc = sqlite3_bind_text(handle, index, value, -1, sqliteTransient)
        if !sqliteOK(rc) {
            let reason = String(cString: sqlite3_errmsg(sqlite3_db_handle(handle)))
            throw SQLiteError.bindFailed(column: Int(index), reason: reason)
        }
    }

    /// Binds a `REAL` (Double) value at the given 1-based parameter index.
    func bindDouble(_ value: Double, at index: Int32) throws {
        let rc = sqlite3_bind_double(handle, index, value)
        if !sqliteOK(rc) {
            let reason = String(cString: sqlite3_errmsg(sqlite3_db_handle(handle)))
            throw SQLiteError.bindFailed(column: Int(index), reason: reason)
        }
    }

    /// Binds an `INTEGER` (Int64) value at the given 1-based parameter index.
    func bindInt64(_ value: Int64, at index: Int32) throws {
        let rc = sqlite3_bind_int64(handle, index, value)
        if !sqliteOK(rc) {
            let reason = String(cString: sqlite3_errmsg(sqlite3_db_handle(handle)))
            throw SQLiteError.bindFailed(column: Int(index), reason: reason)
        }
    }

    /// Binds `NULL` at the given 1-based parameter index.
    func bindNull(at index: Int32) throws {
        let rc = sqlite3_bind_null(handle, index)
        if !sqliteOK(rc) {
            let reason = String(cString: sqlite3_errmsg(sqlite3_db_handle(handle)))
            throw SQLiteError.bindFailed(column: Int(index), reason: reason)
        }
    }

    /// Binds an optional `REAL` (Double?) — binds NULL if nil.
    func bindOptionalDouble(_ value: Double?, at index: Int32) throws {
        if let v = value {
            try bindDouble(v, at: index)
        } else {
            try bindNull(at: index)
        }
    }

    /// Binds an optional `TEXT` — binds NULL if nil.
    func bindOptionalText(_ value: String?, at index: Int32) throws {
        if let v = value {
            try bindText(v, at: index)
        } else {
            try bindNull(at: index)
        }
    }

    // MARK: - Column accessors (0-indexed)

    /// Returns the TEXT value from the given 0-based column index.
    func columnText(_ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(handle, index) else { return "" }
        return String(cString: ptr)
    }

    /// Returns the REAL value from the given 0-based column index.
    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(handle, index)
    }

    /// Returns the INTEGER value from the given 0-based column index.
    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    /// Returns whether the given 0-based column value is NULL.
    func columnIsNull(_ index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    /// Returns the optional TEXT value (nil if NULL) from the given 0-based column.
    func columnOptionalText(_ index: Int32) -> String? {
        columnIsNull(index) ? nil : columnText(index)
    }

    /// Returns the optional REAL value (nil if NULL) from the given 0-based column.
    func columnOptionalDouble(_ index: Int32) -> Double? {
        columnIsNull(index) ? nil : columnDouble(index)
    }
}
