import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.list" as list

import "./error" as e

import "./constraints" as c

import "./field" as f

type Json = JNull | JBool(Bool) | JInt(Int) | JFloat(Float) | JStr(Str) | JList(List[Json]) | JObj(List[(Str, Json)])

type ParseErr = { pos :: Int, message :: Str }

type ParseStep = { pos :: Int, value :: Json }

fn parse(src :: Str) -> Result[Json, ParseErr] {
  match parse_value(src, 0) {
    Err(e1) => Err(e1),
    Ok(step) => {
      let end := skip_ws(src, step.pos)
      if end == str.len(src) {
        Ok(step.value)
      } else {
        Err({ pos: end, message: "trailing characters after JSON value" })
      }
    },
  }
}

fn parse_into_errors(src :: Str) -> Result[Json, e.Errors] {
  match parse(src) {
    Ok(j) => Ok(j),
    Err(p) => Err(e.single("", e.code_parse(), str.concat(p.message, str.concat(" at byte ", int.to_str(p.pos))))),
  }
}

fn parse_value(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  let p1 := skip_ws(src, p)
  if p1 >= str.len(src) {
    Err({ pos: p1, message: "unexpected end of input" })
  } else {
    let c := char_at(src, p1)
    match c {
      "{" => parse_object(src, p1),
      "[" => parse_array(src, p1),
      "\"" => parse_string_value(src, p1),
      "t" => parse_literal(src, p1, "true", JBool(true)),
      "f" => parse_literal(src, p1, "false", JBool(false)),
      "n" => parse_literal(src, p1, "null", JNull),
      _ => parse_number(src, p1),
    }
  }
}

fn skip_ws(src :: Str, p :: Int) -> Int {
  if p >= str.len(src) {
    p
  } else {
    let c := char_at(src, p)
    if c == " " or c == "\t" or c == "\n" or c == "\r" {
      skip_ws(src, p + 1)
    } else {
      p
    }
  }
}

fn parse_literal(src :: Str, p :: Int, word :: Str, value :: Json) -> Result[ParseStep, ParseErr] {
  let n := str.len(word)
  if p + n > str.len(src) {
    Err({ pos: p, message: str.concat("expected `", str.concat(word, "`")) })
  } else {
    let seen := str.slice(src, p, p + n)
    if seen == word {
      Ok({ pos: p + n, value: value })
    } else {
      Err({ pos: p, message: str.concat("expected `", str.concat(word, "`")) })
    }
  }
}

fn parse_number(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  let start := p
  let p1 := if char_at(src, p) == "-" {
    p + 1
  } else {
    p
  }
  let p2 := skip_digits(src, p1)
  if p2 == p1 {
    Err({ pos: p, message: "expected number" })
  } else {
    let p3 := if peek_char(src, p2) == "." {
      skip_digits(src, p2 + 1)
    } else {
      p2
    }
    let p4 := match peek_char(src, p3) {
      "e" => skip_exponent(src, p3 + 1),
      "E" => skip_exponent(src, p3 + 1),
      _ => p3,
    }
    let text := str.slice(src, start, p4)
    if p3 == p2 and p4 == p3 {
      match str.to_int(text) {
        Some(n) => Ok({ pos: p4, value: JInt(n) }),
        None => match str.to_float(text) {
          Some(x) => Ok({ pos: p4, value: JFloat(x) }),
          None => Err({ pos: start, message: "invalid number" }),
        },
      }
    } else {
      match str.to_float(text) {
        Some(x) => Ok({ pos: p4, value: JFloat(x) }),
        None => Err({ pos: start, message: "invalid number" }),
      }
    }
  }
}

fn skip_digits(src :: Str, p :: Int) -> Int {
  if p >= str.len(src) {
    p
  } else {
    let c := char_at(src, p)
    if is_digit(c) {
      skip_digits(src, p + 1)
    } else {
      p
    }
  }
}

fn skip_exponent(src :: Str, p :: Int) -> Int {
  let p1 := match peek_char(src, p) {
    "+" => p + 1,
    "-" => p + 1,
    _ => p,
  }
  skip_digits(src, p1)
}

fn is_digit(c :: Str) -> Bool {
  match c {
    "0" => true,
    "1" => true,
    "2" => true,
    "3" => true,
    "4" => true,
    "5" => true,
    "6" => true,
    "7" => true,
    "8" => true,
    "9" => true,
    _ => false,
  }
}

fn parse_string_value(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  match parse_string_raw(src, p) {
    Err(e1) => Err(e1),
    Ok(r) => Ok({ pos: r.pos, value: JStr(r.text) }),
  }
}

type StringStep = { pos :: Int, text :: Str }

