import "std.sql" as sql

import "./predicate" as p

import "./query" as q

import "./connection" as conn

import "./error" as dbe

fn where_not_deleted(sel :: q.SelectQuery) -> q.SelectQuery {
  q.where_clause(sel, p.is_null("deleted_at"))
}

fn with_deleted(sel :: q.SelectQuery) -> q.SelectQuery {
  sel
}

fn soft_delete(repo :: q.RepoSchema, pred :: p.Predicate, timestamp :: Str) -> q.UpdateQuery {
  q.where_update(q.set_col(q.update(repo), "deleted_at", PStr(timestamp)), pred)
}

fn restore(repo :: q.RepoSchema, pred :: p.Predicate) -> q.UpdateQuery {
  q.where_update(q.set_col(q.update(repo), "deleted_at", PNull), pred)
}

fn run_soft_delete(repo :: q.RepoSchema, pred :: p.Predicate, timestamp :: Str, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  q.run_update(soft_delete(repo, pred, timestamp), db)
}

fn run_restore(repo :: q.RepoSchema, pred :: p.Predicate, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  q.run_update(restore(repo, pred), db)
}
