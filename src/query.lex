import "std.str"  as str
import "std.list" as list
import "std.int"  as int
import "std.sql"  as sql
import "std.iter" as iter

import "lex-schema/schema"     as s
import "lex-schema/json_value" as jv
import "lex-schema/error"      as se

import "./predicate"  as p
import "./connection" as conn
import "./error"      as dbe

# RepoSchema is non-generic: just schema + table name.
# Callers pass a decode function explicitly to run_* functions.
type RepoSchema = {
  schema :: s.ModelSchema,
  table  :: Str,
}

fn for_schema(schema :: s.ModelSchema) -> RepoSchema {
  { schema: schema, table: sql_ident(schema.title) }
}

fn with_table(repo :: RepoSchema, table :: Str) -> RepoSchema {
  { schema: repo.schema, table: table }
}

type Order = Asc | Desc

# All query types are non-generic record aliases (non-generic aliases work in lex 0.9.1).
type SelectQuery = {
  repo     :: RepoSchema,
  filters  :: List[p.Predicate],
  ordering :: List[(Str, Order)],
  limit_n  :: Option[Int],
  offset_n :: Option[Int],
}

type InsertQuery = {
  repo  :: RepoSchema,
  value :: jv.Json,
}

type UpdateQuery = {
  repo    :: RepoSchema,
  sets    :: List[(Str, SqlParam)],
  filters :: List[p.Predicate],
}

type DeleteQuery = {
  repo    :: RepoSchema,
  filters :: List[p.Predicate],
}

type UpsertQuery = {
  repo       :: RepoSchema,
  value      :: jv.Json,
  conflict   :: List[Str],
  update_set :: List[(Str, SqlParam)],
}

type BulkInsertQuery = {
  repo   :: RepoSchema,
  values :: List[jv.Json],
}

type SqlQuery = {
  sql    :: Str,
  params :: List[SqlParam],
}

# ---- Query builders (pure) ----------------------------------------

fn select(repo :: RepoSchema) -> SelectQuery {
  { repo: repo, filters: [], ordering: [], limit_n: None, offset_n: None }
}

fn where_clause(q :: SelectQuery, pred :: p.Predicate) -> SelectQuery {
  { repo: q.repo, filters: list.concat(q.filters, [pred]),
    ordering: q.ordering, limit_n: q.limit_n, offset_n: q.offset_n }
}

fn order_by(q :: SelectQuery, col :: Str, dir :: Order) -> SelectQuery {
  { repo: q.repo, filters: q.filters,
    ordering: list.concat(q.ordering, [(col, dir)]),
    limit_n: q.limit_n, offset_n: q.offset_n }
}

fn limit(q :: SelectQuery, n :: Int) -> SelectQuery {
  { repo: q.repo, filters: q.filters, ordering: q.ordering,
    limit_n: Some(n), offset_n: q.offset_n }
}

fn offset(q :: SelectQuery, n :: Int) -> SelectQuery {
  { repo: q.repo, filters: q.filters, ordering: q.ordering,
    limit_n: q.limit_n, offset_n: Some(n) }
}

fn paginate(q :: SelectQuery, page :: Int, per_page :: Int) -> SelectQuery {
  let offs := (page - 1) * per_page
  offset(limit(q, per_page), offs)
}

fn insert(repo :: RepoSchema, value :: jv.Json) -> InsertQuery {
  { repo: repo, value: value }
}

fn update(repo :: RepoSchema) -> UpdateQuery {
  { repo: repo, sets: [], filters: [] }
}

fn set_col(q :: UpdateQuery, col :: Str, v :: SqlParam) -> UpdateQuery {
  { repo: q.repo, sets: list.concat(q.sets, [(col, v)]), filters: q.filters }
}

fn where_update(q :: UpdateQuery, pred :: p.Predicate) -> UpdateQuery {
  { repo: q.repo, sets: q.sets, filters: list.concat(q.filters, [pred]) }
}

fn delete_from(repo :: RepoSchema) -> DeleteQuery {
  { repo: repo, filters: [] }
}

fn where_delete(q :: DeleteQuery, pred :: p.Predicate) -> DeleteQuery {
  { repo: q.repo, filters: list.concat(q.filters, [pred]) }
}

fn upsert(repo :: RepoSchema, value :: jv.Json, conflict_cols :: List[Str]) -> UpsertQuery {
  { repo: repo, value: value, conflict: conflict_cols, update_set: [] }
}

