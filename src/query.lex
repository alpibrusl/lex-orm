import "std.str" as str

import "std.list" as list

import "std.int" as int

import "std.sql" as sql

import "std.iter" as iter

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "./predicate" as p

import "./connection" as conn

import "./error" as dbe

# Repo[T] bundles a ModelSchema, the target table name, and a row
# decoder. `for_schema(schema, decode)` is the single public
# constructor; the same `Repo[T]` flows through every query builder
# and `run_*` function so callers never thread the decoder by hand.
#
# Requires lex 0.9.5+ for the parametric-record-alias unfold rule
# (#439) — anonymous `{ schema: …, table: …, decode: … }` literals
# do not coerce to `Repo[T]` under earlier versions.
type Repo[T] = { schema :: s.ModelSchema, table :: Str, decode :: (jv.Json) -> Result[T, se.Errors] }

fn for_schema[T](schema :: s.ModelSchema, decode :: (jv.Json) -> Result[T, se.Errors]) -> Repo[T] {
  { schema: schema, table: sql_ident(schema.title), decode: decode }
}

fn with_table[T](repo :: Repo[T], table :: Str) -> Repo[T] {
  { schema: repo.schema, table: table, decode: repo.decode }
}

type Order = Asc(Unit) | Desc(Unit)

type SelectQuery[T] = { repo :: Repo[T], filters :: List[p.Predicate], ordering :: List[(Str, Order)], limit_n :: Option[Int], offset_n :: Option[Int] }

type InsertQuery[T] = { repo :: Repo[T], value :: jv.Json }

type UpdateQuery[T] = { repo :: Repo[T], sets :: List[(Str, SqlParam)], filters :: List[p.Predicate] }

type DeleteQuery[T] = { repo :: Repo[T], filters :: List[p.Predicate] }

type UpsertQuery[T] = { repo :: Repo[T], value :: jv.Json, conflict :: List[Str], update_set :: List[(Str, SqlParam)] }

type BulkInsertQuery[T] = { repo :: Repo[T], values :: List[jv.Json] }

type SqlQuery = { sql :: Str, params :: List[SqlParam] }

# ---- Query builders (pure) ----------------------------------------
fn select[T](repo :: Repo[T]) -> SelectQuery[T] {
  { repo: repo, filters: [], ordering: [], limit_n: None, offset_n: None }
}

fn where_clause[T](q :: SelectQuery[T], pred :: p.Predicate) -> SelectQuery[T] {
  { repo: q.repo, filters: list.concat(q.filters, [pred]), ordering: q.ordering, limit_n: q.limit_n, offset_n: q.offset_n }
}

fn order_by[T](q :: SelectQuery[T], col :: Str, dir :: Order) -> SelectQuery[T] {
  { repo: q.repo, filters: q.filters, ordering: list.concat(q.ordering, [(col, dir)]), limit_n: q.limit_n, offset_n: q.offset_n }
}

fn limit[T](q :: SelectQuery[T], n :: Int) -> SelectQuery[T] {
  { repo: q.repo, filters: q.filters, ordering: q.ordering, limit_n: Some(n), offset_n: q.offset_n }
}

