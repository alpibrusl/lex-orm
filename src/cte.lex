import "std.list" as list

import "std.sql" as sql

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "./query" as q

import "./connection" as conn

import "./error" as dbe

# A SELECT query prefixed with a single named CTE (WITH clause).
type CteQuery = { cte_name :: Str, cte_plan :: q.SqlQuery, main :: q.SelectQuery }

fn with_cte(name :: Str, cte_plan :: q.SqlQuery, main :: q.SelectQuery) -> CteQuery {
  { cte_name: name, cte_plan: cte_plan, main: main }
}

fn build_cte(cq :: CteQuery, dialect :: conn.Dialect) -> q.SqlQuery {
  let main_sq := q.build_select_json(cq.main, dialect)
  let cte_part := "WITH " + sql_quote(cq.cte_name) + " AS (" + cq.cte_plan.sql + ") "
  { sql: cte_part + main_sq.sql, params: list.concat(cq.cte_plan.params, main_sq.params) }
}

fn run_cte[R](cq :: CteQuery, db :: conn.ConnDb, decode :: (jv.Json) -> Result[R, se.Errors]) -> [sql] Result[List[R], dbe.DbErr] {
  let sq := q.for_dialect(build_cte(cq, db.dialect), db.dialect)
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
            Err(_) => Err(dbe.decode_err("cte decode failed")),
            Ok(v) => Ok(list.concat(items, [v])),
          },
        },
      }
    }),
  }
}

fn sql_quote(name :: Str) -> Str {
  "\"" + name + "\""
}