fn parse_string_raw(src :: Str, p :: Int) -> Result[StringStep, ParseErr] {
  if char_at(src, p) != "\"" {
    Err({ pos: p, message: "expected `\"`" })
  } else {
    str_loop(src, p + 1, p + 1, "")
  }
}

fn str_loop(src :: Str, chunk_start :: Int, p :: Int, acc :: Str) -> Result[StringStep, ParseErr] {
  if p >= str.len(src) {
    Err({ pos: p, message: "unterminated string" })
  } else {
    let c := char_at(src, p)
    if c == "\"" {
      let chunk := str.slice(src, chunk_start, p)
      let out := if str.is_empty(acc) {
        chunk
      } else {
        str.concat(acc, chunk)
      }
      Ok({ pos: p + 1, text: out })
    } else {
      if c == "\\" {
        let chunk := str.slice(src, chunk_start, p)
        let acc2 := if str.is_empty(acc) {
          chunk
        } else {
          str.concat(acc, chunk)
        }
        match parse_escape(src, p + 1) {
          Err(e1) => Err(e1),
          Ok(s) => str_loop(src, s.pos, s.pos, str.concat(acc2, s.text)),
        }
      } else {
        str_loop(src, chunk_start, p + 1, acc)
      }
    }
  }
}

fn parse_escape(src :: Str, p :: Int) -> Result[StringStep, ParseErr] {
  if p >= str.len(src) {
    Err({ pos: p, message: "unterminated escape" })
  } else {
    let c := char_at(src, p)
    match c {
      "\"" => Ok({ pos: p + 1, text: "\"" }),
      "\\" => Ok({ pos: p + 1, text: "\\" }),
      "/" => Ok({ pos: p + 1, text: "/" }),
      "n" => Ok({ pos: p + 1, text: "\n" }),
      "r" => Ok({ pos: p + 1, text: "\r" }),
      "t" => Ok({ pos: p + 1, text: "\t" }),
      "b" => Err({ pos: p, message: "`\\b` escape not yet supported" }),
      "f" => Err({ pos: p, message: "`\\f` escape not yet supported" }),
      "u" => Err({ pos: p, message: "`\\uXXXX` escapes not yet supported" }),
      _ => Err({ pos: p, message: str.concat("invalid escape `\\\\", str.concat(c, "`")) }),
    }
  }
}

fn parse_array(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  if char_at(src, p) != "[" {
    Err({ pos: p, message: "expected `[`" })
  } else {
    let p1 := skip_ws(src, p + 1)
    if peek_char(src, p1) == "]" {
      Ok({ pos: p1 + 1, value: JList([]) })
    } else {
      array_loop(src, p1, [])
    }
  }
}

fn array_loop(src :: Str, p :: Int, acc :: List[Json]) -> Result[ParseStep, ParseErr] {
  match parse_value(src, p) {
    Err(e1) => Err(e1),
    Ok(step) => {
      let acc2 := list.cons(step.value, acc)
      let p1 := skip_ws(src, step.pos)
      match peek_char(src, p1) {
        "]" => Ok({ pos: p1 + 1, value: JList(list.reverse(acc2)) }),
        "," => array_loop(src, skip_ws(src, p1 + 1), acc2),
        _ => Err({ pos: p1, message: "expected `,` or `]`" }),
      }
    },
  }
}

fn parse_object(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  if char_at(src, p) != "{" {
    Err({ pos: p, message: "expected `{`" })
  } else {
    let p1 := skip_ws(src, p + 1)
    if peek_char(src, p1) == "}" {
      Ok({ pos: p1 + 1, value: JObj([]) })
    } else {
      object_loop(src, p1, [])
    }
  }
}

fn object_loop(src :: Str, p :: Int, acc :: List[(Str, Json)]) -> Result[ParseStep, ParseErr] {
  match parse_string_raw(src, p) {
    Err(e1) => Err(e1),
    Ok(key) => {
      let p1 := skip_ws(src, key.pos)
      if peek_char(src, p1) != ":" {
        Err({ pos: p1, message: "expected `:` after object key" })
      } else {
        match parse_value(src, p1 + 1) {
          Err(e1) => Err(e1),
          Ok(step) => {
            let acc2 := list.cons((key.text, step.value), acc)
            let p2 := skip_ws(src, step.pos)
            match peek_char(src, p2) {
              "}" => Ok({ pos: p2 + 1, value: JObj(list.reverse(acc2)) }),
              "," => object_loop(src, skip_ws(src, p2 + 1), acc2),
              _ => Err({ pos: p2, message: "expected `,` or `}`" }),
            }
          },
        }
      }
    },
  }
}

fn char_at(src :: Str, p :: Int) -> Str {
  str.slice(src, p, p + 1)
}

