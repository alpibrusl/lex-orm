import "std.sql"  as sql

import "./connection" as conn
import "./error"      as dbe

# Nested transaction via SQL SAVEPOINT / RELEASE / ROLLBACK TO.
# Safe to call inside an existing transaction[A] block.
fn savepoint[A](
  db   :: conn.ConnDb,
  name :: Str,
  body :: (conn.ConnDb) -> [sql] Result[A, dbe.DbErr],
) -> [sql] Result[A, dbe.DbErr] {
  match sql.exec(db.handle, "SAVEPOINT " + name, []) {
    Err(se) => Err(DbTransactionFailed("SAVEPOINT " + name + " failed: " + se.message)),
    Ok(_)   =>
      match body(db) {
        Err(e) => {
          let _ := sql.exec(db.handle, "ROLLBACK TO SAVEPOINT " + name, [])
          let _ := sql.exec(db.handle, "RELEASE SAVEPOINT " + name, [])
          Err(e)
        },
        Ok(v) =>
          match sql.exec(db.handle, "RELEASE SAVEPOINT " + name, []) {
            Err(se) => Err(DbTransactionFailed("RELEASE SAVEPOINT " + name + " failed: " + se.message)),
            Ok(_)   => Ok(v),
          },
      },
  }
}
