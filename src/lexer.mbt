///|
/// 文件用途: YAML 词法分析器 - 将输入字符串分词为 Token 流
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.0
/// 风险提示: 当前为最简实现, 部分高级功能待完善

///|
/// 词法分析器
priv struct Lexer {
  chars : Array[Char]
  pos : Ref[Int]
  line : Ref[Int]
  col : Ref[Int]
  len : Int
}

///|
/// 创建新的词法分析器
fn Lexer::new(input : String) -> Lexer {
  let chars = input.to_array()
  {
    chars,
    pos: { val: 0 },
    line: { val: 1 },
    col: { val: 1 },
    len: chars.length(),
  }
}

///|
/// 主扫描入口, 将输入字符串分词为 Token 流
fn Lexer::scan(self : Lexer) -> Result[Array[TokenWithPos], YamlError] {
  let tokens : Array[TokenWithPos] = []
  while self.pos.val < self.len {
    self.skip_spaces()
    if self.pos.val >= self.len {
      break
    }
    let c = self.current_char()
    let start_line = self.line.val
    let start_col = self.col.val
    if c == '\n' {
      tokens.push({ token: NewLine, pos: { line: start_line, col: start_col } })
      self.advance()
    } else if c == '\r' {
      self.advance()
      if self.pos.val < self.len && self.current_char() == '\n' {
        self.advance()
      }
      tokens.push({ token: NewLine, pos: { line: start_line, col: start_col } })
    } else if c == '#' {
      self.skip_comment()
    } else if c == '-' && self.match_str("---") {
      tokens.push({
        token: DocumentStart,
        pos: { line: start_line, col: start_col },
      })
    } else if c == '.' && self.match_str("...") {
      tokens.push({
        token: DocumentEnd,
        pos: { line: start_line, col: start_col },
      })
    } else if c == '-' && self.is_block_entry() {
      tokens.push({
        token: BlockEntry,
        pos: { line: start_line, col: start_col },
      })
      self.advance()
      self.skip_spaces()
    } else if c == '"' {
      // 双引号字符串
      match self.read_double_quoted() {
        Ok(content) => {
          self.skip_spaces()
          if self.pos.val < self.len && self.current_char() == ':' {
            tokens.push({
              token: Key(content),
              pos: { line: start_line, col: start_col },
            })
            self.advance()
            if self.pos.val < self.len {
              let next_c = self.current_char()
              if next_c == ' ' || next_c == '\t' {
                self.skip_spaces()
              }
            }
            tokens.push({
              token: ValueIndicator,
              pos: { line: self.line.val, col: self.col.val },
            })
          } else {
            tokens.push({
              token: DoubleQuoted(content),
              pos: { line: start_line, col: start_col },
            })
          }
        }
        Err(e) => return Err(e)
      }
    } else if c == '\'' {
      // 单引号字符串
      match self.read_single_quoted() {
        Ok(content) => {
          self.skip_spaces()
          if self.pos.val < self.len && self.current_char() == ':' {
            tokens.push({
              token: Key(content),
              pos: { line: start_line, col: start_col },
            })
            self.advance()
            if self.pos.val < self.len {
              let next_c = self.current_char()
              if next_c == ' ' || next_c == '\t' {
                self.skip_spaces()
              }
            }
            tokens.push({
              token: ValueIndicator,
              pos: { line: self.line.val, col: self.col.val },
            })
          } else {
            tokens.push({
              token: SingleQuoted(content),
              pos: { line: start_line, col: start_col },
            })
          }
        }
        Err(e) => return Err(e)
      }
    } else if c == '|' && self.is_block_scalar_indicator() {
      // 字面量块标量 (|) - 读取整个块内容
      self.advance()
      let chomp = self.skip_block_indicators()
      self.skip_to_eol()
      match self.read_block_content(chomp, true) {
        Ok(content) =>
          // 块标量作为值出现(在冒号后), 直接作为Scalar
          tokens.push({
            token: Scalar(content),
            pos: { line: start_line, col: start_col },
          })
        Err(e) => return Err(e)
      }
    } else if c == '>' && self.is_block_scalar_indicator() {
      // 折叠块标量 (>) - 读取整个块内容
      self.advance()
      let chomp = self.skip_block_indicators()
      self.skip_to_eol()
      match self.read_block_content(chomp, false) {
        Ok(content) =>
          tokens.push({
            token: Scalar(content),
            pos: { line: start_line, col: start_col },
          })
        Err(e) => return Err(e)
      }
    } else if c == '[' {
      // 流序列开始
      tokens.push({
        token: FlowSequenceStart,
        pos: { line: start_line, col: start_col },
      })
      self.advance()
    } else if c == ']' {
      // 流序列结束
      tokens.push({
        token: FlowSequenceEnd,
        pos: { line: start_line, col: start_col },
      })
      self.advance()
    } else if c == '{' {
      // 流映射开始
      tokens.push({
        token: FlowMappingStart,
        pos: { line: start_line, col: start_col },
      })
      self.advance()
    } else if c == '}' {
      // 流映射结束
      tokens.push({
        token: FlowMappingEnd,
        pos: { line: start_line, col: start_col },
      })
      self.advance()
    } else if c == ',' {
      // 流元素分隔符
      tokens.push({ token: Comma, pos: { line: start_line, col: start_col } })
      self.advance()
    } else if c == '&' {
      // 锚点 &name
      self.advance()
      match self.read_anchor_name() {
        Ok(name) =>
          tokens.push({
            token: Anchor(name),
            pos: { line: start_line, col: start_col },
          })
        Err(e) => return Err(e)
      }
    } else if c == '*' {
      // 别名 *name
      self.advance()
      match self.read_anchor_name() {
        Ok(name) =>
          tokens.push({
            token: Alias(name),
            pos: { line: start_line, col: start_col },
          })
        Err(e) => return Err(e)
      }
    } else {
      match self.read_scalar() {
        Ok(scalar) => {
          self.skip_spaces()
          if self.pos.val < self.len && self.current_char() == ':' {
            tokens.push({
              token: Key(scalar),
              pos: { line: start_line, col: start_col },
            })
            self.advance()
            if self.pos.val < self.len {
              let next_c = self.current_char()
              if next_c == ' ' || next_c == '\t' {
                self.skip_spaces()
              }
            }
            tokens.push({
              token: ValueIndicator,
              pos: { line: self.line.val, col: self.col.val },
            })
          } else {
            tokens.push({
              token: Scalar(scalar),
              pos: { line: start_line, col: start_col },
            })
          }
        }
        Err(e) => return Err(e)
      }
    }
  }
  tokens.push({ token: Eof, pos: { line: self.line.val, col: self.col.val } })
  Ok(tokens)
}

