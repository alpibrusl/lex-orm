import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.list" as list

import "./error" as e

import "./constraints" as c

import "./field" as f

import "./combine" as cm

import "./json_value" as jv

type FieldKind = KStr(List[c.StrCheck]) | KInt(List[c.IntCheck]) | KFloat(List[c.FloatCheck]) | KBool | KArray((FieldKind, List[c.ListCheck])) | KObject(ModelSchema)

type Field = { name :: Str, required :: Bool, description :: Str, kind :: FieldKind }

type ModelSchema = { title :: Str, description :: Str, fields :: List[Field] }

fn required_str(name :: Str, checks :: List[c.StrCheck]) -> Field {
  { name: name, required: true, description: "", kind: KStr(checks) }
}

fn required_int(name :: Str, checks :: List[c.IntCheck]) -> Field {
  { name: name, required: true, description: "", kind: KInt(checks) }
}

fn required_float(name :: Str, checks :: List[c.FloatCheck]) -> Field {
  { name: name, required: true, description: "", kind: KFloat(checks) }
}

fn required_bool(name :: Str) -> Field {
  { name: name, required: true, description: "", kind: KBool }
}

fn required_array(name :: Str, element :: FieldKind, checks :: List[c.ListCheck]) -> Field {
  { name: name, required: true, description: "", kind: KArray(element, checks) }
}

fn required_object(name :: Str, sub :: ModelSchema) -> Field {
  { name: name, required: true, description: "", kind: KObject(sub) }
}

fn optional(field :: Field) -> Field {
  { name: field.name, required: false, description: field.description, kind: field.kind }
}

fn with_desc(field :: Field, desc :: Str) -> Field {
  { name: field.name, required: field.required, description: desc, kind: field.kind }
}

fn validate(schema :: ModelSchema, j :: jv.Json) -> Result[jv.Json, e.Errors] {
  validate_at("", schema, j)
}

fn validate_at(path_prefix :: Str, schema :: ModelSchema, j :: jv.Json) -> Result[jv.Json, e.Errors] {
  let walked := list.fold(schema.fields, walk_init(), fn (acc :: (List[(Str, jv.Json)], e.Errors), field :: Field) -> (List[(Str, jv.Json)], e.Errors) {
    let entries := match acc {
      (es, _errs) => es,
    }
    let errs := match acc {
      (_es, errs) => errs,
    }
    match validate_field(path_prefix, field, j) {
      FieldOk(value) => (list.concat(entries, [(field.name, value)]), errs),
      FieldSkip => (entries, errs),
      FieldErr(more) => (entries, list.concat(errs, more)),
    }
  })
  let entries := match walked {
    (es, _) => es,
  }
  let errs := match walked {
    (_, e2) => e2,
  }
  if e.is_ok(errs) {
    Ok(JObj(entries))
  } else {
    Err(errs)
  }
}

fn walk_init() -> (List[(Str, jv.Json)], e.Errors) {
  ([], [])
}

type FieldOutcome = FieldOk(jv.Json) | FieldSkip | FieldErr(e.Errors)

fn validate_field(path_prefix :: Str, field :: Field, parent :: jv.Json) -> FieldOutcome {
  let path := join_path(path_prefix, field.name)
  match jv.get_field(parent, field.name) {
    None => if field.required {
      FieldErr(e.single(path, e.code_missing(), "field is required"))
    } else {
      FieldSkip
    },
    Some(value) => validate_kind(path, field.kind, value),
  }
}

fn validate_kind(path :: Str, kind :: FieldKind, v :: jv.Json) -> FieldOutcome {
  match kind {
    KStr(checks) => match jv.as_str(v) {
      Some(s) => match f.check_str(path, s, checks) {
        Ok(s2) => FieldOk(JStr(s2)),
        Err(es) => FieldErr(es),
      },
      None => FieldErr(e.single(path, e.code_type(), str.concat("expected string, got ", jv.type_name(v)))),
    },
    KInt(checks) => match jv.as_int(v) {
      Some(n) => match f.check_int(path, n, checks) {
        Ok(n2) => FieldOk(JInt(n2)),
        Err(es) => FieldErr(es),
      },
      None => FieldErr(e.single(path, e.code_type(), str.concat("expected integer, got ", jv.type_name(v)))),
    },
    KFloat(checks) => match jv.as_float(v) {
      Some(x) => match f.check_float(path, x, checks) {
        Ok(x2) => FieldOk(JFloat(x2)),
        Err(es) => FieldErr(es),
      },
      None => FieldErr(e.single(path, e.code_type(), str.concat("expected number, got ", jv.type_name(v)))),
    },
    KBool => match jv.as_bool(v) {
      Some(b) => FieldOk(JBool(b)),
      None => FieldErr(e.single(path, e.code_type(), str.concat("expected boolean, got ", jv.type_name(v)))),
    },
    KArray(elem_kind, shape_checks) => match jv.as_list(v) {
      None => FieldErr(e.single(path, e.code_type(), str.concat("expected array, got ", jv.type_name(v)))),
      Some(xs) => validate_array(path, elem_kind, xs, shape_checks),
    },
    KObject(sub) => match jv.as_obj(v) {
      None => FieldErr(e.single(path, e.code_type(), str.concat("expected object, got ", jv.type_name(v)))),
      Some(_) => match validate_at(path, sub, v) {
        Ok(j) => FieldOk(j),
        Err(es) => FieldErr(es),
      },
    },
  }
}