fn on_conflict_update(q :: UpsertQuery, col :: Str, v :: SqlParam) -> UpsertQuery {
  { repo: q.repo, value: q.value, conflict: q.conflict,
    update_set: list.concat(q.update_set, [(col, v)]) }
}

fn bulk_insert(repo :: RepoSchema, values :: List[jv.Json]) -> BulkInsertQuery {
  { repo: repo, values: values }
}

# Stamp updated_at on an update query. Caller provides the timestamp string.
fn touch(upd :: UpdateQuery, now :: Str) -> UpdateQuery {
  set_col(upd, "updated_at", PStr(now))
}

# Build an EXISTS (...) predicate from a sub-select.
fn exists_subquery(sub :: SelectQuery) -> p.Predicate {
  let wr         := p.render_where(sub.filters)
  let where_sql  := match wr { (s2, _) => s2 }
  let where_ps   := match wr { (_, ps) => ps }
  let where_part := if str.is_empty(where_sql) { "" }
    else { " WHERE " + where_sql }
  let limit_part := match sub.limit_n {
    None    => "",
    Some(n) => " LIMIT " + int.to_str(n),
  }
  PRaw("EXISTS (SELECT 1 FROM " + sql_quote(sub.repo.table) + where_part + limit_part + ")", where_ps)
}

# ---- SQL building (pure) ------------------------------------------

fn build_select(q :: SelectQuery) -> SqlQuery {
  let tname  := sql_quote(q.repo.table)
  let base   := "SELECT * FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s2, _) => s2 }
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

fn build_count(q :: SelectQuery) -> SqlQuery {
  let tname  := sql_quote(q.repo.table)
  let base   := "SELECT COUNT(*) AS count FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s2, _) => s2 }
  let where_params := match where_result { (_, ps) => ps }
  let final_sql := if str.is_empty(where_sql) { base }
    else { base + " WHERE " + where_sql }
  { sql: final_sql, params: where_params }
}

fn build_insert(q :: InsertQuery) -> SqlQuery {
  let tname  := sql_quote(q.repo.table)
  let fields := q.repo.schema.fields
  let col_names    := list.map(fields, fn (f :: s.Field) -> Str { sql_quote(f.name) })
  let placeholders := list.map(fields, fn (_f :: s.Field) -> Str { "?" })
  let params       := list.map(fields, fn (f :: s.Field) -> SqlParam {
    json_to_param(jv.get_field(q.value, f.name))
  })
  let sql_str :=
    "INSERT INTO " + tname + " (" +
    str.join(col_names, ", ") +
    ") VALUES (" +
    str.join(placeholders, ", ") + ")"
  { sql: sql_str, params: params }
}

fn build_update(q :: UpdateQuery) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let set_parts := list.map(q.sets, fn (pair :: (Str, SqlParam)) -> Str {
    let col := match pair { (c, _) => c }
    sql_quote(col) + " = ?"
  })
  let set_params := list.map(q.sets, fn (pair :: (Str, SqlParam)) -> SqlParam {
    match pair { (_, v) => v }
  })
  let base := "UPDATE " + tname + " SET " + str.join(set_parts, ", ")
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s2, _) => s2 }
  let where_params := match where_result { (_, ps) => ps }
  let final_sql := if str.is_empty(where_sql) { base }
    else { base + " WHERE " + where_sql }
  { sql: final_sql, params: list.concat(set_params, where_params) }
}

fn build_delete(q :: DeleteQuery) -> SqlQuery {
  let tname  := sql_quote(q.repo.table)
  let base   := "DELETE FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql    := match where_result { (s2, _) => s2 }
  let where_params := match where_result { (_, ps) => ps }
  let final_sql := if str.is_empty(where_sql) { base }
    else { base + " WHERE " + where_sql }
  { sql: final_sql, params: where_params }
}

