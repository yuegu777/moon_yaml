///|
/// 文件用途: YAML 语法分析器 - 将 Token 流解析为 YamlValue AST
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.0
/// 风险提示: 当前为最简实现, 部分高级功能待完善

///|
/// 语法分析器
struct Parser {
    tokens: Array[TokenWithPos]
    pos: Ref[Int]
    len: Int
    depth: Ref[Int]
    config: ParserConfig
}

///|
/// 创建新的语法分析器
fn Parser::new(tokens: Array[TokenWithPos], config: ParserConfig) -> Parser {
    {
        tokens: tokens,
        pos: { val: 0 },
        len: tokens.length(),
        depth: { val: 0 },
        config: config
    }
}

///|
/// 主解析入口, 将 Token 流解析为文档列表
fn Parser::parse(self: Parser) -> Result[Array[YamlValue], YamlError] {
    let docs: Array[YamlValue] = []

    while self.pos.val < self.len {
        self.skip_newlines()

        if self.pos.val >= self.len {
            break
        }

        match self.current_token() {
            DocumentStart => {
                self.advance()
                self.skip_newlines()
                match self.parse_document() {
                    Ok(doc) => docs.push(doc)
                    Err(e) => return Err(e)
                }
            }
            Eof => break
            _ => {
                match self.parse_document() {
                    Ok(doc) => docs.push(doc)
                    Err(e) => return Err(e)
                }
            }
        }
    }

    Ok(docs)
}

///|
/// 解析单个文档
fn Parser::parse_document(self: Parser) -> Result[YamlValue, YamlError] {
    self.skip_newlines()

    if self.pos.val >= self.len {
        return Ok(Null)
    }

    match self.current_token() {
        DocumentEnd => {
            self.advance()
            Ok(Null)
        }
        Eof => Ok(Null)
        _ => self.parse_value()
    }
}

///|
/// 解析值(根据当前 Token 决定解析策略)
fn Parser::parse_value(self: Parser) -> Result[YamlValue, YamlError] {
    if self.depth.val >= self.config.max_depth {
        return Err(ParseError(
            line=self.current_pos().line,
            col=self.current_pos().col,
            msg="嵌套深度超过最大限制"
        ))
    }

    self.skip_newlines()

    if self.pos.val >= self.len {
        return Ok(Null)
    }

    match self.current_token() {
        BlockEntry => self.parse_sequence()
        Key(_) => self.parse_mapping_value()
        Scalar(_) => self.parse_scalar_value()
        DocumentEnd => {
            self.advance()
            Ok(Null)
        }
        Eof => Ok(Null)
        _ => {
            let pos = self.current_pos()
            Err(ParseError(
                line=pos.line,
                col=pos.col,
                msg="意外的 Token"
            ))
        }
    }
}

///|
/// 解析序列(BlockEntry 开始)
fn Parser::parse_sequence(self: Parser) -> Result[YamlValue, YamlError] {
    let items: Array[YamlValue] = []
    self.depth.val = self.depth.val + 1

    while self.pos.val < self.len {
        self.skip_newlines()

        if self.pos.val >= self.len {
            break
        }

        match self.current_token() {
            BlockEntry => {
                self.advance()
                self.skip_newlines()
                match self.parse_value() {
                    Ok(value) => items.push(value)
                    Err(e) => {
                        self.depth.val = self.depth.val - 1
                        return Err(e)
                    }
                }
            }
            _ => break
        }
    }

    self.depth.val = self.depth.val - 1
    Ok(Array(items))
}

///|
/// 解析 mapping(Key 开始)
fn Parser::parse_mapping_value(self: Parser) -> Result[YamlValue, YamlError] {
    let mapping: Map[String, YamlValue] = Map::new()
    self.depth.val = self.depth.val + 1

    while self.pos.val < self.len {
        self.skip_newlines()

        if self.pos.val >= self.len {
            break
        }

        match self.current_token() {
            Key(key_str) => {
                let key = key_str
                self.advance()

                if self.pos.val >= self.len {
                    self.depth.val = self.depth.val - 1
                    return Err(ParseError(
                        line=self.current_pos().line,
                        col=self.current_pos().col,
                        msg="key 后缺少 value"
                    ))
                }

                match self.current_token() {
                    ValueIndicator => {
                        self.advance()
                        self.skip_newlines()
                        match self.parse_value() {
                            Ok(value) => mapping.set(key, value)
                            Err(e) => {
                                self.depth.val = self.depth.val - 1
                                return Err(e)
                            }
                        }
                    }
                    _ => {
                        self.depth.val = self.depth.val - 1
                        return Err(ParseError(
                            line=self.current_pos().line,
                            col=self.current_pos().col,
                            msg="key 后预期 ':'"
                        ))
                    }
                }
            }
            _ => break
        }
    }

    self.depth.val = self.depth.val - 1
    Ok(Object(mapping))
}

