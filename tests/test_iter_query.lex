# tests/test_iter_query.lex — run_select_iter pure plan tests
#
# run_select_iter carries [sql] so we can't call it directly without a
# database. These tests verify the plan-building path (pure) to ensure
# the builder produces the expected SQL, matching the existing
# test_query.lex pattern.

import "std.str" as str

import "std.list" as list

import "../src/query" as q

import "../src/predicate" as p

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "lex-schema/schema" as s

# ---- Minimal repo fixture ----------------------------------------
type Item = { id :: Int, name :: Str }

fn item_schema() -> s.ModelSchema {
  { title: "items", description: "", fields: [s.required_int("id", []), s.required_str("name", [])] }
}

fn decode_item(j :: jv.Json) -> Result[Item, se.Errors] {
  match jv.j_int("", j, "id", []) {
    Err(e) => Err(e),
    Ok(id) => match jv.j_str("", j, "name", []) {
      Err(e) => Err(e),
      Ok(name) => Ok({ id: id, name: name }),
    },
  }
}

fn item_repo() -> q.RepoSchema {
  q.for_schema(item_schema())
}

# ---- Plan-building tests (pure) ----------------------------------
fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn test_select_iter_plan_sql() -> Result[Unit, Str] {
  let plan := q.build_select(q.select(item_repo()))
  check("plan sql", plan.sql == "SELECT * FROM \"items\"")
}

fn test_select_iter_plan_with_where() -> Result[Unit, Str] {
  let q1 := q.where_clause(q.select(item_repo()), p.eq("id", PInt(1)))
  let plan := q.build_select(q1)
  check("plan WHERE", str.contains(plan.sql, "WHERE"))
}

fn test_select_iter_plan_with_limit() -> Result[Unit, Str] {
  let q1 := q.limit(q.select(item_repo()), 10)
  let plan := q.build_select(q1)
  check("plan LIMIT", str.contains(plan.sql, "LIMIT 10"))
}

fn test_select_iter_plan_params_empty() -> Result[Unit, Str] {
  let plan := q.build_select(q.select(item_repo()))
  check("plan empty params", list.len(plan.params) == 0)
}

fn test_select_iter_plan_params_with_where() -> Result[Unit, Str] {
  let q1 := q.where_clause(q.select(item_repo()), p.eq("id", PInt(42)))
  let plan := q.build_select(q1)
  check("plan one param", list.len(plan.params) == 1)
}

fn suite() -> List[Result[Unit, Str]] {
  [test_select_iter_plan_sql(), test_select_iter_plan_with_where(), test_select_iter_plan_with_limit(), test_select_iter_plan_params_empty(), test_select_iter_plan_params_with_where()]
}

# ---- Runner -------------------------------------------------------
fn run_all() -> Int {
  let failed := list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
  if failed > 0 {
    1 / 0
  } else {
    0
  }
}