fn build_upsert(q :: UpsertQuery) -> SqlQuery {
  let base          := build_insert({ repo: q.repo, value: q.value })
  let conflict_str  := str.join(list.map(q.conflict, sql_quote), ", ")
  let update_params := list.map(q.update_set, fn (pair :: (Str, SqlParam)) -> SqlParam {
    match pair { (_, v) => v }
  })
  let conflict_clause :=
    if list.is_empty(q.conflict) {
      " ON CONFLICT DO NOTHING"
    } else {
      if list.is_empty(q.update_set) {
        " ON CONFLICT (" + conflict_str + ") DO NOTHING"
      } else {
        let updates := list.map(q.update_set, fn (pair :: (Str, SqlParam)) -> Str {
          let qc := sql_quote(match pair { (c, _) => c })
          qc + " = EXCLUDED." + qc
        })
        " ON CONFLICT (" + conflict_str + ") DO UPDATE SET " + str.join(updates, ", ")
      }
    }
  { sql: base.sql + conflict_clause, params: list.concat(base.params, update_params) }
}

fn build_bulk_insert(q :: BulkInsertQuery) -> SqlQuery {
  let tname     := sql_quote(q.repo.table)
  let fields    := q.repo.schema.fields
  let col_names := list.map(fields, fn (f :: s.Field) -> Str { sql_quote(f.name) })
  let row_ph    := "(" + str.join(list.map(fields, fn (_f :: s.Field) -> Str { "?" }), ", ") + ")"
  let all_rows  := list.map(q.values, fn (_v :: jv.Json) -> Str { row_ph })
  let all_params := list.fold(q.values, [],
    fn (acc :: List[SqlParam], v :: jv.Json) -> List[SqlParam] {
      list.concat(acc, list.map(fields, fn (f :: s.Field) -> SqlParam {
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

fn json_agg_expr(fields :: List[s.Field], dialect :: conn.Dialect) -> Str {
  let pairs := list.fold(fields, [],
    fn (acc :: List[Str], f :: s.Field) -> List[Str] {
      list.concat(acc, ["'" + f.name + "'", sql_quote(f.name)])
    })
  let json_fn := match dialect { DbPostgres => "json_build_object", DbSqlite => "json_object" }
  json_fn + "(" + str.join(pairs, ", ") + ") AS _j"
}

fn build_select_json(q :: SelectQuery, dialect :: conn.Dialect) -> SqlQuery {
  let tname     := sql_quote(q.repo.table)
  let json_expr := json_agg_expr(q.repo.schema.fields, dialect)
  let base      := "SELECT " + json_expr + " FROM " + tname
  let full      := build_select(q)
  let star_pfx  := "SELECT * FROM " + tname
  let suffix    := str.slice(full.sql, str.len(star_pfx), str.len(full.sql))
  { sql: base + suffix, params: full.params }
}

fn build_insert_returning_json(q :: InsertQuery, dialect :: conn.Dialect) -> SqlQuery {
  let base      := build_insert(q)
  let json_expr := json_agg_expr(q.repo.schema.fields, dialect)
  { sql: base.sql + " RETURNING " + json_expr, params: base.params }
}

# ---- Dialect-aware placeholder numbering --------------------------

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
    let first := match list.head(parts) { None => "", Some(s2) => s2 }
    let rest  := list.tail(parts)
    let result := list.fold(rest, (first, 1),
      fn (acc :: (Str, Int), part :: Str) -> (Str, Int) {
        let s2 := match acc { (s3, _) => s3 }
        let i  := match acc { (_, i2) => i2 }
        (s2 + "$" + int.to_str(i) + part, i + 1)
      })
    match result { (s2, _) => s2 }
  }
}

# ---- Row decoding -------------------------------------------------

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
            Err(pe) => Err(dbe.decode_err(pe.message)),
            Ok(j)   =>
              match decode(j) {
                Err(_)  => Err(dbe.decode_err("schema validation failed")),
                Ok(v)   => Ok(list.concat(items, [v])),
              },
          },
      }
    })
}

# ---- Runtime execution --------------------------------------------

fn run_select[T](
  q      :: SelectQuery,
  decode :: (jv.Json) -> Result[T, se.Errors],
  db     :: conn.ConnDb
) -> [sql] Result[List[T], dbe.DbErr] {
  let sq         := for_dialect(build_select_json(q, db.dialect), db.dialect)
  let raw :: Result[List[{ _j :: Str }], Str] := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e)   => Err(dbe.sql_error(e.code, e.detail)),
    Ok(rows) => decode_rows(rows, decode),
  }
}

fn run_count(q :: SelectQuery, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq         := for_dialect(build_count(q), db.dialect)
  let raw :: Result[List[{ count :: Int }], Str] := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e)   => Err(dbe.sql_error(e.code, e.detail)),
    Ok(rows) => match list.head(rows) {
      None    => Ok(0),
      Some(r) => Ok(r.count),
    },
  }
}

