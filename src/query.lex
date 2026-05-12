import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "lex-schema/schema"     as s
import "lex-schema/json_value" as jv
import "lex-schema/error"      as se

import "./predicate"  as p
import "./connection" as conn
import "./error"      as dbe

type Repo[T] = {
  schema :: s.ModelSchema,
  table  :: Str,
  decode :: (jv.Json) -> Result[T, se.Errors],
}

fn for_schema[T](
  schema :: s.ModelSchema,
  decode :: (jv.Json) -> Result[T, se.Errors]
) -> Repo[T] {
  { schema: schema, table: sql_ident(schema.title), decode: decode }
}

fn with_table[T](repo :: Repo[T], table :: Str) -> Repo[T] {
  { schema: repo.schema, table: table, decode: repo.decode }
}

type Order = Asc | Desc

type SelectQuery[T] = {
  repo     :: Repo[T],
  filters  :: List[p.Predicate],
  ordering :: List[(Str, Order)],
  limit_n  :: Option[Int],
  offset_n :: Option[Int],
}

type InsertQuery[T] = {
  repo  :: Repo[T],
  value :: jv.Json,
}

type UpdateQuery[T] = {
  repo    :: Repo[T],
  sets    :: List[(Str, p.Param)],
  filters :: List[p.Predicate],
}

type DeleteQuery[T] = {
  repo    :: Repo[T],
  filters :: List[p.Predicate],
}

type SqlQuery = {
  sql    :: Str,
  params :: List[p.Param],
}

# ---- Query builders (pure) ----------------------------------------

fn select[T](repo :: Repo[T]) -> SelectQuery[T] {
  { repo: repo, filters: [], ordering: [], limit_n: None, offset_n: None }
}

fn where_clause[T](q :: SelectQuery[T], pred :: p.Predicate) -> SelectQuery[T] {
  { repo: q.repo, filters: list.concat(q.filters, [pred]),
    ordering: q.ordering, limit_n: q.limit_n, offset_n: q.offset_n }
}

fn order_by[T](q :: SelectQuery[T], col :: Str, dir :: Order) -> SelectQuery[T] {
  { repo: q.repo, filters: q.filters,
    ordering: list.concat(q.ordering, [(col, dir)]),
    limit_n: q.limit_n, offset_n: q.offset_n }
}

fn limit[T](q :: SelectQuery[T], n :: Int) -> SelectQuery[T] {
  { repo: q.repo, filters: q.filters, ordering: q.ordering,
    limit_n: Some(n), offset_n: q.offset_n }
}

fn offset[T](q :: SelectQuery[T], n :: Int) -> SelectQuery[T] {
  { repo: q.repo, filters: q.filters, ordering: q.ordering,
    limit_n: q.limit_n, offset_n: Some(n) }
}

fn insert[T](repo :: Repo[T], value :: jv.Json) -> InsertQuery[T] {
  { repo: repo, value: value }
}

fn update[T](repo :: Repo[T]) -> UpdateQuery[T] {
  { repo: repo, sets: [], filters: [] }
}

fn set_col[T](q :: UpdateQuery[T], col :: Str, v :: p.Param) -> UpdateQuery[T] {
  { repo: q.repo, sets: list.concat(q.sets, [(col, v)]), filters: q.filters }
}

fn where_update[T](q :: UpdateQuery[T], pred :: p.Predicate) -> UpdateQuery[T] {
  { repo: q.repo, sets: q.sets, filters: list.concat(q.filters, [pred]) }
}

fn delete_from[T](repo :: Repo[T]) -> DeleteQuery[T] {
  { repo: repo, filters: [] }
}

fn where_delete[T](q :: DeleteQuery[T], pred :: p.Predicate) -> DeleteQuery[T] {
  { repo: q.repo, filters: list.concat(q.filters, [pred]) }
}

# ---- SQL building (pure) ------------------------------------------