fn offset[T](q :: SelectQuery[T], n :: Int) -> SelectQuery[T] {
  { repo: q.repo, filters: q.filters, ordering: q.ordering, limit_n: q.limit_n, offset_n: Some(n) }
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

fn set_col[T](q :: UpdateQuery[T], col :: Str, v :: SqlParam) -> UpdateQuery[T] {
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

fn on_conflict_update[T](q :: UpsertQuery[T], col :: Str, v :: SqlParam) -> UpsertQuery[T] {
  { repo: q.repo, value: q.value, conflict: q.conflict, update_set: list.concat(q.update_set, [(col, v)]) }
}

fn bulk_insert[T](repo :: Repo[T], values :: List[jv.Json]) -> BulkInsertQuery[T] {
  { repo: repo, values: values }
}

fn touch[T](upd :: UpdateQuery[T], now :: Str) -> UpdateQuery[T] {
  set_col(upd, "updated_at", PStr(now))
}

fn exists_subquery[T](sub :: SelectQuery[T]) -> p.Predicate {
  let wr := p.render_where(sub.filters)
  let where_sql := match wr {
    (s2, _) => s2,
  }
  let where_ps := match wr {
    (_, ps) => ps,
  }
  let where_part := if str.is_empty(where_sql) {
    ""
  } else {
    " WHERE " + where_sql
  }
  let limit_part := match sub.limit_n {
    None => "",
    Some(n) => " LIMIT " + int.to_str(n),
  }
  PRaw("EXISTS (SELECT 1 FROM " + sql_quote(sub.repo.table) + where_part + limit_part + ")", where_ps)
}

# ---- SQL building (pure) ------------------------------------------
fn build_select[T](q :: SelectQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let base := "SELECT * FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql := match where_result {
    (s2, _) => s2,
  }
  let where_params := match where_result {
    (_, ps) => ps,
  }
  let with_where := if str.is_empty(where_sql) {
    base
  } else {
    base + " WHERE " + where_sql
  }
  let with_order := if list.is_empty(q.ordering) {
    with_where
  } else {
    let order_parts := list.map(q.ordering, fn (pair :: (Str, Order)) -> Str {
      let col := match pair {
        (c, _) => c,
      }
      let dir := match pair {
        (_, d) => d,
      }
      sql_quote(col) + match dir {
        Asc(_) => " ASC",
        Desc(_) => " DESC",
      }
    })
    with_where + " ORDER BY " + str.join(order_parts, ", ")
  }
  let with_limit := match q.limit_n {
    None => with_order,
    Some(n) => with_order + " LIMIT " + int.to_str(n),
  }
  let final_sql := match q.offset_n {
    None => with_limit,
    Some(n) => with_limit + " OFFSET " + int.to_str(n),
  }
  { sql: final_sql, params: where_params }
}

fn build_count[T](q :: SelectQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let base := "SELECT COUNT(*) AS count FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql := match where_result {
    (s2, _) => s2,
  }
  let where_params := match where_result {
    (_, ps) => ps,
  }
  let final_sql := if str.is_empty(where_sql) {
    base
  } else {
    base + " WHERE " + where_sql
  }
  { sql: final_sql, params: where_params }
}

fn build_insert[T](q :: InsertQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let fields := q.repo.schema.fields
  let col_names := list.map(fields, fn (f :: s.Field) -> Str {
    sql_quote(f.name)
  })
  let placeholders := list.map(fields, fn (_f :: s.Field) -> Str {
    "?"
  })
  let params := list.map(fields, fn (f :: s.Field) -> SqlParam {
    json_to_param(jv.get_field(q.value, f.name))
  })
  let sql_str := "INSERT INTO " + tname + " (" + str.join(col_names, ", ") + ") VALUES (" + str.join(placeholders, ", ") + ")"
  { sql: sql_str, params: params }
}

fn build_update[T](q :: UpdateQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let set_parts := list.map(q.sets, fn (pair :: (Str, SqlParam)) -> Str {
    let col := match pair {
      (c, _) => c,
    }
    sql_quote(col) + " = ?"
  })
  let set_params := list.map(q.sets, fn (pair :: (Str, SqlParam)) -> SqlParam {
    match pair {
      (_, v) => v,
    }
  })
  let base := "UPDATE " + tname + " SET " + str.join(set_parts, ", ")
  let where_result := p.render_where(q.filters)
  let where_sql := match where_result {
    (s2, _) => s2,
  }
  let where_params := match where_result {
    (_, ps) => ps,
  }
  let final_sql := if str.is_empty(where_sql) {
    base
  } else {
    base + " WHERE " + where_sql
  }
  { sql: final_sql, params: list.concat(set_params, where_params) }
}

