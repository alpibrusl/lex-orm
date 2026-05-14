# lex-orm — database error type
#
# DbErr wraps every failure surface the ORM can produce. Callers
# pattern-match on the variant; `message` turns any variant into a
# human-readable string for logging.
#
# lex-lang 0.9.2 made std.sql return structured SqlError values
# ({ message :: Str, code :: Option[Str], detail :: Option[Str] })
# instead of bare strings. DbSqlError stores the unwrapped SQLSTATE
# code (empty string when absent) and the human-readable message.

import "std.str" as str

# ---- Error ADT ---------------------------------------------------

type DbErr =
    DbConnErr(Str)
  | DbQueryErr(Str)
  | DbDecodeErr(Str)
  | DbNotFound
  | DbConflict(Str)
  | DbSqlError(Str, Str)

# ---- Constructors ------------------------------------------------

fn conn_err(msg :: Str)     -> DbErr { DbConnErr(msg) }
fn query_err(msg :: Str)    -> DbErr { DbQueryErr(msg) }
fn decode_err(msg :: Str)   -> DbErr { DbDecodeErr(msg) }
fn not_found()              -> DbErr { DbNotFound }
fn conflict(msg :: Str)     -> DbErr { DbConflict(msg) }

# Wrap a structured SqlError from std.sql (lex 0.9.2+).
# `code` is the SQLSTATE string (e.g. "23505" for unique violation).
# `detail` is the driver-level message.
fn sql_error(code :: Str, detail :: Str) -> DbErr {
  DbSqlError(code, detail)
}

# ---- Rendering ---------------------------------------------------

fn message(err :: DbErr) -> Str {
  match err {
    DbConnErr(msg)     => str.concat("connection error: ", msg),
    DbQueryErr(msg)    => str.concat("query error: ", msg),
    DbDecodeErr(msg)   => str.concat("decode error: ", msg),
    DbNotFound         => "not found",
    DbConflict(msg)    => str.concat("conflict: ", msg),
    DbSqlError(code, detail) =>
      str.concat("sql error [", str.concat(code, str.concat("]: ", detail))),
  }
}

# ---- SQLSTATE helpers --------------------------------------------

# True when the SQLSTATE indicates a unique-constraint violation.
# Postgres: 23505. SQLite: driver-level "UNIQUE constraint failed".
fn is_unique_violation(err :: DbErr) -> Bool {
  match err {
    DbSqlError(code, _) => code == "23505",
    _ => false,
  }
}

# True for foreign-key violations (Postgres 23503).
fn is_fk_violation(err :: DbErr) -> Bool {
  match err {
    DbSqlError(code, _) => code == "23503",
    _ => false,
  }
}

# True for serialization failures (Postgres 40001) — worth retrying.
fn is_serialization_failure(err :: DbErr) -> Bool {
  match err {
    DbSqlError(code, _) => code == "40001",
    _ => false,
  }
}
