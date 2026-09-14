# test_sqlite_tuning.lex — a database opened by lex-orm survives a second
# process.
#
# SQLite's default journal mode is `delete`: a writer takes an exclusive lock
# on the whole file and readers are locked out until it commits. std.sql
# already sets busy_timeout=5000, so a contending connection waits -- and then
# fails with "database is locked" anyway when the write outlives the wait.
#
# Found live in lex-loom#485: a company's orchestrator and its build worker
# share one company.db, and the worker logged "database is locked" twenty-four
# times in a row -- two minutes of five-second waits -- before it could claim a
# job, by which time the iteration it belonged to had been closed as failed.
# Six iterations of that company had never shipped.
#
# These assert WAL is actually SET on the handle lex-orm hands back, that the
# timeout is configurable above std.sql's default, and that neither pragma
# reaches an in-memory database or turns a working open into a failure.

import "std.str" as str

import "std.list" as list

import "std.io" as io

import "std.sql" as sql

import "std.int" as int

import "std.process" as proc

import "../src/connection" as conn

fn tmp_db() -> Str {
  "/tmp/lex-orm-tuning-test.db"
}

type JournalRow = { journal_mode :: Str }

type TimeoutRow = { timeout :: Int }

fn journal_mode(db :: conn.ConnDb) -> [sql] Str {
  let rows :: Result[List[JournalRow], SqlError] := sql.query(db.handle, "PRAGMA journal_mode", [])
  match rows {
    Err(_) => "",
    Ok(rs) => match list.head(rs) {
      None => "",
      Some(r) => r.journal_mode,
    },
  }
}

fn busy_timeout(db :: conn.ConnDb) -> [sql] Int {
  let rows :: Result[List[TimeoutRow], SqlError] := sql.query(db.handle, "PRAGMA busy_timeout", [])
  match rows {
    Err(_) => 0 - 1,
    Ok(rs) => match list.head(rs) {
      None => 0 - 1,
      Some(r) => r.timeout,
    },
  }
}

fn fresh() -> [sql, fs_write, proc] Result[conn.ConnDb, Str] {
  let __ := proc.run("bash", ["-c", str.concat("rm -f ", str.concat(tmp_db(), "*"))])
  match conn.open(tmp_db()) {
    Err(_) => Err("could not open the test database"),
    Ok(db) => Ok(db),
  }
}

fn test_a_file_database_is_in_wal_mode() -> [sql, fs_write, proc] Result[Unit, Str] {
  match fresh() {
    Err(e) => Err(e),
    Ok(db) => {
      let mode := str.to_lower(journal_mode(db))
      let __c := conn.close(db)
      if mode == "wal" {
        Ok(())
      } else {
        Err(str.concat("journal_mode is ", mode))
      }
    },
  }
}

# std.sql sets this, not us -- the guard is that lex-orm never LOWERS it while
# tuning the connection for concurrency.
fn test_a_file_database_waits_instead_of_failing() -> [sql, fs_write, proc] Result[Unit, Str] {
  match fresh() {
    Err(e) => Err(e),
    Ok(db) => {
      let t := busy_timeout(db)
      let __c := conn.close(db)
      if t > 0 {
        Ok(())
      } else {
        Err(str.concat("busy_timeout is ", int.to_str(t)))
      }
    },
  }
}

# WAL means nothing for an in-memory database, and the pragma must not turn a
# working open into a failure.
fn test_an_in_memory_database_still_opens() -> [sql, fs_write] Result[Unit, Str] {
  match conn.open(":memory:") {
    Err(_) => Err("an in-memory database no longer opens"),
    Ok(db) => {
      let mode := str.to_lower(journal_mode(db))
      let __c := conn.close(db)
      if mode == "wal" {
        Err("an in-memory database was put into WAL, which it cannot be")
      } else {
        Ok(())
      }
    },
  }
}

fn test_the_timeout_is_configurable() -> [sql, fs_write, proc] Result[Unit, Str] {
  let __ := proc.run("bash", ["-c", "rm -f /tmp/lex-orm-tuning-cfg.db*"])
  match conn.open_with_busy_timeout("/tmp/lex-orm-tuning-cfg.db", 1234) {
    Err(_) => Err("open_with_busy_timeout could not open"),
    Ok(db) => {
      let t := busy_timeout(db)
      let __c := conn.close(db)
      if t == 1234 {
        Ok(())
      } else {
        Err(str.concat("busy_timeout is ", int.to_str(t)))
      }
    },
  }
}

fn run_all() -> [sql, fs_write, proc, io] Int {
  let results := [("a file database is in WAL mode", test_a_file_database_is_in_wal_mode()), ("a file database still waits on a busy lock", test_a_file_database_waits_instead_of_failing()), ("an in-memory database still opens", test_an_in_memory_database_still_opens()), ("the timeout is configurable", test_the_timeout_is_configurable())]
  list.fold(results, 0, fn (fails :: Int, r :: (Str, Result[Unit, Str])) -> [io] Int {
    match r {
      (name, Ok(_)) => {
        let __ := io.print(str.concat("ok   ", name))
        fails
      },
      (name, Err(e)) => {
        let __ := io.print(str.join(["FAIL ", name, ": ", e], ""))
        fails + 1
      },
    }
  })
}

