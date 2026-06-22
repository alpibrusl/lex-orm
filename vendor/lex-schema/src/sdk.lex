import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.list" as list

import "./constraints" as c

import "./schema" as s

fn to_typescript(schema :: s.ModelSchema) -> Str {
  let nested := collect_nested(schema)
  let head := ts_interface(schema)
  let rest := list.map(nested, fn (m :: s.ModelSchema) -> Str {
    ts_interface(m)
  })
  str.join(list.concat([head], rest), "\n\n")
}

fn ts_interface(schema :: s.ModelSchema) -> Str {
  let header := if str.is_empty(schema.description) {
    str.concat("export interface ", str.concat(schema.title, " {"))
  } else {
    str.concat("/** ", str.concat(schema.description, str.concat(" */\nexport interface ", str.concat(schema.title, " {"))))
  }
  let body := list.fold(schema.fields, "", fn (acc :: Str, field :: s.Field) -> Str {
    str.concat(acc, str.concat("\n", ts_field_line(field)))
  })
  str.concat(header, str.concat(body, "\n}"))
}

fn ts_field_line(field :: s.Field) -> Str {
  let doc := if str.is_empty(field.description) {
    ""
  } else {
    str.concat("  /** ", str.concat(field.description, " */\n"))
  }
  let opt := if field.required {
    ""
  } else {
    "?"
  }
  let ty := ts_type(field.kind)
  let constraint_hint := ts_constraint_hint(field.kind)
  let main := str.concat("  ", str.concat(field.name, str.concat(opt, str.concat(": ", str.concat(ty, ";")))))
  if str.is_empty(constraint_hint) {
    str.concat(doc, main)
  } else {
    str.concat(doc, str.concat(main, str.concat("  // ", constraint_hint)))
  }
}

fn ts_type(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(checks) => match ts_enum_str(checks) {
      Some(union) => union,
      None => "string",
    },
    KInt(checks) => match ts_enum_int(checks) {
      Some(union) => union,
      None => "number",
    },
    KFloat(_) => "number",
    KBool => "boolean",
    KArray(elem, _) => str.concat(ts_type(elem), "[]"),
    KObject(sub) => sub.title,
  }
}

fn ts_enum_str(checks :: List[c.StrCheck]) -> Option[Str] {
  let opts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
    match chk {
      StrOneOf(opts) => if list.is_empty(acc) {
        opts
      } else {
        acc
      },
      _ => acc,
    }
  })
  if list.is_empty(opts) {
    None
  } else {
    let quoted := list.map(opts, fn (s :: Str) -> Str {
      str.concat("\"", str.concat(s, "\""))
    })
    Some(str.join(quoted, " | "))
  }
}

fn ts_enum_int(checks :: List[c.IntCheck]) -> Option[Str] {
  let opts := list.fold(checks, [], fn (acc :: List[Int], chk :: c.IntCheck) -> List[Int] {
    match chk {
      IntOneOf(opts) => if list.is_empty(acc) {
        opts
      } else {
        acc
      },
      _ => acc,
    }
  })
  if list.is_empty(opts) {
    None
  } else {
    Some(str.join(list.map(opts, fn (n :: Int) -> Str {
      int.to_str(n)
    }), " | "))
  }
}

fn ts_constraint_hint(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(checks) => str_hint(checks),
    KInt(checks) => int_hint(checks),
    KFloat(checks) => float_hint(checks),
    _ => "",
  }
}

