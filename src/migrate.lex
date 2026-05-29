import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.sql" as sql

import "lex-schema/schema" as s

import "./error" as dbe

import "./connection" as conn

type DdlChange = AddColumn(s.Field) | DropColumn(Str) | RenameColumn({ from :: Str, to :: Str }) | SetNullable(Str) | SetNotNull(Str) | AddIndex({ name :: Str, columns :: List[Str], unique :: Bool }) | DropIndex(Str)

type SchemaVersion = { version :: Int, schema :: s.ModelSchema }

# Smart constructors for index changes.
fn add_index(name :: Str, columns :: List[Str]) -> DdlChange {
  AddIndex({ name: name, columns: columns, unique: false })
}

fn add_unique_index(name :: Str, columns :: List[Str]) -> DdlChange {
  AddIndex({ name: name, columns: columns, unique: true })
}

fn drop_index(name :: Str) -> DdlChange {
  DropIndex(name)
}

# Diff two ModelSchemas: detect added, dropped, and nullability-changed columns.
fn diff(old :: s.ModelSchema, new :: s.ModelSchema) -> List[DdlChange] {
  let added := list.fold(new.fields, [], fn (acc :: List[DdlChange], nf :: s.Field) -> List[DdlChange] {
    if field_present(old.fields, nf.name) {
      acc
    } else {
      list.concat(acc, [AddColumn(nf)])
    }
  })
  let dropped := list.fold(old.fields, [], fn (acc :: List[DdlChange], of :: s.Field) -> List[DdlChange] {
    if field_present(new.fields, of.name) {
      acc
    } else {
      list.concat(acc, [DropColumn(of.name)])
    }
  })
  let nullability := list.fold(new.fields, [], fn (acc :: List[DdlChange], nf :: s.Field) -> List[DdlChange] {
    match find_field(old.fields, nf.name) {
      None => acc,
      Some(of) => if of.required == nf.required {
        acc
      } else {
        if nf.required {
          list.concat(acc, [SetNotNull(nf.name)])
        } else {
          list.concat(acc, [SetNullable(nf.name)])
        }
      },
    }
  })
  list.concat(list.concat(added, dropped), nullability)
}

# Emit a CREATE TABLE IF NOT EXISTS statement for a ModelSchema.
# Table name defaults to `schema.title`; use `to_create_table_named`
# if the table identifier differs from the schema title.
fn to_create_table(schema :: s.ModelSchema, dialect :: conn.Dialect) -> Str {
  to_create_table_named(schema.title, schema, dialect)
}

fn to_create_table_named(table :: Str, schema :: s.ModelSchema, dialect :: conn.Dialect) -> Str {
  let qt := sql_quote(table)
  let col_defs := list.map(schema.fields, fn (f :: s.Field) -> Str {
    let null_part := if f.required {
      " NOT NULL"
    } else {
      ""
    }
    "  " + sql_quote(f.name) + " " + field_base_type(f.kind, dialect) + null_part
  })
  "CREATE TABLE IF NOT EXISTS " + qt + " (\n" + str.join(col_defs, ",\n") + "\n)"
}

# Emit a DROP TABLE IF EXISTS statement for a ModelSchema.
fn to_drop_table(schema :: s.ModelSchema, dialect :: conn.Dialect) -> Str {
  "DROP TABLE IF EXISTS " + sql_quote(schema.title)
}

# Emit ALTER TABLE / CREATE INDEX SQL for a list of DdlChanges.
fn to_alter_table(table :: Str, changes :: List[DdlChange], dialect :: conn.Dialect) -> Str {
  str.join(list.map(changes, fn (ch :: DdlChange) -> Str {
    alter_stmt(table, ch, dialect)
  }), "\n")
}

fn alter_stmt(table :: Str, ch :: DdlChange, dialect :: conn.Dialect) -> Str {
  let qt := sql_quote(table)
  match ch {
    AddColumn(f) => "ALTER TABLE " + qt + " ADD COLUMN " + sql_quote(f.name) + " " + field_base_type(f.kind, dialect) + if f.required {
      " NOT NULL"
    } else {
      ""
    },
    DropColumn(name) => "ALTER TABLE " + qt + " DROP COLUMN " + sql_quote(name),
    RenameColumn(r) => "ALTER TABLE " + qt + " RENAME COLUMN " + sql_quote(r.from) + " TO " + sql_quote(r.to),
    SetNullable(name) => match dialect {
      DbPostgres(_) => "ALTER TABLE " + qt + " ALTER COLUMN " + sql_quote(name) + " DROP NOT NULL",
      DbSqlite(_) => "-- SQLite: rebuild table to drop NOT NULL on " + name,
    },
    SetNotNull(name) => match dialect {
      DbPostgres(_) => "ALTER TABLE " + qt + " ALTER COLUMN " + sql_quote(name) + " SET NOT NULL",
      DbSqlite(_) => "-- SQLite: rebuild table to add NOT NULL on " + name,
    },
    AddIndex(idx) => {
      let unique_pfx := if idx.unique {
        "UNIQUE "
      } else {
        ""
      }
      "CREATE " + unique_pfx + "INDEX IF NOT EXISTS " + sql_quote(idx.name) + " ON " + qt + " (" + str.join(list.map(idx.columns, sql_quote), ", ") + ")"
    },
    DropIndex(name) => "DROP INDEX IF EXISTS " + sql_quote(name),
  }
}

