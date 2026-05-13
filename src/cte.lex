import "std.list" as list
import "std.sql"  as sql

import "./query"      as q
import "./connection" as conn
import "./error"      as dbe

# A SELECT query prefixed with a single named CTE (WITH clause).
type CteQuery[T] = {
  cte_name :: Str,
  cte_plan :: q.SqlQuery,
  main     :: q.SelectQuery[T],
}

fn with_cte[T](
  name     :: Str,
  cte_plan :: q.SqlQuery,
  main     :: q.SelectQuery[T],
) -> CteQuery[T] {
  { cte_name: name, cte_plan: cte_plan, main: main }
}

fn build_cte[T](cq :: CteQuery[T], dialect :: conn.Dialect) -> q.SqlQuery {
  let main_sq  := q.build_select_json(cq.main, dialect)
  let cte_part := "WITH " + sql_quote(cq.cte_name) + " AS (" + cq.cte_plan.sql + ") "
  { sql: cte_part + main_sq.sql,
    params: list.concat(cq.cte_plan.params, main_sq.params) }
}

fn run_cte[T](cq :: CteQuery[T], db :: conn.Db) -> [sql] Result[List[T], dbe.DbErr] {
  let sq         := q.for_dialect(build_cte(cq, db.dialect), db.dialect)
  let sql_params := list.map(sq.params, q.param_to_sql)
  let raw :: Result[List[{ _j :: Str }], Str] := sql.query(db.handle, sq.sql, sql_params)
  match raw {
    Err(e)   => Err(DbQueryFailed(e)),
    Ok(rows) => q.decode_rows(rows, cq.main.repo.decode),
  }
}

fn sql_quote(name :: Str) -> Str { "\"" + name + "\"" }