fn build_select[T](q :: SelectQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let base  := str.concat("SELECT * FROM ", tname)
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s, _) => s }
  let where_params := match where_result { (_, ps) => ps }
  let with_where := if str.is_empty(where_sql) { base }
    else { str.concat(base, str.concat(" WHERE ", where_sql)) }
  let with_order := if list.is_empty(q.ordering) { with_where }
    else {
      let order_parts := list.map(q.ordering, fn (pair :: (Str, Order)) -> Str {
        let col := match pair { (c, _) => c }
        let dir := match pair { (_, d) => d }
        str.concat(sql_quote(col), match dir { Asc => " ASC", Desc => " DESC" })
      })
      str.concat(with_where, str.concat(" ORDER BY ", str.join(order_parts, ", ")))
    }
  let with_limit := match q.limit_n {
    None    => with_order,
    Some(n) => str.concat(with_order, str.concat(" LIMIT ", int.to_str(n))),
  }
  let final_sql := match q.offset_n {
    None    => with_limit,
    Some(n) => str.concat(with_limit, str.concat(" OFFSET ", int.to_str(n))),
  }
  { sql: final_sql, params: where_params }
}

fn build_insert[T](q :: InsertQuery[T]) -> SqlQuery {
  let tname  := sql_quote(q.repo.table)
  let fields := q.repo.schema.fields
  let col_names := list.map(fields, fn (f :: s.Field) -> Str {
    sql_quote(f.name)
  })
  let placeholders := list.map(fields, fn (_f :: s.Field) -> Str { "?" })
  let params := list.map(fields, fn (f :: s.Field) -> p.Param {
    json_to_param(jv.get_field(q.value, f.name))
  })
  let sql := str.concat(
    str.concat("INSERT INTO ", str.concat(tname, " (")),
    str.concat(
      str.concat(str.join(col_names, ", "), ") VALUES ("),
      str.concat(str.join(placeholders, ", "), ")")))
  { sql: sql, params: params }
}

fn build_update[T](q :: UpdateQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let set_parts := list.map(q.sets, fn (pair :: (Str, p.Param)) -> Str {
    let col := match pair { (c, _) => c }
    str.concat(sql_quote(col), " = ?")
  })
  let set_params := list.map(q.sets, fn (pair :: (Str, p.Param)) -> p.Param {
    match pair { (_, v) => v }
  })
  let base := str.concat("UPDATE ", str.concat(tname,
    str.concat(" SET ", str.join(set_parts, ", "))))
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s, _) => s }
  let where_params := match where_result { (_, ps) => ps }
  let final_sql := if str.is_empty(where_sql) { base }
    else { str.concat(base, str.concat(" WHERE ", where_sql)) }
  { sql: final_sql, params: list.concat(set_params, where_params) }
}

fn build_delete[T](q :: DeleteQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let base  := str.concat("DELETE FROM ", tname)
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s, _) => s }
  let where_params := match where_result { (_, ps) => ps }
  let final_sql := if str.is_empty(where_sql) { base }
    else { str.concat(base, str.concat(" WHERE ", where_sql)) }
  { sql: final_sql, params: where_params }
}

# ---- Dialect-aware placeholder numbering --------------------------
# build_* always emits ? markers. Call for_dialect before execution
# to get the correct style: ? for SQLite, $1/$2/... for Postgres.

fn for_dialect(q :: SqlQuery, dialect :: conn.Dialect) -> SqlQuery {
  match dialect {
    DbSqlite   => q,
    DbPostgres => { sql: number_placeholders(q.sql), params: q.params },
  }
}

fn number_placeholders(sql :: Str) -> Str {
  let parts := str.split(sql, "?")
  if list.len(parts) <= 1 { sql }
  else {
    let first := match list.head(parts) { None => "", Some(s) => s }
    let rest  := list.tail(parts)
    let result := list.fold(rest, (first, 1),
      fn (acc :: (Str, Int), part :: Str) -> (Str, Int) {
        let s := match acc { (s2, _) => s2 }
        let i := match acc { (_, i2) => i2 }
        (str.concat(s, str.concat(str.concat("$", int.to_str(i)), part)), i + 1)
      })
    match result { (s, _) => s }
  }
}

