import "std.str" as str

import "std.sql" as sql

import "./error" as e

# DbPostgres/DbSqlite avoids constructor collision with lex-schema sdk's SqlDialect.
type Dialect = DbPostgres(Unit) | DbSqlite(Unit)

type ConnDb = { dialect :: Dialect, handle :: Db }

type ConnTx = { dialect :: Dialect, handle :: Db }

fn dialect(db :: ConnDb) -> Dialect {
  db.dialect
}

fn dialect_name(d :: Dialect) -> Str {
  match d {
    DbPostgres(_) => "postgres",
    DbSqlite(_) => "sqlite",
  }
}

fn open(url :: Str) -> [sql, fs_write] Result[ConnDb, e.DbErr] {
  let d := if str_starts_with(url, "postgres://") or str_starts_with(url, "postgresql://") {
    DbPostgres(())
  } else {
    DbSqlite(())
  }
  match sql.open(url) {
    Err(msg) => Err(DbConnErr(msg.message)),
    Ok(h) => Ok({ dialect: d, handle: h }),
  }
}

fn connect_postgres(url :: Str) -> [sql, fs_write] Result[ConnDb, e.DbErr] {
  match sql.open(url) {
    Err(msg) => Err(DbConnErr(msg.message)),
    Ok(h) => Ok({ dialect: DbPostgres(()), handle: h }),
  }
}

fn connect_sqlite(path :: Str) -> [sql, fs_write] Result[ConnDb, e.DbErr] {
  match sql.open(path) {
    Err(msg) => Err(DbConnErr(msg.message)),
    Ok(h) => Ok({ dialect: DbSqlite(()), handle: h }),
  }
}

fn close(db :: ConnDb) -> [sql] Unit {
  sql.close(db.handle)
}

fn db_to_tx(db :: ConnDb) -> ConnTx {
  { dialect: db.dialect, handle: db.handle }
}

fn str_starts_with(s :: Str, prefix :: Str) -> Bool {
  let n := str.len(prefix)
  if str.len(s) < n {
    false
  } else {
    str.slice(s, 0, n) == prefix
  }
}

