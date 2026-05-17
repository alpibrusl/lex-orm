import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.sql" as sql

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "./predicate" as p

import "./query" as q

import "./connection" as conn

import "./error" as dbe

type AggExpr = AggCount | AggCountCol(Str) | AggSum(Str) | AggAvg(Str) | AggMin(Str) | AggMax(Str)

type AggQuery[T] = { repo :: q.Repo[T], aggs :: List[(Str, AggExpr)], filters :: List[p.Predicate], group_by :: List[Str], having :: List[p.Predicate], ordering :: List[(Str, q.Order)], limit_n :: Option[Int] }

fn agg_select[T](repo :: q.Repo[T]) -> AggQuery[T] {
  { repo: repo, aggs: [], filters: [], group_by: [], having: [], ordering: [], limit_n: None }
}

fn add_agg[T](aq :: AggQuery[T], alias :: Str, expr :: AggExpr) -> AggQuery[T] {
  { repo: aq.repo, aggs: list.concat(aq.aggs, [(alias, expr)]), filters: aq.filters, group_by: aq.group_by, having: aq.having, ordering: aq.ordering, limit_n: aq.limit_n }
}

fn group_by_col[T](aq :: AggQuery[T], col :: Str) -> AggQuery[T] {
  { repo: aq.repo, aggs: aq.aggs, filters: aq.filters, group_by: list.concat(aq.group_by, [col]), having: aq.having, ordering: aq.ordering, limit_n: aq.limit_n }
}

fn having_clause[T](aq :: AggQuery[T], pred :: p.Predicate) -> AggQuery[T] {
  { repo: aq.repo, aggs: aq.aggs, filters: aq.filters, group_by: aq.group_by, having: list.concat(aq.having, [pred]), ordering: aq.ordering, limit_n: aq.limit_n }
}

fn where_agg[T](aq :: AggQuery[T], pred :: p.Predicate) -> AggQuery[T] {
  { repo: aq.repo, aggs: aq.aggs, filters: list.concat(aq.filters, [pred]), group_by: aq.group_by, having: aq.having, ordering: aq.ordering, limit_n: aq.limit_n }
}

fn order_agg[T](aq :: AggQuery[T], col :: Str, dir :: q.Order) -> AggQuery[T] {
  { repo: aq.repo, aggs: aq.aggs, filters: aq.filters, group_by: aq.group_by, having: aq.having, ordering: list.concat(aq.ordering, [(col, dir)]), limit_n: aq.limit_n }
}

fn limit_agg[T](aq :: AggQuery[T], n :: Int) -> AggQuery[T] {
  { repo: aq.repo, aggs: aq.aggs, filters: aq.filters, group_by: aq.group_by, having: aq.having, ordering: aq.ordering, limit_n: Some(n) }
}

fn render_agg_expr(expr :: AggExpr) -> Str {
  match expr {
    AggCount => "COUNT(*)",
    AggCountCol(col) => "COUNT(" + sql_quote(col) + ")",
    AggSum(col) => "SUM(" + sql_quote(col) + ")",
    AggAvg(col) => "AVG(" + sql_quote(col) + ")",
    AggMin(col) => "MIN(" + sql_quote(col) + ")",
    AggMax(col) => "MAX(" + sql_quote(col) + ")",
  }
}

fn build_agg[T](aq :: AggQuery[T]) -> q.SqlQuery {
  let tname := sql_quote(aq.repo.table)
  let group_cols := list.map(aq.group_by, sql_quote)
  let agg_cols := list.map(aq.aggs, fn (pair :: (Str, AggExpr)) -> Str {
    let alias := match pair {
      (a, _) => a,
    }
    let expr := match pair {
      (_, e) => e,
    }
    render_agg_expr(expr) + " AS " + sql_quote(alias)
  })
  let sel_cols := list.concat(group_cols, agg_cols)
  let sel_str := if list.is_empty(sel_cols) {
    "COUNT(*) AS count"
  } else {
    str.join(sel_cols, ", ")
  }
  let base := "SELECT " + sel_str + " FROM " + tname
  let where_r := p.render_where(aq.filters)
  let where_sql := match where_r {
    (s, _) => s,
  }
  let where_params := match where_r {
    (_, ps) => ps,
  }
  let with_where := if str.is_empty(where_sql) {
    base
  } else {
    base + " WHERE " + where_sql
  }
  let with_group := if list.is_empty(aq.group_by) {
    with_where
  } else {
    with_where + " GROUP BY " + str.join(list.map(aq.group_by, sql_quote), ", ")
  }
  let having_r := p.render_where(aq.having)
  let having_sql := match having_r {
    (s, _) => s,
  }
  let having_params := match having_r {
    (_, ps) => ps,
  }
  let with_having := if str.is_empty(having_sql) {
    with_group
  } else {
    with_group + " HAVING " + having_sql
  }
  let with_order := if list.is_empty(aq.ordering) {
    with_having
  } else {
    let parts := list.map(aq.ordering, fn (pair :: (Str, q.Order)) -> Str {
      let col := match pair {
        (c, _) => c,
      }
      let dir := match pair {
        (_, d) => d,
      }
      sql_quote(col) + match dir {
        Asc => " ASC",
        Desc => " DESC",
      }
    })
    with_having + " ORDER BY " + str.join(parts, ", ")
  }
  let final_sql := match aq.limit_n {
    None => with_order,
    Some(n) => with_order + " LIMIT " + int.to_str(n),
  }
  { sql: final_sql, params: list.concat(where_params, having_params) }
}

fn build_agg_json[T](aq :: AggQuery[T], dialect :: conn.Dialect) -> q.SqlQuery {
  let inner := build_agg(aq)
  let group_als := aq.group_by
  let agg_als := list.map(aq.aggs, fn (pair :: (Str, AggExpr)) -> Str {
    match pair {
      (a, _) => a,
    }
  })
  let aliases := list.concat(group_als, agg_als)
  let pairs := list.fold(aliases, [], fn (acc :: List[Str], alias :: Str) -> List[Str] {
    list.concat(acc, ["'" + alias + "'", sql_quote(alias)])
  })
  let json_fn := match dialect {
    DbPostgres => "json_build_object",
    DbSqlite => "json_object",
  }
  let wrap_sql := "SELECT " + json_fn + "(" + str.join(pairs, ", ") + ") AS _j FROM (" + inner.sql + ") _agg"
  { sql: wrap_sql, params: inner.params }
}

# Run an aggregate query; decode each result row with a caller-supplied
# JSON decoder. The aggregate result type R is separate from the repo's
# row type T, so the decoder cannot be reused from `Repo[T]`.
fn run_agg[T, R](aq :: AggQuery[T], db :: conn.ConnDb, decode :: (jv.Json) -> Result[R, se.Errors]) -> [sql] Result[List[R], dbe.DbErr] {
  let sq := q.for_dialect(build_agg_json(aq, db.dialect), db.dialect)
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
            Err(_) => Err(dbe.decode_err("aggregate decode failed")),
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
