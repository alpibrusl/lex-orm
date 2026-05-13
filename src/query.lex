import "std.str"  as str
import "std.list" as list
import "std.int"  as int
import "std.sql"  as sql

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

type UpsertQuery[T] = {
  repo       :: Repo[T],
  value      :: jv.Json,
  conflict   :: List[Str],
  update_set :: List[(Str, p.Param)],
}

type BulkInsertQuery[T] = {
  repo   :: Repo[T],
  values :: List[jv.Json],
}

type Page[T] = {
  items    :: List[T],
  total    :: Int,
  page     :: Int,
  per_page :: Int,
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

fn paginate[T](q :: SelectQuery[T], page :: Int, per_page :: Int) -> SelectQuery[T] {
  let offs := (page - 1) * per_page
  offset(limit(q, per_page), offs)
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

fn upsert[T](repo :: Repo[T], value :: jv.Json, conflict_cols :: List[Str]) -> UpsertQuery[T] {
  { repo: repo, value: value, conflict: conflict_cols, update_set: [] }
}

fn on_conflict_update[T](q :: UpsertQuery[T], col :: Str, v :: p.Param) -> UpsertQuery[T] {
  { repo: q.repo, value: q.value, conflict: q.conflict,
    update_set: list.concat(q.update_set, [(col, v)]) }
}

fn bulk_insert[T](repo :: Repo[T], values :: List[jv.Json]) -> BulkInsertQuery[T] {
  { repo: repo, values: values }
}

fn page_result[T](items :: List[T], total :: Int, page :: Int, per_page :: Int) -> Page[T] {
  { items: items, total: total, page: page, per_page: per_page }
}

# ---- SQL building (pure) ------------------------------------------

fn build_select[T](q :: SelectQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let base  := "SELECT * FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s, _) => s }
  let where_params := match where_result { (_, ps) => ps }
  let with_where := if str.is_empty(where_sql) { base }
    else { base + " WHERE " + where_sql }
  let with_order := if list.is_empty(q.ordering) { with_where }
    else {
      let order_parts := list.map(q.ordering, fn (pair :: (Str, Order)) -> Str {
        let col := match pair { (c, _) => c }
        let dir := match pair { (_, d) => d }
        sql_quote(col) + match dir { Asc => " ASC", Desc => " DESC" }
      })
      with_where + " ORDER BY " + str.join(order_parts, ", ")
    }
  let with_limit := match q.limit_n {
    None    => with_order,
    Some(n) => with_order + " LIMIT " + int.to_str(n),
  }
  let final_sql := match q.offset_n {
    None    => with_limit,
    Some(n) => with_limit + " OFFSET " + int.to_str(n),
  }
  { sql: final_sql, params: where_params }
}

fn build_count[T](q :: SelectQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let base  := "SELECT COUNT(*) AS count FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s, _) => s }
  let where_params := match where_result { (_, ps) => ps }
  let final_sql := if str.is_empty(where_sql) { base }
    else { base + " WHERE " + where_sql }
  { sql: final_sql, params: where_params }
}

fn build_insert[T](q :: InsertQuery[T]) -> SqlQuery {
  let tname  := sql_quote(q.repo.table)
  let fields := q.repo.schema.fields
  let col_names    := list.map(fields, fn (f :: s.Field) -> Str { sql_quote(f.name) })
  let placeholders := list.map(fields, fn (_f :: s.Field) -> Str { "?" })
  let params       := list.map(fields, fn (f :: s.Field) -> p.Param {
    json_to_param(jv.get_field(q.value, f.name))
  })
  let sql_str :=
    "INSERT INTO " + tname + " (" +
    str.join(col_names, ", ") +
    ") VALUES (" +
    str.join(placeholders, ", ") + ")"
  { sql: sql_str, params: params }
}

fn build_update[T](q :: UpdateQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let set_parts := list.map(q.sets, fn (pair :: (Str, p.Param)) -> Str {
    let col := match pair { (c, _) => c }
    sql_quote(col) + " = ?"
  })
  let set_params := list.map(q.sets, fn (pair :: (Str, p.Param)) -> p.Param {
    match pair { (_, v) => v }
  })
  let base := "UPDATE " + tname + " SET " + str.join(set_parts, ", ")
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s, _) => s }
  let where_params := match where_result { (_, ps) => ps }
  let final_sql := if str.is_empty(where_sql) { base }
    else { base + " WHERE " + where_sql }
  { sql: final_sql, params: list.concat(set_params, where_params) }
}

