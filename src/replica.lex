import "std.list" as list

import "./connection" as conn

# A primary + zero-or-more read replicas.
# All writes go to primary; reads are served from a replica if available.
type DbPool = {
  primary  :: conn.ConnDb,
  replicas :: List[conn.ConnDb],
}

fn pool(primary :: conn.ConnDb) -> DbPool {
  { primary: primary, replicas: [] }
}

fn add_replica(pl :: DbPool, replica :: conn.ConnDb) -> DbPool {
  { primary: pl.primary, replicas: list.concat(pl.replicas, [replica]) }
}

# Returns the first replica for read queries, falling back to primary.
fn read_db(pl :: DbPool) -> conn.ConnDb {
  match list.head(pl.replicas) {
    None    => pl.primary,
    Some(r) => r,
  }
}

# Always returns primary for write queries.
fn write_db(pl :: DbPool) -> conn.ConnDb { pl.primary }