fn build_delete[T](q :: DeleteQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let base := "DELETE FROM " + tname
  let where_result := p.render_where(q.filters)
  let where_sql := match where_result {
    (s2, _) => s2,
  }
  let where_params := match where_result {
    (_, ps) => ps,
  }
  let final_sql := if str.is_empty(where_sql) {
    base
  } else {
    base + " WHERE " + where_sql
  }
  { sql: final_sql, params: where_params }
}

fn build_upsert[T](q :: UpsertQuery[T]) -> SqlQuery {
  let base := build_insert({ repo: q.repo, value: q.value })
  let conflict_str := str.join(list.map(q.conflict, sql_quote), ", ")
  let update_params := list.map(q.update_set, fn (pair :: (Str, SqlParam)) -> SqlParam {
    match pair {
      (_, v) => v,
    }
  })
  let conflict_clause := if list.is_empty(q.conflict) {
    " ON CONFLICT DO NOTHING"
  } else {
    if list.is_empty(q.update_set) {
      " ON CONFLICT (" + conflict_str + ") DO NOTHING"
    } else {
      let updates := list.map(q.update_set, fn (pair :: (Str, SqlParam)) -> Str {
        let qc := sql_quote(match pair {
          (c, _) => c,
        })
        qc + " = EXCLUDED." + qc
      })
      " ON CONFLICT (" + conflict_str + ") DO UPDATE SET " + str.join(updates, ", ")
    }
  }
  { sql: base.sql + conflict_clause, params: list.concat(base.params, update_params) }
}

fn build_bulk_insert[T](q :: BulkInsertQuery[T]) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let fields := q.repo.schema.fields
  let col_names := list.map(fields, fn (f :: s.Field) -> Str {
    sql_quote(f.name)
  })
  let row_ph := "(" + str.join(list.map(fields, fn (_f :: s.Field) -> Str {
    "?"
  }), ", ") + ")"
  let all_rows := list.map(q.values, fn (_v :: jv.Json) -> Str {
    row_ph
  })
  let all_params := list.fold(q.values, [], fn (acc :: List[SqlParam], v :: jv.Json) -> List[SqlParam] {
    list.concat(acc, list.map(fields, fn (f :: s.Field) -> SqlParam {
      json_to_param(jv.get_field(v, f.name))
    }))
  })
  let sql_str := "INSERT INTO " + tname + " (" + str.join(col_names, ", ") + ") VALUES " + str.join(all_rows, ", ")
  { sql: sql_str, params: all_params }
}

# ---- Row-to-JSON bridge -------------------------------------------
fn json_agg_expr(fields :: List[s.Field], dialect :: conn.Dialect) -> Str {
  let pairs := list.fold(fields, [], fn (acc :: List[Str], f :: s.Field) -> List[Str] {
    list.concat(acc, ["'" + f.name + "'", sql_quote(f.name)])
  })
  # Postgres returns json_build_object as a `json`-typed column, which the
  # driver cannot deserialize into the Str the decode layer expects — cast to
  # TEXT (SQLite's json_object already yields TEXT).
  match dialect {
    DbPostgres(_) => "json_build_object(" + str.join(pairs, ", ") + ")::TEXT AS _j",
    DbSqlite(_) => "json_object(" + str.join(pairs, ", ") + ") AS _j",
  }
}

fn build_select_json[T](q :: SelectQuery[T], dialect :: conn.Dialect) -> SqlQuery {
  let tname := sql_quote(q.repo.table)
  let json_expr := json_agg_expr(q.repo.schema.fields, dialect)
  let base := "SELECT " + json_expr + " FROM " + tname
  let full := build_select(q)
  let star_pfx := "SELECT * FROM " + tname
  let suffix := str.slice(full.sql, str.len(star_pfx), str.len(full.sql))
  { sql: base + suffix, params: full.params }
}