///|
/// 解析标量值
fn Parser::parse_scalar_value(self: Parser) -> Result[YamlValue, YamlError] {
    match self.current_token() {
        Scalar(s) => {
            self.advance()
            Ok(self.resolve_scalar(s))
        }
        _ => {
            let pos = self.current_pos()
            Err(ParseError(
                line=pos.line,
                col=pos.col,
                msg="预期标量值"
            ))
        }
    }
}

///|
/// 标量类型推断(Core Schema)
fn Parser::resolve_scalar(self: Parser, s: String) -> YamlValue {
    let trimmed = s.trim_space().to_string()

    // null
    if trimmed == "~" || trimmed == "null" || trimmed == "Null" ||
       trimmed == "NULL" {
        return Null
    }

    // bool
    if trimmed == "true" || trimmed == "True" || trimmed == "TRUE" {
        return Bool(true)
    }
    if trimmed == "false" || trimmed == "False" || trimmed == "FALSE" {
        return Bool(false)
    }

    // int
    match self.parse_int(trimmed) {
        Some(i) => return Int(i)
        None => ()
    }

    // float
    match self.parse_float(trimmed) {
        Some(f) => return Double(f)
        None => ()
    }

    // fallback to string
    String(s)
}

///|
/// 解析整数
fn Parser::parse_int(self: Parser, s: String) -> Option[Int] {
    if s.length() == 0 {
        return None
    }

    let chars = s.to_array()
    let mut start = 0
    let mut negative = false

    if chars[0] == '-' {
        negative = true
        start = 1
    } else if chars[0] == '+' {
        start = 1
    }

    if start >= chars.length() {
        return None
    }

    // 十六进制
    if chars[start] == '0' && start + 1 < chars.length() {
        let next = chars[start + 1]
        if next == 'x' || next == 'X' {
            return self.parse_hex(s, start + 2, negative)
        }
    }

    // 十进制
    let mut result = 0
    let mut i = start
    while i < chars.length() {
        let c = chars[i]
        if c < '0' || c > '9' {
            return None
        }
        result = result * 10 + (c.to_int() - '0'.to_int())
        i = i + 1
    }

    if negative {
        result = -result
    }

    Some(result)
}

///|
/// 解析十六进制
fn Parser::parse_hex(self: Parser, s: String, start: Int, negative: Bool) -> Option[Int] {
    let chars = s.to_array()
    if start >= chars.length() {
        return None
    }

    let mut result = 0
    let mut i = start
    while i < chars.length() {
        let c = chars[i]
        let digit = if c >= '0' && c <= '9' {
            c.to_int() - '0'.to_int()
        } else if c >= 'a' && c <= 'f' {
            c.to_int() - 'a'.to_int() + 10
        } else if c >= 'A' && c <= 'F' {
            c.to_int() - 'A'.to_int() + 10
        } else {
            return None
        }
        result = result * 16 + digit
        i = i + 1
    }

    if negative {
        result = -result
    }

    Some(result)
}

///|
/// 解析浮点数
fn Parser::parse_float(self: Parser, s: String) -> Option[Double] {
    if s == ".inf" || s == ".Inf" || s == ".INF" {
        return Some(1.0e308)
    }
    if s == "-.inf" || s == "-.Inf" || s == "-.INF" {
        return Some(-1.0e308)
    }
    if s == ".nan" || s == ".NaN" || s == ".NAN" {
        return Some(0.0)
    }

    let chars = s.to_array()
    let mut start = 0
    let mut negative = false

    if chars[0] == '-' {
        negative = true
        start = 1
    } else if chars[0] == '+' {
        start = 1
    }

    if start >= chars.length() {
        return None
    }

    let mut int_part = 0
    let mut has_dot = false
    let mut frac_value = 0.0
    let mut frac_div = 1.0

    let mut i = start
    while i < chars.length() {
        let c = chars[i]
        if c == '.' {
            if has_dot {
                return None
            }
            has_dot = true
        } else if c >= '0' && c <= '9' {
            let digit = c.to_int() - '0'.to_int()
            if not(has_dot) {
                int_part = int_part * 10 + digit
            } else {
                frac_div = frac_div * 10.0
                frac_value = frac_value + digit.to_double() / frac_div
            }
        } else {
            return None
        }
        i = i + 1
    }

    if not(has_dot) {
        return None
    }

    let mut result = int_part.to_double() + frac_value
    if negative {
        result = -result
    }

    Some(result)
}

///|
/// 辅助方法

fn Parser::current_token(self: Parser) -> Token {
    self.tokens[self.pos.val].token
}

fn Parser::current_pos(self: Parser) -> TokenPos {
    self.tokens[self.pos.val].pos
}

fn Parser::advance(self: Parser) -> Unit {
    if self.pos.val < self.len {
        self.pos.val = self.pos.val + 1
    }
}

fn Parser::skip_newlines(self: Parser) -> Unit {
    while self.pos.val < self.len {
        match self.current_token() {
            NewLine => self.advance()
            _ => break
        }
    }
}