# Return versions with version > current_version, sorted ascending.
fn plan_migrations(current_version :: Int, versions :: List[SchemaVersion]) -> List[SchemaVersion] {
  let pending := list.fold(versions, [], fn (acc :: List[SchemaVersion], sv :: SchemaVersion) -> List[SchemaVersion] {
    if sv.version > current_version {
      list.concat(acc, [sv])
    } else {
      acc
    }
  })
  list.sort_by(pending, fn (sv :: SchemaVersion) -> Int {
    sv.version
  })
}

# DDL for the migrations tracking table.
fn migrations_table_ddl(dialect :: conn.Dialect) -> Str {
  match dialect {
    DbPostgres(_) => "CREATE TABLE IF NOT EXISTS \"lex_schema_migrations\" (\n  version BIGINT PRIMARY KEY,\n  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()\n);",
    DbSqlite(_) => "CREATE TABLE IF NOT EXISTS \"lex_schema_migrations\" (\n  version INTEGER PRIMARY KEY,\n  applied_at TEXT NOT NULL DEFAULT (datetime('now'))\n);",
  }
}

# Apply pending migrations and record each version in lex_schema_migrations.
fn apply(db :: conn.ConnDb, current :: Int, versions :: List[SchemaVersion]) -> [sql] Result[Int, dbe.DbErr] {
  let ddl := migrations_table_ddl(db.dialect)
  match sql.exec(db.handle, ddl, []) {
    Err(e) => Err(dbe.sql_error(match e.code {
      None => "",
      Some(c) => c,
    }, e.message)),
    Ok(_) => {
      let all_sorted := list.sort_by(versions, fn (sv :: SchemaVersion) -> Int {
        sv.version
      })
      let pending := plan_migrations(current, versions)
      run_pending(db, all_sorted, pending, 0)
    },
  }
}

fn run_pending(db :: conn.ConnDb, all_sorted :: List[SchemaVersion], pending :: List[SchemaVersion], applied :: Int) -> [sql] Result[Int, dbe.DbErr] {
  match list.head(pending) {
    None => Ok(applied),
    Some(sv) => {
      let rest := list.tail(pending)
      let prev_schema := schema_before(all_sorted, sv.version)
      let stmts := match prev_schema {
        None => [to_create_table(sv.schema, db.dialect)],
        Some(old_sch) => list.map(diff(old_sch, sv.schema), fn (ch :: DdlChange) -> Str {
          alter_stmt(sv.schema.title, ch, db.dialect)
        }),
      }
      match exec_stmts(db, stmts) {
        Err(e) => Err(e),
        Ok(_) => {
          let insert_sql := "INSERT INTO \"lex_schema_migrations\" (version) VALUES (" + int.to_str(sv.version) + ")"
          match sql.exec(db.handle, insert_sql, []) {
            Err(e) => Err(dbe.sql_error(match e.code {
              None => "",
              Some(c) => c,
            }, e.message)),
            Ok(_) => run_pending(db, all_sorted, rest, applied + 1),
          }
        },
      }
    },
  }
}

# Roll back the n most-recently applied versions.
fn rollback(db :: conn.ConnDb, current :: Int, versions :: List[SchemaVersion], n :: Int) -> [sql] Result[Int, dbe.DbErr] {
  let all_sorted := list.sort_by(versions, fn (sv :: SchemaVersion) -> Int {
    sv.version
  })
  let to_undo := find_to_rollback(all_sorted, current, n, [])
  rollback_pending(db, all_sorted, to_undo, 0)
}

