import "std.str" as str
import "./error" as e

# Dialect variants are DbPostgres/DbSqlite (not DialectPostgres/DialectSqlite)
# to avoid collision with lex-schema/sdk's SqlDialect constructors.
type Dialect = DbPostgres | DbSqlite

type DbHandle = DbHandle(Int)

type Db = {
  dialect :: Dialect,
  handle  :: DbHandle,
}

type Tx = {
  dialect :: Dialect,
  handle  :: DbHandle,
}

fn dialect(db :: Db) -> Dialect { db.dialect }

fn dialect_name(d :: Dialect) -> Str {
  match d {
    DbPostgres => "postgres",
    DbSqlite   => "sqlite",
  }
}

fn connect_postgres(url :: Str) -> [sql] Result[Db, e.DbErr] {
  if str.is_empty(url) {
    Err(DbConnFailed("empty connection URL"))
  } else {
    Ok({ dialect: DbPostgres, handle: DbHandle(0) })
  }
}

fn connect_sqlite(path :: Str) -> [sql] Result[Db, e.DbErr] {
  if str.is_empty(path) {
    Err(DbConnFailed("empty file path"))
  } else {
    Ok({ dialect: DbSqlite, handle: DbHandle(0) })
  }
}

fn close(_db :: Db) -> [sql] Result[Unit, e.DbErr] { Ok(()) }

fn db_to_tx(db :: Db) -> Tx {
  { dialect: db.dialect, handle: db.handle }
}