fn str_hint(checks :: List[c.StrCheck]) -> Str {
  let parts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
    match str_hint_one(chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
  str.join(parts, ", ")
}

fn str_hint_one(chk :: c.StrCheck) -> Option[Str] {
  match chk {
    StrMinLen(n) => Some(str.concat("minLength: ", int.to_str(n))),
    StrMaxLen(n) => Some(str.concat("maxLength: ", int.to_str(n))),
    StrPattern(p) => Some(str.concat("pattern: ", p)),
    StrEmail => Some("format: email"),
    StrUrl => Some("format: uri"),
    StrUuid => Some("format: uuid"),
    StrIPv4 => Some("format: ipv4"),
    StrIPv6 => Some("format: ipv6"),
    StrHostname => Some("format: hostname"),
    StrIsoDate => Some("format: date"),
    StrIsoTime => Some("format: time"),
    StrBase64 => Some("format: base64"),
    StrHex => Some("format: hex"),
    StrPhoneE164 => Some("format: phone-e164"),
    StrCreditCardLuhn => Some("format: credit-card-luhn"),
    StrNonEmpty => Some("minLength: 1"),
    _ => None,
  }
}

fn int_hint(checks :: List[c.IntCheck]) -> Str {
  let parts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.IntCheck) -> List[Str] {
    match int_hint_one(chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
  str.join(parts, ", ")
}

fn int_hint_one(chk :: c.IntCheck) -> Option[Str] {
  match chk {
    IntMin(n) => Some(str.concat("min: ", int.to_str(n))),
    IntMax(n) => Some(str.concat("max: ", int.to_str(n))),
    IntInRange(a, b) => Some(str.concat("min: ", str.concat(int.to_str(a), str.concat(", max: ", int.to_str(b))))),
    IntPositive => Some("> 0"),
    IntNonNegative => Some(">= 0"),
    _ => None,
  }
}

fn float_hint(checks :: List[c.FloatCheck]) -> Str {
  let parts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.FloatCheck) -> List[Str] {
    match float_hint_one(chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
  str.join(parts, ", ")
}

fn float_hint_one(chk :: c.FloatCheck) -> Option[Str] {
  match chk {
    FloatMin(x) => Some(str.concat("min: ", float.to_str(x))),
    FloatMax(x) => Some(str.concat("max: ", float.to_str(x))),
    FloatInRange(a, b) => Some(str.concat("min: ", str.concat(float.to_str(a), str.concat(", max: ", float.to_str(b))))),
    FloatPositive => Some("> 0"),
    FloatNonNegative => Some(">= 0"),
    _ => None,
  }
}

fn collect_nested(schema :: s.ModelSchema) -> List[s.ModelSchema] {
  list.fold(schema.fields, [], fn (acc :: List[s.ModelSchema], field :: s.Field) -> List[s.ModelSchema] {
    list.concat(acc, kind_nested(field.kind))
  })
}

fn kind_nested(kind :: s.FieldKind) -> List[s.ModelSchema] {
  match kind {
    KObject(sub) => list.concat([sub], collect_nested(sub)),
    KArray(elem, _) => kind_nested(elem),
    _ => [],
  }
}

fn to_python(schema :: s.ModelSchema) -> Str {
  let nested := collect_nested(schema)
  let head := py_class(schema)
  let rest := list.map(nested, fn (m :: s.ModelSchema) -> Str {
    py_class(m)
  })
  let blocks := list.concat(rest, [head])
  let body := str.join(blocks, "\n\n\n")
  str.concat(py_header(), str.concat("\n\n", body))
}

fn py_header() -> Str {
  "from pydantic import BaseModel, Field\nfrom typing  import Optional, List, Literal"
}

fn py_class(schema :: s.ModelSchema) -> Str {
  let docstr := if str.is_empty(schema.description) {
    ""
  } else {
    str.concat("    \"\"\"", str.concat(schema.description, "\"\"\"\n"))
  }
  let fields := list.fold(schema.fields, "", fn (acc :: Str, field :: s.Field) -> Str {
    str.concat(acc, str.concat("\n", py_field_line(field)))
  })
  str.concat("class ", str.concat(schema.title, str.concat("(BaseModel):\n", str.concat(docstr, if str.is_empty(fields) {
    "    pass"
  } else {
    fields
  }))))
}

fn py_field_line(field :: s.Field) -> Str {
  let ty := py_type(field.kind)
  let ty_wrapped := if field.required {
    ty
  } else {
    str.concat("Optional[", str.concat(ty, "]"))
  }
  let args := py_field_args(field)
  str.concat("    ", str.concat(field.name, str.concat(": ", str.concat(ty_wrapped, if str.is_empty(args) {
    if field.required {
      ""
    } else {
      " = None"
    }
  } else {
    str.concat(" = Field(", str.concat(args, ")"))
  }))))
}

fn py_type(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(checks) => match py_literal_str(checks) {
      Some(lit) => lit,
      None => "str",
    },
    KInt(checks) => match py_literal_int(checks) {
      Some(lit) => lit,
      None => "int",
    },
    KFloat(_) => "float",
    KBool => "bool",
    KArray(elem, _) => str.concat("List[", str.concat(py_type(elem), "]")),
    KObject(sub) => sub.title,
  }
}

fn py_literal_str(checks :: List[c.StrCheck]) -> Option[Str] {
  let opts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
    match chk {
      StrOneOf(opts) => if list.is_empty(acc) {
        opts
      } else {
        acc
      },
      _ => acc,
    }
  })
  if list.is_empty(opts) {
    None
  } else {
    let quoted := list.map(opts, fn (s :: Str) -> Str {
      str.concat("\"", str.concat(s, "\""))
    })
    Some(str.concat("Literal[", str.concat(str.join(quoted, ", "), "]")))
  }
}

