import "std.sql" as sql

import "./predicate" as p

import "./query" as q

import "./connection" as conn

import "./error" as dbe

fn where_not_deleted[T](sel :: q.SelectQuery[T]) -> q.SelectQuery[T] {
  q.where_clause(sel, p.is_null("deleted_at"))
}

fn with_deleted[T](sel :: q.SelectQuery[T]) -> q.SelectQuery[T] {
  sel
}

fn soft_delete[T](repo :: q.Repo[T], pred :: p.Predicate, timestamp :: Str) -> q.UpdateQuery[T] {
  q.where_update(q.set_col(q.update(repo), "deleted_at", PStr(timestamp)), pred)
}

fn restore[T](repo :: q.Repo[T], pred :: p.Predicate) -> q.UpdateQuery[T] {
  q.where_update(q.set_col(q.update(repo), "deleted_at", PNull), pred)
}

fn run_soft_delete[T](repo :: q.Repo[T], pred :: p.Predicate, timestamp :: Str, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  q.run_update(soft_delete(repo, pred, timestamp), db)
}

fn run_restore[T](repo :: q.Repo[T], pred :: p.Predicate, db :: conn.ConnDb) -> [sql] Result[Int, dbe.DbErr] {
  q.run_update(restore(repo, pred), db)
}