///|
/// 获取当前字符
fn Lexer::current_char(self : Lexer) -> Char {
  self.chars[self.pos.val]
}

///|
/// 前进一个字符
fn Lexer::advance(self : Lexer) -> Unit {
  if self.pos.val < self.len {
    if self.chars[self.pos.val] == '\n' {
      self.line.val = self.line.val + 1
      self.col.val = 1
    } else {
      self.col.val = self.col.val + 1
    }
    self.pos.val = self.pos.val + 1
  }
}

///|
/// 跳过空格和制表符
fn Lexer::skip_spaces(self : Lexer) -> Unit {
  while self.pos.val < self.len {
    let c = self.current_char()
    if c == ' ' || c == '\t' {
      self.advance()
    } else {
      break
    }
  }
}

///|
/// 跳过注释到行尾
fn Lexer::skip_comment(self : Lexer) -> Unit {
  while self.pos.val < self.len && self.current_char() != '\n' {
    self.advance()
  }
}

///|
/// 检查是否是块序列项('- ' 在行首或缩进后)
fn Lexer::is_block_entry(self : Lexer) -> Bool {
  if self.pos.val + 1 >= self.len {
    return false
  }
  let next_c = self.chars[self.pos.val + 1]
  next_c == ' ' || next_c == '\t' || next_c == '\n' || next_c == '\r'
}