fn peek_char(src :: Str, p :: Int) -> Str {
  if p >= str.len(src) {
    ""
  } else {
    char_at(src, p)
  }
}

fn get_field(j :: Json, key :: Str) -> Option[Json] {
  match j {
    JObj(entries) => find_entry(entries, key),
    _ => None,
  }
}

fn find_entry(entries :: List[(Str, Json)], key :: Str) -> Option[Json] {
  list.fold(entries, None, fn (acc :: Option[Json], pair :: (Str, Json)) -> Option[Json] {
    match acc {
      Some(_) => acc,
      None => match pair {
        (k, v) => if k == key {
          Some(v)
        } else {
          None
        },
      },
    }
  })
}

fn as_str(j :: Json) -> Option[Str] {
  match j {
    JStr(s) => Some(s),
    _ => None,
  }
}

fn as_int(j :: Json) -> Option[Int] {
  match j {
    JInt(n) => Some(n),
    _ => None,
  }
}

fn as_float(j :: Json) -> Option[Float] {
  match j {
    JFloat(x) => Some(x),
    JInt(n) => Some(int.to_float(n)),
    _ => None,
  }
}

fn as_bool(j :: Json) -> Option[Bool] {
  match j {
    JBool(b) => Some(b),
    _ => None,
  }
}

fn as_list(j :: Json) -> Option[List[Json]] {
  match j {
    JList(xs) => Some(xs),
    _ => None,
  }
}

fn as_obj(j :: Json) -> Option[List[(Str, Json)]] {
  match j {
    JObj(xs) => Some(xs),
    _ => None,
  }
}

fn is_null(j :: Json) -> Bool {
  match j {
    JNull => true,
    _ => false,
  }
}

fn type_name(j :: Json) -> Str {
  match j {
    JNull => "null",
    JBool(_) => "boolean",
    JInt(_) => "integer",
    JFloat(_) => "number",
    JStr(_) => "string",
    JList(_) => "array",
    JObj(_) => "object",
  }
}

fn j_str(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.StrCheck]) -> Result[Str, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_str(j) {
      Some(s) => f.check_str(p, s, checks),
      None => Err(e.single(p, e.code_type(), str.concat("expected string, got ", type_name(j)))),
    },
  }
}

fn j_int(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.IntCheck]) -> Result[Int, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_int(j) {
      Some(n) => f.check_int(p, n, checks),
      None => Err(e.single(p, e.code_type(), str.concat("expected integer, got ", type_name(j)))),
    },
  }
}

fn j_float(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.FloatCheck]) -> Result[Float, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_float(j) {
      Some(x) => f.check_float(p, x, checks),
      None => Err(e.single(p, e.code_type(), str.concat("expected number, got ", type_name(j)))),
    },
  }
}

fn j_bool(path_prefix :: Str, parent :: Json, field :: Str) -> Result[Bool, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_bool(j) {
      Some(b) => Ok(b),
      None => Err(e.single(p, e.code_type(), str.concat("expected boolean, got ", type_name(j)))),
    },
  }
}

fn j_obj(path_prefix :: Str, parent :: Json, field :: Str) -> Result[Json, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_obj(j) {
      Some(_) => Ok(j),
      None => Err(e.single(p, e.code_type(), str.concat("expected object, got ", type_name(j)))),
    },
  }
}

fn j_list(path_prefix :: Str, parent :: Json, field :: Str) -> Result[List[Json], e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_list(j) {
      Some(xs) => Ok(xs),
      None => Err(e.single(p, e.code_type(), str.concat("expected array, got ", type_name(j)))),
    },
  }
}

fn j_optional_str(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.StrCheck]) -> Result[Option[Str], e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Ok(None),
    Some(j) => if is_null(j) {
      Ok(None)
    } else {
      match as_str(j) {
        Some(s) => match f.check_str(p, s, checks) {
          Ok(v) => Ok(Some(v)),
          Err(es) => Err(es),
        },
        None => Err(e.single(p, e.code_type(), str.concat("expected string or null, got ", type_name(j)))),
      }
    },
  }
}

fn j_optional_int(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.IntCheck]) -> Result[Option[Int], e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Ok(None),
    Some(j) => if is_null(j) {
      Ok(None)
    } else {
      match as_int(j) {
        Some(n) => match f.check_int(p, n, checks) {
          Ok(v) => Ok(Some(v)),
          Err(es) => Err(es),
        },
        None => Err(e.single(p, e.code_type(), str.concat("expected integer or null, got ", type_name(j)))),
      }
    },
  }
}

fn join_path(prefix :: Str, leaf :: Str) -> Str {
  if str.is_empty(prefix) {
    leaf
  } else {
    str.concat(prefix, str.concat(".", leaf))
  }
}