fn validate_array(path :: Str, elem :: FieldKind, xs :: List[jv.Json], shape :: List[c.ListCheck]) -> FieldOutcome {
  let shape_errs := list.fold(shape, [], fn (acc :: e.Errors, chk :: c.ListCheck) -> e.Errors {
    match c.eval_list(chk, list.len(xs)) {
      None => acc,
      Some(msg) => list.concat(acc, e.single(path, e.code_min_len(), msg)),
    }
  })
  let walked := list.fold(list.enumerate(xs), array_walk_init(), fn (acc :: (List[jv.Json], e.Errors), p :: (Int, jv.Json)) -> (List[jv.Json], e.Errors) {
    let items := match acc {
      (it, _) => it,
    }
    let errs := match acc {
      (_, er) => er,
    }
    let i := match p {
      (a, _) => a,
    }
    let item_v := match p {
      (_, b) => b,
    }
    let item_path := elem_path(path, i)
    match validate_kind(item_path, elem, item_v) {
      FieldOk(v2) => (list.concat(items, [v2]), errs),
      FieldSkip => (items, errs),
      FieldErr(es) => (items, list.concat(errs, es)),
    }
  })
  let items := match walked {
    (it, _) => it,
  }
  let item_errs := match walked {
    (_, er) => er,
  }
  let all := list.concat(shape_errs, item_errs)
  if e.is_ok(all) {
    FieldOk(JList(items))
  } else {
    FieldErr(all)
  }
}

fn array_walk_init() -> (List[jv.Json], e.Errors) {
  ([], [])
}

fn to_json_schema(schema :: ModelSchema) -> jv.Json {
  let entries := list.concat([("$schema", JStr("https://json-schema.org/draft/2020-12/schema")), ("title", JStr(schema.title))], schema_body(schema))
  let with_desc := if str.is_empty(schema.description) {
    entries
  } else {
    list.concat(entries, [("description", JStr(schema.description))])
  }
  JObj(with_desc)
}

fn to_openapi_schema(schema :: ModelSchema) -> jv.Json {
  let entries := list.concat([("title", JStr(schema.title))], schema_body(schema))
  let with_desc := if str.is_empty(schema.description) {
    entries
  } else {
    list.concat(entries, [("description", JStr(schema.description))])
  }
  JObj(with_desc)
}

fn schema_body(schema :: ModelSchema) -> List[(Str, jv.Json)] {
  let props := list.map(schema.fields, fn (field :: Field) -> (Str, jv.Json) {
    (field.name, field_to_schema(field))
  })
  let required_names := list.fold(schema.fields, [], fn (acc :: List[jv.Json], field :: Field) -> List[jv.Json] {
    if field.required {
      list.concat(acc, [JStr(field.name)])
    } else {
      acc
    }
  })
  [("type", JStr("object")), ("properties", JObj(props)), ("required", JList(required_names))]
}

fn field_to_schema(field :: Field) -> jv.Json {
  let body := kind_to_schema(field.kind)
  if str.is_empty(field.description) {
    body
  } else {
    match body {
      JObj(entries) => JObj(list.concat(entries, [("description", JStr(field.description))])),
      other => other,
    }
  }
}

