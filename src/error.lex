import "std.str" as str

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
    DbConnFailed(m)          => str.concat("connection failed: ", m),
    DbQueryFailed(m)         => str.concat("query failed: ", m),
    DbNotFound               => "no row found",
    DbTooManyRows            => "too many rows",
    DbConstraintViolation(m) => str.concat("constraint violation: ", m),
    DbTimeout                => "query timed out",
    DbTransactionFailed(m)   => str.concat("transaction failed: ", m),
    DbDecodeFailed(m)        => str.concat("decode failed: ", m),
  }
}
