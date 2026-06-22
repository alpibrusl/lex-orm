# lex-schema — field validators
#
# A `check_xxx` function takes an *already-typed* value (Str, Int,
# Float, Bool, or List), a `path` label for nested error reporting,
# and a list of constraints. It returns `Result[T, Errors]`:
#
#   - `Ok(value)`         — every constraint passed
#   - `Err([...errors])`  — one entry per failing constraint
#
# All constraints in the list run unconditionally so callers see the
# full set of failures for that field on a single pass, never just
# the first.
#
# Effects: none. Pure functions over pure inputs.

import "std.list" as list

import "std.int" as int

import "std.str" as str

import "./constraints" as c

import "./error" as e

fn str_code(chk :: c.StrCheck) -> Str {
  match chk {
    StrNonEmpty => e.code_min_len(),
    StrMinLen(_) => e.code_min_len(),
    StrMaxLen(_) => e.code_max_len(),
    StrExactLen(_) => e.code_min_len(),
    StrPattern(_) => e.code_pattern(),
    StrOneOf(_) => e.code_one_of(),
    StrStartsWith(_) => e.code_pattern(),
    StrEndsWith(_) => e.code_pattern(),
    StrEmail => e.code_email(),
    StrUrl => e.code_url(),
    StrUuid => e.code_pattern(),
    StrIPv4 => e.code_pattern(),
    StrIPv6 => e.code_pattern(),
    StrHostname => e.code_pattern(),
    StrIsoDate => e.code_pattern(),
    StrIsoTime => e.code_pattern(),
    StrBase64 => e.code_pattern(),
    StrHex => e.code_pattern(),
    StrPhoneE164 => e.code_pattern(),
    StrCreditCardLuhn => e.code_pattern(),
  }
}

fn int_code(chk :: c.IntCheck) -> Str {
  match chk {
    IntMin(_) => e.code_min(),
    IntMax(_) => e.code_max(),
    IntInRange(_, _) => e.code_min(),
    IntEq(_) => e.code_one_of(),
    IntOneOf(_) => e.code_one_of(),
    IntPositive => e.code_min(),
    IntNonNegative => e.code_min(),
  }
}

fn float_code(chk :: c.FloatCheck) -> Str {
  match chk {
    FloatMin(_) => e.code_min(),
    FloatMax(_) => e.code_max(),
    FloatInRange(_, _) => e.code_min(),
    FloatFinite => e.code_finite(),
    FloatPositive => e.code_min(),
    FloatNonNegative => e.code_min(),
  }
}

fn list_code(chk :: c.ListCheck) -> Str {
  match chk {
    ListMinLen(_) => e.code_min_len(),
    ListMaxLen(_) => e.code_max_len(),
    ListExactLen(_) => e.code_min_len(),
    ListNonEmpty => e.code_min_len(),
  }
}

fn run_str_checks(path :: Str, s :: Str, checks :: List[c.StrCheck]) -> e.Errors {
  list.fold(checks, [], fn (acc :: e.Errors, chk :: c.StrCheck) -> e.Errors {
    match c.eval_str(chk, s) {
      None => acc,
      Some(msg) => list.concat(acc, e.single(path, str_code(chk), msg)),
    }
  })
}

fn run_int_checks(path :: Str, n :: Int, checks :: List[c.IntCheck]) -> e.Errors {
  list.fold(checks, [], fn (acc :: e.Errors, chk :: c.IntCheck) -> e.Errors {
    match c.eval_int(chk, n) {
      None => acc,
      Some(msg) => list.concat(acc, e.single(path, int_code(chk), msg)),
    }
  })
}

fn run_float_checks(path :: Str, x :: Float, checks :: List[c.FloatCheck]) -> e.Errors {
  list.fold(checks, [], fn (acc :: e.Errors, chk :: c.FloatCheck) -> e.Errors {
    match c.eval_float(chk, x) {
      None => acc,
      Some(msg) => list.concat(acc, e.single(path, float_code(chk), msg)),
    }
  })
}

fn run_list_checks(path :: Str, n :: Int, checks :: List[c.ListCheck]) -> e.Errors {
  list.fold(checks, [], fn (acc :: e.Errors, chk :: c.ListCheck) -> e.Errors {
    match c.eval_list(chk, n) {
      None => acc,
      Some(msg) => list.concat(acc, e.single(path, list_code(chk), msg)),
    }
  })
}

