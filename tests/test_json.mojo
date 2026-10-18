# mojoui.json: the reader and the writer round-trip what the .omx metadata holds.
#   pixi run mojo run -I . tests/test_json.mojo
from std.testing import assert_equal, assert_true, assert_false
from mojoui.json import Json, json_string, J_ARRAY, J_OBJECT


def main() raises:
    var j = Json.parse(' {"omx": 2, "name": "a\\"b\\n\\u00e9\\ud83d\\ude00", "ok": true, "no": false, "n": null, "list": [1, -20, {"x": []}], "empty": {}} ')
    assert_equal(j.number(j.get(0, "omx")), 2)
    assert_equal(j.text(j.get(0, "name")), 'a"b\né😀')
    assert_true(j.flag(j.get(0, "ok")))
    assert_false(j.flag(j.get(0, "no")))
    var list = j.get(0, "list")
    assert_equal(j.kind(list), J_ARRAY)
    assert_equal(j.size(list), 3)
    assert_equal(j.number(j.at(list, 1)), -20)
    assert_equal(j.kind(j.at(list, 2)), J_OBJECT)
    assert_equal(j.size(j.get(j.at(list, 2), "x")), 0)
    assert_equal(j.get(0, "missing"), -1)
    assert_equal(j.number(j.get(0, "missing"), 7), 7)
    var back = Json.parse(json_string('tab\t quote" back\\ é \x01'))
    assert_equal(back.text(0), 'tab\t quote" back\\ é \x01')
    for bad in ["", "{", '{"a" 1}', "[1,]", '"open', "1.5", "{} x", '{"a": tru}']:
        var failed = False
        try:
            _ = Json.parse(bad)
        except e:
            failed = String(e).startswith("not JSON: ")
        assert_true(failed, "refuses: " + bad)
    print("JSON TESTS PASSED")
