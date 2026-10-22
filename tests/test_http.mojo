# mojoui.http against a real server on this machine: a request with a body and headers, the reply's status and
# body, an error status, and a port nothing listens on.
#   pixi run python -m http.server … is not enough (it has no POST): tests/http_echo.py is the server.
#   pixi run python tests/http_echo.py 8799 & pixi run mojo run -I . tests/test_http.mojo 8799
from std.testing import assert_equal, assert_true
from std.sys import argv
from mojoui.http import http_request, parse_reply
from mojoui.json import Json


def main() raises:
    var port = Int(String(argv()[1]))
    var r = http_request(port, "POST", "/echo", '{"sql": "SELECT \'é\'"}', ["X-Session: abc"])
    assert_equal(r.status, 200)
    var j = Json.parse(r.body)
    assert_equal(j.text(j.get(0, "method")), "POST")
    assert_equal(j.text(j.get(0, "session")), "abc")
    assert_equal(j.text(j.get(0, "body")), '{"sql": "SELECT \'é\'"}')
    var big = http_request(port, "GET", "/big")  # more than one recv's worth
    assert_equal(big.status, 200)
    assert_equal(big.body.byte_length(), 300_000)
    assert_equal(http_request(port, "GET", "/missing").status, 404)
    var none = http_request(1, "GET", "/")
    assert_equal(none.status, 0)
    assert_true(none.body.startswith("nothing is listening"))
    var raw = List[UInt8]()
    for b in "garbage".as_bytes():
        raw.append(b)
    assert_equal(parse_reply(raw).status, 0)
    print("PASSED test_http")