fn build_insert_returning_json[T](q :: InsertQuery[T], dialect :: conn.Dialect) -> SqlQuery {
  let base := build_insert(q)
  let json_expr := json_agg_expr(q.repo.schema.fields, dialect)
  { sql: base.sql + " RETURNING " + json_expr, params: base.params }
}

# ---- Dialect-aware placeholder numbering --------------------------
fn for_dialect(q :: SqlQuery, dialect :: conn.Dialect) -> SqlQuery {
  match dialect {
    DbSqlite(_) => q,
    DbPostgres(_) => { sql: number_placeholders(q.sql), params: q.params },
  }
}

fn number_placeholders(raw :: Str) -> Str {
  let parts := str.split(raw, "?")
  if list.len(parts) <= 1 {
    raw
  } else {
    let first := match list.head(parts) {
      None => "",
      Some(s2) => s2,
    }
    let rest := list.tail(parts)
    let result := list.fold(rest, (first, 1), fn (acc :: (Str, Int), part :: Str) -> (Str, Int) {
      let s2 := match acc {
        (s3, _) => s3,
      }
      let i := match acc {
        (_, i2) => i2,
      }
      (s2 + "$" + int.to_str(i) + part, i + 1)
    })
    match result {
      (s2, _) => s2,
    }
  }
}

# ---- Row decoding -------------------------------------------------
fn decode_rows[T](rows :: List[{ _j :: Str }], decode :: (jv.Json) -> Result[T, se.Errors]) -> Result[List[T], dbe.DbErr] {
  list.fold(rows, Ok([]), fn (acc :: Result[List[T], dbe.DbErr], row :: { _j :: Str }) -> Result[List[T], dbe.DbErr] {
    match acc {
      Err(e) => Err(e),
      Ok(items) => match jv.parse(row._j) {
        Err(pe) => Err(dbe.decode_err(pe.message)),
        Ok(j) => match decode(j) {
          Err(_) => Err(dbe.decode_err("schema validation failed")),
          Ok(v) => Ok(list.concat(items, [v])),
        },
      },
    }
  })
}

# ---- Runtime execution --------------------------------------------
fn run_select[T](q :: SelectQuery[T], db :: conn.ConnDb) -> [sql] Result[List[T], dbe.DbErr] {
  let sq := for_dialect(build_select_json(q, db.dialect), db.dialect)
  let raw := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(rows) => decode_rows(rows, q.repo.decode),
  }
}

fn run_count[T](q :: SelectQuery[T], db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_count(q), db.dialect)
  let raw :: Result[List[{ count :: Int }], SqlError] := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(rows) => match list.head(rows) {
      None => Ok(0),
      Some(r) => Ok(r.count),
    },
  }
}

fn run_insert[T](q :: InsertQuery[T], db :: conn.ConnDb) -> [sql] Result[T, dbe.DbErr] {
  let sq := for_dialect(build_insert_returning_json(q, db.dialect), db.dialect)
  let raw := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(rows) => match decode_rows(rows, q.repo.decode) {
      Err(e) => Err(e),
      Ok(items) => match list.head(items) {
        None => Err(dbe.query_err("INSERT returned no rows")),
        Some(v) => Ok(v),
      },
    },
  }
}

fn run_insert_returning[T](q :: InsertQuery[T], db :: conn.ConnDb) -> [sql] Result[List[T], dbe.DbErr] {
  let sq := for_dialect(build_insert_returning_json(q, db.dialect), db.dialect)
  let raw := sql.query(db.handle, sq.sql, sq.params)
  match raw {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(rows) => decode_rows(rows, q.repo.decode),
  }
}

fn run_update[T](q :: UpdateQuery[T], db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_update(q), db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(n) => Ok(n),
  }
}

fn run_delete[T](q :: DeleteQuery[T], db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_delete(q), db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(n) => Ok(n),
  }
}

fn run_upsert[T](q :: UpsertQuery[T], db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_upsert(q), db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(n) => Ok(n),
  }
}