fn build_delete[T](q :: DeleteQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let base  := "DELETE FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s, _) => s }
  let where_params := match where_result { (_, ps) => ps }
  let final_sql := if str.is_empty(where_sql) { base }
    else { base + " WHERE " + where_sql }
  { sql: final_sql, params: where_params }
}

fn build_upsert[T](q :: UpsertQuery[T]) -> SqlQuery {
  let base          := build_insert({ repo: q.repo, value: q.value })
  let conflict_str  := str.join(list.map(q.conflict, sql_quote), ", ")
  let update_params := list.map(q.update_set, fn (pair :: (Str, p.Param)) -> p.Param {
    match pair { (_, v) => v }
  })
  let conflict_clause :=
    if list.is_empty(q.conflict) {
      " ON CONFLICT DO NOTHING"
    } else if list.is_empty(q.update_set) {
      " ON CONFLICT (" + conflict_str + ") DO NOTHING"
    } else {
      let updates := list.map(q.update_set, fn (pair :: (Str, p.Param)) -> Str {
        let qc := sql_quote(match pair { (c, _) => c })
        qc + " = EXCLUDED." + qc
      })
      " ON CONFLICT (" + conflict_str + ") DO UPDATE SET " + str.join(updates, ", ")
    }
  { sql: base.sql + conflict_clause, params: list.concat(base.params, update_params) }
}

fn build_bulk_insert[T](q :: BulkInsertQuery[T]) -> SqlQuery {
  let tname     := sql_quote(q.repo.table)
  let fields    := q.repo.schema.fields
  let col_names := list.map(fields, fn (f :: s.Field) -> Str { sql_quote(f.name) })
  let row_ph    := "(" + str.join(list.map(fields, fn (_f :: s.Field) -> Str { "?" }), ", ") + ")"
  let all_rows  := list.map(q.values, fn (_v :: jv.Json) -> Str { row_ph })
  let all_params := list.fold(q.values, [],
    fn (acc :: List[p.Param], v :: jv.Json) -> List[p.Param] {
      list.concat(acc, list.map(fields, fn (f :: s.Field) -> p.Param {
        json_to_param(jv.get_field(v, f.name))
      }))
    })
  let sql_str :=
    "INSERT INTO " + tname + " (" +
    str.join(col_names, ", ") +
    ") VALUES " + str.join(all_rows, ", ")
  { sql: sql_str, params: all_params }
}

# ---- Row-to-JSON bridge -------------------------------------------
# Wraps SELECT/INSERT with json_object (SQLite) or json_build_object
# (Postgres) so sql.query decodes a single _j :: Str column instead
# of a structural record per field.

fn json_agg_expr(fields :: List[s.Field], dialect :: conn.Dialect) -> Str {
  let pairs := list.fold(fields, [],
    fn (acc :: List[Str], f :: s.Field) -> List[Str] {
      list.concat(acc, ["'" + f.name + "'", sql_quote(f.name)])
    })
  let json_fn := match dialect { DbPostgres => "json_build_object", DbSqlite => "json_object" }
  json_fn + "(" + str.join(pairs, ", ") + ") AS _j"
}

