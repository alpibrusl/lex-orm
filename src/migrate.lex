import "std.str"  as str
import "std.int"  as int
import "std.list" as list

import "lex-schema/schema" as s
import "./error"      as dbe
import "./connection" as conn

type DdlChange =
    AddColumn(s.Field)
  | DropColumn(Str)
  | RenameColumn({ from :: Str, to :: Str })
  | SetNullable(Str)
  | SetNotNull(Str)

type SchemaVersion = {
  version :: Int,
  schema  :: s.ModelSchema,
}

# Diff two ModelSchemas: detect added, dropped, and nullability-changed columns.
fn diff(old :: s.ModelSchema, new :: s.ModelSchema) -> List[DdlChange] {
  let added := list.fold(new.fields, [],
    fn (acc :: List[DdlChange], nf :: s.Field) -> List[DdlChange] {
      if field_present(old.fields, nf.name) { acc }
      else { list.concat(acc, [AddColumn(nf)]) }
    })
  let dropped := list.fold(old.fields, [],
    fn (acc :: List[DdlChange], of :: s.Field) -> List[DdlChange] {
      if field_present(new.fields, of.name) { acc }
      else { list.concat(acc, [DropColumn(of.name)]) }
    })
  let nullability := list.fold(new.fields, [],
    fn (acc :: List[DdlChange], nf :: s.Field) -> List[DdlChange] {
      match find_field(old.fields, nf.name) {
        None     => acc,
        Some(of) =>
          if of.required == nf.required { acc }
          else if nf.required {
            list.concat(acc, [SetNotNull(nf.name)])
          } else {
            list.concat(acc, [SetNullable(nf.name)])
          },
      }
    })
  list.concat(list.concat(added, dropped), nullability)
}

# Emit ALTER TABLE SQL for a list of DdlChanges.
fn to_alter_table(
  table   :: Str,
  changes :: List[DdlChange],
  dialect :: conn.Dialect
) -> Str {
  let stmts := list.map(changes, fn (ch :: DdlChange) -> Str {
    alter_stmt(table, ch, dialect)
  })
  str.join(stmts, "\n")
}

fn alter_stmt(table :: Str, ch :: DdlChange, dialect :: conn.Dialect) -> Str {
  let qt := sql_quote(table)
  match ch {
    AddColumn(f) => {
      let col := sql_quote(f.name)
      let ty  := field_base_type(f.kind, dialect)
      let nn  := if f.required { " NOT NULL" } else { "" }
      str.concat("ALTER TABLE ", str.concat(qt,
        str.concat(" ADD COLUMN ", str.concat(col,
          str.concat(" ", str.concat(ty, nn))))))
    },
    DropColumn(name) =>
      str.concat("ALTER TABLE ", str.concat(qt,
        str.concat(" DROP COLUMN ", sql_quote(name)))),
    RenameColumn(r) => {
      let from_q := sql_quote(r.from)
      let to_q   := sql_quote(r.to)
      # Both Postgres and SQLite >=3.25 support RENAME COLUMN
      str.concat("ALTER TABLE ", str.concat(qt,
        str.concat(" RENAME COLUMN ", str.concat(from_q,
          str.concat(" TO ", to_q)))))
    },
    SetNullable(name) => {
      match dialect {
        DbPostgres =>
          str.concat("ALTER TABLE ", str.concat(qt,
            str.concat(" ALTER COLUMN ", str.concat(sql_quote(name),
              " DROP NOT NULL")))),
        DbSqlite =>
          str.concat("-- SQLite: rebuild table to drop NOT NULL on ", name),
      }
    },
    SetNotNull(name) => {
      match dialect {
        DbPostgres =>
          str.concat("ALTER TABLE ", str.concat(qt,
            str.concat(" ALTER COLUMN ", str.concat(sql_quote(name),
              " SET NOT NULL")))),
        DbSqlite =>
          str.concat("-- SQLite: rebuild table to add NOT NULL on ", name),
      }
    },
  }
}

# Return versions with version > current_version, sorted ascending.
# Uses list.sort_by (landed in lex 0.9, issue #338).
fn plan_migrations(
  current_version :: Int,
  versions        :: List[SchemaVersion]
) -> List[SchemaVersion] {
  let pending := list.fold(versions, [],
    fn (acc :: List[SchemaVersion], sv :: SchemaVersion) -> List[SchemaVersion] {
      if sv.version > current_version { list.concat(acc, [sv]) } else { acc }
    })
  list.sort_by(pending, fn (sv :: SchemaVersion) -> Int { sv.version })
}

# DDL for the migrations tracking table.
fn migrations_table_ddl(dialect :: conn.Dialect) -> Str {
  match dialect {
    DbPostgres =>
      "CREATE TABLE IF NOT EXISTS \"lex_schema_migrations\" (\n  version BIGINT PRIMARY KEY,\n  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()\n);",
    DbSqlite =>
      "CREATE TABLE IF NOT EXISTS \"lex_schema_migrations\" (\n  version INTEGER PRIMARY KEY,\n  applied_at TEXT NOT NULL DEFAULT (datetime('now'))\n);",
  }
}

# Runtime stubs — std.sql not yet in lex 0.9.
fn apply(
  _db       :: conn.Db,
  _current  :: Int,
  _versions :: List[SchemaVersion]
) -> Result[Int, dbe.DbErr] {
  Err(DbQueryFailed("std.sql not yet available; use plan_migrations + to_alter_table to inspect the migration plan"))
}

fn rollback(
  _db       :: conn.Db,
  _current  :: Int,
  _versions :: List[SchemaVersion],
  _n        :: Int
) -> Result[Int, dbe.DbErr] {
  Err(DbQueryFailed("std.sql not yet available"))
}

# ---- Helpers (pure) -----------------------------------------------

fn sql_quote(name :: Str) -> Str {
  str.concat("\"", str.concat(name, "\""))
}

fn field_present(fields :: List[s.Field], name :: Str) -> Bool {
  list.fold(fields, false, fn (acc :: Bool, f :: s.Field) -> Bool {
    acc or (f.name == name)
  })
}

fn find_field(fields :: List[s.Field], name :: Str) -> Option[s.Field] {
  list.fold(fields, None, fn (acc :: Option[s.Field], f :: s.Field) -> Option[s.Field] {
    match acc {
      Some(_) => acc,
      None    => if f.name == name { Some(f) } else { None },
    }
  })
}

fn field_base_type(kind :: s.FieldKind, dialect :: conn.Dialect) -> Str {
  match kind {
    KStr(_)      => "TEXT",
    KInt(_)      => match dialect { DbPostgres => "BIGINT",           DbSqlite => "INTEGER" },
    KFloat(_)    => match dialect { DbPostgres => "DOUBLE PRECISION", DbSqlite => "REAL" },
    KBool        => match dialect { DbPostgres => "BOOLEAN",          DbSqlite => "INTEGER" },
    KArray(_, _) => match dialect { DbPostgres => "JSONB",            DbSqlite => "TEXT" },
    KObject(_)   => match dialect { DbPostgres => "BIGINT",           DbSqlite => "INTEGER" },
  }
}
