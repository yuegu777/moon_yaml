///|
/// 文件用途: YAML 序列化生成器 - 将 YamlValue 序列化为 YAML 字符串
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v1.0.0
/// 风险提示: 不输出锚点/别名(合并键在输出时已内联展开)

///|
/// YAML 序列化生成器
priv struct Emitter {
  indent_size : Int
  buf : StringBuilder
}

///|
/// 创建新的生成器
fn Emitter::new() -> Emitter {
  { indent_size: 2, buf: StringBuilder::new() }
}

///|
/// 设置缩进空格数
fn Emitter::with_indent(self : Emitter, size : Int) -> Emitter {
  { indent_size: size, buf: self.buf }
}

///|
/// 将 YamlValue 序列化为 YAML 字符串
fn Emitter::emit(self : Emitter, value : YamlValue) -> String {
  let e = { indent_size: self.indent_size, buf: StringBuilder::new() }
  e.emit_value(value, 0)
  e.buf.to_string()
}

///|
/// 序列化文档列表
fn Emitter::emit_documents(self : Emitter, docs : Array[YamlValue]) -> String {
  let e = { indent_size: self.indent_size, buf: StringBuilder::new() }
  let mut i = 0
  while i < docs.length() {
    if i > 0 {
      e.buf.write_string("---\n")
    }
    e.emit_value(docs[i], 0)
    if i < docs.length() - 1 {
      e.buf.write_char('\n')
    }
    i = i + 1
  }
  e.buf.to_string()
}

///|
/// 内部: 根据值类型选择序列化方式
fn Emitter::emit_value(self : Emitter, value : YamlValue, indent : Int) -> Unit {
  match value {
    Null => self.buf.write_string("null")
    Bool(b) => self.buf.write_string(if b { "true" } else { "false" })
    Int(i) => self.buf.write_string(i.to_string())
    Double(d) => self.emit_double(d)
    String(s) => self.emit_string(s)
    Array(arr) => self.emit_array(arr, indent)
    Object(obj) => self.emit_object(obj, indent, true)
  }
}

///|
/// 序列化浮点数(处理特殊值)
fn Emitter::emit_double(self : Emitter, d : Double) -> Unit {
  if d.is_inf() {
    if d > 0.0 {
      self.buf.write_string(".inf")
    } else {
      self.buf.write_string("-.inf")
    }
  } else if d.is_nan() {
    self.buf.write_string(".nan")
  } else {
    self.buf.write_string(d.to_string())
  }
}

///|
/// 序列化标量字符串
fn Emitter::emit_string(self : Emitter, s : String) -> Unit {
  if self.needs_quotes(s) {
    self.buf.write_char('"')
    self.escape_string(s)
    self.buf.write_char('"')
  } else {
    self.buf.write_string(s)
  }
}

