import "std.str" as str

import "std.sql" as sql

import "std.int" as int

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

# A SQLite database opened by two processes needs WAL, or the second one waits
# five seconds and then fails anyway.
#
# SQLite's default journal mode is `delete`: a writer takes an EXCLUSIVE lock
# on the whole file, and every reader is locked out for the duration of the
# write. std.sql already sets busy_timeout=5000, so a contending connection
# does wait -- and when the lock outlives those five seconds it still returns
# "database is locked". A timeout only converts an instant failure into a slow
# one; it does not make concurrent access work.
#
# Found live in lex-loom (alpibrusl/lex-loom#485). A company runs an
# orchestrator process and one or more worker processes against one
# company.db. The worker logged
#
#   [loom/worker w1] claim error (transient, backing off): database is locked
#
# twenty-four times in a row -- about two minutes of five-second waits -- and
# by the time it claimed a job, the iteration it belonged to had been closed
# as failed. Six iterations of that company had never shipped. `PRAGMA
# journal_mode` on its database said `delete`, and lex-orm set no pragma at
# all.
#
# WAL lets readers and writers proceed concurrently (one writer at a time
# still, which is the honest limit of SQLite). The busy timeout stays
# configurable for callers who want to wait longer than std.sql's five
# seconds; the default here matches it, so passing nothing changes nothing.
#
# Neither is applied to Postgres, or to an in-memory database where WAL means
# nothing. Neither can fail an open: a filesystem that cannot do WAL (some
# network mounts) simply reports the mode it kept, and the pragma results are
# discarded rather than checked.
#
# NOTE for callers who copy database files: WAL keeps recent commits in a
# `-wal` sidecar until a checkpoint, so copying only `foo.db` can miss them.
# Copy `foo.db`, `foo.db-wal` and `foo.db-shm` together, or close the database
# first -- closing the last connection checkpoints.
fn open(url :: Str) -> [sql, fs_write] Result[ConnDb, e.DbErr] {
  open_with_busy_timeout(url, default_busy_timeout_ms())
}

# Matches what std.sql already sets, so the default is a no-op and only a
# caller who raises it changes anything.
fn default_busy_timeout_ms() -> Int {
  5000
}

fn open_with_busy_timeout(url :: Str, busy_timeout_ms :: Int) -> [sql, fs_write] Result[ConnDb, e.DbErr] {
  let d := if str_starts_with(url, "postgres://") or str_starts_with(url, "postgresql://") {
    DbPostgres(())
  } else {
    DbSqlite(())
  }
  match sql.open(url) {
    Err(msg) => Err(DbConnErr(msg.message)),
    Ok(h) => {
      let __tuned := tune_sqlite({ dialect: d, handle: h }, url, busy_timeout_ms)
      Ok({ dialect: d, handle: h })
    },
  }
}

# Best effort by construction: the result of every pragma is discarded, so a
# database that cannot take one is still a usable database.
fn tune_sqlite(db :: ConnDb, url :: Str, busy_timeout_ms :: Int) -> [sql] Unit {
  match db.dialect {
    DbPostgres(_) => (),
    DbSqlite(_) => if is_memory(url) {
      ()
    } else {
      let __wal := sql.query(db.handle, "PRAGMA journal_mode=WAL", [])
      let __busy := sql.query(db.handle, str.concat("PRAGMA busy_timeout=", int.to_str(busy_timeout_ms)), [])
      ()
    },
  }
}

# ":memory:" and the shared-cache URI form both mean "no file, no WAL".
fn is_memory(url :: Str) -> Bool {
  if url == ":memory:" {
    true
  } else {
    str.contains(url, "mode=memory")
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
    Ok(h) => {
      let __tuned := tune_sqlite({ dialect: DbSqlite(()), handle: h }, path, default_busy_timeout_ms())
      Ok({ dialect: DbSqlite(()), handle: h })
    },
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

