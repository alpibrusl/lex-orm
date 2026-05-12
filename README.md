# lex-orm

A typed query builder and migration runner for [lex-lang](https://github.com/alpibrusl/lex-lang), built on top of [lex-schema](https://github.com/alpibrusl/lex-schema).

Implements [lex-lang#357](https://github.com/alpibrusl/lex-lang/issues/357). Requires **lex 0.9+**.

## What it does

- **Pure SQL builder** — `build_select`, `build_insert`, `build_update`, `build_delete` return a `SqlQuery = { sql, params }` value with no effects. Fully testable without a database.
- **Predicate DSL** — composable `PEq / PNeq / PIn / PIsNull / PAnd / POr / PNot` predicates with `?` placeholder params.
- **Schema-driven DDL diffing** — `diff(old, new)` detects added/dropped columns and nullability changes; `to_alter_table` emits `ALTER TABLE` SQL for Postgres and SQLite.
- **Migration planner** — `plan_migrations(current_version, versions)` returns pending `SchemaVersion` entries sorted ascending (uses `list.sort_by` from lex 0.9).
- **Runtime stubs** — `run_select / run_insert / run_update / run_delete / transaction` return `Err(DbQueryFailed(...))` until `std.sql` lands in a future release.

## Repository layout

```
lex.toml           package manifest (lex 0.9+)
src/
  error.lex        DbErr ADT + message/0
  connection.lex   Dialect (DbPostgres | DbSqlite), Db, Tx, connect_*/close
  predicate.lex    Param, Predicate ADT, render_where/render_pred
  query.lex        Repo[T], query builders, build_*, run_* stubs
  migrate.lex      DdlChange, diff, to_alter_table, plan_migrations

tests/
  test_predicate.lex
  test_query.lex
  test_migrate.lex

examples/
  01_blog_posts.lex   SELECT / INSERT / UPDATE / DELETE query plans
  02_migrations.lex   Schema diffing and ALTER TABLE generation

vendor/             kept for lex <0.9 compatibility; ignored when lex.toml resolves deps
```

## Installation

Add lex-orm and lex-schema as dependencies in your project's `lex.toml`:

```toml
[dependencies]
lex-orm    = { path = "../lex-orm" }
lex-schema = { path = "../lex-schema" }
```

Or via git:

```toml
[dependencies]
lex-orm    = { git = "https://github.com/alpibrusl/lex-orm" }
lex-schema = { git = "https://github.com/alpibrusl/lex-schema" }
```

Then import by package name:

```lex
import "lex-orm/query"     as q
import "lex-orm/predicate" as p
```

## Usage

### Query builder

```lex
import "lex-orm/query"     as q
import "lex-orm/predicate" as p
import "lex-schema/schema" as s

let repo := q.for_schema(my_schema, my_decode_fn)

# Build a SELECT (pure, no effects)
let plan :=
  q.build_select(
    q.limit(
      q.where_clause(q.select(repo), p.eq("status", PStr("active"))),
      50
    )
  )
# plan.sql    => SELECT * FROM "my_table" WHERE "status" = ? LIMIT 50
# plan.params => [PStr("active")]
```

### Migrations

```lex
import "lex-orm/migrate"    as m
import "lex-orm/connection" as conn

let changes := m.diff(schema_v1, schema_v2)
let sql     := m.to_alter_table("posts", changes, DbPostgres)
# ALTER TABLE "posts" ADD COLUMN "body" TEXT NOT NULL
# ALTER TABLE "posts" ADD COLUMN "slug" TEXT

let pending := m.plan_migrations(current_version, all_versions)
```

### Dialect variants

lex-orm uses `DbPostgres | DbSqlite` (not `DialectPostgres | DialectSqlite`) to avoid constructor collision with lex-schema's `sdk.SqlDialect` type.

## Running tests

```sh
lex test                   # runs all tests/test_*.lex via lex 0.9 runner
lex test tests/test_predicate.lex  # single file
```

All three test files export `run_all() -> ()` and use `assert` per the lex 0.9 test convention.

## Running examples

```sh
lex run examples/01_blog_posts.lex
lex run examples/02_migrations.lex
```

## Design notes

- **Pure/effectful split**: all SQL *building* is pure; all SQL *execution* (`run_*`) is a stub returning `Err`. Write and test query logic today; plug in `std.sql` when it ships.
- **Generics**: `Repo[T]` is parameterised; the caller supplies `decode :: (Json) -> Result[T, Errors]`. lex-orm only serialises (via schema fields), never deserialises to a concrete type.
- **`?` placeholders**: uniform for both Postgres and SQLite. A thin adapter in the future runtime driver will rewrite them to `$1, $2, ...` for Postgres.
- **`list.sort_by`**: `plan_migrations` uses the key-extractor form added in lex 0.9 (issue #338).
- **Tuple destructuring**: lex-lang does not support `let (a, b) := tuple`; all pair unpacking uses `match pair { (a, b) => ... }`.