///|
/// 判断字符串是否需要引号
fn Emitter::needs_quotes(self : Emitter, s : String) -> Bool {
  if s.length() == 0 {
    return true
  }
  let chars = s.to_array()
  let first = chars[0]
  if first == '-' ||
    first == '?' ||
    first == ':' ||
    first == '#' ||
    first == '&' ||
    first == '*' ||
    first == '!' ||
    first == '|' ||
    first == '>' ||
    first == '\'' ||
    first == '"' ||
    first == '%' ||
    first == '@' ||
    first == '`' ||
    first == '{' ||
    first == '[' {
    return true
  }
  let trimmed = s.trim_space().to_string()
  if trimmed.length() == 0 {
    return true
  }

  // 布尔/空值关键字
  if self.is_reserved_word(trimmed) {
    return true
  }

  // 数字格式
  if self.looks_like_number(trimmed) {
    return true
  }

  // 特殊字符
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == ':' {
      if i + 1 >= chars.length() ||
        chars[i + 1] == ' ' ||
        chars[i + 1] == '\n' ||
        chars[i + 1] == '\r' ||
        chars[i + 1] == '\t' {
        return true
      }
    }
    if c == '#' ||
      c == '{' ||
      c == '}' ||
      c == '[' ||
      c == ']' ||
      c == ',' ||
      c == '&' ||
      c == '*' ||
      c == '?' ||
      c == '|' ||
      c == '<' ||
      c == '>' ||
      c == '=' ||
      c == '!' ||
      c == '%' ||
      c == '@' ||
      c == '`' ||
      c == '"' ||
      c == '\'' ||
      c == '\n' ||
      c == '\r' ||
      c == '\t' {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// 检查是否是YAML保留字(布尔/空值)
fn Emitter::is_reserved_word(_ : Emitter, s : String) -> Bool {
  s == "null" ||
  s == "true" ||
  s == "false" ||
  s == "~" ||
  s == "Null" ||
  s == "NULL" ||
  s == "True" ||
  s == "TRUE" ||
  s == "False" ||
  s == "FALSE" ||
  s == ".inf" ||
  s == ".Inf" ||
  s == ".INF" ||
  s == "-.inf" ||
  s == "-.Inf" ||
  s == "-.INF" ||
  s == ".nan" ||
  s == ".NaN" ||
  s == ".NAN" ||
  s == "y" ||
  s == "Y" ||
  s == "yes" ||
  s == "Yes" ||
  s == "YES" ||
  s == "n" ||
  s == "N" ||
  s == "no" ||
  s == "No" ||
  s == "NO" ||
  s == "on" ||
  s == "On" ||
  s == "ON" ||
  s == "off" ||
  s == "Off" ||
  s == "OFF"
}

///|
/// 检查字符串是否看起来像数字
fn Emitter::looks_like_number(_ : Emitter, s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let chars = s.to_array()
  let mut i = 0
  let mut has_digits = false
  let mut has_dot = false
  let mut has_exp = false
  if chars[0] == '+' || chars[0] == '-' {
    if s.length() == 1 {
      return false
    }
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      has_digits = true
    } else if c == '.' {
      if has_dot || has_exp {
        return false
      }
      has_dot = true
    } else if c == 'e' || c == 'E' {
      if has_exp || not(has_digits) {
        return false
      }
      has_exp = true
      has_digits = false
      if i + 1 < chars.length() && (chars[i + 1] == '+' || chars[i + 1] == '-') {
        i = i + 1
      }
    } else if c == '_' {
      // 数字分隔符
    } else if c == 'o' || c == 'O' {
      return i == 1 && chars[0] == '0'
    } else if c == 'x' || c == 'X' {
      return i == 1 && chars[0] == '0'
    } else if c == 'b' || c == 'B' {
      return i == 1 && chars[0] == '0'
    } else {
      return false
    }
    i = i + 1
  }
  has_digits
}

///|
/// 转义字符串中的特殊字符
fn Emitter::escape_string(self : Emitter, s : String) -> Unit {
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' {
      self.buf.write_string("\\\\")
    } else if c == '"' {
      self.buf.write_string("\\\"")
    } else if c == '\n' {
      self.buf.write_string("\\n")
    } else if c == '\r' {
      self.buf.write_string("\\r")
    } else if c == '\t' {
      self.buf.write_string("\\t")
    } else {
      self.buf.write_char(c)
    }
    i = i + 1
  }
}

///|
/// 序列化数组
fn Emitter::emit_array(
  self : Emitter,
  arr : Array[YamlValue],
  indent : Int
) -> Unit {
  if arr.length() == 0 {
    self.buf.write_string("[]")
    return
  }
  let mut i = 0
  while i < arr.length() {
    if i > 0 {
      self.buf.write_char('\n')
    }
    self.write_indent(indent)
    self.buf.write_string("- ")
    let item = arr[i]
    match item {
      Object(_) => self.emit_object_inline(item, indent + self.indent_size)
      Array(_) => {
        self.buf.write_char('\n')
        self.emit_value(item, indent + self.indent_size)
      }
      _ => self.emit_value(item, 0)
    }
    i = i + 1
  }
}

