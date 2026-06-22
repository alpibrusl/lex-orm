# lex-schema — constraint datatypes + their evaluators
#
# Constraints are *values*, not closures. Each typed validator
# (`check_str`, `check_int`, ...) takes a `List[XxxCheck]` and runs
# each check in turn. Modeling them as variants keeps every active
# rule readable from the call site (no opaque function bodies), and
# `audit`-friendly: a search like `lex audit --calls StrPattern`
# instantly lists every regex check in a codebase.
#
# Each evaluator returns `Option[Str]`: `None` means "passed",
# `Some(msg)` means "failed with this message". The outer
# `check_xxx` translates these into `error.Error` records.
#
# Effects: none. The whole module is pure builtins.

import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.list" as list

import "std.math" as math

import "std.regex" as regex

# ---- Constraint datatypes -----------------------------------------
type StrCheck = StrNonEmpty | StrMinLen(Int) | StrMaxLen(Int) | StrExactLen(Int) | StrPattern(Str) | StrOneOf(List[Str]) | StrStartsWith(Str) | StrEndsWith(Str) | StrEmail | StrUrl | StrUuid | StrIPv4 | StrIPv6 | StrHostname | StrIsoDate | StrIsoTime | StrBase64 | StrHex | StrPhoneE164 | StrCreditCardLuhn

type IntCheck = IntMin(Int) | IntMax(Int) | IntInRange((Int, Int)) | IntEq(Int) | IntOneOf(List[Int]) | IntPositive | IntNonNegative

type FloatCheck = FloatMin(Float) | FloatMax(Float) | FloatInRange((Float, Float)) | FloatFinite | FloatPositive | FloatNonNegative

type ListCheck = ListMinLen(Int) | ListMaxLen(Int) | ListExactLen(Int) | ListNonEmpty

fn email_pattern() -> Str {
  "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
}

fn url_pattern() -> Str {
  "^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/[^ \\t\\r\\n]*)?$"
}

fn uuid_pattern() -> Str {
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
}

fn ipv4_pattern() -> Str {
  "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
}

fn ipv6_pattern() -> Str {
  "^(([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4})*)?::([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4})*)?|([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4})$"
}

fn hostname_pattern() -> Str {
  "^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
}

fn iso_date_pattern() -> Str {
  "^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$"
}

fn iso_time_pattern() -> Str {
  "^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?$"
}

fn base64_pattern() -> Str {
  "^[A-Za-z0-9+/]+={0,2}$"
}

fn hex_pattern() -> Str {
  "^[0-9a-fA-F]+$"
}

fn phone_e164_pattern() -> Str {
  "^\\+[1-9][0-9]{6,14}$"
}

# ---- Per-constraint evaluators ------------------------------------
fn eval_str(c :: StrCheck, s :: Str) -> Option[Str] {
  match c {
    StrNonEmpty => if str.is_empty(s) {
      Some("must not be empty")
    } else {
      None
    },
    StrMinLen(n) => if str.len(s) < n {
      Some(str.concat("must be at least ", str.concat(int.to_str(n), " characters")))
    } else {
      None
    },
    StrMaxLen(n) => if str.len(s) > n {
      Some(str.concat("must be at most ", str.concat(int.to_str(n), " characters")))
    } else {
      None
    },
    StrExactLen(n) => if str.len(s) == n {
      None
    } else {
      Some(str.concat("must be exactly ", str.concat(int.to_str(n), " characters")))
    },
    StrPattern(p) => if regex.is_match_str(p, s) {
      None
    } else {
      Some(str.concat("does not match pattern ", p))
    },
    StrOneOf(opts) => if list_contains_str(opts, s) {
      None
    } else {
      Some(str.concat("must be one of ", str.join(opts, ", ")))
    },
    StrStartsWith(p) => if str.starts_with(s, p) {
      None
    } else {
      Some(str.concat("must start with ", p))
    },
    StrEndsWith(p) => if str.ends_with(s, p) {
      None
    } else {
      Some(str.concat("must end with ", p))
    },
    StrEmail => if regex.is_match_str(email_pattern(), s) {
      None
    } else {
      Some("not a valid email address")
    },
    StrUrl => if regex.is_match_str(url_pattern(), s) {
      None
    } else {
      Some("not a valid http(s) URL")
    },
    StrUuid => if regex.is_match_str(uuid_pattern(), s) {
      None
    } else {
      Some("not a valid UUID")
    },
    StrIPv4 => if regex.is_match_str(ipv4_pattern(), s) {
      None
    } else {
      Some("not a valid IPv4 address")
    },
    StrIPv6 => if regex.is_match_str(ipv6_pattern(), s) {
      None
    } else {
      Some("not a valid IPv6 address")
    },
    StrHostname => if regex.is_match_str(hostname_pattern(), s) and str.len(s) <= 253 {
      None
    } else {
      Some("not a valid hostname")
    },
    StrIsoDate => if regex.is_match_str(iso_date_pattern(), s) {
      None
    } else {
      Some("not a valid ISO 8601 date (YYYY-MM-DD)")
    },
    StrIsoTime => if regex.is_match_str(iso_time_pattern(), s) {
      None
    } else {
      Some("not a valid ISO 8601 time (HH:MM:SS)")
    },
    StrBase64 => if regex.is_match_str(base64_pattern(), s) and str.len(s) % 4 == 0 {
      None
    } else {
      Some("not a valid base64 string")
    },
    StrHex => if regex.is_match_str(hex_pattern(), s) {
      None
    } else {
      Some("not a valid hex string")
    },
    StrPhoneE164 => if regex.is_match_str(phone_e164_pattern(), s) {
      None
    } else {
      Some("not a valid E.164 phone number")
    },
    StrCreditCardLuhn => if luhn_valid(s) {
      None
    } else {
      Some("not a valid credit card number (Luhn check failed)")
    },
  }
}