fn build_select_json[T](q :: SelectQuery[T], dialect :: conn.Dialect) -> SqlQuery {
  let tname     := sql_quote(q.repo.table)
  let json_expr := json_agg_expr(q.repo.schema.fields, dialect)
  let base      := "SELECT " + json_expr + " FROM " + tname
  let full      := build_select(q)
  let star_pfx  := "SELECT * FROM " + tname
  let suffix    := str.slice(full.sql, str.len(star_pfx), str.len(full.sql))
  { sql: base + suffix, params: full.params }
}

fn build_insert_returning_json[T](q :: InsertQuery[T], dialect :: conn.Dialect) -> SqlQuery {
  let base      := build_insert(q)
  let json_expr := json_agg_expr(q.repo.schema.fields, dialect)
  { sql: base.sql + " RETURNING " + json_expr, params: base.params }
}

# ---- Dialect-aware placeholder numbering --------------------------
# build_* always emits ? markers. Call for_dialect before execution.

fn for_dialect(q :: SqlQuery, dialect :: conn.Dialect) -> SqlQuery {
  match dialect {
    DbSqlite   => q,
    DbPostgres => { sql: number_placeholders(q.sql), params: q.params },
  }
}

fn number_placeholders(raw :: Str) -> Str {
  let parts := str.split(raw, "?")
  if list.len(parts) <= 1 { raw }
  else {
    let first := match list.head(parts) { None => "", Some(s) => s }
    let rest  := list.tail(parts)
    let result := list.fold(rest, (first, 1),
      fn (acc :: (Str, Int), part :: Str) -> (Str, Int) {
        let s := match acc { (s2, _) => s2 }
        let i := match acc { (_, i2) => i2 }
        (s + "$" + int.to_str(i) + part, i + 1)
      })
    match result { (s, _) => s }
  }
}

# ---- Param / row conversion ---------------------------------------

fn param_to_sql(param :: p.Param) -> sql.SqlParam {
  match param {
    PStr(s)   => PStr(s),
    PInt(n)   => PInt(n),
    PFloat(x) => PFloat(x),
    PBool(b)  => PBool(b),
    PNull     => PNull,
  }
}

fn decode_rows[T](
  rows   :: List[{ _j :: Str }],
  decode :: (jv.Json) -> Result[T, se.Errors]
) -> Result[List[T], dbe.DbErr] {
  list.fold(rows, Ok([]),
    fn (acc :: Result[List[T], dbe.DbErr], row :: { _j :: Str }) -> Result[List[T], dbe.DbErr] {
      match acc {
        Err(e)    => Err(e),
        Ok(items) =>
          match jv.parse(row._j) {
            Err(pe) => Err(DbDecodeFailed(pe.message)),
            Ok(j)   =>
              match decode(j) {
                Err(_)  => Err(DbDecodeFailed("schema validation failed")),
                Ok(v)   => Ok(list.concat(items, [v])),
              },
          },
      }
    })
}

# ---- Runtime execution --------------------------------------------

fn run_select[T](q :: SelectQuery[T], db :: conn.Db) -> [sql] Result[List[T], dbe.DbErr] {
  let sq         := for_dialect(build_select_json(q, db.dialect), db.dialect)
  let sql_params := list.map(sq.params, param_to_sql)
  let raw :: Result[List[{ _j :: Str }], Str] := sql.query(db.handle, sq.sql, sql_params)
  match raw {
    Err(e)   => Err(DbQueryFailed(e)),
    Ok(rows) => decode_rows(rows, q.repo.decode),
  }
}

fn run_count[T](q :: SelectQuery[T], db :: conn.Db) -> [sql] Result[Int, dbe.DbErr] {
  let sq         := for_dialect(build_count(q), db.dialect)
  let sql_params := list.map(sq.params, param_to_sql)
  let raw :: Result[List[{ count :: Int }], Str] := sql.query(db.handle, sq.sql, sql_params)
  match raw {
    Err(e)   => Err(DbQueryFailed(e)),
    Ok(rows) => match list.head(rows) {
      None    => Ok(0),
      Some(r) => Ok(r.count),
    },
  }
}

