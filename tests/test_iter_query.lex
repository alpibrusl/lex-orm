# tests/test_iter_query.lex — run_select_iter pure plan tests
#
# run_select_iter carries [sql] so we can't call it directly without a
# database. These tests verify the plan-building path (pure) to ensure
# the builder produces the expected SQL, matching the existing
# test_query.lex pattern.

import "std.str"  as str
import "std.list" as list

import "../src/query"     as q
import "../src/predicate" as p

import "lex-schema/json_value" as jv
import "lex-schema/error"      as se
import "lex-schema/schema"     as s

# ---- Minimal repo fixture ----------------------------------------

type Item = { id :: Int, name :: Str }

fn item_schema() -> s.ModelSchema {
  { title: "items", description: "",
    fields: [
      s.required_int("id",   []),
      s.required_str("name", []),
    ] }
}

fn decode_item(j :: jv.Json) -> Result[Item, se.Errors] {
  match jv.j_int("", j, "id", []) {
    Err(e) => Err(e),
    Ok(id) =>
      match jv.j_str("", j, "name", []) {
        Err(e)    => Err(e),
        Ok(name)  => Ok({ id: id, name: name }),
      },
  }
}

fn item_repo() -> q.RepoSchema {
  q.for_schema(item_schema())
}

# ---- Plan-building tests (pure) ----------------------------------

fn test_select_iter_plan_sql() -> Bool {
  let plan := q.build_select(q.select(item_repo()))
  plan.sql == "SELECT * FROM \"items\""
}

fn test_select_iter_plan_with_where() -> Bool {
  let q1   := q.where_clause(q.select(item_repo()), p.eq("id", PInt(1)))
  let plan := q.build_select(q1)
  str.contains(plan.sql, "WHERE")
}

fn test_select_iter_plan_with_limit() -> Bool {
  let q1   := q.limit(q.select(item_repo()), 10)
  let plan := q.build_select(q1)
  str.contains(plan.sql, "LIMIT 10")
}

fn test_select_iter_plan_params_empty() -> Bool {
  let plan := q.build_select(q.select(item_repo()))
  list.len(plan.params) == 0
}

fn test_select_iter_plan_params_with_where() -> Bool {
  let q1   := q.where_clause(q.select(item_repo()), p.eq("id", PInt(42)))
  let plan := q.build_select(q1)
  list.len(plan.params) == 1
}

# ---- Runner -------------------------------------------------------

fn run_all() -> Int {
  let cases := [
    test_select_iter_plan_sql(),
    test_select_iter_plan_with_where(),
    test_select_iter_plan_with_limit(),
    test_select_iter_plan_params_empty(),
    test_select_iter_plan_params_with_where(),
  ]
  list.fold(cases, 0, fn (n :: Int, ok :: Bool) -> Int {
    if ok { n } else { n + 1 }
  })
}