# ---- Runtime stubs ------------------------------------------------
# std.sql is not yet in lex 0.9. These stubs return Err so callers
# can wire up the interface now and get real execution once std.sql
# lands. for_dialect is called here so the stubs are already correct.

fn run_select[T](q :: SelectQuery[T], db :: conn.Db) -> Result[List[T], dbe.DbErr] {
  let _sq := for_dialect(build_select(q), db.dialect)
  Err(DbQueryFailed("std.sql not yet available; use build_select to inspect the SQL plan"))
}

fn run_insert[T](q :: InsertQuery[T], db :: conn.Db) -> Result[T, dbe.DbErr] {
  let _sq := for_dialect(build_insert(q), db.dialect)
  Err(DbQueryFailed("std.sql not yet available; use build_insert to inspect the SQL plan"))
}

fn run_update[T](q :: UpdateQuery[T], db :: conn.Db) -> Result[Int, dbe.DbErr] {
  let _sq := for_dialect(build_update(q), db.dialect)
  Err(DbQueryFailed("std.sql not yet available; use build_update to inspect the SQL plan"))
}

fn run_delete[T](q :: DeleteQuery[T], db :: conn.Db) -> Result[Int, dbe.DbErr] {
  let _sq := for_dialect(build_delete(q), db.dialect)
  Err(DbQueryFailed("std.sql not yet available; use build_delete to inspect the SQL plan"))
}

fn transaction[A](
  _db   :: conn.Db,
  _body :: (conn.Tx) -> Result[A, dbe.DbErr]
) -> Result[A, dbe.DbErr] {
  Err(DbQueryFailed("std.sql not yet available"))
}

# ---- Helpers (pure) -----------------------------------------------

fn sql_quote(name :: Str) -> Str {
  str.concat("\"", str.concat(name, "\""))
}

fn sql_ident(name :: Str) -> Str {
  let segs := list.fold(str.split(name, "_"), [],
    fn (acc :: List[Str], seg :: Str) -> List[Str] {
      list.concat(acc, str.split(seg, "-"))
    })
  let split := list.fold(segs, [],
    fn (acc :: List[Str], seg :: Str) -> List[Str] {
      list.concat(acc, snake_split(seg))
    })
  str.to_lower(str.join(split, "_"))
}

fn snake_split(s :: Str) -> List[Str] {
  if str.is_empty(s) { [] }
  else { snake_split_at(s, 1, 0, []) }
}

fn snake_split_at(
  s :: Str, i :: Int, start :: Int, acc :: List[Str]
) -> List[Str] {
  let n := str.len(s)
  if i >= n {
    list.concat(acc, [str.slice(s, start, n)])
  } else {
    let prev := str.slice(s, i - 1, i)
    let curr := str.slice(s, i, i + 1)
    if is_lower(prev) and is_upper(curr) {
      snake_split_at(s, i + 1, i, list.concat(acc, [str.slice(s, start, i)]))
    } else {
      snake_split_at(s, i + 1, start, acc)
    }
  }
}

fn is_upper(c :: Str) -> Bool { str.to_upper(c) == c and str.to_lower(c) != c }
fn is_lower(c :: Str) -> Bool { str.to_lower(c) == c and str.to_upper(c) != c }

fn json_to_param(j :: Option[jv.Json]) -> p.Param {
  match j {
    None    => PNull,
    Some(v) => match v {
      JNull     => PNull,
      JBool(b)  => PBool(b),
      JInt(n)   => PInt(n),
      JFloat(x) => PFloat(x),
      JStr(s)   => PStr(s),
      _         => PStr(jv.stringify(v)),
    },
  }
}
