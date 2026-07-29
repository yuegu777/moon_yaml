# moon_yaml 项目申报书

## 基本信息

● 项目名称：Moon YAML: YAML 1.2 Core Schema 解析器的 MoonBit 实现
● 参赛者：胡彪
● 联系方式：18327794809
● GitHub 仓库链接：https://github.com/yuegu777/moon_yaml
● 项目方向：MoonBit 系统能力于运行时框架 / 面向特定格式（反）序列化工具
● 是否为移植项目：是

## 项目简介

Moon YAML 是一个为 MoonBit 生态打造的 YAML 1.2 Core Schema 解析与生成库，参考 Rust 生态的 [yaml-rust](https://github.com/chyh1990/yaml-rust) 和 Go 生态的 [go-yaml](https://github.com/go-yaml/yaml) 设计理念，使用 MoonBit 原生语法和类型系统重新实现。

YAML 作为现代云原生生态的事实标准配置语言，广泛应用于 Kubernetes 清单、Docker Compose、GitHub Actions、CI/CD 流水线等场景。MoonBit 生态目前缺乏原生的 YAML 解析能力，开发者需要借助 JavaScript interop 或其他外部工具间接处理 YAML 数据，增加了构建复杂度和运行时开销。

本项目致力于为 MoonBit 生态提供标准化的 YAML 读写支持，使开发者能够直接在前端（Wasm）、服务端和边缘计算场景中高效解析和生成 YAML 数据，特别适用于配置管理、DevOps 工具链和数据序列化等场景。

## 核心功能范围

● 遵循 YAML 1.2 Core Schema 标准，提供完整的标量类型自动推断；
● 支持块映射解析（`key: value` 格式），包括多层嵌套对象；
● 支持块序列解析（`- item` 格式），包括嵌套数组与对象混合结构；
● 支持多文档流（`---` 分隔的多个 YAML 文档）；
● 标量类型自动推断：自动识别 null、bool、int（含十六进制）、float、string；
● 错误精确定位：提供行号、列号信息，方便排查异常数据；
● 读写双向能力：同时提供 YAML 解析（Loader）与生成（Emitter）API；
● 可配置解析器：支持严格模式、最大嵌套深度等配置选项；
● 纯 MoonBit 实现，零外部依赖，Wasm-GC 后端友好；
● 提供不少于 10 个 MoonBit 单元测试文件，覆盖标量、映射、序列、嵌套、多文档、往返一致性等场景；
● 提供 README 使用示例，覆盖解析、生成、多文档和错误处理。

## 移植或参考说明

● 参考项目一名称：yaml-rust
● 参考项目一链接：https://github.com/chyh1990/yaml-rust
● 参考项目一许可证：MIT / Apache-2.0

● 参考项目二名称：go-yaml / yaml.v3
● 参考项目二链接：https://github.com/go-yaml/yaml
● 参考项目二许可证：MIT / Apache-2.0

● 本项目许可证：MIT

与参考项目相比，本项目会做以下优化和重新设计：

● 使用 MoonBit 原生语法、类型系统和模式匹配重新组织代码，而非复制 Rust/Go 的工程结构；
● 基于 MoonBit 的 enum 和 struct 定义 YAML AST（`YamlValue`），利用模式匹配实现类型安全的访问；
● 适配 MoonBit 的 `Ref` 可变状态模型，替代 Rust 的 `&mut` 和 Go 的隐式可变引用；
● 对 Rust 标准库中 `io::Read` / `io::Write` 和 Go 的 `io.Reader` / `io.Writer` 做 MoonBit 适配，改为基于字符串的输入输出，适配 Wasm 后端；
● 采用 Builder 风格 API（`YamlLoader::new().with_config(...)` / `YamlEmitter::new().with_indent(...)`），更符合 MoonBit 生态的接口设计习惯；
● 弱化 yaml-rust 中依赖 Serde 框架的复杂序列化层，保留基于 `YamlValue` enum 的基础 API 作为主要使用方式，结构化反序列化作为后续扩展方向；
● 以纯字符串输入输出为主要交付接口，方便接入 CLI 工具、IDE 插件和数据处理场景；
● 针对 MoonBit 的 Wasm-GC 后端优化，无系统 I/O 依赖，可直接在浏览器和受限环境中运行。
