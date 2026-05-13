import "std.sql"  as sql

import "./connection" as conn
import "./error"      as dbe

# Nested transaction via SQL SAVEPOINT / RELEASE / ROLLBACK TO.
# Safe to call inside an existing transaction[A] block.
fn savepoint[A](
  db   :: conn.Db,
  name :: Str,
  body :: (conn.Db) -> [sql] Result[A, dbe.DbErr],
) -> [sql] Result[A, dbe.DbErr] {
  match sql.exec(db.handle, "SAVEPOINT " + name, []) {
    Err(e) => Err(DbTransactionFailed("SAVEPOINT " + name + " failed: " + e)),
    Ok(_)  =>
      match body(db) {
        Err(e) => {
          let _ := sql.exec(db.handle, "ROLLBACK TO SAVEPOINT " + name, [])
          let _ := sql.exec(db.handle, "RELEASE SAVEPOINT " + name, [])
          Err(e)
        },
        Ok(v) =>
          match sql.exec(db.handle, "RELEASE SAVEPOINT " + name, []) {
            Err(e) => Err(DbTransactionFailed("RELEASE SAVEPOINT " + name + " failed: " + e)),
            Ok(_)  => Ok(v),
          },
      },
  }
}
