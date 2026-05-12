import "std.str"  as str
import "std.int"  as int
import "std.list" as list

import "./error"       as e
import "./constraints" as c
import "./json_value"  as jv
import "./schema"      as s

type Transform =
    Rename({ from :: Str, to :: Str })
  | DropField(Str)
  | AddField({ name :: Str, default :: jv.Json })
  | SetField({ name :: Str, value :: jv.Json })
  | CoerceStrToInt(Str)
  | CoerceStrToFloat(Str)
  | CoerceStrToBool(Str)
  | NestInto({ name :: Str, fields :: List[Str] })
  | UnnestFrom(Str)

fn apply(j :: jv.Json, ts :: List[Transform]) -> jv.Json {
  list.fold(ts, j, fn (acc :: jv.Json, t :: Transform) -> jv.Json {
    apply_one(acc, t)
  })
}

fn apply_one(j :: jv.Json, t :: Transform) -> jv.Json {
  match jv.as_obj(j) {
    None       => j,
    Some(pairs) => match t {
      Rename(r)             => JObj(rename_field(pairs, r.from, r.to)),
      DropField(name)       => JObj(drop_field(pairs, name)),
      AddField(a)           => JObj(add_field_if_absent(pairs, a.name, a.default)),
      SetField(s2)          => JObj(set_field(pairs, s2.name, s2.value)),
      CoerceStrToInt(name)  => JObj(coerce_field(pairs, name, coerce_int)),
      CoerceStrToFloat(name)=> JObj(coerce_field(pairs, name, coerce_float)),
      CoerceStrToBool(name) => JObj(coerce_field(pairs, name, coerce_bool)),
      NestInto(n)           => JObj(nest_into(pairs, n.name, n.fields)),
      UnnestFrom(name)      => JObj(unnest_from(pairs, name)),
    },
  }
}

fn rename_field(
  pairs :: List[(Str, jv.Json)],
  from :: Str,
  to :: Str
) -> List[(Str, jv.Json)] {
  list.map(pairs, fn (p :: (Str, jv.Json)) -> (Str, jv.Json) {
    match p { (k, v) => if k == from { (to, v) } else { (k, v) } }
  })
}

fn drop_field(
  pairs :: List[(Str, jv.Json)],
  name :: Str
) -> List[(Str, jv.Json)] {
  list.fold(pairs, [], fn (acc :: List[(Str, jv.Json)], p :: (Str, jv.Json)) -> List[(Str, jv.Json)] {
    match p { (k, _v) => if k == name { acc } else { list.concat(acc, [p]) } }
  })
}

fn add_field_if_absent(
  pairs :: List[(Str, jv.Json)],
  name :: Str,
  default :: jv.Json
) -> List[(Str, jv.Json)] {
  let exists := list.fold(pairs, false, fn (acc :: Bool, p :: (Str, jv.Json)) -> Bool {
    acc or match p { (k, _v) => k == name }
  })
  if exists { pairs } else { list.concat(pairs, [(name, default)]) }
}

fn set_field(
  pairs :: List[(Str, jv.Json)],
  name :: Str,
  value :: jv.Json
) -> List[(Str, jv.Json)] {
  let replaced_pairs := list.map(pairs, fn (p :: (Str, jv.Json)) -> (Str, jv.Json) {
    match p { (k, v) => if k == name { (k, value) } else { (k, v) } }
  })
  add_field_if_absent(replaced_pairs, name, value)
}

fn coerce_field(
  pairs :: List[(Str, jv.Json)],
  name :: Str,
  coerce :: (Str) -> Option[jv.Json]
) -> List[(Str, jv.Json)] {
  list.fold(pairs, [], fn (acc :: List[(Str, jv.Json)], p :: (Str, jv.Json)) -> List[(Str, jv.Json)] {
    match p { (k, v) =>
      if k == name {
        match jv.as_str(v) {
          None    => list.concat(acc, [p]),
          Some(s) => match coerce(s) {
            Some(new_v) => list.concat(acc, [(k, new_v)]),
            None        => acc,
          },
        }
      } else { list.concat(acc, [p]) }
    }
  })
}

fn coerce_int(s :: Str) -> Option[jv.Json] {
  match str.to_int(str.trim(s)) {
    Some(n) => Some(JInt(n)),
    None    => None,
  }
}

fn coerce_float(s :: Str) -> Option[jv.Json] {
  match str.to_float(str.trim(s)) {
    Some(x) => Some(JFloat(x)),
    None    => None,
  }
}