fn run_insert[T](q :: InsertQuery[T], db :: conn.Db) -> [sql] Result[T, dbe.DbErr] {
  let sq         := for_dialect(build_insert_returning_json(q, db.dialect), db.dialect)
  let sql_params := list.map(sq.params, param_to_sql)
  let raw :: Result[List[{ _j :: Str }], Str] := sql.query(db.handle, sq.sql, sql_params)
  match raw {
    Err(e)   => Err(DbQueryFailed(e)),
    Ok(rows) =>
      match decode_rows(rows, q.repo.decode) {
        Err(e)    => Err(e),
        Ok(items) => match list.head(items) {
          None    => Err(DbQueryFailed("INSERT returned no rows")),
          Some(v) => Ok(v),
        },
      },
  }
}

fn run_insert_returning[T](q :: InsertQuery[T], db :: conn.Db) -> [sql] Result[List[T], dbe.DbErr] {
  let sq         := for_dialect(build_insert_returning_json(q, db.dialect), db.dialect)
  let sql_params := list.map(sq.params, param_to_sql)
  let raw :: Result[List[{ _j :: Str }], Str] := sql.query(db.handle, sq.sql, sql_params)
  match raw {
    Err(e)   => Err(DbQueryFailed(e)),
    Ok(rows) => decode_rows(rows, q.repo.decode),
  }
}

fn run_update[T](q :: UpdateQuery[T], db :: conn.Db) -> [sql] Result[Int, dbe.DbErr] {
  let sq         := for_dialect(build_update(q), db.dialect)
  let sql_params := list.map(sq.params, param_to_sql)
  match sql.exec(db.handle, sq.sql, sql_params) {
    Err(e) => Err(DbQueryFailed(e)),
    Ok(n)  => Ok(n),
  }
}

fn run_delete[T](q :: DeleteQuery[T], db :: conn.Db) -> [sql] Result[Int, dbe.DbErr] {
  let sq         := for_dialect(build_delete(q), db.dialect)
  let sql_params := list.map(sq.params, param_to_sql)
  match sql.exec(db.handle, sq.sql, sql_params) {
    Err(e) => Err(DbQueryFailed(e)),
    Ok(n)  => Ok(n),
  }
}

fn run_upsert[T](q :: UpsertQuery[T], db :: conn.Db) -> [sql] Result[Int, dbe.DbErr] {
  let sq         := for_dialect(build_upsert(q), db.dialect)
  let sql_params := list.map(sq.params, param_to_sql)
  match sql.exec(db.handle, sq.sql, sql_params) {
    Err(e) => Err(DbQueryFailed(e)),
    Ok(n)  => Ok(n),
  }
}

fn run_bulk_insert[T](q :: BulkInsertQuery[T], db :: conn.Db) -> [sql] Result[Int, dbe.DbErr] {
  let sq         := for_dialect(build_bulk_insert(q), db.dialect)
  let sql_params := list.map(sq.params, param_to_sql)
  match sql.exec(db.handle, sq.sql, sql_params) {
    Err(e) => Err(DbQueryFailed(e)),
    Ok(n)  => Ok(n),
  }
}

fn transaction[A](
  db   :: conn.Db,
  body :: (conn.Db) -> [sql] Result[A, dbe.DbErr]
) -> [sql] Result[A, dbe.DbErr] {
  match sql.exec(db.handle, "BEGIN", []) {
    Err(e) => Err(DbTransactionFailed("BEGIN failed: " + e)),
    Ok(_)  =>
      match body(db) {
        Err(e) => {
          let _ := sql.exec(db.handle, "ROLLBACK", [])
          Err(e)
        },
        Ok(v) =>
          match sql.exec(db.handle, "COMMIT", []) {
            Err(e) => Err(DbTransactionFailed("COMMIT failed: " + e)),
            Ok(_)  => Ok(v),
          },
      },
  }
}

# ---- Helpers (pure) -----------------------------------------------

fn sql_quote(name :: Str) -> Str { "\"" + name + "\"" }

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
