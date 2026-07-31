///|
/// 文件用途: YAML 语法分析器 - 将 Token 流解析为 YamlValue AST
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.1
/// 风险提示: 引入缩进感知, 基于列号判断嵌套层级

///|
/// 语法分析器
priv struct Parser {
  tokens : Array[TokenWithPos]
  pos : Ref[Int]
  len : Int
  depth : Ref[Int]
  anchors : Ref[Map[String, YamlValue]]
  config : ParserConfig
}

///|
/// 创建新的语法分析器
fn Parser::new(tokens : Array[TokenWithPos], config : ParserConfig) -> Parser {
  {
    tokens,
    pos: { val: 0 },
    len: tokens.length(),
    depth: { val: 0 },
    anchors: { val: Map::new() },
    config,
  }
}

///|
/// 主解析入口, 将 Token 流解析为文档列表
fn Parser::parse(self : Parser) -> Result[Array[YamlValue], YamlError] {
  let docs : Array[YamlValue] = []
  while self.pos.val < self.len {
    self.skip_newlines()
    if self.pos.val >= self.len {
      break
    }
    match self.current_token() {
      DocumentStart => {
        self.advance()
        self.skip_newlines()
        // 新文档开始, 重置锚点表
        self.anchors.val = Map::new()
        match self.parse_document() {
          Ok(doc) => docs.push(doc)
          Err(e) => return Err(e)
        }
      }
      Eof => break
      _ => {
        // 新文档开始(隐式), 重置锚点表
        self.anchors.val = Map::new()
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
fn Parser::parse_document(self : Parser) -> Result[YamlValue, YamlError] {
  self.skip_newlines()
  if self.pos.val >= self.len {
    return Ok(Null)
  }
  match self.current_token() {
    DocumentEnd => {
      self.advance()
      Ok(Null)
    }
    DocumentStart =>
      // 遇到新的文档开始符, 当前文档为空
      Ok(Null)
    Eof => Ok(Null)
    _ => self.parse_value(0)
  }
}

///|
/// 解析值(根据当前 Token 决定解析策略)
/// base_indent: 当前值的父级缩进, token col <= base_indent 表示已离开当前层级
fn Parser::parse_value(
  self : Parser,
  base_indent : Int
) -> Result[YamlValue, YamlError] {
  if self.depth.val >= self.config.max_depth {
    return Err(
      ParseError(
        line=self.current_pos().line,
        col=self.current_pos().col,
        msg="嵌套深度超过最大限制",
      ),
    )
  }
  self.skip_newlines()
  if self.pos.val >= self.len {
    return Ok(Null)
  }

  // 先处理别名
  if self.current_token() is Alias(_) {
    return self.parse_alias()
  }

  // 检查是否有锚点
  let anchor_name = if self.current_token() is Anchor(_) {
    match self.current_token() {
      Anchor(name) => {
        self.advance()
        Some(name)
      }
      _ => None
    }
  } else {
    None
  }

  // 递归解析值(锚点后的值)
  let value_result = self.parse_value_inner(base_indent)
  match value_result {
    Ok(value) =>
      // 如果有锚点, 注册到锚点表
      match anchor_name {
        Some(name) => {
          self.anchors.val.set(name, value)
          Ok(value)
        }
        None => Ok(value)
      }
    Err(e) => Err(e)
  }
}

///|
/// 内部值解析(处理锚点后调用)
fn Parser::parse_value_inner(
  self : Parser,
  base_indent : Int
) -> Result[YamlValue, YamlError] {
  self.skip_newlines()
  if self.pos.val >= self.len {
    return Ok(Null)
  }
  match self.current_token() {
    BlockEntry => {
      let entry_col = self.current_pos().col
      // BlockEntry 的列号如果 <= base_indent, 说明不属于当前值
      if entry_col <= base_indent {
        return Ok(Null)
      }
      self.parse_sequence(base_indent, entry_col)
    }
    Key(_) => {
      let key_col = self.current_pos().col
      // Key 的列号如果 <= base_indent, 说明不属于当前值(空值情况)
      if key_col <= base_indent {
        return Ok(Null)
      }
      self.parse_mapping_value(base_indent, key_col)
    }
    Scalar(_) => self.parse_scalar_value()
    DoubleQuoted(_) => self.parse_quoted_string()
    SingleQuoted(_) => self.parse_quoted_string()
    FlowSequenceStart => self.parse_flow_sequence()
    FlowMappingStart => self.parse_flow_mapping()
    FlowSequenceEnd => Ok(Null) // 空序列
    FlowMappingEnd => Ok(Null) // 空映射
    Comma => Ok(Null) // 逗号分隔
    DocumentEnd => {
      self.advance()
      Ok(Null)
    }
    Eof => Ok(Null)
    Anchor(_) =>
      // 多个锚点(不常见, 但允许, 递归处理)
      self.parse_value(base_indent)
    Alias(_) => self.parse_alias()
    _ => {
      let pos = self.current_pos()
      Err(ParseError(line=pos.line, col=pos.col, msg="意外的 Token"))
    }
  }
}

///|
/// 解析别名引用
fn Parser::parse_alias(self : Parser) -> Result[YamlValue, YamlError] {
  let pos = self.current_pos()
  match self.current_token() {
    Alias(name) => {
      self.advance()
      match self.anchors.val.get(name) {
        Some(value) => Ok(value)
        None =>
          Err(
            ParseError(
              line=pos.line,
              col=pos.col,
              msg="未找到锚点: " + name,
            ),
          )
      }
    }
    _ => Err(ParseError(line=pos.line, col=pos.col, msg="预期别名"))
  }
}

///|
/// 应用合并键 <<: 将源映射合并到目标映射(不覆盖已有键)
fn Parser::apply_merge_key(
  self : Parser,
  target : Map[String, YamlValue],
  value : YamlValue
) -> Unit {
  match value {
    Object(source) =>
      // 单个映射: 合并所有不存在的键
      source.each(fn(k, v) {
        match target.get(k) {
          None => target.set(k, v)
          Some(_) => () // 已存在, 不覆盖
        }
      })
    Array(items) => {
      // 序列: 依次合并每个项(必须是映射)
      let mut i = 0
      while i < items.length() {
        self.apply_merge_key(target, items[i])
        i = i + 1
      }
    }
    _ => ()
    // 非映射/序列类型忽略(不符合YAML规范但容错处理)
  }
}

///|
/// 解析序列(BlockEntry 开始)
/// base_indent: 父级缩进; entry_col: 当前序列项 '-' 的列号
fn Parser::parse_sequence(
  self : Parser,
  base_indent : Int,
  entry_col : Int
) -> Result[YamlValue, YamlError] {
  let items : Array[YamlValue] = []
  self.depth.val = self.depth.val + 1
  while self.pos.val < self.len {
    self.skip_newlines()
    if self.pos.val >= self.len {
      break
    }
    match self.current_token() {
      BlockEntry => {
        let col = self.current_pos().col
        // 序列项缩进小于等于父级, 离开序列
        if col <= base_indent {
          break
        }
        // 序列项列号与当前 entry_col 不同但大于 base_indent:
        // 属于更深层嵌套(在当前项值内部), 由 parse_value 处理
        if col != entry_col {
          break
        }
        self.advance()
        self.skip_newlines()
        // 序列项的值的基准缩进是 entry_col(即 '-' 所在列)
        match self.parse_value(entry_col) {
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
/// base_indent: 父级缩进; key_col: 当前 mapping 键的列号
fn Parser::parse_mapping_value(
  self : Parser,
  base_indent : Int,
  key_col : Int
) -> Result[YamlValue, YamlError] {
  let mapping : Map[String, YamlValue] = Map::new()
  self.depth.val = self.depth.val + 1
  while self.pos.val < self.len {
    self.skip_newlines()
    if self.pos.val >= self.len {
      break
    }
    match self.current_token() {
      Key(cur_key_str) => {
        let col = self.current_pos().col
        // Key 缩进小于等于父级, 离开当前 mapping
        if col <= base_indent {
          break
        }
        // Key 列号与 key_col 不同:
        // 如果 col > key_col, 说明是更深层的 key(应该已被前一个值的 parse_value 消费)
        // 如果 col < key_col 但 > base_indent, 缩进不一致, 也退出
        if col != key_col {
          break
        }
        let key = cur_key_str
        self.advance()
        if self.pos.val >= self.len {
          // key 后直接 Eof, 值为 Null
          mapping.set(key, Null)
          break
        }
        match self.current_token() {
          ValueIndicator => {
            self.advance()
            self.skip_newlines()
            // 值的基准缩进是 key_col
            match self.parse_value(key_col) {
              Ok(value) =>
                if key == "<<" {
                  // 合并键: 将引用的映射合并到当前映射
                  self.apply_merge_key(mapping, value)
                } else {
                  mapping.set(key, value)
                }
              Err(e) => {
                self.depth.val = self.depth.val - 1
                return Err(e)
              }
            }
          }
          _ => {
            self.depth.val = self.depth.val - 1
            return Err(
              ParseError(
                line=self.current_pos().line,
                col=self.current_pos().col,
                msg="key 后预期 ':'",
              ),
            )
          }
        }
      }
      BlockEntry => {
        // BlockEntry 可能属于序列值内部(已被 parse_value 处理), 或退出到外层
        let col = self.current_pos().col
        if col <= base_indent {
          break
        }
        // BlockEntry 列号大于 base_indent 但不在 key_col, 说明是前一个 key 的序列值延续?
        // 这种情况应该已被 parse_value(key_col) 消费, 这里 break 防止死循环
        break
      }
      _ => break
    }
  }
  self.depth.val = self.depth.val - 1
  Ok(Object(mapping))
}

///|
/// 解析标量值
fn Parser::parse_scalar_value(self : Parser) -> Result[YamlValue, YamlError] {
  match self.current_token() {
    Scalar(s) => {
      self.advance()
      Ok(self.resolve_scalar(s))
    }
    _ => {
      let pos = self.current_pos()
      Err(ParseError(line=pos.line, col=pos.col, msg="预期标量值"))
    }
  }
}

///|
/// 解析引号字符串(双引号/单引号, 始终返回 String, 不做类型推断)
fn Parser::parse_quoted_string(self : Parser) -> Result[YamlValue, YamlError] {
  match self.current_token() {
    DoubleQuoted(s) => {
      self.advance()
      Ok(String(s))
    }
    SingleQuoted(s) => {
      self.advance()
      Ok(String(s))
    }
    _ => {
      let pos = self.current_pos()
      Err(ParseError(line=pos.line, col=pos.col, msg="预期引号字符串"))
    }
  }
}

///|
/// 解析流序列 [item1, item2, ...]
fn Parser::parse_flow_sequence(self : Parser) -> Result[YamlValue, YamlError] {
  // 消费 [
  self.advance()
  let items : Array[YamlValue] = []
  self.depth.val = self.depth.val + 1
  if self.depth.val >= self.config.max_depth {
    self.depth.val = self.depth.val - 1
    return Err(
      ParseError(
        line=self.current_pos().line,
        col=self.current_pos().col,
        msg="嵌套深度超过最大限制",
      ),
    )
  }
  while self.pos.val < self.len {
    self.skip_newlines()
    // 跳过逗号
    while self.pos.val < self.len && self.current_token() is Comma {
      self.advance()
      self.skip_newlines()
    }
    if self.pos.val >= self.len {
      self.depth.val = self.depth.val - 1
      return Err(
        ParseError(
          line=self.current_pos().line,
          col=self.current_pos().col,
          msg="流序列未闭合",
        ),
      )
    }
    match self.current_token() {
      FlowSequenceEnd => {
        self.advance()
        self.depth.val = self.depth.val - 1
        return Ok(Array(items))
      }
      _ =>
        // 流样式中, 使用 -1 作为 base_indent (不基于缩进判断结束)
        match self.parse_flow_value() {
          Ok(value) => items.push(value)
          Err(e) => {
            self.depth.val = self.depth.val - 1
            return Err(e)
          }
        }
    }
  }
  self.depth.val = self.depth.val - 1
  Err(
    ParseError(
      line=self.current_pos().line,
      col=self.current_pos().col,
      msg="流序列未闭合",
    ),
  )
}

///|
/// 解析流映射 {key: value, key2: value2, ...}
fn Parser::parse_flow_mapping(self : Parser) -> Result[YamlValue, YamlError] {
  // 消费 {
  self.advance()
  let mapping : Map[String, YamlValue] = Map::new()
  self.depth.val = self.depth.val + 1
  if self.depth.val >= self.config.max_depth {
    self.depth.val = self.depth.val - 1
    return Err(
      ParseError(
        line=self.current_pos().line,
        col=self.current_pos().col,
        msg="嵌套深度超过最大限制",
      ),
    )
  }
  while self.pos.val < self.len {
    self.skip_newlines()
    // 跳过逗号
    while self.pos.val < self.len && self.current_token() is Comma {
      self.advance()
      self.skip_newlines()
    }
    if self.pos.val >= self.len {
      self.depth.val = self.depth.val - 1
      return Err(
        ParseError(
          line=self.current_pos().line,
          col=self.current_pos().col,
          msg="流映射未闭合",
        ),
      )
    }
    match self.current_token() {
      FlowMappingEnd => {
        self.advance()
        self.depth.val = self.depth.val - 1
        return Ok(Object(mapping))
      }
      Key(k) | Scalar(k) | DoubleQuoted(k) | SingleQuoted(k) => {
        let key = k
        self.advance()
        self.skip_newlines()

        // 期望冒号(ValueIndicator)
        if self.pos.val >= self.len ||
          not(self.current_token() is ValueIndicator) {
          self.depth.val = self.depth.val - 1
          return Err(
            ParseError(
              line=self.current_pos().line,
              col=self.current_pos().col,
              msg="流映射中 key 后期望 ':'",
            ),
          )
        }
        self.advance() // 消费 :
        self.skip_newlines()
        match self.parse_flow_value() {
          Ok(value) =>
            if key == "<<" {
              self.apply_merge_key(mapping, value)
            } else {
              mapping.set(key, value)
            }
          Err(e) => {
            self.depth.val = self.depth.val - 1
            return Err(e)
          }
        }
      }
      _ => {
        self.depth.val = self.depth.val - 1
        return Err(
          ParseError(
            line=self.current_pos().line,
            col=self.current_pos().col,
            msg="流映射中预期 key",
          ),
        )
      }
    }
  }
  self.depth.val = self.depth.val - 1
  Err(
    ParseError(
      line=self.current_pos().line,
      col=self.current_pos().col,
      msg="流映射未闭合",
    ),
  )
}

///|
/// 在流样式中解析值(忽略缩进, 但处理闭合括号)
fn Parser::parse_flow_value(self : Parser) -> Result[YamlValue, YamlError] {
  self.skip_newlines()
  if self.pos.val >= self.len {
    return Ok(Null)
  }

  // 先处理别名
  if self.current_token() is Alias(_) {
    return self.parse_alias()
  }

  // 检查是否有锚点
  let anchor_name = if self.current_token() is Anchor(_) {
    match self.current_token() {
      Anchor(name) => {
        self.advance()
        Some(name)
      }
      _ => None
    }
  } else {
    None
  }

  // 递归解析流值
  let value_result = self.parse_flow_value_inner()
  match value_result {
    Ok(value) =>
      match anchor_name {
        Some(name) => {
          self.anchors.val.set(name, value)
          Ok(value)
        }
        None => Ok(value)
      }
    Err(e) => Err(e)
  }
}

///|
/// 流样式内部值解析
fn Parser::parse_flow_value_inner(
  self : Parser
) -> Result[YamlValue, YamlError] {
  self.skip_newlines()
  if self.pos.val >= self.len {
    return Ok(Null)
  }
  match self.current_token() {
    FlowSequenceStart => self.parse_flow_sequence()
    FlowMappingStart => self.parse_flow_mapping()
    Scalar(_) => self.parse_scalar_value()
    DoubleQuoted(_) => self.parse_quoted_string()
    SingleQuoted(_) => self.parse_quoted_string()
    BlockEntry => {
      // 流样式中 - 不是合法的
      let pos = self.current_pos()
      Err(
        ParseError(
          line=pos.line,
          col=pos.col,
          msg="流样式中不支持块序列项 '-'",
        ),
      )
    }
    Key(_) => {
      // Key token 意味着 key:value 但没有包含在 {} 中, 视为错误
      let pos = self.current_pos()
      Err(
        ParseError(line=pos.line, col=pos.col, msg="流样式中意外的 key"),
      )
    }
    FlowSequenceEnd | FlowMappingEnd | Comma =>
      // 遇到闭合括号或逗号, 值为空
      Ok(Null)
    DocumentEnd => {
      self.advance()
      Ok(Null)
    }
    Anchor(_) =>
      // 递归处理锚点
      self.parse_flow_value()
    Alias(_) => self.parse_alias()
    Eof => Ok(Null)
    _ => {
      let pos = self.current_pos()
      Err(
        ParseError(
          line=pos.line,
          col=pos.col,
          msg="流样式中意外的 Token",
        ),
      )
    }
  }
}

///|
/// 标量类型推断(Core Schema)
fn Parser::resolve_scalar(self : Parser, s : String) -> YamlValue {
  let trimmed = s.trim_space().to_string()

  // 空字符串也视为 null? 不, 空字符串是 String("")
  // 但如果 trim 后为空且原字符串 trim 后为空, 可能是空值场景
  // 实际上 key:  后面只有空格的情况在 lexer 中已经处理为 ValueIndicator 后无 scalar

  // null
  if trimmed == "" ||
    trimmed == "~" ||
    trimmed == "null" ||
    trimmed == "Null" ||
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
/// 解析整数(支持十进制、十六进制、八进制、二进制、下划线分隔符)
fn Parser::parse_int(_ : Parser, s : String) -> Int? {
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

  // 检查符号后是否为 0(可能是十六/八/二进制前缀)
  if chars[start] == '0' && start + 1 < chars.length() {
    let next = chars[start + 1]
    if next == 'x' || next == 'X' {
      return parse_hex(s, start + 2, negative)
    }
    if next == 'o' || next == 'O' {
      return parse_oct(s, start + 2, negative)
    }
    if next == 'b' || next == 'B' {
      return parse_bin(s, start + 2, negative)
    }
  }

  // 十进制(支持下划线分隔符)
  let mut result = 0
  let mut i = start
  let mut has_digits = false
  while i < chars.length() {
    let c = chars[i]
    if c == '_' {
      // 下划线不能在开头或结尾, 不能连续
      if not(has_digits) || i == chars.length() - 1 {
        return None
      }
      i = i + 1
      continue
    }
    if c < '0' || c > '9' {
      return None
    }
    result = result * 10 + (c.to_int() - '0'.to_int())
    has_digits = true
    i = i + 1
  }
  if not(has_digits) {
    return None
  }
  if negative {
    result = -result
  }
  Some(result)
}

///|
/// 解析十六进制
fn parse_hex(s : String, start : Int, negative : Bool) -> Int? {
  let chars = s.to_array()
  if start >= chars.length() {
    return None
  }
  let mut result = 0
  let mut i = start
  let mut has_digits = false
  while i < chars.length() {
    let c = chars[i]
    if c == '_' {
      if not(has_digits) || i == chars.length() - 1 {
        return None
      }
      i = i + 1
      continue
    }
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
    has_digits = true
    i = i + 1
  }
  if not(has_digits) {
    return None
  }
  if negative {
    result = -result
  }
  Some(result)
}

///|
/// 解析八进制(0o 前缀)
fn parse_oct(s : String, start : Int, negative : Bool) -> Int? {
  let chars = s.to_array()
  if start >= chars.length() {
    return None
  }
  let mut result = 0
  let mut i = start
  let mut has_digits = false
  while i < chars.length() {
    let c = chars[i]
    if c == '_' {
      if not(has_digits) || i == chars.length() - 1 {
        return None
      }
      i = i + 1
      continue
    }
    if c < '0' || c > '7' {
      return None
    }
    result = result * 8 + (c.to_int() - '0'.to_int())
    has_digits = true
    i = i + 1
  }
  if not(has_digits) {
    return None
  }
  if negative {
    result = -result
  }
  Some(result)
}

///|
/// 解析二进制(0b 前缀)
fn parse_bin(s : String, start : Int, negative : Bool) -> Int? {
  let chars = s.to_array()
  if start >= chars.length() {
    return None
  }
  let mut result = 0
  let mut i = start
  let mut has_digits = false
  while i < chars.length() {
    let c = chars[i]
    if c == '_' {
      if not(has_digits) || i == chars.length() - 1 {
        return None
      }
      i = i + 1
      continue
    }
    if c != '0' && c != '1' {
      return None
    }
    result = result * 2 + (c.to_int() - '0'.to_int())
    has_digits = true
    i = i + 1
  }
  if not(has_digits) {
    return None
  }
  if negative {
    result = -result
  }
  Some(result)
}

///|
/// 解析浮点数(固定小数、科学计数法、简写、inf/nan、下划线分隔符)
fn Parser::parse_float(_ : Parser, s : String) -> Double? {
  if s == ".inf" ||
    s == ".Inf" ||
    s == ".INF" ||
    s == "+.inf" ||
    s == "+.Inf" ||
    s == "+.INF" {
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

  // 检查是否包含科学计数法标记
  let mut has_exp = false
  let mut exp_pos = -1
  let mut i = start
  while i < chars.length() {
    if chars[i] == 'e' || chars[i] == 'E' {
      if has_exp {
        return None
      }
      has_exp = true
      exp_pos = i
    }
    i = i + 1
  }
  if has_exp {
    return parse_float_sci(chars, start, negative, exp_pos)
  }

  // 固定小数解析(支持 .5 和 5. 简写)
  let mut int_part = 0
  let mut has_dot = false
  let mut frac_value = 0.0
  let mut frac_div = 1.0
  let mut has_int_digits = false
  let mut has_frac_digits = false
  i = start
  while i < chars.length() {
    let c = chars[i]
    if c == '_' {
      // 下划线不能在开头或结尾, 不能在小数点旁边
      if i == start || i == chars.length() - 1 {
        return None
      }
      let prev = chars[i - 1]
      let next = chars[i + 1]
      if prev == '.' || next == '.' {
        return None
      }
      i = i + 1
      continue
    }
    if c == '.' {
      if has_dot {
        return None
      }
      has_dot = true
    } else if c >= '0' && c <= '9' {
      let digit = c.to_int() - '0'.to_int()
      if not(has_dot) {
        int_part = int_part * 10 + digit
        has_int_digits = true
      } else {
        frac_div = frac_div * 10.0
        frac_value = frac_value + digit.to_double() / frac_div
        has_frac_digits = true
      }
    } else {
      return None
    }
    i = i + 1
  }

  // 必须有小数点, 且整数部分或小数部分至少有一个有数字
  if not(has_dot) {
    return None
  }
  // 不允许只有一个 "." (如 "." 或 "+." 或 "-.")
  if not(has_int_digits) && not(has_frac_digits) {
    return None
  }
  let mut result = int_part.to_double() + frac_value
  if negative {
    result = -result
  }
  Some(result)
}

///|
/// 解析科学计数法浮点数
fn parse_float_sci(
  chs : Array[Char],
  start : Int,
  negative : Bool,
  exp_pos : Int
) -> Double? {
  // 解析尾数部分(可能含小数点)
  let mantissa_chars : Array[Char] = []
  let mut i = start
  while i < exp_pos {
    mantissa_chars.push(chs[i])
    i = i + 1
  }

  // 解析指数部分
  let mut exp_start = exp_pos + 1
  let mut exp_negative = false
  if exp_start < chs.length() {
    if chs[exp_start] == '-' {
      exp_negative = true
      exp_start = exp_start + 1
    } else if chs[exp_start] == '+' {
      exp_start = exp_start + 1
    }
  }
  let mut exp_val = 0
  let mut has_exp_digits = false
  i = exp_start
  while i < chs.length() {
    let c = chs[i]
    if c == '_' {
      if not(has_exp_digits) || i == chs.length() - 1 {
        return None
      }
      i = i + 1
      continue
    }
    if c < '0' || c > '9' {
      return None
    }
    exp_val = exp_val * 10 + (c.to_int() - '0'.to_int())
    has_exp_digits = true
    i = i + 1
  }
  if not(has_exp_digits) {
    return None
  }

  // 解析尾数(可能含小数点)
  let mut int_part = 0
  let mut frac_value = 0.0
  let mut frac_div = 1.0
  let mut has_dot = false
  let mut has_int_digits = false
  let mut has_frac_digits = false
  i = 0
  while i < mantissa_chars.length() {
    let c = mantissa_chars[i]
    if c == '_' {
      if i == 0 || i == mantissa_chars.length() - 1 {
        return None
      }
      i = i + 1
      continue
    }
    if c == '.' {
      if has_dot {
        return None
      }
      has_dot = true
    } else if c >= '0' && c <= '9' {
      let digit = c.to_int() - '0'.to_int()
      if not(has_dot) {
        int_part = int_part * 10 + digit
        has_int_digits = true
      } else {
        frac_div = frac_div * 10.0
        frac_value = frac_value + digit.to_double() / frac_div
        has_frac_digits = true
      }
    } else {
      return None
    }
    i = i + 1
  }
  if not(has_int_digits) && not(has_frac_digits) {
    return None
  }
  let mut mantissa = int_part.to_double() + frac_value
  // 计算 10^exp
  let mut mult = 1.0
  let mut e = exp_val
  while e > 0 {
    mult = mult * 10.0
    e = e - 1
  }
  if exp_negative {
    mantissa = mantissa / mult
  } else {
    mantissa = mantissa * mult
  }
  if negative {
    mantissa = -mantissa
  }
  Some(mantissa)
}

///|
/// 辅助方法
fn Parser::current_token(self : Parser) -> Token {
  self.tokens[self.pos.val].token
}

///|
fn Parser::current_pos(self : Parser) -> TokenPos {
  self.tokens[self.pos.val].pos
}

///|
fn Parser::advance(self : Parser) -> Unit {
  if self.pos.val < self.len {
    self.pos.val = self.pos.val + 1
  }
}

///|
fn Parser::skip_newlines(self : Parser) -> Unit {
  while self.pos.val < self.len {
    match self.current_token() {
      NewLine => self.advance()
      _ => break
    }
  }
}
