import "std.str"  as str
import "std.list" as list
import "std.int"  as int

type Param =
    PStr(Str)
  | PInt(Int)
  | PFloat(Float)
  | PBool(Bool)
  | PNull

type Predicate =
    PEq(Str, Param)
  | PNeq(Str, Param)
  | PGt(Str, Param)
  | PGte(Str, Param)
  | PLt(Str, Param)
  | PLte(Str, Param)
  | PIn(Str, List[Param])
  | PIsNull(Str)
  | PIsNotNull(Str)
  | PLike(Str, Str)
  | PILike(Str, Str)
  | PBetween(Str, Param, Param)
  | PRaw(Str, List[Param])
  | PAnd(Predicate, Predicate)
  | POr(Predicate, Predicate)
  | PNot(Predicate)

# Smart constructors
fn eq(col :: Str, v :: Param)                    -> Predicate { PEq(col, v) }
fn neq(col :: Str, v :: Param)                   -> Predicate { PNeq(col, v) }
fn gt(col :: Str, v :: Param)                    -> Predicate { PGt(col, v) }
fn gte(col :: Str, v :: Param)                   -> Predicate { PGte(col, v) }
fn lt(col :: Str, v :: Param)                    -> Predicate { PLt(col, v) }
fn lte(col :: Str, v :: Param)                   -> Predicate { PLte(col, v) }
fn in_list(col :: Str, vs :: List[Param])        -> Predicate { PIn(col, vs) }
fn is_null(col :: Str)                           -> Predicate { PIsNull(col) }
fn is_not_null(col :: Str)                       -> Predicate { PIsNotNull(col) }
fn like(col :: Str, pattern :: Str)              -> Predicate { PLike(col, pattern) }
fn ilike(col :: Str, pattern :: Str)             -> Predicate { PILike(col, pattern) }
fn between(col :: Str, lo :: Param, hi :: Param) -> Predicate { PBetween(col, lo, hi) }
fn raw_pred(sql :: Str, params :: List[Param])   -> Predicate { PRaw(sql, params) }
fn and_pred(a :: Predicate, b :: Predicate)      -> Predicate { PAnd(a, b) }
fn or_pred(a :: Predicate, b :: Predicate)       -> Predicate { POr(a, b) }
fn not_pred(p :: Predicate)                      -> Predicate { PNot(p) }

# Render a list of predicates ANDed together.
# Returns (sql_fragment, params_list). Empty list => ("", []).
fn render_where(preds :: List[Predicate]) -> (Str, List[Param]) {
  if list.is_empty(preds) {
    ("", [])
  } else {
    let first := list.head(preds)
    let rest  := list.tail(preds)
    match first {
      None    => ("", []),
      Some(p) => {
        let init        := render_pred(p)
        let init_sql    := match init { (s, _) => s }
        let init_params := match init { (_, ps) => ps }
        let folded := list.fold(rest,
          (init_sql, init_params),
          fn (acc :: (Str, List[Param]), pred :: Predicate) -> (Str, List[Param]) {
            let acc_sql    := match acc { (s, _) => s }
            let acc_params := match acc { (_, ps) => ps }
            let r        := render_pred(pred)
            let r_sql    := match r { (s, _) => s }
            let r_params := match r { (_, ps) => ps }
            (acc_sql + " AND " + r_sql, list.concat(acc_params, r_params))
          })
        folded
      },
    }
  }
}

fn render_pred(p :: Predicate) -> (Str, List[Param]) {
  match p {
    PEq(col, v)           => (sql_quote(col) + " = ?",             [v]),
    PNeq(col, v)          => (sql_quote(col) + " != ?",            [v]),
    PGt(col, v)           => (sql_quote(col) + " > ?",             [v]),
    PGte(col, v)          => (sql_quote(col) + " >= ?",            [v]),
    PLt(col, v)           => (sql_quote(col) + " < ?",             [v]),
    PLte(col, v)          => (sql_quote(col) + " <= ?",            [v]),
    PIn(col, vs)          => {
      let placeholders := list.map(vs, fn (_v :: Param) -> Str { "?" })
      (sql_quote(col) + " IN (" + str.join(placeholders, ", ") + ")", vs)
    },
    PIsNull(col)          => (sql_quote(col) + " IS NULL",         []),
    PIsNotNull(col)       => (sql_quote(col) + " IS NOT NULL",     []),
    PLike(col, pat)       => (sql_quote(col) + " LIKE ?",          [PStr(pat)]),
    PILike(col, pat)      => (sql_quote(col) + " ILIKE ?",         [PStr(pat)]),
    PBetween(col, lo, hi) => (sql_quote(col) + " BETWEEN ? AND ?", [lo, hi]),
    PRaw(sql, ps)         => (sql, ps),
    PAnd(a, b) => {
      let ra := render_pred(a)
      let rb := render_pred(b)
      let sa := match ra { (s, _) => s }
      let pa := match ra { (_, ps) => ps }
      let sb := match rb { (s, _) => s }
      let pb := match rb { (_, ps) => ps }
      (sa + " AND " + sb, list.concat(pa, pb))
    },
    POr(a, b) => {
      let ra := render_pred(a)
      let rb := render_pred(b)
      let sa := match ra { (s, _) => s }
      let pa := match ra { (_, ps) => ps }
      let sb := match rb { (s, _) => s }
      let pb := match rb { (_, ps) => ps }
      ("(" + sa + " OR " + sb + ")", list.concat(pa, pb))
    },
    PNot(inner) => {
      let r  := render_pred(inner)
      let s  := match r { (s2, _) => s2 }
      let ps := match r { (_, ps2) => ps2 }
      ("NOT (" + s + ")", ps)
    },
  }
}

fn sql_quote(name :: Str) -> Str { "\"" + name + "\"" }

fn param_to_str(p :: Param) -> Str {
  match p {
    PStr(s)   => "'" + s + "'",
    PInt(n)   => int.to_str(n),
    PFloat(_) => "<float>",
    PBool(b)  => if b { "true" } else { "false" },
    PNull     => "NULL",
  }
}