fn coerce_bool(s :: Str) -> Option[jv.Json] {
  match str.to_lower(str.trim(s)) {
    "true"  => Some(JBool(true)),
    "false" => Some(JBool(false)),
    "1"     => Some(JBool(true)),
    "0"     => Some(JBool(false)),
    _       => None,
  }
}

fn nest_into(
  pairs :: List[(Str, jv.Json)],
  target :: Str,
  field_names :: List[Str]
) -> List[(Str, jv.Json)] {
  let gathered := list.fold(pairs, [],
    fn (acc :: List[(Str, jv.Json)], p :: (Str, jv.Json)) -> List[(Str, jv.Json)] {
      match p { (k, v) =>
        if list_contains_str(field_names, k) {
          list.concat(acc, [(k, v)])
        } else { acc }
      }
    })
  let remaining := list.fold(pairs, [],
    fn (acc :: List[(Str, jv.Json)], p :: (Str, jv.Json)) -> List[(Str, jv.Json)] {
      match p { (k, _v) =>
        if list_contains_str(field_names, k) { acc }
        else { list.concat(acc, [p]) }
      }
    })
  list.concat(remaining, [(target, JObj(gathered))])
}

fn unnest_from(
  pairs :: List[(Str, jv.Json)],
  source :: Str
) -> List[(Str, jv.Json)] {
  list.fold(pairs, [], fn (acc :: List[(Str, jv.Json)], p :: (Str, jv.Json)) -> List[(Str, jv.Json)] {
    match p { (k, v) =>
      if k == source {
        match jv.as_obj(v) {
          Some(inner) => list.concat(acc, inner),
          None        => list.concat(acc, [p]),
        }
      } else { list.concat(acc, [p]) }
    }
  })
}

fn list_contains_str(xs :: List[Str], needle :: Str) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or (x == needle)
  })
}

type Incompat = {
  field :: Str,
  reason :: Str,
}

fn is_backward_compatible(
  old :: s.ModelSchema,
  new :: s.ModelSchema
) -> Result[Unit, List[Incompat]] {
  let issues := compare_schemas(old, new)
  if list.is_empty(issues) { Ok(()) } else { Err(issues) }
}

fn compare_schemas(
  old :: s.ModelSchema,
  new :: s.ModelSchema
) -> List[Incompat] {
  let new_required := list.fold(new.fields, [],
    fn (acc :: List[Incompat], nf :: s.Field) -> List[Incompat] {
      if nf.required and (not field_present(old.fields, nf.name)) {
        list.concat(acc, [{
          field: nf.name,
          reason: "new required field not present in old schema",
        }])
      } else { acc }
    })
  let field_issues := list.fold(new.fields, [],
    fn (acc :: List[Incompat], nf :: s.Field) -> List[Incompat] {
      match find_field(old.fields, nf.name) {
        None     => acc,
        Some(of) => list.concat(acc, compare_field(of, nf)),
      }
    })
  list.concat(new_required, field_issues)
}

fn field_present(fields :: List[s.Field], name :: Str) -> Bool {
  list.fold(fields, false, fn (acc :: Bool, f :: s.Field) -> Bool {
    acc or (f.name == name)
  })
}

fn find_field(fields :: List[s.Field], name :: Str) -> Option[s.Field] {
  list.fold(fields, None, fn (acc :: Option[s.Field], f :: s.Field) -> Option[s.Field] {
    match acc {
      Some(_) => acc,
      None    => if f.name == name { Some(f) } else { None },
    }
  })
}

fn compare_field(old_f :: s.Field, new_f :: s.Field) -> List[Incompat] {
  let kind_change := if kind_label(old_f.kind) == kind_label(new_f.kind) {
    []
  } else {
    [{ field: new_f.name,
       reason: str.concat("type changed from ",
                          str.concat(kind_label(old_f.kind),
                                     str.concat(" to ", kind_label(new_f.kind)))) }]
  }
  let req_change := if old_f.required == new_f.required { [] }
    else {
      if new_f.required and (not old_f.required) {
        [{ field: new_f.name, reason: "field became required" }]
      } else { [] }
    }
  list.concat(kind_change, req_change)
}

fn kind_label(k :: s.FieldKind) -> Str {
  match k {
    KStr(_)    => "string",
    KInt(_)    => "integer",
    KFloat(_)  => "number",
    KBool      => "boolean",
    KArray(_,_) => "array",
    KObject(_) => "object",
  }
}

fn format_incompats(issues :: List[Incompat]) -> Str {
  let lines := list.map(issues, fn (i :: Incompat) -> Str {
    str.concat(i.field, str.concat(": ", i.reason))
  })
  str.join(lines, "\n")
}
