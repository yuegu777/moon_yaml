///|
/// 文件用途: Moon YAML 核心类型定义
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.0
/// 风险提示: 当前为早期版本, API 可能发生变化

///|
/// YAML 值类型(对应 YAML 1.2 Core Schema)
pub(all) enum YamlValue {
    Null
    Bool(Bool)
    Int(Int)
    Double(Double)
    String(String)
    Array(Array[YamlValue])
    Object(Map[String, YamlValue])
}

///|
/// YAML 解析错误
pub(all) enum YamlError {
    LexError(line~: Int, col~: Int, msg~: String)
    ParseError(line~: Int, col~: Int, msg~: String)
    UnexpectedToken(expected~: String, got~: String)
    UnsupportedFeature(feature~: String)
}

///|
/// 将错误转为可读字符串
pub fn YamlError::to_string(self: YamlError) -> String {
    match self {
        LexError(line~, col~, msg~) =>
            "词法错误: 第 " + line.to_string() + " 行第 " + col.to_string() + " 列: " + msg
        ParseError(line~, col~, msg~) =>
            "语法错误: 第 " + line.to_string() + " 行第 " + col.to_string() + " 列: " + msg
        UnexpectedToken(expected~, got~) =>
            "预期 " + expected + ", 实际得到 " + got
        UnsupportedFeature(feature~) =>
            "不支持的功能: " + feature
    }
}

///|
/// 词法 Token
pub enum Token {
    DocumentStart
    DocumentEnd
    Key(String)
    ValueIndicator
    BlockEntry
    Scalar(String)
    DoubleQuoted(String)
    SingleQuoted(String)
    FlowSequenceStart
    FlowSequenceEnd
    FlowMappingStart
    FlowMappingEnd
    Comma
    Anchor(String)
    Alias(String)
    NewLine
    Eof
}

///|
/// Token 位置信息
pub(all) struct TokenPos {
    line: Int
    col: Int
}

///|
/// 带位置的 Token
pub(all) struct TokenWithPos {
    token: Token
    pos: TokenPos
}

///|
/// 解析器配置
pub(all) struct ParserConfig {
    strict: Bool
    max_depth: Int
}

///|
/// 创建默认配置
pub fn ParserConfig::default() -> ParserConfig {
    { strict: false, max_depth: 50 }
}
