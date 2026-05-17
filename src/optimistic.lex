import "std.int" as int

import "std.sql" as sql

import "./predicate" as p

import "./query" as q

import "./connection" as conn

import "./error" as dbe

fn with_version_check(upd :: q.UpdateQuery, version_col :: Str, expected_ver :: Int) -> q.UpdateQuery {
  q.where_update(q.set_col(upd, version_col, PInt(expected_ver + 1)), p.eq(version_col, PInt(expected_ver)))
}

fn run_optimistic(upd :: q.UpdateQuery, version_col :: Str, expected_ver :: Int, db :: conn.ConnDb) -> [sql] Result[Unit, dbe.DbErr] {
  match q.run_update(with_version_check(upd, version_col, expected_ver), db) {
    Err(e) => Err(dbe.conflict("version conflict on " + version_col + ": expected " + int.to_str(expected_ver)))
  }
}