fn rollback_pending(db :: conn.ConnDb, all_sorted :: List[SchemaVersion], to_undo :: List[SchemaVersion], count :: Int) -> [sql] Result[Int, dbe.DbErr] {
  match list.head(to_undo) {
    None => Ok(count),
    Some(sv) => {
      let rest := list.tail(to_undo)
      let prev_schema := schema_before(all_sorted, sv.version)
      let stmts := match prev_schema {
        None => [to_drop_table(sv.schema, db.dialect)],
        Some(old_sch) => list.map(diff(sv.schema, old_sch), fn (ch :: DdlChange) -> Str {
          alter_stmt(sv.schema.title, ch, db.dialect)
        }),
      }
      match exec_stmts(db, stmts) {
        Err(e) => Err(e),
        Ok(_) => {
          let delete_sql := "DELETE FROM \"lex_schema_migrations\" WHERE version = " + int.to_str(sv.version)
          match sql.exec(db.handle, delete_sql, []) {
            Err(e) => Err(dbe.sql_error(match e.code {
              None => "",
              Some(c) => c,
            }, e.message)),
            Ok(_) => rollback_pending(db, all_sorted, rest, count + 1),
          }
        },
      }
    },
  }
}

# Find the n highest versions <= max_ver to roll back (descending order).
fn find_to_rollback(sorted :: List[SchemaVersion], max_ver :: Int, n :: Int, acc :: List[SchemaVersion]) -> List[SchemaVersion] {
  if n <= 0 {
    acc
  } else {
    let highest := list.fold(sorted, None, fn (best :: Option[SchemaVersion], sv :: SchemaVersion) -> Option[SchemaVersion] {
      if sv.version <= max_ver {
        match best {
          None => Some(sv),
          Some(b) => if sv.version > b.version {
            Some(sv)
          } else {
            Some(b)
          },
        }
      } else {
        best
      }
    })
    match highest {
      None => acc,
      Some(sv) => find_to_rollback(sorted, sv.version - 1, n - 1, list.concat(acc, [sv])),
    }
  }
}

# Find the schema immediately before the given version.
fn schema_before(sorted :: List[SchemaVersion], version :: Int) -> Option[s.ModelSchema] {
  let prev := list.fold(sorted, None, fn (acc :: Option[SchemaVersion], sv :: SchemaVersion) -> Option[SchemaVersion] {
    if sv.version < version {
      match acc {
        None => Some(sv),
        Some(b) => if sv.version > b.version {
          Some(sv)
        } else {
          Some(b)
        },
      }
    } else {
      acc
    }
  })
  match prev {
    None => None,
    Some(sv) => Some(sv.schema),
  }
}

fn exec_stmts(db :: conn.ConnDb, stmts :: List[Str]) -> [sql] Result[Unit, dbe.DbErr] {
  list.fold(stmts, Ok(()), fn (acc :: Result[Unit, dbe.DbErr], stmt :: Str) -> [sql] Result[Unit, dbe.DbErr] {
    match acc {
      Err(e) => Err(e),
      Ok(_) => match sql.exec(db.handle, stmt, []) {
        Err(e) => Err(dbe.sql_error(match e.code {
          None => "",
          Some(c) => c,
        }, e.message)),
        Ok(_) => Ok(()),
      },
    }
  })
}

# ---- Helpers (pure) -----------------------------------------------
fn sql_quote(name :: Str) -> Str {
  "\"" + name + "\""
}

fn field_present(fields :: List[s.Field], name :: Str) -> Bool {
  list.fold(fields, false, fn (acc :: Bool, f :: s.Field) -> Bool {
    acc or f.name == name
  })
}

fn find_field(fields :: List[s.Field], name :: Str) -> Option[s.Field] {
  list.fold(fields, None, fn (acc :: Option[s.Field], f :: s.Field) -> Option[s.Field] {
    match acc {
      Some(_) => acc,
      None => if f.name == name {
        Some(f)
      } else {
        None
      },
    }
  })
}

fn field_base_type(kind :: s.FieldKind, dialect :: conn.Dialect) -> Str {
  match kind {
    KStr(_) => "TEXT",
    KInt(_) => match dialect {
      DbPostgres(_) => "BIGINT",
      DbSqlite(_) => "INTEGER",
    },
    KFloat(_) => match dialect {
      DbPostgres(_) => "DOUBLE PRECISION",
      DbSqlite(_) => "REAL",
    },
    KBool => match dialect {
      DbPostgres(_) => "BOOLEAN",
      DbSqlite(_) => "INTEGER",
    },
    KArray(_, _) => match dialect {
      DbPostgres(_) => "JSONB",
      DbSqlite(_) => "TEXT",
    },
    KObject(_) => match dialect {
      DbPostgres(_) => "JSONB",
      DbSqlite(_) => "TEXT",
    },
  }
}