fn check_str(path :: Str, s :: Str, checks :: List[c.StrCheck]) -> Result[Str, e.Errors] {
  let errs := run_str_checks(path, s, checks)
  if e.is_ok(errs) {
    Ok(s)
  } else {
    Err(errs)
  }
}

fn check_int(path :: Str, n :: Int, checks :: List[c.IntCheck]) -> Result[Int, e.Errors] {
  let errs := run_int_checks(path, n, checks)
  if e.is_ok(errs) {
    Ok(n)
  } else {
    Err(errs)
  }
}

fn check_float(path :: Str, x :: Float, checks :: List[c.FloatCheck]) -> Result[Float, e.Errors] {
  let errs := run_float_checks(path, x, checks)
  if e.is_ok(errs) {
    Ok(x)
  } else {
    Err(errs)
  }
}

fn check_bool(path :: Str, b :: Bool) -> Result[Bool, e.Errors] {
  let __lex_discard_1 := path
  Ok(b)
}

fn check_optional_str(path :: Str, opt :: Option[Str], checks :: List[c.StrCheck]) -> Result[Option[Str], e.Errors] {
  match opt {
    None => Ok(None),
    Some(s) => match check_str(path, s, checks) {
      Ok(v) => Ok(Some(v)),
      Err(es) => Err(es),
    },
  }
}

fn check_optional_int(path :: Str, opt :: Option[Int], checks :: List[c.IntCheck]) -> Result[Option[Int], e.Errors] {
  match opt {
    None => Ok(None),
    Some(n) => match check_int(path, n, checks) {
      Ok(v) => Ok(Some(v)),
      Err(es) => Err(es),
    },
  }
}

fn check_optional_float(path :: Str, opt :: Option[Float], checks :: List[c.FloatCheck]) -> Result[Option[Float], e.Errors] {
  match opt {
    None => Ok(None),
    Some(x) => match check_float(path, x, checks) {
      Ok(v) => Ok(Some(v)),
      Err(es) => Err(es),
    },
  }
}

fn check_optional_bool(path :: Str, opt :: Option[Bool]) -> Result[Option[Bool], e.Errors] {
  let __lex_discard_2 := path
  Ok(opt)
}

fn with_default[T](opt :: Option[T], default :: T) -> T {
  match opt {
    Some(v) => v,
    None => default,
  }
}

fn with_default_lazy[T](opt :: Option[T], thunk :: () -> T) -> T {
  match opt {
    Some(v) => v,
    None => thunk(),
  }
}

fn check_list_shape[T](path :: Str, xs :: List[T], checks :: List[c.ListCheck]) -> Result[List[T], e.Errors] {
  let errs := run_list_checks(path, list.len(xs), checks)
  if e.is_ok(errs) {
    Ok(xs)
  } else {
    Err(errs)
  }
}

fn check_list_of[T](name :: Str, xs :: List[T], shape_checks :: List[c.ListCheck], per_item :: (Str, T) -> Result[T, e.Errors]) -> Result[List[T], e.Errors] {
  let shape_errs := run_list_checks(name, list.len(xs), shape_checks)
  let item_errs := list.fold(list.enumerate(xs), [], fn (acc :: e.Errors, p :: (Int, T)) -> e.Errors {
    let i := fst_pair(p)
    let v := snd_pair(p)
    match per_item(item_path(name, i), v) {
      Ok(_) => acc,
      Err(es) => list.concat(acc, es),
    }
  })
  let all := list.concat(shape_errs, item_errs)
  if e.is_ok(all) {
    Ok(xs)
  } else {
    Err(all)
  }
}

fn validate[T](path :: Str, value :: T, code :: Str, predicate :: (T) -> Option[Str]) -> Result[T, e.Errors] {
  match predicate(value) {
    None => Ok(value),
    Some(msg) => Err(e.single(path, code, msg)),
  }
}

fn fst_pair[T](p :: (Int, T)) -> Int {
  match p {
    (a, _) => a,
  }
}

fn snd_pair[T](p :: (Int, T)) -> T {
  match p {
    (_, b) => b,
  }
}

fn item_path(name :: Str, idx :: Int) -> Str {
  str.concat(str.concat(name, "["), str.concat(int.to_str(idx), "]"))
}