///|
/// 匹配特定字符串
fn Lexer::match_str(self : Lexer, s : String) -> Bool {
  let s_chars = s.to_array()
  let s_len = s_chars.length()
  if self.pos.val + s_len > self.len {
    return false
  }
  let mut i = 0
  while i < s_len {
    if self.chars[self.pos.val + i] != s_chars[i] {
      return false
    }
    i = i + 1
  }
  // 检查后面是否是空白、行尾或注释
  if self.pos.val + s_len < self.len {
    let next_c = self.chars[self.pos.val + s_len]
    if next_c != ' ' &&
      next_c != '\t' &&
      next_c != '\n' &&
      next_c != '\r' &&
      next_c != '#' {
      return false
    }
  }
  // 匹配成功, 前进
  i = 0
  while i < s_len {
    self.advance()
    i = i + 1
  }
  true
}

///|
/// 读取标量值
fn Lexer::read_scalar(self : Lexer) -> Result[String, YamlError] {
  let start_line = self.line.val
  let start_col = self.col.val
  let scalar_chars : Array[Char] = []
  while self.pos.val < self.len {
    let c = self.current_char()
    // 标量结束条件: 换行、回车
    if c == '\n' || c == '\r' {
      break
    }
    // 标量结束条件: 流样式分隔符
    if c == '[' || c == ']' || c == '{' || c == '}' || c == ',' {
      break
    }
    // 标量结束条件: 冒号后跟空白(表示 key-value 分隔)
    if c == ':' {
      if self.pos.val + 1 < self.len {
        let next_c = self.chars[self.pos.val + 1]
        if next_c == ' ' ||
          next_c == '\t' ||
          next_c == '\n' ||
          next_c == '\r' ||
          next_c == '}' ||
          next_c == ',' ||
          next_c == ']' {
          break
        }
      } else {
        break
      }
    }
    // 标量结束条件: 注释开始(# 前面有空白)
    if c == '#' {
      if scalar_chars.length() > 0 {
        let prev_c = self.chars[self.pos.val - 1]
        if prev_c == ' ' || prev_c == '\t' {
          break
        }
      }
    }
    scalar_chars.push(c)
    self.advance()
  }
  if scalar_chars.length() == 0 {
    return Err(LexError(line=start_line, col=start_col, msg="空的标量值"))
  }
  Ok(String::from_array(scalar_chars).trim_space().to_string())
}

///|
/// 读取双引号字符串(支持转义序列)
fn Lexer::read_double_quoted(self : Lexer) -> Result[String, YamlError] {
  let start_line = self.line.val
  let start_col = self.col.val
  // 跳过开头的双引号
  self.advance()
  let content_chars : Array[Char] = []
  while self.pos.val < self.len {
    let c = self.current_char()
    if c == '\\' {
      // 转义序列
      self.advance()
      if self.pos.val >= self.len {
        return Err(
          LexError(
            line=self.line.val,
            col=self.col.val,
            msg="双引号字符串未闭合",
          ),
        )
      }
      let esc = self.current_char()
      match esc {
        '"' => content_chars.push('"')
        '\\' => content_chars.push('\\')
        '/' => content_chars.push('/')
        'n' => content_chars.push('\n')
        't' => content_chars.push('\t')
        'r' => content_chars.push('\r')
        'b' => content_chars.push('\u{0008}')
        'f' => content_chars.push('\u{000C}')
        '0' => content_chars.push('\u{0000}')
        _ => {
          // 未知转义序列, 保留原字符
          content_chars.push('\\')
          content_chars.push(esc)
        }
      }
      self.advance()
    } else if c == '"' {
      // 闭合双引号
      self.advance()
      return Ok(String::from_array(content_chars))
    } else if c == '\n' || c == '\r' {
      // 双引号字符串不能跨行(简单实现)
      return Err(
        LexError(
          line=start_line,
          col=start_col,
          msg="双引号字符串不能跨行",
        ),
      )
    } else {
      content_chars.push(c)
      self.advance()
    }
  }
  Err(
    LexError(line=start_line, col=start_col, msg="双引号字符串未闭合"),
  )
}