fn kind_to_schema(kind :: FieldKind) -> jv.Json {
  match kind {
    KStr(checks) => JObj(list.concat([("type", JStr("string"))], str_checks_to_schema(checks))),
    KInt(checks) => JObj(list.concat([("type", JStr("integer"))], int_checks_to_schema(checks))),
    KFloat(checks) => JObj(list.concat([("type", JStr("number"))], float_checks_to_schema(checks))),
    KBool => JObj([("type", JStr("boolean"))]),
    KArray(elem, shape) => JObj(list.concat(list.concat([("type", JStr("array"))], [("items", kind_to_schema(elem))]), list_checks_to_schema(shape))),
    KObject(sub) => to_openapi_schema(sub),
  }
}

fn str_checks_to_schema(checks :: List[c.StrCheck]) -> List[(Str, jv.Json)] {
  list.fold(checks, [], fn (acc :: List[(Str, jv.Json)], chk :: c.StrCheck) -> List[(Str, jv.Json)] {
    match chk {
      StrMinLen(n) => list.concat(acc, [("minLength", JInt(n))]),
      StrMaxLen(n) => list.concat(acc, [("maxLength", JInt(n))]),
      StrExactLen(n) => list.concat(acc, [("minLength", JInt(n)), ("maxLength", JInt(n))]),
      StrNonEmpty => list.concat(acc, [("minLength", JInt(1))]),
      StrPattern(p) => list.concat(acc, [("pattern", JStr(p))]),
      StrEmail => list.concat(acc, [("format", JStr("email"))]),
      StrUrl => list.concat(acc, [("format", JStr("uri"))]),
      StrUuid => list.concat(acc, [("format", JStr("uuid"))]),
      StrOneOf(opts) => list.concat(acc, [("enum", JList(list.map(opts, fn (s :: Str) -> jv.Json {
        JStr(s)
      })))]),
      StrStartsWith(p) => list.concat(acc, [("pattern", JStr(str.concat("^", regex_escape(p))))]),
      StrEndsWith(p) => list.concat(acc, [("pattern", JStr(str.concat(regex_escape(p), "$")))]),
      StrIPv4 => list.concat(acc, [("format", JStr("ipv4"))]),
      StrIPv6 => list.concat(acc, [("format", JStr("ipv6"))]),
      StrHostname => list.concat(acc, [("format", JStr("hostname"))]),
      StrIsoDate => list.concat(acc, [("format", JStr("date"))]),
      StrIsoTime => list.concat(acc, [("format", JStr("time"))]),
      StrBase64 => list.concat(acc, [("pattern", JStr("^[A-Za-z0-9+/]+={0,2}$"))]),
      StrHex => list.concat(acc, [("pattern", JStr("^[0-9a-fA-F]+$"))]),
      StrPhoneE164 => list.concat(acc, [("pattern", JStr("^\\+[1-9][0-9]{6,14}$"))]),
      StrCreditCardLuhn => list.concat(acc, [("pattern", JStr("^[0-9]{13,19}$"))]),
    }
  })
}

fn int_checks_to_schema(checks :: List[c.IntCheck]) -> List[(Str, jv.Json)] {
  list.fold(checks, [], fn (acc :: List[(Str, jv.Json)], chk :: c.IntCheck) -> List[(Str, jv.Json)] {
    match chk {
      IntMin(n) => list.concat(acc, [("minimum", JInt(n))]),
      IntMax(n) => list.concat(acc, [("maximum", JInt(n))]),
      IntInRange(lo, hi) => list.concat(acc, [("minimum", JInt(lo)), ("maximum", JInt(hi))]),
      IntEq(n) => list.concat(acc, [("const", JInt(n))]),
      IntOneOf(opts) => list.concat(acc, [("enum", JList(list.map(opts, fn (n :: Int) -> jv.Json {
        JInt(n)
      })))]),
      IntPositive => list.concat(acc, [("exclusiveMinimum", JInt(0))]),
      IntNonNegative => list.concat(acc, [("minimum", JInt(0))]),
    }
  })
}

fn float_checks_to_schema(checks :: List[c.FloatCheck]) -> List[(Str, jv.Json)] {
  list.fold(checks, [], fn (acc :: List[(Str, jv.Json)], chk :: c.FloatCheck) -> List[(Str, jv.Json)] {
    match chk {
      FloatMin(x) => list.concat(acc, [("minimum", JFloat(x))]),
      FloatMax(x) => list.concat(acc, [("maximum", JFloat(x))]),
      FloatInRange(lo, hi) => list.concat(acc, [("minimum", JFloat(lo)), ("maximum", JFloat(hi))]),
      FloatFinite => acc,
      FloatPositive => list.concat(acc, [("exclusiveMinimum", JFloat(0.0))]),
      FloatNonNegative => list.concat(acc, [("minimum", JFloat(0.0))]),
    }
  })
}