fn py_literal_int(checks :: List[c.IntCheck]) -> Option[Str] {
  let opts := list.fold(checks, [], fn (acc :: List[Int], chk :: c.IntCheck) -> List[Int] {
    match chk {
      IntOneOf(opts) => if list.is_empty(acc) {
        opts
      } else {
        acc
      },
      _ => acc,
    }
  })
  if list.is_empty(opts) {
    None
  } else {
    Some(str.concat("Literal[", str.concat(str.join(list.map(opts, fn (n :: Int) -> Str {
      int.to_str(n)
    }), ", "), "]")))
  }
}

fn py_field_args(field :: s.Field) -> Str {
  let kind_args := match field.kind {
    KStr(checks) => py_str_args(checks),
    KInt(checks) => py_int_args(checks),
    KFloat(checks) => py_float_args(checks),
    KArray(_, shape) => py_list_args(shape),
    _ => "",
  }
  let desc_arg := if str.is_empty(field.description) {
    ""
  } else {
    str.concat("description=\"", str.concat(field.description, "\""))
  }
  let parts := list.fold([kind_args, desc_arg], [], fn (acc :: List[Str], part :: Str) -> List[Str] {
    if str.is_empty(part) {
      acc
    } else {
      list.concat(acc, [part])
    }
  })
  str.join(parts, ", ")
}