///|
/// 读取单引号字符串(字面量, 仅 '' 表示一个单引号)
fn Lexer::read_single_quoted(self : Lexer) -> Result[String, YamlError] {
  let start_line = self.line.val
  let start_col = self.col.val
  // 跳过开头的单引号
  self.advance()
  let content_chars : Array[Char] = []
  while self.pos.val < self.len {
    let c = self.current_char()
    if c == '\'' {
      self.advance()
      if self.pos.val < self.len && self.current_char() == '\'' {
        // '' 转义为一个单引号
        content_chars.push('\'')
        self.advance()
      } else {
        // 闭合单引号
        return Ok(String::from_array(content_chars))
      }
    } else if c == '\n' || c == '\r' {
      // 单引号字符串不能跨行(简单实现)
      return Err(
        LexError(
          line=start_line,
          col=start_col,
          msg="单引号字符串不能跨行",
        ),
      )
    } else {
      content_chars.push(c)
      self.advance()
    }
  }
  Err(
    LexError(line=start_line, col=start_col, msg="单引号字符串未闭合"),
  )
}

///|
/// 检查当前位置的 | 或 > 是否是块标量指示符
/// (后面必须是行尾、空白+行尾、或数字/+-后接行尾)
fn Lexer::is_block_scalar_indicator(self : Lexer) -> Bool {
  let mut i = self.pos.val + 1
  // 跳过可选的数字(缩进指示符)和 +/-(chomp指示符)
  while i < self.len {
    let c = self.chars[i]
    if c >= '1' && c <= '9' {
      i = i + 1
    } else if c == '+' || c == '-' {
      i = i + 1
      break
    } else {
      break
    }
  }
  // 后面必须是空白字符后接行尾, 或直接行尾
  while i < self.len {
    let c = self.chars[i]
    if c == ' ' || c == '\t' {
      i = i + 1
    } else if c == '\n' || c == '\r' {
      return true
    } else {
      return false
    }
  }
  // 文件末尾也算
  true
}

///|
/// 跳过块标量的缩进/chomp指示符(数字和+/-)
/// 返回 chomp 模式: 0=clip(默认), 1=keep(+), -1=strip(-)
fn Lexer::skip_block_indicators(self : Lexer) -> Int {
  let mut chomp = 0 // 0=clip, 1=keep, -1=strip
  while self.pos.val < self.len {
    let c = self.current_char()
    if c >= '1' && c <= '9' {
      self.advance()
    } else if c == '+' {
      chomp = 1
      self.advance()
      break
    } else if c == '-' {
      chomp = -1
      self.advance()
      break
    } else {
      break
    }
  }
  chomp
}

///|
/// 跳过到行尾(包括换行符)
fn Lexer::skip_to_eol(self : Lexer) -> Unit {
  while self.pos.val < self.len {
    let c = self.current_char()
    if c == '\n' {
      self.advance()
      return
    } else if c == '\r' {
      self.advance()
      if self.pos.val < self.len && self.current_char() == '\n' {
        self.advance()
      }
      return
    }
    self.advance()
  }
}

///|
/// 读取一行(从当前位置到换行符), 返回内容和是否遇到换行
fn Lexer::read_line_raw(self : Lexer) -> String {
  let line_chars : Array[Char] = []
  while self.pos.val < self.len {
    let c = self.current_char()
    if c == '\n' {
      self.advance()
      break
    } else if c == '\r' {
      self.advance()
      if self.pos.val < self.len && self.current_char() == '\n' {
        self.advance()
      }
      break
    }
    line_chars.push(c)
    self.advance()
  }
  String::from_array(line_chars)
}

///|
/// 检查当前位置是否在文件末尾或遇到更少缩进的内容
fn Lexer::peek_line_indent(self : Lexer) -> Int {
  let mut i = self.pos.val
  let mut indent = 0
  while i < self.len {
    let c = self.chars[i]
    if c == ' ' {
      indent = indent + 1
      i = i + 1
    } else if c == '\t' {
      indent = indent + 1
      i = i + 1
    } else {
      break
    }
  }
  // 如果行是空的(只有换行), 返回 -1
  if i < self.len && (self.chars[i] == '\n' || self.chars[i] == '\r') {
    return -1
  }
  // 如果到文件末尾, 返回 -2
  if i >= self.len {
    return -2
  }
  indent
}

