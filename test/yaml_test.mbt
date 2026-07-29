///|
/// 文件用途: Moon YAML 端到端测试
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.0
/// 风险提示: 无

///|
/// 测试基础标量解析 - null
test "parse_null" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("null") {
        Ok(@yaml.Null) => ()
        Ok(_) => fail!("预期 Null")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
}

///|
/// 测试基础标量解析 - bool
test "parse_bool" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("true") {
        Ok(@yaml.Bool(true)) => ()
        Ok(_) => fail!("预期 Bool(true)")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
    match loader.load_single("false") {
        Ok(@yaml.Bool(false)) => ()
        Ok(_) => fail!("预期 Bool(false)")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
}

///|
/// 测试基础标量解析 - 整数
test "parse_int" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("42") {
        Ok(@yaml.Int(42)) => ()
        Ok(_) => fail!("预期 Int(42)")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
    match loader.load_single("-10") {
        Ok(@yaml.Int(-10)) => ()
        Ok(_) => fail!("预期 Int(-10)")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
}

///|
/// 测试基础标量解析 - 字符串
test "parse_string" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("hello") {
        Ok(@yaml.String("hello")) => ()
        Ok(_) => fail!("预期 String(hello)")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
}

///|
/// 测试基础 mapping 解析
test "parse_mapping" {
    let loader = @yaml.YamlLoader::new()
    let input = "name: Alice\nage: 30"
    match loader.load_single(input) {
        Ok(@yaml.Object(obj)) => {
            match obj.get("name") {
                Some(@yaml.String("Alice")) => ()
                _ => fail!("name 字段不匹配")
            }
            match obj.get("age") {
                Some(@yaml.Int(30)) => ()
                _ => fail!("age 字段不匹配")
            }
        }
        Ok(_) => fail!("预期 Object")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
}

///|
/// 测试基础 sequence 解析
test "parse_sequence" {
    let loader = @yaml.YamlLoader::new()
    let input = "- apple\n- banana\n- cherry"
    match loader.load_single(input) {
        Ok(@yaml.Array(arr)) => {
            if arr.length() != 3 {
                fail!("序列长度应为 3")
            }
            match arr[0] {
                @yaml.String("apple") => ()
                _ => fail!("第一项不匹配")
            }
        }
        Ok(_) => fail!("预期 Array")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
}

///|
/// 测试嵌套结构
test "parse_nested" {
    let loader = @yaml.YamlLoader::new()
    let input = "person:\n  name: Bob\n  age: 25"
    match loader.load_single(input) {
        Ok(@yaml.Object(obj)) => {
            match obj.get("person") {
                Some(@yaml.Object(person)) => {
                    match person.get("name") {
                        Some(@yaml.String("Bob")) => ()
                        _ => fail!("name 不匹配")
                    }
                    match person.get("age") {
                        Some(@yaml.Int(25)) => ()
                        _ => fail!("age 不匹配")
                    }
                }
                _ => fail!("person 应为 Object")
            }
        }
        Ok(_) => fail!("预期 Object")
        Err(e) => fail!("解析失败: " + e.to_string())
    }
}

///|
/// 测试多文档
test "parse_multi_document" {
    let loader = @yaml.YamlLoader::new()
    let input = "---\ndoc1: value1\n---\ndoc2: value2"
    match loader.load_from_str(input) {
        Ok(docs) => {
            if docs.length() != 2 {
                fail!("文档数量应为 2")
            }
            match docs[0] {
                @yaml.Object(obj) => {
                    match obj.get("doc1") {
                        Some(@yaml.String("value1")) => ()
                        _ => fail!("doc1 不匹配")
                    }
                }
                _ => fail!("第一个文档应为 Object")
            }
        }
        Err(e) => fail!("解析失败: " + e.to_string())
    }
}

///|
/// 测试序列化
test "emit_yaml" {
    let emitter = @yaml.YamlEmitter::new()
    let value = @yaml.Object(Map::from_array([
        ("name", @yaml.String("Alice")),
        ("age", @yaml.Int(30))
    ]))
    let yaml_str = emitter.emit(value)
    if not(yaml_str.contains("name: Alice")) {
        fail!("序列化结果应包含 name: Alice")
    }
    if not(yaml_str.contains("age: 30")) {
        fail!("序列化结果应包含 age: 30")
    }
}

///|
/// 测试往返一致性
test "roundtrip" {
    let loader = @yaml.YamlLoader::new()
    let emitter = @yaml.YamlEmitter::new()
    let original = "name: Alice\nage: 30"
    match loader.load_single(original) {
        Ok(doc) => {
            let output = emitter.emit(doc)
            match loader.load_single(output) {
                Ok(doc2) => {
                    // 验证两个文档结构一致
                    match (doc, doc2) {
                        (@yaml.Object(a), @yaml.Object(b)) => {
                            match (a.get("name"), b.get("name")) {
                                (Some(@yaml.String(n1)), Some(@yaml.String(n2))) => {
                                    if n1 != n2 {
                                        fail!("name 往返不一致")
                                    }
                                }
                                _ => fail!("name 字段缺失")
                            }
                        }
                        _ => fail!("往返后类型不一致")
                    }
                }
                Err(e) => fail!("往返解析失败: " + e.to_string())
            }
        }
        Err(e) => fail!("初始解析失败: " + e.to_string())
    }
}