///|
/// 在数组项中内联输出对象(第一个键值对同行, 后续换行)
fn Emitter::emit_object_inline(
  self : Emitter,
  value : YamlValue,
  indent : Int
) -> Unit {
  match value {
    Object(obj) => {
      let keys = self.collect_keys(obj)
      if keys.length() == 0 {
        self.buf.write_string("{}")
        return
      }
      let first_key = keys[0]
      match obj.get(first_key) {
        Some(first_val) => {
          self.emit_key(first_key)
          self.buf.write_string(": ")
          match first_val {
            Object(_) | Array(_) => {
              self.buf.write_char('\n')
              self.emit_value(first_val, indent)
            }
            _ => self.emit_value(first_val, 0)
          }
        }
        None => ()
      }
      let mut ki = 1
      while ki < keys.length() {
        self.buf.write_char('\n')
        self.write_indent(indent)
        let key = keys[ki]
        match obj.get(key) {
          Some(val) => {
            self.emit_key(key)
            self.buf.write_string(": ")
            match val {
              Object(_) | Array(_) => {
                self.buf.write_char('\n')
                self.emit_value(val, indent + self.indent_size)
              }
              _ => self.emit_value(val, 0)
            }
          }
          None => ()
        }
        ki = ki + 1
      }
    }
    _ => self.emit_value(value, indent)
  }
}

///|
/// 序列化对象
fn Emitter::emit_object(
  self : Emitter,
  obj : Map[String, YamlValue],
  indent : Int,
  is_block : Bool
) -> Unit {
  let keys = self.collect_keys(obj)
  if keys.length() == 0 {
    self.buf.write_string("{}")
    return
  }
  let mut i = 0
  while i < keys.length() {
    if i > 0 {
      self.buf.write_char('\n')
    }
    if is_block || i > 0 {
      self.write_indent(indent)
    }
    let key = keys[i]
    match obj.get(key) {
      Some(val) => {
        self.emit_key(key)
        self.buf.write_string(":")
        match val {
          Object(_) | Array(_) => {
            self.buf.write_char('\n')
            self.emit_value(val, indent + self.indent_size)
          }
          _ => {
            self.buf.write_char(' ')
            self.emit_value(val, 0)
          }
        }
      }
      None => ()
    }
    i = i + 1
  }
}

///|
/// 输出键名
fn Emitter::emit_key(self : Emitter, key : String) -> Unit {
  if self.key_needs_quotes(key) {
    self.buf.write_char('"')
    self.escape_string(key)
    self.buf.write_char('"')
  } else {
    self.buf.write_string(key)
  }
}

///|
/// 判断键名是否需要引号
fn Emitter::key_needs_quotes(self : Emitter, key : String) -> Bool {
  if key.length() == 0 {
    return true
  }
  let chars = key.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == ':' ||
      c == '#' ||
      c == '{' ||
      c == '}' ||
      c == '[' ||
      c == ']' ||
      c == ',' ||
      c == '&' ||
      c == '*' ||
      c == '?' ||
      c == '|' ||
      c == '-' ||
      c == '<' ||
      c == '>' ||
      c == '=' ||
      c == '!' ||
      c == '%' ||
      c == '@' ||
      c == '`' ||
      c == '"' ||
      c == '\'' ||
      c == '\n' ||
      c == '\r' ||
      c == '\t' ||
      c == ' ' ||
      c == '/' {
      return true
    }
    i = i + 1
  }
  if self.looks_like_number(key) {
    return true
  }
  false
}

///|
/// 写入缩进空格
fn Emitter::write_indent(self : Emitter, level : Int) -> Unit {
  let mut i = 0
  while i < level {
    self.buf.write_char(' ')
    i = i + 1
  }
}

///|
/// 收集 Map 的 key 到 Array
fn Emitter::collect_keys(
  _ : Emitter,
  obj : Map[String, YamlValue]
) -> Array[String] {
  let keys : Array[String] = []
  obj.each(fn(k, _v) { keys.push(k) })
  keys
}
