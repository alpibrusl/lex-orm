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

type CountRow = { n :: Int }

fn rows_in(path :: Str) -> [sql, fs_write] Int {
  match conn.open(path) {
    Err(_) => 0 - 1,
    Ok(db) => {
      let rs :: Result[List[CountRow], SqlError] := sql.query(db.handle, "SELECT count(*) AS n FROM notes", [])
      let n := match rs {
        Err(_) => 0 - 1,
        Ok(list_rows) => match list.head(list_rows) {
          None => 0 - 1,
          Some(r) => r.n,
        },
      }
      let __c := conn.close(db)
      n
    },
  }
}

fn seed(path :: Str) -> [sql, fs_write, proc] Result[conn.ConnDb, Str] {
  let __ := proc.run("bash", ["-c", str.concat("rm -f ", str.concat(path, "*"))])
  match conn.open(path) {
    Err(_) => Err("could not open"),
    Ok(db) => {
      let __t := sql.exec(db.handle, "CREATE TABLE notes (body TEXT)", [])
      let __i := sql.exec(db.handle, "INSERT INTO notes (body) VALUES ('one')", [])
      let __j := sql.exec(db.handle, "INSERT INTO notes (body) VALUES ('two')", [])
      Ok(db)
    },
  }
}

# The handover case: someone copies ONE file and expects a whole database.
fn test_a_checkpointed_database_copies_as_one_file() -> [sql, fs_write, proc] Result[Unit, Str] {
  let src := "/tmp/lex-orm-ckpt-src.db"
  let dst := "/tmp/lex-orm-ckpt-dst.db"
  match seed(src) {
    Err(e) => Err(e),
    Ok(db) => {
      let __ck := conn.checkpoint(db)
      let __cp := proc.run("bash", ["-c", str.join(["rm -f ", dst, "*; cp ", src, " ", dst], "")])
      let n := rows_in(dst)
      let __c := conn.close(db)
      if n == 2 {
        Ok(())
      } else {
        Err(str.concat("the single-file copy has rows: ", int.to_str(n)))
      }
    },
  }
}

# close() checkpoints too, so a database someone finished with is complete.
fn test_close_leaves_a_complete_file() -> [sql, fs_write, proc] Result[Unit, Str] {
  let src := "/tmp/lex-orm-close-src.db"
  let dst := "/tmp/lex-orm-close-dst.db"
  match seed(src) {
    Err(e) => Err(e),
    Ok(db) => {
      let __c := conn.close(db)
      let __cp := proc.run("bash", ["-c", str.join(["rm -f ", dst, "*; cp ", src, " ", dst], "")])
      let n := rows_in(dst)
      if n == 2 {
        Ok(())
      } else {
        Err(str.concat("the copy of a closed database has rows: ", int.to_str(n)))
      }
    },
  }
}

fn run_all() -> [sql, fs_write, proc, io] Int {
  let results := [("a file database is in WAL mode", test_a_file_database_is_in_wal_mode()), ("a file database still waits on a busy lock", test_a_file_database_waits_instead_of_failing()), ("an in-memory database still opens", test_an_in_memory_database_still_opens()), ("the timeout is configurable", test_the_timeout_is_configurable()), ("a checkpointed database copies as one file", test_a_checkpointed_database_copies_as_one_file()), ("close leaves a complete file", test_close_leaves_a_complete_file())]
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

