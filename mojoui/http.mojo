# mojoui.http: a small HTTP/1.0 client for a server on this machine (127.0.0.1), over the C library's sockets.
# It's for an app's own helper process (an engine in Python, a local service), not the internet: no TLS, no
# redirects, no chunked replies (HTTP/1.0 servers close the connection at the end of the body).
#
#   var r = http_request(port, "POST", "/api/query", '{"sql": "SELECT 1"}', ["X-Session: " + secret])
#   r.status   (200, 400, …; 0 when nothing answered)    r.body   (the reply's body as text)

from std.ffi import external_call, c_int
from std.sys import CompilationTarget

comptime AF_INET = 2
comptime SOCK_STREAM = 1


@fieldwise_init
struct Reply(Copyable, Movable):
    var status: Int  # the HTTP status; 0 when the server couldn't be reached (body says why)
    var body: String


def _address(port: Int) -> List[UInt8]:
    """A sockaddr_in for 127.0.0.1:port. Apple's starts with its own length; Linux's family is two bytes."""
    var a = List[UInt8](length=16, fill=0)
    comptime if CompilationTarget.is_macos():
        a[0] = 16
        a[1] = AF_INET
    else:
        a[0] = AF_INET
    a[2] = UInt8((port >> 8) & 255)
    a[3] = UInt8(port & 255)
    a[4] = 127
    a[7] = 1
    return a^


def _send_all(fd: c_int, data: String) -> Bool:
    var bytes = data.as_bytes()
    var sent = 0
    while sent < len(bytes):
        var n = external_call["send", Int](fd, bytes.unsafe_ptr().unsafe_offset(sent), len(bytes) - sent, c_int(0))
        if n <= 0:
            return False
        sent += n
    return True


def parse_reply(raw: List[UInt8]) -> Reply:
    """'HTTP/1.0 200 OK\\r\\n…\\r\\n\\r\\nbody' → Reply(200, body)."""
    var text = String(unsafe_from_utf8=raw)
    var head_end = text.find("\r\n\r\n")
    if not text.startswith("HTTP/") or head_end < 0:
        return Reply(0, "not an HTTP reply")
    var first = text.find(" ")
    try:
        return Reply(Int(String(text[byte = first + 1 : first + 4])), String(text[byte = head_end + 4 :]))
    except:
        return Reply(0, "not an HTTP reply")


def http_request(port: Int, method: String, path: String, body: String = "", headers: List[String] = []) -> Reply:
    """One request to 127.0.0.1:port; waits for the whole reply."""
    var fd = external_call["socket", c_int](c_int(AF_INET), c_int(SOCK_STREAM), c_int(0))
    if fd < 0:
        return Reply(0, "no socket")
    var addr = _address(port)
    if external_call["connect", c_int](fd, addr.unsafe_ptr(), c_int(16)) != 0:
        _ = external_call["close", c_int](fd)
        return Reply(0, "nothing is listening on port " + String(port))
    var req = method + " " + path + " HTTP/1.0\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"
    for h in headers:
        req += h + "\r\n"
    req += "Content-Length: " + String(body.byte_length()) + "\r\n\r\n" + body
    if not _send_all(fd, req):
        _ = external_call["close", c_int](fd)
        return Reply(0, "the connection closed while sending")
    var raw = List[UInt8]()
    var buf = List[UInt8](length=65536, fill=0)
    while True:
        var n = external_call["recv", Int](fd, buf.unsafe_ptr(), 65536, c_int(0))
        if n <= 0:
            break
        for i in range(n):
            raw.append(buf[i])
    _ = external_call["close", c_int](fd)
    return parse_reply(raw)


def open_url(url: String) -> Bool:
    """Opens a web address in the system's browser (open on a Mac, xdg-open elsewhere), without waiting."""
    var safe = True
    for c in url.codepoint_slices():  # it goes through the shell: only plain URL characters
        if c == "'" or c == "\\" or c == "\n":
            safe = False
    if not safe:
        return False
    comptime if CompilationTarget.is_macos():
        var cmd = "open '" + url + "'"
        return external_call["system", c_int](cmd.as_c_string_span().ptr()) == 0
    else:
        var cmd = "xdg-open '" + url + "' >/dev/null 2>&1 &"
        return external_call["system", c_int](cmd.as_c_string_span().ptr()) == 0
