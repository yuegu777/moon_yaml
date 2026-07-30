///|
/// 文件用途: Moon YAML 端到端测试
/// 创建时间: 2026-07-29
/// 兼容环境: macOS/Linux/Docker/TRAE 云端 / MoonBit Wasm 后端
/// 版本: v0.1.1
/// 风险提示: 无

///|
/// 测试基础标量解析 - null
test "parse_null" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("null") {
        Ok(@yaml.Null) => ()
        Ok(_) => fail!("预期 Null")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试基础标量解析 - bool
test "parse_bool" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("true") {
        Ok(@yaml.Bool(true)) => ()
        Ok(_) => fail!("预期 Bool(true)")
        Err(e) => fail!("解析失败")
    }
    match loader.load_single("false") {
        Ok(@yaml.Bool(false)) => ()
        Ok(_) => fail!("预期 Bool(false)")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试基础标量解析 - 整数
test "parse_int" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("42") {
        Ok(@yaml.Int(42)) => ()
        Ok(_) => fail!("预期 Int(42)")
        Err(e) => fail!("解析失败")
    }
    match loader.load_single("-10") {
        Ok(@yaml.Int(-10)) => ()
        Ok(_) => fail!("预期 Int(-10)")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试基础标量解析 - 字符串
test "parse_string" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("hello") {
        Ok(@yaml.String("hello")) => ()
        Ok(_) => fail!("预期 String(hello)")
        Err(e) => fail!("解析失败")
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
        Err(e) => fail!("解析失败")
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
        Err(e) => fail!("解析失败")
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
        Err(e) => fail!("解析失败")
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
        Err(e) => fail!("解析失败")
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
                Err(e) => fail!("往返解析失败")
            }
        }
        Err(e) => fail!("初始解析失败")
    }
}

///|
/// 测试空值 key: 解析为 Null
test "parse_null_value" {
    let loader = @yaml.YamlLoader::new()
    let input = "key1:\nkey2: value"
    match loader.load_single(input) {
        Ok(@yaml.Object(obj)) => {
            match obj.get("key1") {
                Some(@yaml.Null) => ()
                _ => fail!("key1 应为 Null")
            }
            match obj.get("key2") {
                Some(@yaml.String("value")) => ()
                _ => fail!("key2 应为 String(value)")
            }
        }
        Ok(_) => fail!("预期 Object")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试十六进制整数
test "parse_hex_int" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("0xFF") {
        Ok(@yaml.Int(255)) => ()
        Ok(_) => fail!("预期 Int(255)")
        Err(e) => fail!("解析失败")
    }
    match loader.load_single("0x1A") {
        Ok(@yaml.Int(26)) => ()
        Ok(_) => fail!("预期 Int(26)")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试八进制整数 (0o 前缀)
test "parse_oct_int" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("0o777") {
        Ok(@yaml.Int(511)) => ()
        Ok(_) => fail!("预期 Int(511)")
        Err(e) => fail!("解析失败")
    }
    match loader.load_single("0o10") {
        Ok(@yaml.Int(8)) => ()
        Ok(_) => fail!("预期 Int(8)")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试二进制整数 (0b 前缀)
test "parse_bin_int" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("0b1010") {
        Ok(@yaml.Int(10)) => ()
        Ok(_) => fail!("预期 Int(10)")
        Err(e) => fail!("解析失败")
    }
    match loader.load_single("0b11111111") {
        Ok(@yaml.Int(255)) => ()
        Ok(_) => fail!("预期 Int(255)")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试整数下划线分隔符
test "parse_int_underscore" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("1_000_000") {
        Ok(@yaml.Int(1000000)) => ()
        Ok(_) => fail!("预期 Int(1000000)")
        Err(e) => fail!("解析失败")
    }
    match loader.load_single("0xFF_FF") {
        Ok(@yaml.Int(65535)) => ()
        Ok(_) => fail!("预期 Int(65535)")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试浮点数
test "parse_float" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("3.14") {
        Ok(@yaml.Double(f)) => {
            if f < 3.13 || f > 3.15 {
                fail!("预期约 3.14")
            }
        }
        Ok(_) => fail!("预期 Double")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试浮点数科学计数法
test "parse_float_sci" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single("1e3") {
        Ok(@yaml.Double(f)) => {
            if f < 999.0 || f > 1001.0 {
                fail!("预期约 1000.0")
            }
        }
        Ok(_) => fail!("预期 Double")
        Err(e) => fail!("解析失败")
    }
    match loader.load_single("1.5e-2") {
        Ok(@yaml.Double(f)) => {
            if f < 0.014 || f > 0.016 {
                fail!("预期约 0.015")
            }
        }
        Ok(_) => fail!("预期 Double")
        Err(e) => fail!("解析失败")
    }
}

///|
/// 测试浮点数简写 (.5 和 5.)
test "parse_float_shorthand" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single(".5") {
        Ok(@yaml.Double(f)) => {
            if f < 0.49 || f > 0.51 {
                fail!(".5 预期约 0.5")
            }
        }
        Ok(_) => fail!("预期 Double")
        Err(e) => fail!(".5 解析失败")
    }
    match loader.load_single("5.") {
        Ok(@yaml.Double(f)) => {
            if f < 4.99 || f > 5.01 {
                fail!("5. 预期约 5.0")
            }
        }
        Ok(_) => fail!("预期 Double")
        Err(e) => fail!("5. 解析失败")
    }
}

///|
/// 测试特殊浮点值 (inf/nan)
test "parse_float_special" {
    let loader = @yaml.YamlLoader::new()
    match loader.load_single(".inf") {
        Ok(@yaml.Double(_)) => ()
        Ok(_) => fail!("预期 Double(inf)")
        Err(e) => fail!(".inf 解析失败")
    }
    match loader.load_single("-.inf") {
        Ok(@yaml.Double(_)) => ()
        Ok(_) => fail!("预期 Double(-inf)")
        Err(e) => fail!("-.inf 解析失败")
    }
    match loader.load_single(".nan") {
        Ok(@yaml.Double(_)) => ()
        Ok(_) => fail!("预期 Double(nan)")
        Err(e) => fail!(".nan 解析失败")
    }
}

///|
/// 测试嵌套空值
test "parse_nested_null" {
    let loader = @yaml.YamlLoader::new()
    let input = "parent:\n  child1:\n  child2: value"
    match loader.load_single(input) {
        Ok(@yaml.Object(obj)) => {
            match obj.get("parent") {
                Some(@yaml.Object(parent)) => {
                    match parent.get("child1") {
                        Some(@yaml.Null) => ()
                        _ => fail!("child1 应为 Null")
                    }
                    match parent.get("child2") {
                        Some(@yaml.String("value")) => ()
                        _ => fail!("child2 应为 String(value)")
                    }
                }
                _ => fail!("parent 应为 Object")
            }
        }
        Ok(_) => fail!("预期 Object")
        Err(e) => fail!("解析失败")
    }
}
