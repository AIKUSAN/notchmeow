// What the link's tests share: reading a fixture of tests/fixtures/link/ and a few JSON helpers.

use std::path::Path;

use serde_json::Value;

pub fn fixture(name: &str) -> Value {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/link").join(name);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
}

pub fn arr<'a>(v: &'a Value, key: &str) -> &'a Vec<Value> {
    v[key].as_array().unwrap_or_else(|| panic!("{key} is not a list"))
}

pub fn name(case: &Value) -> &str {
    case["name"].as_str().unwrap_or("?")
}
