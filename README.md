# lex-orm

A typed query builder and migration runner for [lex-lang](https://github.com/alpibrusl/lex-lang), built on top of [lex-schema](https://github.com/alpibrusl/lex-schema).

Implements [lex-lang#357](https://github.com/alpibrusl/lex-lang/issues/357).

## What it does

- **Pure SQL builder** — `build_select`, `build_insert`, `build_update`, `build_delete` return a `SqlQuery = { sql, params }` value with no effects. Fully testable today without a database.
- **Predicate DSL** — composable `PEq / PNeq / PIn / PIsNull / PAnd / POr / PNot` predicates with `?` placeholder params.
- **Schema-driven DDL diffing** — `diff(old, new)` detects added/dropped columns and nullability changes; `to_alter_table` emits `ALTER TABLE` SQL for Postgres and SQLite.
- **Migration planner** — `plan_migrations(current_version, versions)` returns pending `SchemaVersion` entries sorted ascending.
- **Runtime stubs** — `run_select / run_insert / run_update / run_delete / transaction` carry the `[sql]` effect annotation and return `Err(DbQueryFailed(...))` until `std.sql` lands in lex 0.9+.

## Repository layout

```
src/
  error.lex       DbErr ADT + message/0
  connection.lex  Dialect (DbPostgres | DbSqlite), Db, Tx, connect_*/close
  predicate.lex   Param, Predicate ADT, render_where/render_pred
  query.lex       Repo[T], query builders, build_*, run_* stubs
  migrate.lex     DdlChange, diff, to_alter_table, plan_migrations

tests/
  test_predicate.lex
  test_query.lex
  test_migrate.lex

examples/
  01_blog_posts.lex   SELECT / INSERT / UPDATE / DELETE query plans
  02_migrations.lex   Schema diffing and ALTER TABLE generation

vendor/
  lex-schema/src/   Vendored copy of lex-schema (no package manager yet)
```

## Installation (vendoring)

Since lex has no package manager yet, vendor lex-schema alongside your project:

```sh
mkdir -p vendor/lex-schema/src
cp path/to/lex-schema/src/*.lex vendor/lex-schema/src/
```

Then import lex-orm modules with relative paths:

```
import "./src/query"     as q
import "./src/predicate" as p
```

## Usage

### Query builder

```
import "./src/query"     as q
import "./src/predicate" as p
import "./vendor/lex-schema/src/schema" as s

let repo := q.for_schema(my_schema, my_decode_fn)

# Build a SELECT (pure, no effects)
let plan :=
  q.build_select(
    q.limit(
      q.where_clause(q.select(repo), p.eq("status", PStr("active"))),
      50
    )
  )
# plan.sql   => SELECT * FROM "my_table" WHERE "status" = ? LIMIT 50
# plan.params => [PStr("active")]
```

### Migrations

```
import "./src/migrate"    as m
import "./src/connection" as conn

let changes := m.diff(schema_v1, schema_v2)
let sql     := m.to_alter_table("posts", changes, DbPostgres)
# ALTER TABLE "posts" ADD COLUMN "body" TEXT NOT NULL
# ALTER TABLE "posts" ADD COLUMN "slug" TEXT

let pending := m.plan_migrations(current_version, all_versions)
```

### Dialect variants

lex-orm uses `DbPostgres | DbSqlite` (not `DialectPostgres | DialectSqlite`) to avoid constructor collision with lex-schema's `sdk.SqlDialect` type. If you import both packages, be aware of this distinction.

## Running tests

```sh
lex run tests/test_predicate.lex
lex run tests/test_query.lex
lex run tests/test_migrate.lex
```

All three test files export `run_all() -> Int` which returns the number of failures (0 = all pass).

## Running examples

```sh
lex run examples/01_blog_posts.lex
lex run examples/02_migrations.lex
```

## Design notes

- **Pure/effectful split**: all SQL *building* is pure; all SQL *execution* (`run_*`) carries `[sql]`. This lets you write and test query logic before `std.sql` ships.
- **Generics**: `Repo[T]` is parameterised; the caller supplies a `decode :: (Json) -> Result[T, Errors]` function. lex-orm only serialises (via schema fields), never deserialises to a concrete type.
- **`?` placeholders**: used uniformly for both Postgres (`$1, $2, ...`) and SQLite (`?`). A thin adapter layer in the runtime driver will rewrite them once `std.sql` lands.
- **Tuple destructuring**: lex-lang doesn't support `let (a, b) := tuple`; all pair unpacking uses `match pair { (a, b) => ... }`.