fn py_str_args(checks :: List[c.StrCheck]) -> Str {
  let parts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
    match py_str_arg_one(chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
  str.join(parts, ", ")
}

fn py_str_arg_one(chk :: c.StrCheck) -> Option[Str] {
  match chk {
    StrMinLen(n) => Some(str.concat("min_length=", int.to_str(n))),
    StrMaxLen(n) => Some(str.concat("max_length=", int.to_str(n))),
    StrPattern(p) => Some(str.concat("pattern=r\"", str.concat(p, "\""))),
    StrNonEmpty => Some("min_length=1"),
    _ => None,
  }
}

fn py_int_args(checks :: List[c.IntCheck]) -> Str {
  let parts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.IntCheck) -> List[Str] {
    match py_int_arg_one(chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
  str.join(parts, ", ")
}

fn py_int_arg_one(chk :: c.IntCheck) -> Option[Str] {
  match chk {
    IntMin(n) => Some(str.concat("ge=", int.to_str(n))),
    IntMax(n) => Some(str.concat("le=", int.to_str(n))),
    IntInRange(a, b) => Some(str.concat("ge=", str.concat(int.to_str(a), str.concat(", le=", int.to_str(b))))),
    IntPositive => Some("gt=0"),
    IntNonNegative => Some("ge=0"),
    _ => None,
  }
}

fn py_float_args(checks :: List[c.FloatCheck]) -> Str {
  let parts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.FloatCheck) -> List[Str] {
    match py_float_arg_one(chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
  str.join(parts, ", ")
}

fn py_float_arg_one(chk :: c.FloatCheck) -> Option[Str] {
  match chk {
    FloatMin(x) => Some(str.concat("ge=", float.to_str(x))),
    FloatMax(x) => Some(str.concat("le=", float.to_str(x))),
    FloatInRange(a, b) => Some(str.concat("ge=", str.concat(float.to_str(a), str.concat(", le=", float.to_str(b))))),
    FloatPositive => Some("gt=0.0"),
    FloatNonNegative => Some("ge=0.0"),
    _ => None,
  }
}

fn py_list_args(checks :: List[c.ListCheck]) -> Str {
  let parts := list.fold(checks, [], fn (acc :: List[Str], chk :: c.ListCheck) -> List[Str] {
    match py_list_arg_one(chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
  str.join(parts, ", ")
}

fn py_list_arg_one(chk :: c.ListCheck) -> Option[Str] {
  match chk {
    ListMinLen(n) => Some(str.concat("min_length=", int.to_str(n))),
    ListMaxLen(n) => Some(str.concat("max_length=", int.to_str(n))),
    ListNonEmpty => Some("min_length=1"),
    _ => None,
  }
}

type SqlDialect = DialectPostgres | DialectSqlite

fn to_sql_ddl(schema :: s.ModelSchema, dialect :: SqlDialect) -> Str {
  let nested := collect_nested(schema)
  let children_first := list.reverse(nested)
  let tables := list.concat(children_first, [schema])
  let blocks := list.map(tables, fn (m :: s.ModelSchema) -> Str {
    sql_table(m, dialect)
  })
  str.concat(sql_header(dialect), str.concat("\n\n", str.join(blocks, "\n\n")))
}

fn sql_header(dialect :: SqlDialect) -> Str {
  match dialect {
    DialectPostgres => "-- lex-schema -> SQL DDL (Postgres)",
    DialectSqlite => "-- lex-schema -> SQL DDL (SQLite)",
  }
}

fn sql_table(schema :: s.ModelSchema, dialect :: SqlDialect) -> Str {
  let tname := sql_quote(sql_ident(schema.title))
  let doc := if str.is_empty(schema.description) {
    ""
  } else {
    str.concat("-- ", str.concat(schema.description, "\n"))
  }
  let cols := list.map(schema.fields, fn (f :: s.Field) -> Str {
    sql_column(f, dialect)
  })
  let body := str.join(cols, ",\n")
  str.concat(doc, str.concat("CREATE TABLE ", str.concat(tname, str.concat(" (\n", str.concat(body, "\n);")))))
}

fn sql_quote(name :: Str) -> Str {
  str.concat("\"", str.concat(name, "\""))
}

fn sql_column(f :: s.Field, dialect :: SqlDialect) -> Str {
  let col_name := match f.kind {
    KObject(_) => str.concat(f.name, "_id"),
    _ => f.name,
  }
  let ty := sql_type(f, dialect)
  let pk := if f.name == "id" {
    " PRIMARY KEY"
  } else {
    ""
  }
  let nn := if f.required {
    " NOT NULL"
  } else {
    ""
  }
  let fk := match f.kind {
    KObject(sub) => str.concat(" REFERENCES ", str.concat(sql_quote(sql_ident(sub.title)), "(id)")),
    _ => "",
  }
  let checks := sql_constraints(col_name, f.kind, dialect)
  str.concat("  ", str.concat(col_name, str.concat(" ", str.concat(ty, str.concat(pk, str.concat(nn, str.concat(fk, checks)))))))
}

fn sql_type(f :: s.Field, dialect :: SqlDialect) -> Str {
  match f.kind {
    KStr(checks) => sql_str_type(checks, dialect),
    KInt(_) => match dialect {
      DialectPostgres => "BIGINT",
      DialectSqlite => "INTEGER",
    },
    KFloat(_) => match dialect {
      DialectPostgres => "DOUBLE PRECISION",
      DialectSqlite => "REAL",
    },
    KBool => match dialect {
      DialectPostgres => "BOOLEAN",
      DialectSqlite => "INTEGER",
    },
    KArray(_, _) => match dialect {
      DialectPostgres => "JSONB",
      DialectSqlite => "TEXT",
    },
    KObject(_) => match dialect {
      DialectPostgres => "BIGINT",
      DialectSqlite => "INTEGER",
    },
  }
}

fn sql_str_type(checks :: List[c.StrCheck], dialect :: SqlDialect) -> Str {
  match max_len_of(checks) {
    Some(n) => match dialect {
      DialectPostgres => str.concat("VARCHAR(", str.concat(int.to_str(n), ")")),
      DialectSqlite => "TEXT",
    },
    None => "TEXT",
  }
}

fn max_len_of(checks :: List[c.StrCheck]) -> Option[Int] {
  list.fold(checks, None, fn (acc :: Option[Int], chk :: c.StrCheck) -> Option[Int] {
    match acc {
      Some(_) => acc,
      None => str_check_max_len(chk),
    }
  })
}

fn str_check_max_len(chk :: c.StrCheck) -> Option[Int] {
  match chk {
    StrMaxLen(n) => Some(n),
    StrExactLen(n) => Some(n),
    _ => None,
  }
}

fn sql_constraints(col :: Str, kind :: s.FieldKind, dialect :: SqlDialect) -> Str {
  let parts := match kind {
    KStr(checks) => str_checks_sql(col, checks, dialect),
    KInt(checks) => int_checks_sql(col, checks),
    KFloat(checks) => float_checks_sql(col, checks),
    _ => [],
  }
  if list.is_empty(parts) {
    ""
  } else {
    str.concat(" ", str.join(parts, " "))
  }
}

fn ck(expr :: Str) -> Str {
  str.concat("CHECK (", str.concat(expr, ")"))
}

fn str_checks_sql(col :: Str, checks :: List[c.StrCheck], dialect :: SqlDialect) -> List[Str] {
  list.fold(checks, [], fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
    match str_check_sql(col, chk, dialect) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
}

fn str_check_sql(col :: Str, chk :: c.StrCheck, dialect :: SqlDialect) -> Option[Str] {
  match chk {
    StrNonEmpty => Some(ck(str.concat(col, " <> ''"))),
    StrMinLen(n) => Some(ck(len_expr(col, ">=", n))),
    StrMaxLen(_) => None,
    StrExactLen(_) => None,
    StrPattern(p) => regex_check(col, p, dialect),
    StrOneOf(opts) => Some(ck(str.concat(col, str.concat(" IN ", in_list_str(opts))))),
    StrStartsWith(_) => None,
    StrEndsWith(_) => None,
    StrEmail => regex_check(col, c.email_pattern(), dialect),
    StrUrl => regex_check(col, c.url_pattern(), dialect),
    StrUuid => regex_check(col, c.uuid_pattern(), dialect),
    StrIPv4 => regex_check(col, c.ipv4_pattern(), dialect),
    StrIPv6 => regex_check(col, c.ipv6_pattern(), dialect),
    StrHostname => regex_check(col, c.hostname_pattern(), dialect),
    StrIsoDate => regex_check(col, c.iso_date_pattern(), dialect),
    StrIsoTime => regex_check(col, c.iso_time_pattern(), dialect),
    StrBase64 => regex_check(col, c.base64_pattern(), dialect),
    StrHex => regex_check(col, c.hex_pattern(), dialect),
    StrPhoneE164 => regex_check(col, c.phone_e164_pattern(), dialect),
    StrCreditCardLuhn => None,
  }
}

fn len_expr(col :: Str, op :: Str, n :: Int) -> Str {
  str.concat("length(", str.concat(col, str.concat(") ", str.concat(op, str.concat(" ", int.to_str(n))))))
}

fn regex_check(col :: Str, pat :: Str, dialect :: SqlDialect) -> Option[Str] {
  match dialect {
    DialectPostgres => Some(ck(str.concat(col, str.concat(" ~ ", sql_str_lit(pat))))),
    DialectSqlite => None,
  }
}

fn sql_str_lit(s :: Str) -> Str {
  let escaped := str.replace(s, "'", "''")
  str.concat("'", str.concat(escaped, "'"))
}

fn in_list_str(opts :: List[Str]) -> Str {
  let quoted := list.map(opts, fn (o :: Str) -> Str {
    sql_str_lit(o)
  })
  str.concat("(", str.concat(str.join(quoted, ", "), ")"))
}

fn in_list_int(opts :: List[Int]) -> Str {
  let q := list.map(opts, fn (n :: Int) -> Str {
    int.to_str(n)
  })
  str.concat("(", str.concat(str.join(q, ", "), ")"))
}

fn int_checks_sql(col :: Str, checks :: List[c.IntCheck]) -> List[Str] {
  list.fold(checks, [], fn (acc :: List[Str], chk :: c.IntCheck) -> List[Str] {
    match int_check_sql(col, chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
}

fn int_check_sql(col :: Str, chk :: c.IntCheck) -> Option[Str] {
  match chk {
    IntMin(n) => Some(ck(int_op_expr(col, ">=", n))),
    IntMax(n) => Some(ck(int_op_expr(col, "<=", n))),
    IntInRange(a, b) => Some(ck(str.concat(col, str.concat(" BETWEEN ", str.concat(int.to_str(a), str.concat(" AND ", int.to_str(b))))))),
    IntEq(n) => Some(ck(int_op_expr(col, "=", n))),
    IntOneOf(opts) => Some(ck(str.concat(col, str.concat(" IN ", in_list_int(opts))))),
    IntPositive => Some(ck(int_op_expr(col, ">", 0))),
    IntNonNegative => Some(ck(int_op_expr(col, ">=", 0))),
  }
}

fn int_op_expr(col :: Str, op :: Str, n :: Int) -> Str {
  str.concat(col, str.concat(" ", str.concat(op, str.concat(" ", int.to_str(n)))))
}

fn float_checks_sql(col :: Str, checks :: List[c.FloatCheck]) -> List[Str] {
  list.fold(checks, [], fn (acc :: List[Str], chk :: c.FloatCheck) -> List[Str] {
    match float_check_sql(col, chk) {
      Some(s) => list.concat(acc, [s]),
      None => acc,
    }
  })
}

fn float_check_sql(col :: Str, chk :: c.FloatCheck) -> Option[Str] {
  match chk {
    FloatMin(x) => Some(ck(float_op_expr(col, ">=", x))),
    FloatMax(x) => Some(ck(float_op_expr(col, "<=", x))),
    FloatInRange(a, b) => Some(ck(str.concat(col, str.concat(" BETWEEN ", str.concat(float.to_str(a), str.concat(" AND ", float.to_str(b))))))),
    FloatFinite => None,
    FloatPositive => Some(ck(float_op_expr(col, ">", 0.0))),
    FloatNonNegative => Some(ck(float_op_expr(col, ">=", 0.0))),
  }
}

fn float_op_expr(col :: Str, op :: Str, x :: Float) -> Str {
  str.concat(col, str.concat(" ", str.concat(op, str.concat(" ", float.to_str(x)))))
}

fn sql_ident(name :: Str) -> Str {
  let segs := list.fold(str.split(name, "_"), [], fn (acc :: List[Str], seg :: Str) -> List[Str] {
    list.concat(acc, str.split(seg, "-"))
  })
  let split := list.fold(segs, [], fn (acc :: List[Str], seg :: Str) -> List[Str] {
    list.concat(acc, snake_split(seg))
  })
  str.to_lower(str.join(split, "_"))
}

fn snake_split(s :: Str) -> List[Str] {
  if str.is_empty(s) {
    []
  } else {
    snake_split_at(s, 1, 0, [])
  }
}

fn snake_split_at(s :: Str, i :: Int, start :: Int, acc :: List[Str]) -> List[Str] {
  let n := str.len(s)
  if i >= n {
    list.concat(acc, [str.slice(s, start, n)])
  } else {
    let prev := str.slice(s, i - 1, i)
    let curr := str.slice(s, i, i + 1)
    if is_lower(prev) and is_upper(curr) {
      snake_split_at(s, i + 1, i, list.concat(acc, [str.slice(s, start, i)]))
    } else {
      snake_split_at(s, i + 1, start, acc)
    }
  }
}

fn is_upper(c :: Str) -> Bool {
  str.to_upper(c) == c and str.to_lower(c) != c
}

fn is_lower(c :: Str) -> Bool {
  str.to_lower(c) == c and str.to_upper(c) != c
}

fn to_zod(schema :: s.ModelSchema) -> Str {
  let nested := collect_nested(schema)
  let head := zod_schema(schema)
  let rest := list.map(nested, fn (m :: s.ModelSchema) -> Str {
    zod_schema(m)
  })
  let body := str.join(list.concat(rest, [head]), "\n\n")
  str.concat(zod_header(), str.concat("\n\n", body))
}

fn zod_header() -> Str {
  "import { z } from \"zod\";"
}

fn zod_schema(schema :: s.ModelSchema) -> Str {
  let doc := if str.is_empty(schema.description) {
    ""
  } else {
    str.concat("/** ", str.concat(schema.description, " */\n"))
  }
  let fields := list.map(schema.fields, fn (field :: s.Field) -> Str {
    zod_field_line(field)
  })
  let body := str.join(fields, ",\n")
  str.concat(doc, str.concat("export const ", str.concat(schema.title, str.concat(" = z.object({\n", str.concat(body, "\n});")))))
}

fn zod_field_line(field :: s.Field) -> Str {
  let ty := zod_type(field.kind)
  let ty_opt := if field.required {
    ty
  } else {
    str.concat(ty, ".optional()")
  }
  str.concat("  ", str.concat(field.name, str.concat(": ", ty_opt)))
}

fn zod_type(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(checks) => zod_str(checks),
    KInt(checks) => zod_int(checks),
    KFloat(checks) => zod_float(checks),
    KBool => "z.boolean()",
    KArray(elem, shape) => str.concat(str.concat("z.array(", zod_type(elem)), str.concat(")", zod_list_chain(shape))),
    KObject(sub) => sub.title,
  }
}

fn zod_str(checks :: List[c.StrCheck]) -> Str {
  list.fold(checks, "z.string()", fn (acc :: Str, chk :: c.StrCheck) -> Str {
    str.concat(acc, zod_str_chain(chk))
  })
}

fn zod_str_chain(chk :: c.StrCheck) -> Str {
  match chk {
    StrMinLen(n) => str.concat(".min(", str.concat(int.to_str(n), ")")),
    StrMaxLen(n) => str.concat(".max(", str.concat(int.to_str(n), ")")),
    StrExactLen(n) => str.concat(".length(", str.concat(int.to_str(n), ")")),
    StrNonEmpty => ".min(1)",
    StrPattern(p) => str.concat(".regex(/", str.concat(p, "/)")),
    StrEmail => ".email()",
    StrUrl => ".url()",
    StrUuid => ".uuid()",
    StrIPv4 => ".ip({ version: \"v4\" })",
    StrIPv6 => ".ip({ version: \"v6\" })",
    StrIsoDate => ".regex(/^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/)",
    StrIsoTime => ".regex(/^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?$/)",
    StrBase64 => ".base64()",
    StrPhoneE164 => ".regex(/^\\+[1-9][0-9]{6,14}$/)",
    StrOneOf(opts) => str.concat(".refine(v => [", str.concat(str.join(list.map(opts, fn (s :: Str) -> Str {
      str.concat("\"", str.concat(s, "\""))
    }), ", "), "].includes(v))")),
    _ => "",
  }
}

fn zod_int(checks :: List[c.IntCheck]) -> Str {
  list.fold(checks, "z.number().int()", fn (acc :: Str, chk :: c.IntCheck) -> Str {
    str.concat(acc, zod_int_chain(chk))
  })
}

fn zod_int_chain(chk :: c.IntCheck) -> Str {
  match chk {
    IntMin(n) => str.concat(".min(", str.concat(int.to_str(n), ")")),
    IntMax(n) => str.concat(".max(", str.concat(int.to_str(n), ")")),
    IntInRange(a, b) => str.concat(".min(", str.concat(int.to_str(a), str.concat(").max(", str.concat(int.to_str(b), ")")))),
    IntPositive => ".positive()",
    IntNonNegative => ".nonnegative()",
    _ => "",
  }
}

fn zod_float(checks :: List[c.FloatCheck]) -> Str {
  list.fold(checks, "z.number()", fn (acc :: Str, chk :: c.FloatCheck) -> Str {
    str.concat(acc, zod_float_chain(chk))
  })
}

fn zod_float_chain(chk :: c.FloatCheck) -> Str {
  match chk {
    FloatMin(x) => str.concat(".min(", str.concat(float.to_str(x), ")")),
    FloatMax(x) => str.concat(".max(", str.concat(float.to_str(x), ")")),
    FloatPositive => ".positive()",
    FloatNonNegative => ".nonnegative()",
    FloatFinite => ".finite()",
    _ => "",
  }
}

fn zod_list_chain(checks :: List[c.ListCheck]) -> Str {
  list.fold(checks, "", fn (acc :: Str, chk :: c.ListCheck) -> Str {
    match chk {
      ListMinLen(n) => str.concat(acc, str.concat(".min(", str.concat(int.to_str(n), ")"))),
      ListMaxLen(n) => str.concat(acc, str.concat(".max(", str.concat(int.to_str(n), ")"))),
      ListNonEmpty => str.concat(acc, ".nonempty()"),
      _ => acc,
    }
  })
}

fn to_rust_struct(schema :: s.ModelSchema) -> Str {
  let nested := collect_nested(schema)
  let head := rust_struct(schema)
  let rest := list.map(nested, fn (m :: s.ModelSchema) -> Str {
    rust_struct(m)
  })
  let body := str.join(list.concat(rest, [head]), "\n\n")
  str.concat(rust_header(), str.concat("\n\n", body))
}

fn rust_header() -> Str {
  "use serde::{Deserialize, Serialize};"
}

fn rust_struct(schema :: s.ModelSchema) -> Str {
  let doc := if str.is_empty(schema.description) {
    ""
  } else {
    str.concat("/// ", str.concat(schema.description, "\n"))
  }
  let fields := list.map(schema.fields, fn (field :: s.Field) -> Str {
    rust_field_line(field)
  })
  str.concat(doc, str.concat("#[derive(Debug, Clone, Serialize, Deserialize)]\npub struct ", str.concat(schema.title, str.concat(" {\n", str.concat(str.join(fields, "\n"), "\n}")))))
}

fn rust_field_line(field :: s.Field) -> Str {
  let doc := if str.is_empty(field.description) {
    ""
  } else {
    str.concat("    /// ", str.concat(field.description, "\n"))
  }
  let hint := rust_constraint_hint(field.kind)
  let hint_doc := if str.is_empty(hint) {
    ""
  } else {
    str.concat("    /// constraints: ", str.concat(hint, "\n"))
  }
  let ty := rust_type(field.kind)
  let ty_opt := if field.required {
    ty
  } else {
    str.concat("Option<", str.concat(ty, ">"))
  }
  let serde_attr := if field.required {
    ""
  } else {
    "    #[serde(default)]\n"
  }
  str.concat(doc, str.concat(hint_doc, str.concat(serde_attr, str.concat("    pub ", str.concat(field.name, str.concat(": ", str.concat(ty_opt, ",")))))))
}

fn rust_type(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(_) => "String",
    KInt(_) => "i64",
    KFloat(_) => "f64",
    KBool => "bool",
    KArray(elem, _) => str.concat("Vec<", str.concat(rust_type(elem), ">")),
    KObject(sub) => sub.title,
  }
}

fn rust_constraint_hint(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(checks) => str_hint(checks),
    KInt(checks) => int_hint(checks),
    KFloat(checks) => float_hint(checks),
    _ => "",
  }
}

fn to_go_struct(schema :: s.ModelSchema) -> Str {
  let nested := collect_nested(schema)
  let head := go_struct(schema)
  let rest := list.map(nested, fn (m :: s.ModelSchema) -> Str {
    go_struct(m)
  })
  let body := str.join(list.concat(rest, [head]), "\n\n")
  str.concat(go_header(schema), str.concat("\n\n", body))
}

fn go_header(_schema :: s.ModelSchema) -> Str {
  "package models"
}

fn go_struct(schema :: s.ModelSchema) -> Str {
  let doc := if str.is_empty(schema.description) {
    ""
  } else {
    str.concat("// ", str.concat(schema.description, "\n"))
  }
  let fields := list.map(schema.fields, fn (field :: s.Field) -> Str {
    go_field_line(field)
  })
  str.concat(doc, str.concat("type ", str.concat(go_ident(schema.title), str.concat(" struct {\n", str.concat(str.join(fields, "\n"), "\n}")))))
}

fn go_field_line(field :: s.Field) -> Str {
  let doc := if str.is_empty(field.description) {
    ""
  } else {
    str.concat("\t// ", str.concat(field.description, "\n"))
  }
  let hint := rust_constraint_hint(field.kind)
  let hint_doc := if str.is_empty(hint) {
    ""
  } else {
    str.concat("\t// constraints: ", str.concat(hint, "\n"))
  }
  let ty := go_type(field.kind)
  let ty_opt := if field.required {
    ty
  } else {
    str.concat("*", ty)
  }
  let tag := if field.required {
    str.concat("`json:\"", str.concat(field.name, "\"`"))
  } else {
    str.concat("`json:\"", str.concat(field.name, ",omitempty\"`"))
  }
  str.concat(doc, str.concat(hint_doc, str.concat("\t", str.concat(go_ident(field.name), str.concat(" ", str.concat(ty_opt, str.concat(" ", tag)))))))
}

fn go_type(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(_) => "string",
    KInt(_) => "int64",
    KFloat(_) => "float64",
    KBool => "bool",
    KArray(elem, _) => str.concat("[]", go_type(elem)),
    KObject(sub) => go_ident(sub.title),
  }
}

fn go_ident(name :: Str) -> Str {
  let segs := list.fold(str.split(name, "_"), [], fn (acc :: List[Str], seg :: Str) -> List[Str] {
    list.concat(acc, str.split(seg, "-"))
  })
  list.fold(segs, "", fn (acc :: Str, seg :: Str) -> Str {
    str.concat(acc, capitalize(seg))
  })
}

fn capitalize(s :: Str) -> Str {
  if str.is_empty(s) {
    ""
  } else {
    let head := str.to_upper(str.slice(s, 0, 1))
    let tail := str.slice(s, 1, str.len(s))
    str.concat(head, tail)
  }
}