fn list_checks_to_schema(checks :: List[c.ListCheck]) -> List[(Str, jv.Json)] {
  list.fold(checks, [], fn (acc :: List[(Str, jv.Json)], chk :: c.ListCheck) -> List[(Str, jv.Json)] {
    match chk {
      ListMinLen(n) => list.concat(acc, [("minItems", JInt(n))]),
      ListMaxLen(n) => list.concat(acc, [("maxItems", JInt(n))]),
      ListExactLen(n) => list.concat(acc, [("minItems", JInt(n)), ("maxItems", JInt(n))]),
      ListNonEmpty => list.concat(acc, [("minItems", JInt(1))]),
    }
  })
}

fn regex_escape(s :: Str) -> Str {
  let chars := str.split(s, "")
  list.fold(chars, "", fn (acc :: Str, c :: Str) -> Str {
    str.concat(acc, escape_meta(c))
  })
}

fn escape_meta(c :: Str) -> Str {
  match c {
    "." => "\\.",
    "*" => "\\*",
    "+" => "\\+",
    "?" => "\\?",
    "(" => "\\(",
    ")" => "\\)",
    "[" => "\\[",
    "]" => "\\]",
    "{" => "\\{",
    "}" => "\\}",
    "|" => "\\|",
    "^" => "\\^",
    "$" => "\\$",
    "\\" => "\\\\",
    _ => c,
  }
}

fn join_path(prefix :: Str, leaf :: Str) -> Str {
  if str.is_empty(prefix) {
    leaf
  } else {
    str.concat(prefix, str.concat(".", leaf))
  }
}

fn elem_path(prefix :: Str, idx :: Int) -> Str {
  str.concat(prefix, str.concat("[", str.concat(int.to_str(idx), "]")))
}

fn to_mermaid_er(schema :: ModelSchema) -> Str {
  let entities := str.join(emit_entities(schema), "\n")
  let edges := str.join(emit_edges(schema), "\n")
  let body := if str.is_empty(edges) {
    entities
  } else {
    str.concat(entities, str.concat("\n", edges))
  }
  str.concat("erDiagram\n", body)
}

fn emit_entities(schema :: ModelSchema) -> List[Str] {
  let here := emit_entity(schema)
  let nested := list.fold(schema.fields, [], fn (acc :: List[Str], field :: Field) -> List[Str] {
    list.concat(acc, emit_kind_entities(field.kind))
  })
  list.concat([here], nested)
}

fn emit_kind_entities(kind :: FieldKind) -> List[Str] {
  match kind {
    KObject(sub) => emit_entities(sub),
    KArray(elem, _) => emit_kind_entities(elem),
    _ => [],
  }
}

fn emit_entity(schema :: ModelSchema) -> Str {
  let cols := list.fold(schema.fields, [], fn (acc :: List[Str], field :: Field) -> List[Str] {
    list.concat(acc, [emit_column(field)])
  })
  str.concat("    ", str.concat(schema.title, str.concat(" {\n", str.concat(str.join(cols, "\n"), "\n    }"))))
}

fn emit_column(field :: Field) -> Str {
  let ty := mermaid_type(field.kind)
  let opt_marker := if field.required {
    ""
  } else {
    " \"optional\""
  }
  str.concat("        ", str.concat(ty, str.concat(" ", str.concat(field.name, opt_marker))))
}

fn mermaid_type(kind :: FieldKind) -> Str {
  match kind {
    KStr(_) => "string",
    KInt(_) => "int",
    KFloat(_) => "float",
    KBool => "bool",
    KArray(_, _) => "array",
    KObject(sub) => sub.title,
  }
}

fn emit_edges(schema :: ModelSchema) -> List[Str] {
  list.fold(schema.fields, [], fn (acc :: List[Str], field :: Field) -> List[Str] {
    list.concat(acc, edge_for(schema.title, field))
  })
}

fn edge_for(parent :: Str, field :: Field) -> List[Str] {
  match field.kind {
    KObject(sub) => {
      let here := str.concat("    ", str.concat(parent, str.concat(" ||--|| ", str.concat(sub.title, str.concat(" : ", field.name)))))
      list.concat([here], emit_edges(sub))
    },
    KArray(KObject(sub), _) => {
      let here := str.concat("    ", str.concat(parent, str.concat(" ||--o{ ", str.concat(sub.title, str.concat(" : ", field.name)))))
      list.concat([here], emit_edges(sub))
    },
    _ => [],
  }
}

