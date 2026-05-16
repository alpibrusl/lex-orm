import "std.sql" as sql

import "./connection" as conn

import "./error" as dbe

# Nested transaction via SQL SAVEPOINT / RELEASE / ROLLBACK TO.
# Safe to call inside an existing transaction[A] block.
fn savepoint[A](db :: conn.ConnDb, name :: Str, body :: (conn.ConnDb) -> [sql] Result[A, dbe.DbErr]) -> [sql] Result[A, dbe.DbErr] {
  match sql.exec(db.handle, "SAVEPOINT " + name, []) {
    Err(e) => Err(DbTransactionFailed("SAVEPOINT " + name + " failed: " + e.message)),
    Ok(_) => match body(db) {
      Err(e) => {
        let __lex_discard_1 := sql.exec(db.handle, "ROLLBACK TO SAVEPOINT " + name, [])
        let __lex_discard_2 := sql.exec(db.handle, "RELEASE SAVEPOINT " + name, [])
        Err(e)
      },
      Ok(v) => match sql.exec(db.handle, "RELEASE SAVEPOINT " + name, []) {
        Err(e) => Err(DbTransactionFailed("RELEASE SAVEPOINT " + name + " failed: " + e.message)),
        Ok(_) => Ok(v),
      },
    },
  }
}

