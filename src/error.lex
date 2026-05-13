type DbErr =
    DbConnFailed(Str)
  | DbQueryFailed(Str)
  | DbNotFound
  | DbTooManyRows
  | DbConstraintViolation(Str)
  | DbTimeout
  | DbTransactionFailed(Str)
  | DbDecodeFailed(Str)

fn message(err :: DbErr) -> Str {
  match err {
    DbConnFailed(m)          => "connection failed: " + m,
    DbQueryFailed(m)         => "query failed: " + m,
    DbNotFound               => "no row found",
    DbTooManyRows            => "too many rows",
    DbConstraintViolation(m) => "constraint violation: " + m,
    DbTimeout                => "query timed out",
    DbTransactionFailed(m)   => "transaction failed: " + m,
    DbDecodeFailed(m)        => "decode failed: " + m,
  }
}

# Map a structured SqlError (0.9.2+) to the appropriate DbErr variant.
# Uses SqlError.code (SQLSTATE for Postgres, symbolic name for SQLite)
# to distinguish constraint violations and timeouts without parsing
# the human-readable message string.
fn sql_err_to_db_err(e :: SqlError) -> DbErr {
  match e.code {
    None       => DbQueryFailed(e.message),
    Some(code) =>
      if code == "SQLITE_CONSTRAINT_UNIQUE"
        or code == "SQLITE_CONSTRAINT_PRIMARYKEY"
        or code == "SQLITE_CONSTRAINT_FOREIGNKEY"
        or code == "SQLITE_CONSTRAINT_NOTNULL"
        or code == "23000"
        or code == "23502"
        or code == "23503"
        or code == "23505"
      {
        DbConstraintViolation(e.message)
      } else {
        if code == "SQLITE_BUSY"
          or code == "SQLITE_LOCKED"
          or code == "40001"
          or code == "40P01"
        {
          DbTimeout
        } else {
          DbQueryFailed(e.message)
        }
      },
  }
}
