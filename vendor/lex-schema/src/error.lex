# lex-schema — error types
#
# A validation library models failures as a flat list of structured
# `Error` records so a single call to `validate` can report *every*
# problem at once (the way pydantic's `ValidationError.errors()` does
# in Python), not just the first failure surfaced by short-circuiting
# Result combinators.
#
# Each error names where it came from (`path`) and what went wrong
# (`code` for machine-readable dispatch, `message` for humans). The
# path uses dotted segments — `"address.zip"`, `"items[3].name"` —
# so callers can pinpoint the offending leaf without rebuilding the
# walk.
#
# Combinators in `combine.lex` accumulate by concatenation;
# producers in `field.lex` always return a singleton or empty
# list. The module has no effects.

import "std.str" as str
import "std.int" as int
import "std.list" as list

type Error = {
  path :: Str,
  code :: Str,
  message :: Str,
}

# `Errors` is a transparent alias for `List[Error]`. Restored in
# v0.8.2 once lex-lang#345 closed the polymorphic-closure-param
# alias-unfold gap — fold reducers annotated `(Errors, Errors)
# -> Errors` now unify with `list.fold`'s expected signature.
type Errors = List[Error]

# A handful of canonical codes the library emits. Application code is
# free to add its own; these are documented so dispatchers know what
# to expect from out-of-the-box validators.
fn code_missing()    -> Str { "missing" }      # required field absent
fn code_type()       -> Str { "type" }         # JSON value not the expected shape
fn code_min_len()    -> Str { "min_len" }
fn code_max_len()    -> Str { "max_len" }
fn code_pattern()    -> Str { "pattern" }
fn code_one_of()     -> Str { "one_of" }
fn code_min()        -> Str { "min" }
fn code_max()        -> Str { "max" }
fn code_finite()     -> Str { "finite" }
fn code_email()      -> Str { "email" }
fn code_url()        -> Str { "url" }
fn code_custom()     -> Str { "custom" }
fn code_parse()      -> Str { "parse" }        # outer-shell JSON/TOML/YAML parse failure

# Construct one error.
fn error(path :: Str, code :: Str, message :: Str) -> Error {
  { path: path, code: code, message: message }
}

# Singleton error list.
fn single(path :: Str, code :: Str, message :: Str) -> Errors {
  [{ path: path, code: code, message: message }]
}

# Empty list of errors — used by combinators as the "success" carrier.
fn none() -> Errors { [] }

# Are we error-free?
fn is_ok(errs :: Errors) -> Bool { list.is_empty(errs) }

# Concatenate two error lists. Useful when applicative combinators
# want to merge sibling-field failures without losing any of them.
fn concat(a :: Errors, b :: Errors) -> Errors { list.concat(a, b) }

# Concatenate a list of error lists into one.
fn flatten(parts :: List[Errors]) -> Errors {
  list.fold(parts, [], fn (acc :: Errors, e :: Errors) -> Errors {
    list.concat(acc, e)
  })
}

# Prefix every error's path with `prefix` + ".". This is how nested
# validators report `address.zip` from a sub-validator that on its
# own would only know the field name `zip`.
#
# An empty prefix is the identity (so leaf validators can return
# `prefix=""` paths and parents add structure as they ascend).
fn prefix_path(prefix :: Str, errs :: Errors) -> Errors {
  if str.is_empty(prefix) {
    errs
  } else {
    list.map(errs, fn (e :: Error) -> Error {
      let joined := if str.is_empty(e.path) {
        prefix
      } else {
        str.concat(str.concat(prefix, "."), e.path)
      }
      { path: joined, code: e.code, message: e.message }
    })
  }
}

# Same idea for list-indexed paths: `items[3]`.
fn prefix_index(name :: Str, idx :: Int, errs :: Errors) -> Errors {
  let head := str.concat(name, str.concat("[", str.concat(int.to_str(idx), "]")))
  list.map(errs, fn (e :: Error) -> Error {
    let joined := if str.is_empty(e.path) {
      head
    } else {
      str.concat(str.concat(head, "."), e.path)
    }
    { path: joined, code: e.code, message: e.message }
  })
}

# One-line human-readable rendering, used by `format`. Stable enough
# that tests can assert on it.
fn render_one(e :: Error) -> Str {
  let head := if str.is_empty(e.path) { "<root>" } else { e.path }
  str.concat(head, str.concat(": ", str.concat(e.message, str.concat(" [", str.concat(e.code, "]")))))
}

# Join all errors as "path: message [code]" lines separated by "\n".
fn format(errs :: Errors) -> Str {
  let lines := list.map(errs, fn (e :: Error) -> Str { render_one(e) })
  str.join(lines, "\n")
}
