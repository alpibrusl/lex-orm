# lex-schema — applicative combinators
#
# These functions lift N field validators into a single record
# builder, accumulating *every* failure across the N branches rather
# than short-circuiting at the first.
#
# Effects: none.

import "./error" as e

import "std.list" as list

fn combine2[A, B, T](a :: Result[A, e.Errors], b :: Result[B, e.Errors], build :: (A, B) -> T) -> Result[T, e.Errors] {
  match (a, b) {
    (Ok(av), Ok(bv)) => Ok(build(av, bv)),
    (ar, br) => Err(e.concat(errs_of(ar), errs_of(br))),
  }
}

fn combine3[A, B, C, T](a :: Result[A, e.Errors], b :: Result[B, e.Errors], c :: Result[C, e.Errors], build :: (A, B, C) -> T) -> Result[T, e.Errors] {
  match (a, b, c) {
    (Ok(av), Ok(bv), Ok(cv)) => Ok(build(av, bv, cv)),
    (ar, br, cr) => Err(e.flatten([errs_of(ar), errs_of(br), errs_of(cr)])),
  }
}

fn combine4[A, B, C, D, T](a :: Result[A, e.Errors], b :: Result[B, e.Errors], c :: Result[C, e.Errors], d :: Result[D, e.Errors], build :: (A, B, C, D) -> T) -> Result[T, e.Errors] {
  match (a, b, c, d) {
    (Ok(av), Ok(bv), Ok(cv), Ok(dv)) => Ok(build(av, bv, cv, dv)),
    (ar, br, cr, dr) => Err(e.flatten([errs_of(ar), errs_of(br), errs_of(cr), errs_of(dr)])),
  }
}

fn combine5[A, B, C, D, E, T](a :: Result[A, e.Errors], b :: Result[B, e.Errors], c :: Result[C, e.Errors], d :: Result[D, e.Errors], ee :: Result[E, e.Errors], build :: (A, B, C, D, E) -> T) -> Result[T, e.Errors] {
  match (a, b, c, d, ee) {
    (Ok(av), Ok(bv), Ok(cv), Ok(dv), Ok(ev)) => Ok(build(av, bv, cv, dv, ev)),
    (ar, br, cr, dr, er) => Err(e.flatten([errs_of(ar), errs_of(br), errs_of(cr), errs_of(dr), errs_of(er)])),
  }
}

fn combine6[A, B, C, D, E, F, T](a :: Result[A, e.Errors], b :: Result[B, e.Errors], c :: Result[C, e.Errors], d :: Result[D, e.Errors], ee :: Result[E, e.Errors], f :: Result[F, e.Errors], build :: (A, B, C, D, E, F) -> T) -> Result[T, e.Errors] {
  match (a, b, c, d, ee, f) {
    (Ok(av), Ok(bv), Ok(cv), Ok(dv), Ok(ev), Ok(fv)) => Ok(build(av, bv, cv, dv, ev, fv)),
    (ar, br, cr, dr, er, fr) => Err(e.flatten([errs_of(ar), errs_of(br), errs_of(cr), errs_of(dr), errs_of(er), errs_of(fr)])),
  }
}

fn errs_of[T](r :: Result[T, e.Errors]) -> e.Errors {
  match r {
    Ok(_) => [],
    Err(es) => es,
  }
}

fn and_then[A, B](r :: Result[A, e.Errors], k :: (A) -> Result[B, e.Errors]) -> Result[B, e.Errors] {
  match r {
    Ok(a) => k(a),
    Err(es) => Err(es),
  }
}

fn or_else[T](r :: Result[T, e.Errors], handler :: (e.Errors) -> Result[T, e.Errors]) -> Result[T, e.Errors] {
  match r {
    Ok(v) => Ok(v),
    Err(es) => handler(es),
  }
}

fn pure[T](v :: T) -> Result[T, e.Errors] {
  Ok(v)
}

fn fail[T](es :: e.Errors) -> Result[T, e.Errors] {
  Err(es)
}

fn traverse[A, B](xs :: List[A], f :: (A) -> Result[B, e.Errors]) -> Result[List[B], e.Errors] {
  list.fold(xs, traverse_init(), fn (acc :: Result[List[B], e.Errors], x :: A) -> Result[List[B], e.Errors] {
    match (acc, f(x)) {
      (Ok(out), Ok(b)) => Ok(list.concat(out, [b])),
      (Ok(_), Err(es)) => Err(es),
      (Err(es), Ok(_)) => Err(es),
      (Err(es), Err(es2)) => Err(list.concat(es, es2)),
    }
  })
}

fn traverse_init[B]() -> Result[List[B], e.Errors] {
  Ok([])
}

fn with_path[T](prefix :: Str, r :: Result[T, e.Errors]) -> Result[T, e.Errors] {
  match r {
    Ok(v) => Ok(v),
    Err(es) => Err(e.prefix_path(prefix, es)),
  }
}

fn cross_check[T](value :: T, checks :: List[(T) -> Option[e.Errors]]) -> Result[T, e.Errors] {
  let errs := list.fold(checks, [], fn (acc :: e.Errors, check :: (T) -> Option[e.Errors]) -> e.Errors {
    match check(value) {
      None => acc,
      Some(es) => list.concat(acc, es),
    }
  })
  if e.is_ok(errs) {
    Ok(value)
  } else {
    Err(errs)
  }
}

fn require[T](value :: T, predicate :: (T) -> Bool, path :: Str, code :: Str, message :: Str) -> Result[T, e.Errors] {
  if predicate(value) {
    Ok(value)
  } else {
    Err(e.single(path, code, message))
  }
}

