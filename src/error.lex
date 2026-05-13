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