fn run_bulk_insert[T](q :: BulkInsertQuery[T], db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  let sq := for_dialect(build_bulk_insert(q), db.dialect)
  match sql.exec(db.handle, sq.sql, sq.params) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(n) => Ok(n),
  }
}

fn run_select_iter[T](q :: SelectQuery[T], db :: conn.ConnDb) -> [sql] Iter[Result[T, dbe.DbErr]] {
  let plan := build_select_json(q, db.dialect)
  let rewritten := for_dialect(plan, db.dialect)
  let decode := q.repo.decode
  match sql.query_iter(db.handle, rewritten.sql, rewritten.params) {
    Err(e) => iter.from_list([Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message))]),
    Ok(raw_iter) => iter.map(raw_iter, fn (row :: { _j :: Str }) -> Result[T, dbe.DbErr] {
      match jv.parse(row._j) {
        Err(pe) => Err(dbe.decode_err(pe.message)),
        Ok(j) => match decode(j) {
          Err(_) => Err(dbe.decode_err("schema validation failed")),
          Ok(v) => Ok(v),
        },
      }
    }),
  }
}

fn transaction[A](db :: conn.ConnDb, body :: (conn.ConnDb) -> [sql] Result[A, dbe.DbErr]) -> [sql] Result[A, dbe.DbErr] {
  match sql.exec(db.handle, "BEGIN", []) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, "BEGIN failed: " + e.message)),
    Ok(_) => match body(db) {
      Err(e) => {
        let __lex_discard_1 := sql.exec(db.handle, "ROLLBACK", [])
        Err(e)
      },
      Ok(v) => match sql.exec(db.handle, "COMMIT", []) {
        Err(e) => Err(dbe.sql_error(match e.code {
          None => "",
          Some(c) => c,
        }, "COMMIT failed: " + e.message)),
        Ok(_) => Ok(v),
      },
    },
  }
}

# ---- Helpers (pure) -----------------------------------------------
fn sql_quote(name :: Str) -> Str {
  "\"" + name + "\""
}

fn sql_ident(name :: Str) -> Str {
  let segs := list.fold(str.split(name, "_"), [], fn (acc :: List[Str], seg :: Str) -> List[Str] {
    list.concat(acc, str.split(seg, "-"))
  })
  let split := list.fold(segs, [], fn (acc :: List[Str], seg :: Str) -> List[Str] {
    list.concat(acc, snake_split(seg))
  })
  str.to_lower(str.join(split, "_"))
}

fn snake_split(word :: Str) -> List[Str] {
  if str.is_empty(word) {
    []
  } else {
    snake_split_at(word, 1, 0, [])
  }
}

fn snake_split_at(word :: Str, i :: Int, start :: Int, acc :: List[Str]) -> List[Str] {
  let n := str.len(word)
  if i >= n {
    list.concat(acc, [str.slice(word, start, n)])
  } else {
    let prev := str.slice(word, i - 1, i)
    let curr := str.slice(word, i, i + 1)
    if is_lower(prev) and is_upper(curr) {
      snake_split_at(word, i + 1, i, list.concat(acc, [str.slice(word, start, i)]))
    } else {
      snake_split_at(word, i + 1, start, acc)
    }
  }
}

fn is_upper(c :: Str) -> Bool {
  str.to_upper(c) == c and str.to_lower(c) != c
}

fn is_lower(c :: Str) -> Bool {
  str.to_lower(c) == c and str.to_upper(c) != c
}

fn json_to_param(j :: Option[jv.Json]) -> SqlParam {
  match j {
    None => PNull,
    Some(v) => match v {
      JNull => PNull,
      JBool(b) => if b {
        PInt(1)
      } else {
        PInt(0)
      },
      JInt(n) => PInt(n),
      JFloat(x) => PStr(jv.stringify(JFloat(x))),
      JStr(s2) => PStr(s2),
      _ => PStr(jv.stringify(v)),
    },
  }
}