fn run_insert[T](
  q      :: InsertQuery,
  decode :: (jv.Json) -> Result[T, se.Errors],
  db     :: conn.ConnDb
) -> [sql] Result[T, dbe.DbErr] {
  let sq         := for_dialect(build_insert_returning_json(q, db.dialect), db.dialect)
  let raw :: Result[List[{ _j :: Str }], Str] := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e)   => Err(dbe.sql_error(e.code, e.detail)),
    Ok(rows) =>
      match decode_rows(rows, decode) {
        Err(e)    => Err(e),
        Ok(items) => match list.head(items) {
          None    => Err(dbe.query_err("INSERT returned no rows")),
          Some(v) => Ok(v),
        },
      },
  }
}

fn run_insert_returning[T](
  q      :: InsertQuery,
  decode :: (jv.Json) -> Result[T, se.Errors],
  db     :: conn.ConnDb
) -> [sql] Result[List[T], dbe.DbErr] {
  let sq         := for_dialect(build_insert_returning_json(q, db.dialect), db.dialect)
  let raw :: Result[List[{ _j :: Str }], Str] := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e)   => Err(dbe.sql_error(e.code, e.detail)),
    Ok(rows) => decode_rows(rows, decode),
  }
}

fn run_update(q :: UpdateQuery, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_update(q), db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(e.code, e.detail)),
    Ok(n)  => Ok(n),
  }
}

fn run_delete(q :: DeleteQuery, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_delete(q), db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(e.code, e.detail)),
    Ok(n)  => Ok(n),
  }
}

fn run_upsert(q :: UpsertQuery, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_upsert(q), db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(e.code, e.detail)),
    Ok(n)  => Ok(n),
  }
}

fn run_bulk_insert(q :: BulkInsertQuery, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_bulk_insert(q), db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(e.code, e.detail)),
    Ok(n)  => Ok(n),
  }
}

# Stream SELECT results as a lazy Iter[T] instead of materializing
# them all into a List[T]. Use for large tables or export endpoints
# where you don't want to buffer the full result set in memory.
#
# The iterator is lazy: rows are fetched from the cursor on demand.
# Close the connection only after the iterator is fully consumed.
#
# Effect: [sql]
fn run_select_iter[T](
  q      :: SelectQuery,
  decode :: (jv.Json) -> Result[T, se.Errors],
  db     :: conn.ConnDb
) -> [sql] Iter[Result[T, dbe.DbErr]] {
  let plan     := build_select_json(q, db.dialect)
  let rewritten := for_dialect(plan, db.dialect)
  let raw_iter := sql.query_iter(db.handle, rewritten.sql, rewritten.params)
  iter.map(raw_iter, fn (row :: { _j :: Str }) -> Result[T, dbe.DbErr] {
    match jv.parse(row._j) {
      Err(pe) => Err(dbe.decode_err(pe.message)),
      Ok(j)   =>
        match decode(j) {
          Err(_)  => Err(dbe.decode_err("schema validation failed")),
          Ok(v)   => Ok(v),
        },
    }
  })
}

fn transaction[A](
  db   :: conn.ConnDb,
  body :: (conn.ConnDb) -> [sql] Result[A, dbe.DbErr]
) -> [sql] Result[A, dbe.DbErr] {
  match sql.exec(db.handle, "BEGIN", []) {
    Err(e) => Err(dbe.sql_error(e.code, "BEGIN failed: " + e.detail)),
    Ok(_)  =>
      match body(db) {
        Err(e) => {
          let _ := sql.exec(db.handle, "ROLLBACK", [])
          Err(e)
        },
        Ok(v) =>
          match sql.exec(db.handle, "COMMIT", []) {
            Err(e) => Err(dbe.sql_error(e.code, "COMMIT failed: " + e.detail)),
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

fn json_to_param(j :: Option[jv.Json]) -> SqlParam {
  match j {
    None    => PNull,
    Some(v) => match v {
      JNull     => PNull,
      JBool(b)  => if b { PInt(1) } else { PInt(0) },
      JInt(n)   => PInt(n),
      JFloat(x) => PStr(jv.stringify(JFloat(x))),
      JStr(s2)  => PStr(s2),
      _         => PStr(jv.stringify(v)),
    },
  }
}
