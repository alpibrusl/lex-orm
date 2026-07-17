# tests/test_uuid_params.lex — the uuid marker across dialects (#30).

import "std.io" as io

import "std.str" as str

import "std.list" as list

import "../src/connection" as conn

import "../src/query" as q

import "../src/predicate" as p

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(label)
  }
}

fn marked() -> q.SqlQuery {
  { sql: "SELECT * FROM t WHERE driver_id = ?::uuid AND name = ?", params: [PStr("abc"), PStr("x")] }
}

# PG: the ONLY form that binds — param pinned to text, cast server-side.
fn test_pg_expands_to_double_cast() -> Result[Unit, Str] {
  let out := q.for_dialect(marked(), DbPostgres(()))
  match assert_true(str.contains(out.sql, "$1::text::uuid"), str.concat("pg wrong: ", out.sql)) {
    Err(e) => Err(e),
    Ok(_) => assert_true(str.contains(out.sql, "name = $2"), str.concat("pg numbering wrong: ", out.sql)),
  }
}

# SQLite has no uuid type and no :: cast — the marker must vanish.
fn test_sqlite_strips_marker() -> Result[Unit, Str] {
  let out := q.for_dialect(marked(), DbSqlite(()))
  match assert_true(str.contains(out.sql, "driver_id = ?"), str.concat("sqlite wrong: ", out.sql)) {
    Err(e) => Err(e),
    Ok(_) => assert_true(not str.contains(out.sql, "::"), str.concat("sqlite kept a cast: ", out.sql)),
  }
}

fn test_eq_uuid_predicate_renders_marker() -> Result[Unit, Str] {
  let r := p.render_where([p.eq_uuid("driver_id", PStr("abc"))])
  match r {
    (sql_str, ps) => match assert_true(str.contains(sql_str, "?::uuid"), str.concat("predicate wrong: ", sql_str)) {
      Err(e) => Err(e),
      Ok(_) => assert_true(list.len(ps) == 1, "one param"),
    },
  }
}

fn run_all() -> [io, sql, fs_read, fs_write, time, crypto, random, net, concurrent, llm, proc] Unit {
  let results := [test_pg_expands_to_double_cast(), test_sqlite_strips_marker(), test_eq_uuid_predicate_renders_marker()]
  let failures := list.fold(results, [], fn (acc :: List[Str], r :: Result[Unit, Str]) -> List[Str] {
    match r {
      Ok(_) => acc,
      Err(m) => list.concat(acc, [m]),
    }
  })
  if list.is_empty(failures) {
    ()
  } else {
    let __show := list.fold(failures, (), fn (_a :: Unit, m :: Str) -> [io] Unit {
      io.print(str.concat("FAIL: ", str.concat(m, "\n")))
    })
    let __boom := 1 / 0
    ()
  }
}
