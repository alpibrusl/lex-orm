import "std.sql" as sql

import "./query"      as q
import "./connection" as conn
import "./error"      as dbe

# Streaming SELECT via sql.query_iter (lex 0.9.2+).
# Returns a lazy Iter backed by a bounded mpsc channel (64-row buffer).
# The caller iterates at their own pace — memory stays constant regardless of result size.
fn stream_select(
  sel :: q.SelectQuery,
  db  :: conn.ConnDb,
) -> [sql] Result[Iter[{ _j :: Str }], dbe.DbErr] {
  let sq := q.for_dialect(q.build_select_json(sel, db.dialect), db.dialect)
  match sql.query_iter(db.handle, sq.sql, sq.params) {
    Err(se) => Err(DbQueryFailed(se.message)),
    Ok(it)  => Ok(it),
  }
}
