import "std.list" as list

import "std.sql" as sql

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "./query" as q

import "./connection" as conn

import "./error" as dbe

# Execute arbitrary SQL with no typed return (DDL, raw DML).
# Returns the number of rows affected.
fn exec_raw(sql_str :: Str, params :: List[SqlParam], db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := q.for_dialect({ sql: sql_str, params: params }, db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(n) => Ok(n),
  }
}

# Execute a raw SELECT and decode each row via a caller-supplied JSON decoder.
# The SQL must return a single column aliased as _j containing a JSON string,
# e.g.:  SELECT json_object('id', id, 'name', name) AS _j FROM users WHERE ...
fn query_raw[R](sql_str :: Str, params :: List[SqlParam], db :: conn.ConnDb, decode :: (jv.Json) -> Result[R, se.Errors]) -> [sql] Result[List[R], dbe.DbErr] {
  let sq := q.for_dialect({ sql: sql_str, params: params }, db.dialect)
  let raw :: Result[List[{ _j :: Str }], SqlError] := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(rows) => list.fold(rows, Ok([]), fn (acc :: Result[List[R], dbe.DbErr], row :: { _j :: Str }) -> Result[List[R], dbe.DbErr] {
      match acc {
        Err(e) => Err(e),
        Ok(items) => match jv.parse(row._j) {
          Err(pe) => Err(dbe.decode_err(pe.message)),
          Ok(j) => match decode(j) {
            Err(_) => Err(dbe.decode_err("raw query decode failed")),
            Ok(v) => Ok(list.concat(items, [v])),
          },
        },
      }
    }),
  }
}

# ---- Schema introspection -----------------------------------------
type ColumnInfo = { name :: Str, data_type :: Str }

# List all user-facing table names in the database.
fn introspect_tables(db :: conn.ConnDb) -> [sql] Result[List[Str], dbe.DbErr] {
  let sql_str := match db.dialect {
    DbPostgres => "SELECT table_name AS name FROM information_schema.tables " + "WHERE table_schema = 'public' ORDER BY table_name",
    DbSqlite => "SELECT name FROM sqlite_master WHERE type = 'table' " + "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  }
  let raw :: Result[List[{ name :: Str }], SqlError] := sql.query(db.handle, sql_str, [])
  match raw {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(rows) => Ok(list.map(rows, fn (r :: { name :: Str }) -> Str {
      r.name
    })),
  }
}

# List columns (name + SQL type) for a given table.
fn introspect_columns(db :: conn.ConnDb, table :: Str) -> [sql] Result[List[ColumnInfo], dbe.DbErr] {
  let param := [PStr(table)]
  let raw :: Result[List[{ name :: Str, data_type :: Str }], SqlError] := match db.dialect {
    DbPostgres => sql.query(db.handle, "SELECT column_name AS name, data_type " + "FROM information_schema.columns " + "WHERE table_schema = 'public' AND table_name = $1 " + "ORDER BY ordinal_position", param),
    DbSqlite => sql.query(db.handle, "SELECT name, type AS data_type FROM pragma_table_info(?) ORDER BY cid", param),
  }
  match raw {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(rows) => Ok(list.map(rows, fn (r :: { name :: Str, data_type :: Str }) -> ColumnInfo {
      { name: r.name, data_type: r.data_type }
    })),
  }
}

