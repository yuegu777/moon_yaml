# moon_yaml

> 一个遵循 YAML 1.2 Core Schema 标准的 MoonBit YAML 解析与生成库

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.0-blue.svg)](https://www.moonbitlang.com/)

## 项目简介

Moon YAML 是一个为 MoonBit 生态打造的 YAML 1.2 Core Schema 解析与生成库，参考 Rust 生态的 [yaml-rust](https://github.com/chyh1990/yaml-rust) 和 Go 生态的 [go-yaml](https://github.com/go-yaml/yaml) 设计理念，使用 MoonBit 原生语法和类型系统重新实现。

本项目致力于为配置管理、CI/CD 流水线、Kubernetes 清单处理等场景提供标准化的 YAML 读写支持。开发者可利用 MoonBit 的 Wasm 后端，在浏览器、边缘计算、服务端等场景中高效处理 YAML 数据。

## 特性

- YAML 1.2 Core Schema 兼容 - 完整支持标量类型自动推断
- 块映射解析 - 支持 `key: value` 格式的嵌套对象
- 块序列解析 - 支持 `- item` 格式的数组
- 流样式支持 - 支持 `[a, b, c]` 内联序列和 `{k: v}` 内联映射
- 字符串处理 - 支持双引号、单引号、字面量块标量(`|`)、折叠块标量(`>`)
- 锚点与别名 - 支持 `&anchor` 定义锚点和 `*alias` 引用
- 合并键 - 支持 `<<: *anchor` 映射合并继承
- 多文档流 - 支持 `---` 分隔的多个 YAML 文档
- 标量类型推断 - 自动识别 null、bool、int(含八进制/二进制/下划线分隔符)、float(含科学计数法/.inf/.nan)、string
- 错误定位 - 精确的行号、列号错误位置信息
- 读写双向 - 同时提供 YAML 解析与生成能力
- 纯 MoonBit 实现 - 无外部依赖，Wasm 友好

## 适用场景

- **配置文件解析** - Kubernetes、Docker Compose、GitHub Actions 等 YAML 配置
- **CI/CD 流水线** - 自动化脚本中的 YAML 配置读取与生成
- **数据序列化** - 结构化数据的 YAML 格式导入导出
- **浏览器端配置处理** - 基于 Wasm 在前端直接处理 YAML
- **边缘计算场景** - 资源受限设备上的 YAML 配置解析

## 项目结构

```
moon_yaml/
├── src/
│   ├── lib.mbt        # 主库入口，导出 YamlLoader / YamlEmitter API
│   ├── types.mbt      # 核心类型定义（YamlValue、YamlError、Token）
│   ├── lexer.mbt      # 词法分析器实现
│   ├── parser.mbt     # 语法分析器实现
│   └── emitter.mbt    # YAML 序列化生成器
├── test/
│   └── yaml_test.mbt  # 单元测试
├── moon.mod.json      # MoonBit 项目配置
├── LICENSE            # MIT 许可证
└── README.md          # 项目说明文档
```

## 快速开始

### 环境要求

- MoonBit 工具链（moon、moonc）
- 支持 Wasm-GC 后端

### 安装 MoonBit

如果尚未安装 MoonBit 工具链，请参考 [MoonBit 官方安装指南](https://www.moonbitlang.com/download/)进行安装。

验证安装：

```bash
moon version
```

### 克隆项目

```bash
git clone https://github.com/yuegu777/moon_yaml.git
cd moon_yaml
```

### 构建项目

```bash
moon build
```

构建产物将输出到 `target/wasm-gc/release/build/` 目录。

### 运行测试

```bash
moon test
```

### 在你的项目中使用

在 `moon.mod.json` 中添加依赖：

```json
{
  "dependencies": {
    "yuegu777/moon_yaml": "^0.1.0"
  }
}
```

## 使用示例

### 基础解析

```moonbit
// 解析 YAML 字符串
let input = "name: Alice\nage: 30"
let loader = YamlLoader::new()

match loader.load_single(input) {
  Ok(doc) => {
    // 访问映射字段
    match doc {
      Object(obj) => {
        match obj["name"] {
          Some(String(name)) => println("Name: \(name)")
          _ => {}
        }
      }
      _ => {}
    }
  }
  Err(e) => println("解析失败: \(e)")
}
```

### 解析序列

```moonbit
let input = "- apple\n- banana\n- cherry"
let loader = YamlLoader::new()

match loader.load_single(input) {
  Ok(Array(arr)) => {
    for item in arr {
      println(item.to_string())
    }
  }
  _ => {}
}
```

### 解析嵌套结构

```moonbit
let input =
  "person:\n" +
  "  name: Bob\n" +
  "  age: 25\n" +
  "  hobbies:\n" +
  "    - reading\n" +
  "    - coding"

let loader = YamlLoader::new()
let doc = loader.load_single(input)?
```

### 解析多文档

```moonbit
let input =
  "---\n" +
  "doc1: value1\n" +
  "---\n" +
  "doc2: value2"

let loader = YamlLoader::new()
let docs = loader.load_from_str(input)?
// docs.length() == 2
```

### 生成 YAML

```moonbit
let value = Object(Map::from_array([
  ("name", String("Alice")),
  ("age", Int(30))
]))

let emitter = YamlEmitter::new()
let yaml_str = emitter.emit(value)
println(yaml_str)
// 输出:
// name: Alice
// age: 30
```

### 带缩进配置

```moonbit
let emitter = YamlEmitter::new().with_indent(4)
let yaml_str = emitter.emit(value)
```

### 标量类型自动推断

```moonbit
// null
let doc1 = loader.load_single("null")?  // Null
let doc2 = loader.load_single("~")?     // Null

// bool
let doc3 = loader.load_single("true")?  // Bool(true)
let doc4 = loader.load_single("false")? // Bool(false)

// int
let doc5 = loader.load_single("42")?    // Int(42)
let doc6 = loader.load_single("0x1A")?  // Int(26)

// float
let doc7 = loader.load_single("3.14")?  // Double(3.14)

// string
let doc8 = loader.load_single("hello")? // String("hello")
```

## API 参考

### YamlLoader（加载器）

| 方法 | 说明 |
|------|------|
| `YamlLoader::new()` | 创建新的 YAML 加载器 |
| `.with_config(config: ParserConfig)` | 设置解析器配置 |
| `.load_from_str(input: String)` | 解析 YAML 字符串，返回 `Result[Array[YamlValue], YamlError]` |
| `.load_single(input: String)` | 解析单个 YAML 文档，返回 `Result[YamlValue, YamlError]` |

### YamlEmitter（发射器）

| 方法 | 说明 |
|------|------|
| `YamlEmitter::new()` | 创建新的 YAML 发射器 |
| `.with_indent(size: Int)` | 设置缩进空格数（默认 2） |
| `.emit(doc: YamlValue)` | 将单个文档序列化为 YAML 字符串 |
| `.emit_documents(docs: Array[YamlValue])` | 将文档列表序列化为 YAML 字符串 |

### YamlValue（值类型）

| 变体 | 说明 |
|------|------|
| `Null` | 空值 |
| `Bool(Bool)` | 布尔值 |
| `Int(Int)` | 整数值 |
| `Double(Double)` | 浮点数值 |
| `String(String)` | 字符串值 |
| `Array(Array[YamlValue])` | 数组 |
| `Object(Map[String, YamlValue])` | 对象/映射 |

### YamlError（错误类型）

| 错误类型 | 说明 |
|----------|------|
| `LexError(line, col, msg)` | 词法错误，包含行号、列号、错误信息 |
| `ParseError(line, col, msg)` | 语法错误，包含行号、列号、错误信息 |
| `UnexpectedToken(expected, got)` | 意外的 Token |
| `UnsupportedFeature(feature)` | 不支持的功能 |

### ParserConfig（解析器配置）

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `strict: Bool` | 严格模式 | `false` |
| `max_depth: Int` | 最大嵌套深度 | `50` |

## 错误处理

所有解析操作都返回 `Result` 类型，建议使用模式匹配进行错误处理：

```moonbit
match loader.load_single(input) {
  Ok(doc) => {
    // 处理成功结果
  }
  Err(e) => {
    match e {
      LexError(line, col, msg) =>
        println("第 \(line) 行第 \(col) 列词法错误: \(msg)")
      ParseError(line, col, msg) =>
        println("第 \(line) 行第 \(col) 列语法错误: \(msg)")
      UnexpectedToken(expected, got) =>
        println("预期 \(expected)，实际得到 \(got)")
      UnsupportedFeature(feature) =>
        println("不支持的功能: \(feature)")
    }
  }
}
```

## 开发指南

### 目录规范

- 源码放在 `src/` 目录下
- 测试放在 `test/` 目录下
- 测试文件以 `_test.mbt` 后缀命名

### 命名规范

- 类型名：大驼峰（PascalCase），如 `YamlValue`
- 函数/方法名：小驼峰（camelCase），如 `load_from_str`
- 变量名：小驼峰（camelCase），如 `yaml_input`

### 提交代码

请确保：

1. 所有测试通过：`moon test`
2. 代码格式规范
3. 新增功能附带相应的测试用例

## 路线图

- [x] 流样式支持（`[]` / `{}`）
- [x] 锚点与引用（`&` / `*`）
- [x] 块标量（`|` 字面量 / `>` 折叠）
- [x] 合并键（`<<`）
- [x] 更丰富的标量样式（单引号、双引号）
- [x] 多文档支持（`---` / `...`）
- [ ] 自定义标签（`!tag`）
- [ ] 标签句柄（`!!str` / `!!int` / `!!float`）
- [ ] 循环引用检测
- [ ] 结构化反序列化 API（类似 serde）
- [ ] 性能优化与基准测试
- [ ] 更丰富的测试用例（目标 100+）

## 许可证

本项目采用 [MIT License](LICENSE) 许可证。

## 参考项目

- [yaml-rust](https://github.com/chyh1990/yaml-rust) - Rust YAML 1.2 实现（MIT / Apache-2.0）
- [go-yaml](https://github.com/go-yaml/yaml) - Go YAML 解析库（MIT / Apache-2.0）
- [yaml-cpp](https://github.com/jbeder/yaml-cpp) - C++ YAML 解析库（MIT）

## 贡献

欢迎提交 Issue 和 Pull Request！

---

**项目地址：** https://github.com/yuegu777/moon_yaml
