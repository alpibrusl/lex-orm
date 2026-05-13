import "std.sql"  as sql
import "std.time" as time

import "./predicate"  as p
import "./query"      as q
import "./connection" as conn
import "./error"      as dbe

# Add WHERE deleted_at IS NULL — exclude soft-deleted rows.
fn where_not_deleted(sel :: q.SelectQuery) -> q.SelectQuery {
  q.where_clause(sel, p.is_null("deleted_at"))
}

# Return the query unchanged — explicitly include soft-deleted rows.
fn with_deleted(sel :: q.SelectQuery) -> q.SelectQuery { sel }

# Build UPDATE SET deleted_at = timestamp WHERE pred.
# The caller provides the timestamp string (e.g. "2026-05-13T10:00:00Z").
fn soft_delete(
  repo      :: q.RepoSchema,
  pred      :: p.Predicate,
  timestamp :: Str,
) -> q.UpdateQuery {
  q.where_update(
    q.set_col(q.update(repo), "deleted_at", PStr(timestamp)),
    pred)
}

# Build UPDATE SET deleted_at = NULL WHERE pred (un-delete).
fn restore(repo :: q.RepoSchema, pred :: p.Predicate) -> q.UpdateQuery {
  q.where_update(
    q.set_col(q.update(repo), "deleted_at", PNull),
    pred)
}

fn run_soft_delete(
  repo      :: q.RepoSchema,
  pred      :: p.Predicate,
  timestamp :: Str,
  db        :: conn.ConnDb,
) -> [sql] Result[Int, dbe.DbErr] {
  q.run_update(soft_delete(repo, pred, timestamp), db)
}

fn run_restore(
  repo :: q.RepoSchema,
  pred :: p.Predicate,
  db   :: conn.ConnDb,
) -> [sql] Result[Int, dbe.DbErr] {
  q.run_update(restore(repo, pred), db)
}

# Soft-delete using the current wall-clock time (ISO-8601 UTC via std.time).
fn soft_delete_now(
  repo :: q.RepoSchema,
  pred :: p.Predicate,
) -> [time] q.UpdateQuery {
  q.where_update(
    q.set_col(q.update(repo), "deleted_at", PStr(time.now_str())),
    pred)
}

fn run_soft_delete_now(
  repo :: q.RepoSchema,
  pred :: p.Predicate,
  db   :: conn.ConnDb,
) -> [sql, time] Result[Int, dbe.DbErr] {
  q.run_update(soft_delete_now(repo, pred), db)
}
