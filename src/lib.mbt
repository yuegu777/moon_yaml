///|
/// 文件用途: Moon YAML 主库入口, 导出 YAML 解析与生成的核心 API
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.0
/// 风险提示: 当前为早期版本, API 可能发生变化

///|
/// YAML 文档加载器
pub struct YamlLoader {
  config : ParserConfig
}

///|
/// 创建新的加载器
pub fn YamlLoader::new() -> YamlLoader {
  { config: ParserConfig::default() }
}

///|
/// 设置配置
pub fn YamlLoader::with_config(
  _ : YamlLoader,
  config : ParserConfig
) -> YamlLoader {
  { config, }
}

///|
/// 解析 YAML 字符串, 返回文档列表
pub fn YamlLoader::load_from_str(
  self : YamlLoader,
  input : String
) -> Result[Array[YamlValue], YamlError] {
  let lexer = Lexer::new(input)
  match lexer.scan() {
    Ok(tokens) => {
      let parser = Parser::new(tokens, self.config)
      parser.parse()
    }
    Err(e) => Err(e)
  }
}

///|
/// 解析单个 YAML 文档
pub fn YamlLoader::load_single(
  self : YamlLoader,
  input : String
) -> Result[YamlValue, YamlError] {
  match self.load_from_str(input) {
    Ok(docs) => if docs.length() == 0 { Ok(Null) } else { Ok(docs[0]) }
    Err(e) => Err(e)
  }
}

///|
/// YAML 文档发射器
pub struct YamlEmitter {
  indent_size : Int
}

///|
/// 创建新的发射器
pub fn YamlEmitter::new() -> YamlEmitter {
  { indent_size: 2 }
}

///|
/// 设置缩进
pub fn YamlEmitter::with_indent(_ : YamlEmitter, size : Int) -> YamlEmitter {
  { indent_size: size }
}

///|
/// 将单个文档序列化为 YAML 字符串
pub fn YamlEmitter::emit(self : YamlEmitter, doc : YamlValue) -> String {
  let emitter = Emitter::new().with_indent(self.indent_size)
  emitter.emit(doc)
}

///|
/// 将文档列表序列化为 YAML 字符串
pub fn YamlEmitter::emit_documents(
  self : YamlEmitter,
  docs : Array[YamlValue]
) -> String {
  let emitter = Emitter::new().with_indent(self.indent_size)
  emitter.emit_documents(docs)
}

///|
/// 便捷函数: 解析 YAML 字符串
pub fn parse_yaml(input : String) -> Result[Array[YamlValue], YamlError] {
  let loader = YamlLoader::new()
  loader.load_from_str(input)
}

///|
/// 便捷函数: 生成 YAML 字符串
pub fn emit_yaml(doc : YamlValue) -> String {
  let emitter = YamlEmitter::new()
  emitter.emit(doc)
}
