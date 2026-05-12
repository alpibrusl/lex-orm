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
  | PAnd(Predicate, Predicate)
  | POr(Predicate, Predicate)
  | PNot(Predicate)

# Smart constructors
fn eq(col :: Str, v :: Param)         -> Predicate { PEq(col, v) }
fn neq(col :: Str, v :: Param)        -> Predicate { PNeq(col, v) }
fn gt(col :: Str, v :: Param)         -> Predicate { PGt(col, v) }
fn gte(col :: Str, v :: Param)        -> Predicate { PGte(col, v) }
fn lt(col :: Str, v :: Param)         -> Predicate { PLt(col, v) }
fn lte(col :: Str, v :: Param)        -> Predicate { PLte(col, v) }
fn in_list(col :: Str, vs :: List[Param]) -> Predicate { PIn(col, vs) }
fn is_null(col :: Str)                -> Predicate { PIsNull(col) }
fn is_not_null(col :: Str)            -> Predicate { PIsNotNull(col) }
fn and_pred(a :: Predicate, b :: Predicate) -> Predicate { PAnd(a, b) }
fn or_pred(a :: Predicate, b :: Predicate)  -> Predicate { POr(a, b) }
fn not_pred(p :: Predicate)           -> Predicate { PNot(p) }

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
        let init := render_pred(p)
        let init_sql    := match init { (s, _) => s }
        let init_params := match init { (_, ps) => ps }
        let folded := list.fold(rest,
          (init_sql, init_params),
          fn (acc :: (Str, List[Param]), pred :: Predicate) -> (Str, List[Param]) {
            let acc_sql    := match acc { (s, _) => s }
            let acc_params := match acc { (_, ps) => ps }
            let r := render_pred(pred)
            let r_sql    := match r { (s, _) => s }
            let r_params := match r { (_, ps) => ps }
            (
              str.concat(acc_sql, str.concat(" AND ", r_sql)),
              list.concat(acc_params, r_params)
            )
          })
        folded
      },
    }
  }
}

fn render_pred(p :: Predicate) -> (Str, List[Param]) {
  match p {
    PEq(col, v)       => (str.concat(sql_quote(col), " = ?"),  [v]),
    PNeq(col, v)      => (str.concat(sql_quote(col), " != ?"), [v]),
    PGt(col, v)       => (str.concat(sql_quote(col), " > ?"),  [v]),
    PGte(col, v)      => (str.concat(sql_quote(col), " >= ?"), [v]),
    PLt(col, v)       => (str.concat(sql_quote(col), " < ?"),  [v]),
    PLte(col, v)      => (str.concat(sql_quote(col), " <= ?"), [v]),
    PIn(col, vs)      => {
      let placeholders := list.map(vs, fn (_v :: Param) -> Str { "?" })
      let in_sql := str.concat(
        sql_quote(col),
        str.concat(" IN (", str.concat(str.join(placeholders, ", "), ")")))
      (in_sql, vs)
    },
    PIsNull(col)      => (str.concat(sql_quote(col), " IS NULL"),     []),
    PIsNotNull(col)   => (str.concat(sql_quote(col), " IS NOT NULL"), []),
    PAnd(a, b) => {
      let ra := render_pred(a)
      let rb := render_pred(b)
      let sa := match ra { (s, _) => s }
      let pa := match ra { (_, ps) => ps }
      let sb := match rb { (s, _) => s }
      let pb := match rb { (_, ps) => ps }
      (str.concat(sa, str.concat(" AND ", sb)), list.concat(pa, pb))
    },
    POr(a, b) => {
      let ra := render_pred(a)
      let rb := render_pred(b)
      let sa := match ra { (s, _) => s }
      let pa := match ra { (_, ps) => ps }
      let sb := match rb { (s, _) => s }
      let pb := match rb { (_, ps) => ps }
      (str.concat("(", str.concat(sa, str.concat(" OR ", str.concat(sb, ")")))), list.concat(pa, pb))
    },
    PNot(inner) => {
      let r := render_pred(inner)
      let s := match r { (s2, _) => s2 }
      let ps := match r { (_, ps2) => ps2 }
      (str.concat("NOT (", str.concat(s, ")")), ps)
    },
  }
}

fn sql_quote(name :: Str) -> Str {
  str.concat("\"", str.concat(name, "\""))
}

fn param_to_str(p :: Param) -> Str {
  match p {
    PStr(s)   => str.concat("'", str.concat(s, "'")),
    PInt(n)   => int.to_str(n),
    PFloat(x) => "<float>",
    PBool(b)  => if b { "true" } else { "false" },
    PNull     => "NULL",
  }
}