///|
/// 读取块标量内容
/// chomp: 0=clip(默认), 1=keep(+), -1=strip(-)
/// is_literal: true=|(字面量), false=> (折叠)
fn Lexer::read_block_content(
  self : Lexer,
  chomp : Int,
  is_literal : Bool
) -> Result[String, YamlError] {
  let content_lines : Array[String] = []
  let mut content_indent = -1

  // 首先确定内容的缩进级别(从第一个非空行开始)
  // 跳过前导空行
  while self.pos.val < self.len {
    let indent = self.peek_line_indent()
    if indent == -2 {
      // 文件末尾
      return Ok("")
    }
    if indent == -1 {
      // 空行, 读取并跳过
      let _ = self.read_line_raw()
      content_lines.push("")
    } else {
      if content_indent == -1 {
        content_indent = indent
      }
      break
    }
  }
  if content_indent == -1 {
    return Ok("")
  }

  // 现在逐行读取内容
  let mut trailing_newlines = 0
  while self.pos.val < self.len {
    let saved_pos = self.pos.val
    let saved_line = self.line.val
    let saved_col = self.col.val
    let indent = self.peek_line_indent()
    if indent == -2 {
      // 文件末尾
      break
    }
    if indent >= 0 && indent < content_indent {
      // 缩进小于内容缩进, 块结束
      // 回退位置
      self.pos.val = saved_pos
      self.line.val = saved_line
      self.col.val = saved_col
      break
    }

    // 读取这一行
    let raw_line = self.read_line_raw()
    if indent == -1 {
      // 空行
      content_lines.push("")
      trailing_newlines = trailing_newlines + 1
    } else {
      // 去掉前导 content_indent 个空格
      let line_after_indent = if raw_line.length() > content_indent {
        raw_line.substring(start=content_indent)
      } else {
        ""
      }
      content_lines.push(line_after_indent)
      trailing_newlines = 0
    }
  }

  // 处理 trailing newlines 和 chomp
  // 先移除末尾空行, 根据chomp决定保留多少
  while content_lines.length() > 0 &&
        content_lines[content_lines.length() - 1] == "" {
    let _ = content_lines.pop()

  }

  // 根据 is_literal 和 chomp 拼接结果
  let result = if is_literal {
    // 字面量: 行之间用 \n 连接
    let mut s = ""
    let mut i = 0
    while i < content_lines.length() {
      if i > 0 {
        s = s + "\n"
      }
      s = s + content_lines[i]
      i = i + 1
    }
    // chomp处理
    if chomp >= 0 {
      // clip 或 keep: 末尾加换行
      s = s + "\n"
    }
    s
  } else {
    // 折叠: 非空行之间的换行变成空格, 空行表示段落分隔(保留换行)
    let mut s = ""
    let mut prev_empty = false
    let mut i = 0
    while i < content_lines.length() {
      let line = content_lines[i]
      if line == "" {
        // 空行表示段落分隔
        if s.length() > 0 && not(s.has_suffix("\n")) {
          s = s + "\n"
        }
        s = s + "\n"
        prev_empty = true
      } else {
        if s.length() > 0 && not(prev_empty) && not(s.has_suffix("\n")) {
          s = s + " "
        }
        s = s + line
        prev_empty = false
      }
      i = i + 1
    }
    // chomp处理
    if chomp >= 0 {
      s = s + "\n"
    }
    s
  }
  Ok(result)
}

///|
/// 读取锚点/别名名称(字母、数字、下划线、连字符)
fn Lexer::read_anchor_name(self : Lexer) -> Result[String, YamlError] {
  let start_line = self.line.val
  let start_col = self.col.val
  let name_chars : Array[Char] = []
  while self.pos.val < self.len {
    let c = self.current_char()
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' {
      name_chars.push(c)
      self.advance()
    } else {
      break
    }
  }
  if name_chars.length() == 0 {
    return Err(
      LexError(
        line=start_line,
        col=start_col,
        msg="锚点/别名名称不能为空",
      ),
    )
  }
  Ok(String::from_array(name_chars))
}