fn luhn_valid(s :: Str) -> Bool {
  let chars := str.split(s, "")
  let digits := list.fold(chars, [], fn (acc :: List[Int], c :: Str) -> List[Int] {
    match str.to_int(c) {
      Some(d) => list.concat(acc, [d]),
      None => acc,
    }
  })
  let n := list.len(digits)
  if n < 13 or n > 19 {
    false
  } else {
    let sum := list.fold(list.enumerate(list.reverse(digits)), 0, fn (acc :: Int, p :: (Int, Int)) -> Int {
      let i := match p {
        (a, _) => a,
      }
      let d := match p {
        (_, b) => b,
      }
      let v := if i % 2 == 1 {
        let dd := d * 2
        if dd > 9 {
          dd - 9
        } else {
          dd
        }
      } else {
        d
      }
      acc + v
    })
    sum % 10 == 0
  }
}

fn eval_int(c :: IntCheck, n :: Int) -> Option[Str] {
  match c {
    IntMin(lo) => if n < lo {
      Some(str.concat("must be >= ", int.to_str(lo)))
    } else {
      None
    },
    IntMax(hi) => if n > hi {
      Some(str.concat("must be <= ", int.to_str(hi)))
    } else {
      None
    },
    IntInRange(lo, hi) => if n < lo {
      Some(str.concat("must be >= ", int.to_str(lo)))
    } else {
      if n > hi {
        Some(str.concat("must be <= ", int.to_str(hi)))
      } else {
        None
      }
    },
    IntEq(target) => if n == target {
      None
    } else {
      Some(str.concat("must equal ", int.to_str(target)))
    },
    IntOneOf(opts) => if list_contains_int(opts, n) {
      None
    } else {
      Some(str.concat("must be one of ", str.join(list.map(opts, fn (x :: Int) -> Str {
        int.to_str(x)
      }), ", ")))
    },
    IntPositive => if n > 0 {
      None
    } else {
      Some("must be > 0")
    },
    IntNonNegative => if n >= 0 {
      None
    } else {
      Some("must be >= 0")
    },
  }
}

fn eval_float(c :: FloatCheck, x :: Float) -> Option[Str] {
  match c {
    FloatMin(lo) => if x < lo {
      Some(str.concat("must be >= ", float.to_str(lo)))
    } else {
      None
    },
    FloatMax(hi) => if x > hi {
      Some(str.concat("must be <= ", float.to_str(hi)))
    } else {
      None
    },
    FloatInRange(lo, hi) => if x < lo {
      Some(str.concat("must be >= ", float.to_str(lo)))
    } else {
      if x > hi {
        Some(str.concat("must be <= ", float.to_str(hi)))
      } else {
        None
      }
    },
    FloatFinite => if x == x and math.abs(x) < math.pow(10.0, 309.0) {
      None
    } else {
      Some("must be a finite number")
    },
    FloatPositive => if x > 0.0 {
      None
    } else {
      Some("must be > 0")
    },
    FloatNonNegative => if x >= 0.0 {
      None
    } else {
      Some("must be >= 0")
    },
  }
}

fn eval_list(c :: ListCheck, n :: Int) -> Option[Str] {
  match c {
    ListMinLen(m) => if n < m {
      Some(str.concat("must have at least ", str.concat(int.to_str(m), " items")))
    } else {
      None
    },
    ListMaxLen(m) => if n > m {
      Some(str.concat("must have at most ", str.concat(int.to_str(m), " items")))
    } else {
      None
    },
    ListExactLen(m) => if n == m {
      None
    } else {
      Some(str.concat("must have exactly ", str.concat(int.to_str(m), " items")))
    },
    ListNonEmpty => if n > 0 {
      None
    } else {
      Some("must not be empty")
    },
  }
}

# ---- Internal helpers ---------------------------------------------
fn list_contains_str(xs :: List[Str], needle :: Str) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or x == needle
  })
}

fn list_contains_int(xs :: List[Int], needle :: Int) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, x :: Int) -> Bool {
    acc or x == needle
  })
}