fn get_path(j :: Json, path :: Str) -> Option[Json] {
  let segments := str.split(path, ".")
  list.fold(segments, Some(j), fn (acc :: Option[Json], seg :: Str) -> Option[Json] {
    match acc {
      None => None,
      Some(j_inner) => get_field(j_inner, seg),
    }
  })
}

fn j_str_at(j :: Json, path :: Str, checks :: List[c.StrCheck]) -> Result[Str, e.Errors] {
  match get_path(j, path) {
    None => Err(e.single(path, e.code_missing(), "field is required")),
    Some(v) => match as_str(v) {
      Some(s) => f.check_str(path, s, checks),
      None => Err(e.single(path, e.code_type(), str.concat("expected string, got ", type_name(v)))),
    },
  }
}

fn j_int_at(j :: Json, path :: Str, checks :: List[c.IntCheck]) -> Result[Int, e.Errors] {
  match get_path(j, path) {
    None => Err(e.single(path, e.code_missing(), "field is required")),
    Some(v) => match as_int(v) {
      Some(n) => f.check_int(path, n, checks),
      None => Err(e.single(path, e.code_type(), str.concat("expected integer, got ", type_name(v)))),
    },
  }
}

fn j_optional_str_at(j :: Json, path :: Str, checks :: List[c.StrCheck]) -> Result[Option[Str], e.Errors] {
  match get_path(j, path) {
    None => Ok(None),
    Some(v) => if is_null(v) {
      Ok(None)
    } else {
      match as_str(v) {
        Some(s) => match f.check_str(path, s, checks) {
          Ok(s2) => Ok(Some(s2)),
          Err(es) => Err(es),
        },
        None => Err(e.single(path, e.code_type(), str.concat("expected string or null, got ", type_name(v)))),
      }
    },
  }
}

fn stringify(j :: Json) -> Str {
  match j {
    JNull => "null",
    JBool(b) => if b {
      "true"
    } else {
      "false"
    },
    JInt(n) => int.to_str(n),
    JFloat(x) => float.to_str(x),
    JStr(s) => str.concat("\"", str.concat(escape_str(s), "\"")),
    JList(xs) => {
      let parts := list.map(xs, fn (item :: Json) -> Str {
        stringify(item)
      })
      str.concat("[", str.concat(str.join(parts, ","), "]"))
    },
    JObj(es) => {
      let parts := list.map(es, fn (pair :: (Str, Json)) -> Str {
        match pair {
          (k, v) => str.concat(str.concat("\"", str.concat(escape_str(k), "\":")), stringify(v)),
        }
      })
      str.concat("{", str.concat(str.join(parts, ","), "}"))
    },
  }
}

fn stringify_pretty(j :: Json) -> Str {
  stringify_at(j, 0)
}

fn stringify_at(j :: Json, depth :: Int) -> Str {
  match j {
    JNull => "null",
    JBool(b) => if b {
      "true"
    } else {
      "false"
    },
    JInt(n) => int.to_str(n),
    JFloat(x) => float.to_str(x),
    JStr(s) => str.concat("\"", str.concat(escape_str(s), "\"")),
    JList(xs) => if list.is_empty(xs) {
      "[]"
    } else {
      let inner_indent := indent_str(depth + 1)
      let close_indent := indent_str(depth)
      let parts := list.map(xs, fn (item :: Json) -> Str {
        str.concat(inner_indent, stringify_at(item, depth + 1))
      })
      str.concat("[\n", str.concat(str.join(parts, ",\n"), str.concat("\n", str.concat(close_indent, "]"))))
    },
    JObj(es) => if list.is_empty(es) {
      "{}"
    } else {
      let inner_indent := indent_str(depth + 1)
      let close_indent := indent_str(depth)
      let parts := list.map(es, fn (pair :: (Str, Json)) -> Str {
        match pair {
          (k, v) => str.concat(inner_indent, str.concat("\"", str.concat(escape_str(k), str.concat("\": ", stringify_at(v, depth + 1))))),
        }
      })
      str.concat("{\n", str.concat(str.join(parts, ",\n"), str.concat("\n", str.concat(close_indent, "}"))))
    },
  }
}

fn escape_str(s :: Str) -> Str {
  let chars := str.split(s, "")
  list.fold(chars, "", fn (acc :: Str, c :: Str) -> Str {
    str.concat(acc, escape_char(c))
  })
}

fn escape_char(c :: Str) -> Str {
  match c {
    "\"" => "\\\"",
    "\\" => "\\\\",
    "\n" => "\\n",
    "\r" => "\\r",
    "\t" => "\\t",
    _ => c,
  }
}

fn indent_str(depth :: Int) -> Str {
  if depth <= 0 {
    ""
  } else {
    str.concat("  ", indent_str(depth - 1))
  }
}

