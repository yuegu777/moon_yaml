///|
/// 文件用途: YAML 词法分析器 - 将输入字符串分词为 Token 流
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.0
/// 风险提示: 当前为最简实现, 部分高级功能待完善

///|
/// 词法分析器
struct Lexer {
    input: String
    chars: Array[Char]
    pos: Ref[Int]
    line: Ref[Int]
    col: Ref[Int]
    len: Int
}

///|
/// 创建新的词法分析器
fn Lexer::new(input: String) -> Lexer {
    let chars = input.to_array()
    {
        input: input,
        chars: chars,
        pos: { val: 0 },
        line: { val: 1 },
        col: { val: 1 },
        len: chars.length()
    }
}

///|
/// 主扫描入口, 将输入字符串分词为 Token 流
fn Lexer::scan(self: Lexer) -> Result[Array[TokenWithPos], YamlError] {
    let tokens: Array[TokenWithPos] = []

    while self.pos.val < self.len {
        self.skip_spaces()

        if self.pos.val >= self.len {
            break
        }

        let c = self.current_char()
        let start_line = self.line.val
        let start_col = self.col.val

        if c == '\n' {
            tokens.push({
                token: NewLine,
                pos: { line: start_line, col: start_col }
            })
            self.advance()
        } else if c == '\r' {
            self.advance()
            if self.pos.val < self.len && self.current_char() == '\n' {
                self.advance()
            }
            tokens.push({
                token: NewLine,
                pos: { line: start_line, col: start_col }
            })
        } else if c == '#' {
            self.skip_comment()
        } else if c == '-' && self.match_str("---") {
            tokens.push({
                token: DocumentStart,
                pos: { line: start_line, col: start_col }
            })
        } else if c == '.' && self.match_str("...") {
            tokens.push({
                token: DocumentEnd,
                pos: { line: start_line, col: start_col }
            })
        } else if c == '-' && self.is_block_entry() {
            tokens.push({
                token: BlockEntry,
                pos: { line: start_line, col: start_col }
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
                            pos: { line: start_line, col: start_col }
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
                            pos: { line: self.line.val, col: self.col.val }
                        })
                    } else {
                        tokens.push({
                            token: DoubleQuoted(content),
                            pos: { line: start_line, col: start_col }
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
                            pos: { line: start_line, col: start_col }
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
                            pos: { line: self.line.val, col: self.col.val }
                        })
                    } else {
                        tokens.push({
                            token: SingleQuoted(content),
                            pos: { line: start_line, col: start_col }
                        })
                    }
                }
                Err(e) => return Err(e)
            }
        } else {
            match self.read_scalar() {
                Ok(scalar) => {
                    self.skip_spaces()
                    if self.pos.val < self.len && self.current_char() == ':' {
                        tokens.push({
                            token: Key(scalar),
                            pos: { line: start_line, col: start_col }
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
                            pos: { line: self.line.val, col: self.col.val }
                        })
                    } else {
                        tokens.push({
                            token: Scalar(scalar),
                            pos: { line: start_line, col: start_col }
                        })
                    }
                }
                Err(e) => return Err(e)
            }
        }
    }

    tokens.push({
        token: Eof,
        pos: { line: self.line.val, col: self.col.val }
    })

    Ok(tokens)
}

///|
/// 获取当前字符
fn Lexer::current_char(self: Lexer) -> Char {
    self.chars[self.pos.val]
}

///|
/// 前进一个字符
fn Lexer::advance(self: Lexer) -> Unit {
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
fn Lexer::skip_spaces(self: Lexer) -> Unit {
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
fn Lexer::skip_comment(self: Lexer) -> Unit {
    while self.pos.val < self.len && self.current_char() != '\n' {
        self.advance()
    }
}

///|
/// 检查是否是块序列项('- ' 在行首或缩进后)
fn Lexer::is_block_entry(self: Lexer) -> Bool {
    if self.pos.val + 1 >= self.len {
        return false
    }
    let next_c = self.chars[self.pos.val + 1]
    next_c == ' ' || next_c == '\t' || next_c == '\n' || next_c == '\r'
}

///|
/// 匹配特定字符串
fn Lexer::match_str(self: Lexer, s: String) -> Bool {
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
        if next_c != ' ' && next_c != '\t' && next_c != '\n' &&
           next_c != '\r' && next_c != '#' {
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
fn Lexer::read_scalar(self: Lexer) -> Result[String, YamlError] {
    let start_pos = self.pos.val
    let start_line = self.line.val
    let start_col = self.col.val
    let scalar_chars: Array[Char] = []

    while self.pos.val < self.len {
        let c = self.current_char()
        // 标量结束条件: 换行、回车
        if c == '\n' || c == '\r' {
            break
        }
        // 标量结束条件: 冒号后跟空白(表示 key-value 分隔)
        if c == ':' {
            if self.pos.val + 1 < self.len {
                let next_c = self.chars[self.pos.val + 1]
                if next_c == ' ' || next_c == '\t' || next_c == '\n' ||
                   next_c == '\r' {
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
fn Lexer::read_double_quoted(self: Lexer) -> Result[String, YamlError] {
    let start_line = self.line.val
    let start_col = self.col.val
    // 跳过开头的双引号
    self.advance()
    let content_chars: Array[Char] = []

    while self.pos.val < self.len {
        let c = self.current_char()
        if c == '\\' {
            // 转义序列
            self.advance()
            if self.pos.val >= self.len {
                return Err(LexError(
                    line=self.line.val,
                    col=self.col.val,
                    msg="双引号字符串未闭合"
                ))
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
            return Err(LexError(
                line=start_line,
                col=start_col,
                msg="双引号字符串不能跨行"
            ))
        } else {
            content_chars.push(c)
            self.advance()
        }
    }

    Err(LexError(
        line=start_line,
        col=start_col,
        msg="双引号字符串未闭合"
    ))
}

///|
/// 读取单引号字符串(字面量, 仅 '' 表示一个单引号)
fn Lexer::read_single_quoted(self: Lexer) -> Result[String, YamlError] {
    let start_line = self.line.val
    let start_col = self.col.val
    // 跳过开头的单引号
    self.advance()
    let content_chars: Array[Char] = []

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
            return Err(LexError(
                line=start_line,
                col=start_col,
                msg="单引号字符串不能跨行"
            ))
        } else {
            content_chars.push(c)
            self.advance()
        }
    }

    Err(LexError(
        line=start_line,
        col=start_col,
        msg="单引号字符串未闭合"
    ))
}
