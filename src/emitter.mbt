///|
/// 文件用途: YAML 序列化生成器 - 将 YamlValue 序列化为 YAML 字符串
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.0
/// 风险提示: 当前为最简实现, 部分高级功能待完善

///|
/// YAML 序列化生成器
struct Emitter {
    indent_size: Int
}

///|
/// 创建新的生成器
fn Emitter::new() -> Emitter {
    { indent_size: 2 }
}

///|
/// 设置缩进空格数
fn Emitter::with_indent(self: Emitter, size: Int) -> Emitter {
    { indent_size: size }
}

///|
/// 将 YamlValue 序列化为 YAML 字符串
fn Emitter::emit(self: Emitter, value: YamlValue) -> String {
    self.emit_value(value, 0)
}

///|
/// 序列化文档列表
fn Emitter::emit_documents(self: Emitter, docs: Array[YamlValue]) -> String {
    let mut result = ""
    let mut i = 0
    while i < docs.length() {
        if i > 0 {
            result = result + "---\n"
        }
        result = result + self.emit_value(docs[i], 0)
        result = result + "\n"
        i = i + 1
    }
    result
}

///|
/// 内部: 根据值类型选择序列化方式
fn Emitter::emit_value(self: Emitter, value: YamlValue, indent: Int) -> String {
    match value {
        Null => "null"
        Bool(b) => if b { "true" } else { "false" }
        Int(i) => i.to_string()
        Double(d) => d.to_string()
        String(s) => self.emit_string(s)
        Array(arr) => self.emit_array(arr, indent)
        Object(obj) => self.emit_object(obj, indent)
    }
}

///|
/// 序列化标量字符串
fn Emitter::emit_string(self: Emitter, s: String) -> String {
    if self.needs_quotes(s) {
        "\"" + self.escape_string(s) + "\""
    } else {
        s
    }
}

///|
/// 判断字符串是否需要引号
fn Emitter::needs_quotes(self: Emitter, s: String) -> Bool {
    if s.length() == 0 {
        return true
    }

    let chars = s.to_array()
    let trimmed = s.trim_space().to_string()

    // 检查是否是特殊值
    if trimmed == "null" || trimmed == "true" || trimmed == "false" {
        return true
    }

    // 检查是否包含特殊字符
    let mut i = 0
    while i < chars.length() {
        let c = chars[i]
        if c == ':' || c == '#' || c == '{' || c == '}' ||
           c == '[' || c == ']' || c == ',' || c == '&' ||
           c == '*' || c == '?' || c == '|' || c == '-' ||
           c == '<' || c == '>' || c == '=' || c == '!' ||
           c == '%' || c == '@' || c == '`' || c == '"' ||
           c == '\'' || c == '\n' || c == '\r' || c == '\t' {
            return true
        }
        i = i + 1
    }

    false
}

///|
/// 转义字符串中的特殊字符
fn Emitter::escape_string(self: Emitter, s: String) -> String {
    let chars = s.to_array()
    let buf = StringBuilder::new()

    let mut i = 0
    while i < chars.length() {
        let c = chars[i]
        if c == '\\' {
            buf.write_string("\\\\")
        } else if c == '"' {
            buf.write_string("\\\"")
        } else if c == '\n' {
            buf.write_string("\\n")
        } else if c == '\r' {
            buf.write_string("\\r")
        } else if c == '\t' {
            buf.write_string("\\t")
        } else {
            buf.write_char(c)
        }
        i = i + 1
    }

    buf.to_string()
}

///|
/// 序列化数组
fn Emitter::emit_array(self: Emitter, arr: Array[YamlValue], indent: Int) -> String {
    if arr.length() == 0 {
        return "[]"
    }

    let mut result = ""
    let prefix = self.make_indent(indent)

    let mut i = 0
    while i < arr.length() {
        let item = arr[i]
        result = result + prefix + "-"

        match item {
            Object(_) | Array(_) => {
                result = result + "\n" + self.emit_value(item, indent + self.indent_size)
            }
            _ => {
                result = result + " " + self.emit_value(item, 0)
            }
        }

        if i < arr.length() - 1 {
            result = result + "\n"
        }
        i = i + 1
    }

    result
}

///|
/// 序列化对象
fn Emitter::emit_object(self: Emitter, obj: Map[String, YamlValue], indent: Int) -> String {
    if obj.size() == 0 {
        return "{}"
    }

    let mut result = ""
    let prefix = self.make_indent(indent)
    let mut first = true

    obj.each(fn(key, value) {
        if not(first) {
            result = result + "\n"
        }
        first = false

        result = result + prefix + self.emit_string(key) + ":"

        match value {
            Object(_) | Array(_) => {
                result = result + "\n" + self.emit_value(value, indent + self.indent_size)
            }
            _ => {
                result = result + " " + self.emit_value(value, 0)
            }
        }
    })

    result
}

///|
/// 生成缩进字符串
fn Emitter::make_indent(self: Emitter, level: Int) -> String {
    let buf = StringBuilder::new()
    let mut i = 0
    while i < level {
        buf.write_char(' ')
        i = i + 1
    }
    buf.to_string()
}
