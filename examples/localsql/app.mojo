# LocalSQL in Mojo: a SQL client in omxqua's Developer look. Tables on the left, a query and its results on the right,
# saved queries, a Connect dialog (your connector.py with a server URL and a token, or the demo data) and a Notebook
# tab. The window is Mojo; the work is LocalSQL's Python engine on this machine (pixi run app-mojo starts both), over
# a loopback HTTP API with a per-launch secret. The token is typed into a secure field and only ever sent to the engine.

from mojoui import (
    App, Event, View, VStack, HStack, Text, Button, TextField, TextArea, Segmented, Tabs, Scroll, Spacer, Divider, Card,
    Canvas, ProgressBar, Dialog, Toast, WebView, TITLE, HEADLINE, CAPTION, PROMINENT, SUBTLE, ICON_ONLY, NO_MSG, START, CENTER, END,
    BETWEEN, TONE_GOOD, TONE_ACCENT, TONE_STRONG,
)
from mojoui.canvas import Surface
from mojoui.text import Font
from mojoui.theme import Theme, Palette
from mojoui.datagrid import DataGrid, GridSource, GRID_ROW_H
from mojoui.json import Json, json_string, J_NULL, J_STRING, J_ARRAY
from mojoui.http import http_request, open_url, Reply
from mojoui.shared import environment
from themes.omxqua import omxqua

# messages
comptime TAB = 1
comptime OPEN_CONNECT = 2
comptime CLOSE_CONNECT = 3
comptime KIND = 4
comptime URL_TYPED = 5
comptime TOKEN_TYPED = 6
comptime CONNECT = 7
comptime FILTER = 8
comptime SQL_TYPED = 9
comptime RUN = 10
comptime NAME_TYPED = 11
comptime SAVE = 12
comptime GRID = 13
comptime REFRESH = 14
comptime THEME = 15
comptime NOTEBOOK_START = 16
comptime NOTEBOOK_OPEN = 17
comptime TOAST_GONE = 18
comptime TABLE = 1000  # + table index: expand / collapse (each range holds 10,000+; a server with 19,000 tables would overlap)
comptime INSERT_TABLE = 20_000  # + table index: put its name in the query
comptime INSERT_COLUMN = 40_000  # + column index of the open table
comptime SUGGEST = 60_000  # + suggestion index
comptime LOAD_SAVED = 80_000  # + saved query index
comptime DELETE_SAVED = 90_000

comptime QUERY = 0
comptime NOTEBOOK = 1
comptime KIND_CUSTOM = 0
comptime KIND_DEMO = 1
comptime KEYWORDS: List[String] = ["SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "LIMIT", "JOIN", "LEFT JOIN", "ON", "AND",
                                   "OR", "COUNT(*)", "SUM(", "AVG(", "DISTINCT", "AS", "DESC", "HAVING", "IN", "IS NULL", "LIKE"]


struct Result(Copyable, Movable, GridSource):
    """A query's answer as the grid reads it: every cell as text, NULL marked."""
    var columns: List[String]
    var cells: List[String]  # row-major
    var nulls: List[Bool]
    var numeric: List[Bool]

    def __init__(out self):
        self.columns = List[String]()
        self.cells = List[String]()
        self.nulls = List[Bool]()
        self.numeric = List[Bool]()

    def grid_rows(self) -> Int:
        return len(self.cells) // len(self.columns) if len(self.columns) > 0 else 0

    def grid_alive(self, row: Int) -> Bool:
        return True

    def grid_columns(self) -> Int:
        return len(self.columns)

    def grid_name(self, c: Int) -> String:
        return self.columns[c]

    def grid_numeric(self, c: Int) -> Bool:
        return self.numeric[c]

    def grid_editable(self, c: Int) -> Bool:
        return False

    def grid_formula(self, c: Int) -> Bool:
        return False

    def grid_text(self, c: Int, row: Int) -> String:
        var i = row * len(self.columns) + c
        return "NULL" if self.nulls[i] else self.cells[i]

    def grid_type_width(self, c: Int) -> Float64:
        return 110.0 if self.numeric[c] else 160.0

    def grid_badge(self, c: Int) -> String:
        return "#" if self.numeric[c] else "Aa"

    def grid_edited(self, c: Int, row: Int) -> Bool:
        return False


def looks_numeric(s: String) -> Bool:
    if s.byte_length() == 0:
        return False
    var digits = 0
    var dots = 0
    var i = 0
    for b in s.as_bytes():
        var c = Int(b)
        if 48 <= c <= 57:
            digits += 1
        elif c == 46:
            dots += 1
        elif not (c == 45 and i == 0):  # a minus only in front: 2026-02-02 is a date, not a number
            return False
        i += 1
    return digits > 0 and dots <= 1


def upper(s: String) -> String:
    var out = List[UInt8]()
    for b in s.as_bytes():
        out.append(b - 32 if 97 <= Int(b) <= 122 else b)
    return String(unsafe_from_utf8=out)


def plural(n: Int, word: String) -> String:
    return String(n) + " " + word + ("" if n == 1 else "s")


def thousands(n: Int) -> String:
    var s = String(n)
    var out = String()
    var k = 0
    for i in range(s.byte_length() - 1, -1, -1):
        out = String(s[byte = i : i + 1]) + out
        k += 1
        if k % 3 == 0 and i > 0:
            out = "," + out
    return out^


def last_word_start(text: String) -> Int:
    """Where the word being typed at the end of the query starts (after a space, comma, bracket or operator)."""
    var b = text.as_bytes()
    var i = len(b)
    while i > 0:
        var c = Int(b[i - 1])
        if c == 32 or c == 10 or c == 9 or c == 44 or c == 40 or c == 41 or c == 61 or c == 60 or c == 62 or c == 59:
            break
        i -= 1
    return i


struct Main(App):
    var port: Int
    var session: String
    var engine_error: String
    var tab: Int
    var dark: Bool
    var connected: Bool
    var conn_label: String
    var connect_open: Bool
    var kind: Int
    var url: String
    var token: String
    var connect_error: String
    var tables: List[String]  # qualified names, as you'd type them
    var table_json: List[String]  # each table as the engine sent it (for /api/columns)
    var filter: String
    var open_table: Int
    var columns: List[String]
    var column_types: List[String]
    var all_columns: List[String]  # every column seen, for suggestions
    var sql: String
    var sql_version: Int  # bumped when the app (not typing) changes the query
    var save_name: String
    var saved_names: List[String]
    var saved_sqls: List[String]
    var status: String
    var status_bad: Bool
    var result: Result
    var row_note: String
    var last_sql: String
    var grid: DataGrid
    var font: Font
    var pal: Palette
    var theme_kept: Theme
    var data_version: Int
    var notebook_url: String
    var notebook_status: String
    var toast: String

    def __init__(out self):
        self.port = 0
        self.session = ""
        self.engine_error = ""
        self.tab = QUERY
        self.dark = True
        self.connected = False
        self.conn_label = "Not connected"
        self.connect_open = False
        self.kind = KIND_CUSTOM
        self.url = ""
        self.token = ""
        self.connect_error = ""
        self.tables = List[String]()
        self.table_json = List[String]()
        self.filter = ""
        self.open_table = -1
        self.columns = List[String]()
        self.column_types = List[String]()
        self.all_columns = List[String]()
        self.sql = "-- Connect, then write a query. Suggestions appear under the editor as you type.\nSELECT * FROM sales.orders LIMIT 100"
        self.sql_version = 0
        self.save_name = ""
        self.saved_names = List[String]()
        self.saved_sqls = List[String]()
        self.status = "Not connected yet: use the pill at the top right."
        self.status_bad = False
        self.result = Result()
        self.row_note = "no results"
        self.last_sql = "nothing run yet"
        self.grid = DataGrid()
        self.grid.browse = False
        self.font = Font()
        self.theme_kept = omxqua(True)
        self.pal = self.theme_kept.palette.copy()
        self.data_version = 0
        self.notebook_url = ""
        self.notebook_status = ""
        self.toast = ""
        self.find_engine()
        self.load_saved()

    # ---------- the engine ----------

    def find_engine(mut self):
        """The port and secret: from pixi run app-mojo (its environment), else ~/.localsql/engine.json (pixi run engine)."""
        var p = environment("LOCALSQL_PORT")
        self.session = environment("LOCALSQL_SESSION")
        if p == "":
            try:
                with open(environment("HOME", ".") + "/.localsql/engine.json", "r") as f:
                    var j = Json.parse(f.read())
                    self.port = j.number(j.get(0, "port"))
                    self.session = j.text(j.get(0, "session"))
            except:
                self.engine_error = "The engine isn't running. Start the app with: pixi run app-mojo"
            return
        try:
            self.port = Int(p)
        except:
            self.engine_error = "LOCALSQL_PORT isn't a number"

    def call(self, method: String, path: String, body: String = "") -> Reply:
        if self.port == 0:
            return Reply(0, self.engine_error)
        var r = http_request(self.port, method, path, body, ["X-Session: " + self.session])
        if r.status == 0:
            r.body = "The engine stopped answering (" + r.body + "). Restart with: pixi run app-mojo"
        return r^

    def error_of(self, r: Reply) -> String:
        if r.status == 0:
            return r.body
        try:
            var j = Json.parse(r.body)
            return j.text(j.get(0, "error"), "HTTP " + String(r.status))
        except:
            return "HTTP " + String(r.status) + ": " + String(r.body[byte = 0 : min(r.body.byte_length(), 200)])

    # ---------- actions ----------

    def connect(mut self):
        var body = String('{"kind": ') + json_string("demo" if self.kind == KIND_DEMO else "custom")
        if self.kind == KIND_CUSTOM:
            body += ', "url": ' + json_string(String(self.url.strip())) + ', "token": ' + json_string(self.token)
        body += "}"
        var r = self.call("POST", "/api/connect", body)
        self.token = ""  # the engine has it now; the window keeps no copy
        if r.status != 200:
            self.connect_error = self.error_of(r)
            self.connected = False
            return
        self.connected = True
        self.connect_open = False
        self.connect_error = ""
        self.conn_label = "Demo data" if self.kind == KIND_DEMO else (self.host_of(self.url))
        self.load_tables()
        self.toast = "Connected · " + plural(len(self.tables), "table")

    def host_of(self, url: String) -> String:
        var u = String(url.strip())
        var s = u.find("://")
        if s >= 0:
            var rest = String(u[byte = s + 3 :])
            u = rest
        var slash = u.find("/")
        if slash > 0:
            var head = String(u[byte = :slash])
            u = head
        return u if u != "" else "My connector"

    def load_tables(mut self):
        self.tables = List[String]()
        self.table_json = List[String]()
        self.open_table = -1
        var r = self.call("GET", "/api/tables")
        if r.status != 200:
            self.status = self.error_of(r)
            self.status_bad = True
            return
        try:
            var j = Json.parse(r.body)
            for k in range(j.size(0)):
                var t = j.at(0, k)
                var catalog = j.text(j.get(t, "catalog"))
                var schema = j.text(j.get(t, "schema"))
                var name = j.text(j.get(t, "name"))
                var q = name
                if schema != "":
                    q = schema + "." + name
                if catalog != "" and self.kind != KIND_DEMO:
                    q = catalog + "." + q
                self.tables.append(q)
                self.table_json.append("{" + '"catalog": ' + json_string(catalog) + ', "schema": ' + json_string(schema) + ', "name": ' + json_string(name) + "}")
            self.status = "Connected to " + self.conn_label + ": " + plural(len(self.tables), "table") + ". Write a query and press Run."
            self.status_bad = False
        except e:
            self.status = "The engine sent tables I can't read: " + String(e)
            self.status_bad = True

    def toggle_table(mut self, i: Int):
        if self.open_table == i:
            self.open_table = -1
            return
        self.open_table = i
        self.columns = List[String]()
        self.column_types = List[String]()
        var r = self.call("POST", "/api/columns", self.table_json[i])
        if r.status != 200:
            self.status = self.error_of(r)
            self.status_bad = True
            return
        try:
            var j = Json.parse(r.body)
            for k in range(j.size(0)):
                var c = j.at(0, k)
                var name = j.text(j.get(c, "name"))
                self.columns.append(name)
                self.column_types.append(j.text(j.get(c, "type")))
                var seen = False
                for a in self.all_columns:
                    if a == name:
                        seen = True
                if not seen:
                    self.all_columns.append(name)
        except e:
            self.status = "The engine sent columns I can't read: " + String(e)
            self.status_bad = True

    def runnable(self) -> String:
        """The query without -- comments and a trailing semicolon."""
        var out = String()
        for line in self.sql.split("\n"):
            var l = String(line)
            var dash = l.find("--")
            if dash >= 0:
                var before = String(l[byte = :dash])
                l = before
            if String(l.strip()) != "":
                out += ("\n" if out != "" else "") + l
        var t = String(out.strip())
        while t.endswith(";"):
            var shorter = String(String(t[byte = : t.byte_length() - 1]).strip())
            t = shorter
        return t^

    def run(mut self):
        var q = self.runnable()
        if q == "":
            self.status = "Nothing to run: write a query first."
            self.status_bad = True
            return
        self.status = "Running…"
        var r = self.call("POST", "/api/query", '{"sql": ' + json_string(q) + ', "text": true}')
        if r.status != 200:
            self.status = self.error_of(r)
            self.status_bad = True
            return
        try:
            var j = Json.parse(r.body)
            var res = Result()
            var cols = j.get(0, "columns")
            for k in range(j.size(cols)):
                res.columns.append(j.text(j.at(cols, k)))
                res.numeric.append(True)
            var rows = j.get(0, "rows")
            for k in range(j.size(rows)):
                var row = j.at(rows, k)
                for c in range(len(res.columns)):
                    var cell = j.at(row, c)
                    var null = j.kind(cell) == J_NULL or cell < 0
                    var text = j.text(cell)
                    res.cells.append(text)
                    res.nulls.append(null)
                    if not null and not looks_numeric(text):
                        res.numeric[c] = False
            var n = res.grid_rows()
            if n == 0:
                for c in range(len(res.numeric)):
                    res.numeric[c] = False
            self.result = res^
            self.grid = DataGrid()
            self.grid.prepare(self.result, self.font, self.pal)
            self.data_version += 1
            var truncated = j.flag(j.get(0, "truncated"))
            var ms = j.number(j.get(0, "elapsed_ms"))
            self.row_note = thousands(n) + (" rows (first 10,000)" if truncated else (" row" if n == 1 else " rows"))
            self.status = self.row_note + " in " + String(ms) + " ms"
            self.status_bad = False
            var flat = String()
            for part in q.split("\n"):
                flat += (" " if flat != "" else "") + String(String(part).strip())
            self.last_sql = flat
        except e:
            self.status = "The engine's answer didn't parse: " + String(e)
            self.status_bad = True

    def load_saved(mut self):
        var r = self.call("GET", "/api/queries")
        if r.status != 200:
            return
        try:
            var j = Json.parse(r.body)
            self.saved_names = List[String]()
            self.saved_sqls = List[String]()
            for k in range(j.size(0)):
                var q = j.at(0, k)
                self.saved_names.append(j.text(j.get(q, "name")))
                self.saved_sqls.append(j.text(j.get(q, "sql")))
        except:
            pass

    def store_saved(mut self) -> Bool:
        var body = String("[")
        for k in range(len(self.saved_names)):
            body += (", " if k > 0 else "") + '{"name": ' + json_string(self.saved_names[k]) + ', "sql": ' + json_string(self.saved_sqls[k]) + "}"
        body += "]"
        var r = self.call("POST", "/api/queries", body)
        if r.status != 200:
            self.status = self.error_of(r)
            self.status_bad = True
            return False
        return True

    def save(mut self):
        var name = String(self.save_name.strip())
        if name == "":
            self.status = "Type a name to save this query as."
            self.status_bad = True
            return
        var found = -1
        for k in range(len(self.saved_names)):
            if self.saved_names[k] == name:
                found = k
        if found >= 0:
            self.saved_sqls[found] = self.sql
        else:
            self.saved_names.append(name)
            self.saved_sqls.append(self.sql)
        if self.store_saved():
            self.toast = "Saved “" + name + "”"
            self.save_name = ""

    def suggestions(self) -> List[String]:
        """Words that finish the one being typed at the end of the query: tables, columns, keywords."""
        var out = List[String]()
        var start = last_word_start(self.sql)
        var word = String(self.sql[byte = start:])
        if word.byte_length() < 1:
            return out^
        var up = upper(word)
        for t in self.tables:
            var short = t
            var dot = t.rfind(".")
            if dot >= 0:
                short = String(t[byte = dot + 1 :])
            if (upper(t).startswith(up) or upper(short).startswith(up)) and upper(t) != up and len(out) < 8:
                out.append(t)
        for c in self.all_columns:
            if upper(c).startswith(up) and upper(c) != up and len(out) < 8:
                out.append(c)
        for k in materialize[KEYWORDS]():
            if k.startswith(up) and k != up and len(out) < 8:
                out.append(k)
        return out^

    def insert(mut self, word: String, replace_partial: Bool):
        if replace_partial:
            var start = last_word_start(self.sql)
            self.sql = String(self.sql[byte = :start]) + word + " "
        else:
            var tail = self.sql.byte_length()
            var sep = String("") if tail == 0 or self.sql.endswith(" ") or self.sql.endswith("\n") else String(" ")
            self.sql += sep + word + " "
        self.sql_version += 1

    def start_notebook(mut self):
        self.notebook_status = "Starting JupyterLab… the first start takes a few seconds."
        var r = self.call("POST", "/api/notebook", "{}")
        if r.status != 200:
            self.notebook_status = self.error_of(r)
            return
        try:
            var j = Json.parse(r.body)
            self.notebook_url = j.text(j.get(0, "url"))
            self.notebook_status = "JupyterLab is running, with connect.ipynb open."
        except e:
            self.notebook_status = "The engine's answer didn't parse: " + String(e)

    # ---------- the app ----------

    def title(self) -> String:
        return "LocalSQL"

    def window_size(self) -> Tuple[Int, Int]:
        return (1400, 880)

    def theme(self) -> Theme:
        return self.theme_kept.copy()

    def logo(self) -> String:
        return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect width="24" height="24" rx="6" fill="#ededef"/>'
                + '<text x="12" y="16" font-family="Geist Mono, monospace" font-size="10" font-weight="600" text-anchor="middle" fill="#0b0b0d">ls</text></svg>')

    def update(mut self, event: Event):
        var m = event.message
        if m == TAB:
            self.tab = event.number
        elif m == OPEN_CONNECT:
            self.connect_open = True
            self.connect_error = ""
        elif m == CLOSE_CONNECT:
            self.connect_open = False
            self.token = ""
        elif m == KIND:
            self.kind = event.number
            self.connect_error = ""
        elif m == URL_TYPED:
            self.url = event.text
        elif m == TOKEN_TYPED:
            self.token = event.text
        elif m == CONNECT:
            self.connect()
        elif m == FILTER:
            self.filter = event.text
        elif m == SQL_TYPED:
            self.sql = event.text
        elif m == RUN:
            self.run()
        elif m == NAME_TYPED:
            self.save_name = event.text
        elif m == SAVE:
            self.save()
        elif m == REFRESH:
            if self.connected:
                self.load_tables()
                self.toast = "Tables refreshed · " + plural(len(self.tables), "table")
        elif m == THEME:
            self.dark = not self.dark
            self.theme_kept = omxqua(self.dark)
            self.pal = self.theme_kept.palette.copy()
            self.grid.redraw()
            self.data_version += 1
        elif m == NOTEBOOK_START:
            self.start_notebook()
        elif m == NOTEBOOK_OPEN:
            if not open_url(self.notebook_url):
                self.toast = "Couldn't open the browser"
        elif m == TOAST_GONE:
            self.toast = ""
        elif m == GRID:
            _ = self.grid.handle(event, self.result, self.font, self.pal)
        elif m >= DELETE_SAVED:
            var k = m - DELETE_SAVED
            if k < len(self.saved_names):
                var gone = self.saved_names[k]
                _ = self.saved_names.pop(k)
                _ = self.saved_sqls.pop(k)
                if self.store_saved():
                    self.toast = "Deleted “" + gone + "”"
        elif m >= LOAD_SAVED:
            var k = m - LOAD_SAVED
            if k < len(self.saved_sqls):
                self.sql = self.saved_sqls[k]
                self.save_name = self.saved_names[k]
                self.sql_version += 1
        elif m >= SUGGEST:
            var s = self.suggestions()
            var k = m - SUGGEST
            if k < len(s):
                self.insert(s[k], True)
        elif m >= INSERT_COLUMN:
            var k = m - INSERT_COLUMN
            if k < len(self.columns):
                var word = self.columns[k].copy()
                self.insert(word, False)
        elif m >= INSERT_TABLE:
            var k = m - INSERT_TABLE
            if k < len(self.tables):
                var word = self.tables[k].copy()
                self.insert(word, False)
        elif m >= TABLE:
            var k = m - TABLE
            if k < len(self.tables):
                self.toggle_table(k)

    def draw(mut self, canvas: Int, mut surface: Surface):
        self.grid.draw(surface, self.result, self.font, self.pal)

    # ---------- the screen ----------

    def card_head(self, title: String, var right: List[View]) -> View:
        var items = List[View]()
        items.append(Text(title, HEADLINE))
        items.append(Spacer())
        for v in right:
            items.append(v.copy())
        return HStack(items^, spacing=8).fill().align(CENTER)

    def src(self, text: String) -> View:
        return Text(text, CAPTION).tag("src")

    def tables_card(self) -> View:
        var rows = List[View]()
        var f = upper(String(self.filter.strip()))
        var shown = 0
        for i in range(len(self.tables)):
            if f != "" and upper(self.tables[i]).find(f) < 0:
                continue
            shown += 1
            var open = self.open_table == i
            rows.append(HStack(
                Button(self.tables[i], TABLE + i, SUBTLE, icon="chevron" if open else "chevron-right").grow().align(START).tag("row")
                    .tooltip("Show its columns"),
                Button("Insert", INSERT_TABLE + i, ICON_ONLY, icon="plus").tooltip("Put " + self.tables[i] + " in the query"),
                spacing=2).fill().align(CENTER))
            if open:
                for c in range(len(self.columns)):
                    rows.append(HStack(
                        Button(self.columns[c], INSERT_COLUMN + c, SUBTLE, icon="text").grow().align(START).tag("row")
                            .tooltip("Put " + self.columns[c] + " in the query"),
                        Text(self.column_types[c], CAPTION).tag("mono"),
                        spacing=6).fill().align(CENTER).padding(0, 0))
        if len(rows) == 0:
            rows.append(Text("Connect to list tables." if not self.connected else "No table matches.", CAPTION))
        var badge = plural(len(self.tables), "table") if self.connected else String("not connected")
        var head = List[View]()
        head.append(Text(badge, CAPTION).tag("mono"))
        return Card(
            self.card_head("Tables", head^),
            TextField(self.filter, placeholder="Filter tables", on_change=FILTER).fill(),
            Scroll(VStack(rows^, spacing=0).fill().align(START), height=380).fill().grow(),
            self.src(self.conn_label if self.connected else "connect to list tables"),
            spacing=10).fill().grow()

    def saved_card(self) -> View:
        var rows = List[View]()
        for k in range(len(self.saved_names)):
            rows.append(HStack(
                Button(self.saved_names[k], LOAD_SAVED + k, SUBTLE, icon="file").grow().align(START).tag("row").tooltip("Open it in the editor"),
                Button("Delete", DELETE_SAVED + k, ICON_ONLY, icon="trash").tooltip("Delete " + self.saved_names[k]),
                spacing=2).fill().align(CENTER))
        if len(rows) == 0:
            rows.append(Text("Name a query and press Save: it shows up here.", CAPTION))
        return Card(
            self.card_head("Saved queries", List[View]()),
            Scroll(VStack(rows^, spacing=0).fill().align(START), height=180).fill(),
            self.src("~/.localsql/queries.json"),
            spacing=10).fill()

    def query_card(self) -> View:
        var head = List[View]()
        head.append(TextField(self.save_name, placeholder="Name to save as", on_change=NAME_TYPED, on_submit=SAVE).width(200))
        head.append(Button("Save", SAVE, icon="save"))
        head.append(Button("Run query", RUN, PROMINENT, icon="chevron-right").tooltip("Runs the whole editor"))
        var chips = List[View]()
        var s = self.suggestions()
        for k in range(len(s)):
            chips.append(Button(s[k], SUGGEST + k).tag("chip"))
        if len(chips) == 0:
            chips.append(Text("Suggestions for tables, columns and keywords appear here as you type.", CAPTION))
        chips.append(Spacer())
        var status = Text(self.status, CAPTION).tag("src")
        if self.status_bad:
            status = Text(self.status, CAPTION).tone(TONE_ACCENT).tag("src")
        return Card(
            self.card_head("Query", head^),
            TextArea(self.sql, placeholder="SELECT …", on_change=SQL_TYPED, height=200).fill(),
            HStack(chips^, spacing=6).fill().align(CENTER),
            status,
            spacing=10).fill()

    def results_card(self) -> View:
        var head = List[View]()
        head.append(Text(self.row_note, CAPTION).tag("mono"))
        var body: View
        if len(self.result.columns) == 0:
            body = VStack(Spacer(), Text("No results yet", HEADLINE), Text("Run a query to see its rows here.", CAPTION), Spacer(), spacing=4).fill().grow()
        else:
            body = Canvas(0, self.grid.version + self.data_version, on_gesture=GRID).fill().grow()
        return Card(self.card_head("Results", head^), body^, self.src(self.last_sql), spacing=10).fill().grow()

    def query_view(self) -> View:
        return HStack(
            VStack(self.tables_card(), self.saved_card(), spacing=14).width(320).fill(),
            VStack(self.query_card(), self.results_card(), spacing=14).grow().fill(),
            spacing=14).fill().grow()

    def notebook_view(self) -> View:
        if self.notebook_url != "":
            var head = List[View]()
            head.append(Text(self.notebook_status, CAPTION))
            head.append(Button("Open in browser", NOTEBOOK_OPEN, SUBTLE, icon="open").tooltip("The same notebook in your browser"))
            return Card(
                self.card_head("Notebook", head^),
                WebView(self.notebook_url).grow().fill(),
                self.src("~/.localsql/notebooks/connect.ipynb  ·  writes ~/.localsql/connector.py"),
                spacing=10).fill().grow()
        var steps = VStack(
            Text("Work out your connection, then fix it right there", HEADLINE),
            Text("connect.ipynb walks you through it: unpack your .yxi, find the lines with the server URL, the auth header and the SQL call, "
                 + "type your token into a hidden box (never saved), try one call by hand, then write ~/.localsql/connector.py from a "
                 + "template with three TODOs and test it. Back here, Connect → My connector uses it.", CAPTION).max_width(720),
            spacing=6).align(START)
        var acts = List[View]()
        acts.append(Button("Start the notebook", NOTEBOOK_START, PROMINENT, icon="note"))
        acts.append(Text(self.notebook_status, CAPTION))
        acts.append(Spacer())
        return Card(
            self.card_head("Notebook", List[View]()),
            Divider().fill(),
            steps^,
            HStack(acts^, spacing=12).fill().align(CENTER),
            Spacer(),
            self.src("~/.localsql/notebooks/connect.ipynb  ·  writes ~/.localsql/connector.py"),
            spacing=14).fill().grow()

    def top_bar(self) -> View:
        var tabs: List[String] = ["Query", "Notebook"]
        var dot = String("● ") if self.connected else String("○ ")
        var pill = Button(dot + self.conn_label, OPEN_CONNECT, icon="database").tooltip("Change the connection")
        var right = HStack(
            Button("Refresh", REFRESH, ICON_ONLY, icon="undo").tooltip("Refresh tables"),
            Button("Light" if self.dark else "Dark", THEME, ICON_ONLY, icon="view").tooltip("Switch light and dark"),
            pill^, spacing=6).align(CENTER)
        return HStack(
            HStack(Text("ls", HEADLINE).tag("mono"), Text("LocalSQL", HEADLINE), spacing=8).align(CENTER).width(320),
            Spacer(),
            Tabs(tabs, self.tab, on_select=TAB),
            Spacer(),
            right^,
            spacing=12).fill().align(CENTER).padding(4, 2)

    def connect_dialog(self) -> View:
        var kinds: List[String] = ["My connector", "Demo data"]
        var items = List[View]()
        items.append(Segmented(kinds, self.kind, on_select=KIND))
        if self.kind == KIND_CUSTOM:
            items.append(TextField(self.url, placeholder="Server URL (https://…)", on_change=URL_TYPED).fill())
            items.append(TextField(self.token, placeholder="Personal access token", on_change=TOKEN_TYPED, on_submit=CONNECT).secret().fill())
            items.append(Text("Kept in memory only, gone when you quit. Uses ~/.localsql/connector.py, which the Notebook tab helps you write.", CAPTION).max_width(460))
        else:
            items.append(Text("Three sample tables, built in. No network.", CAPTION))
        if self.connect_error != "":
            items.append(Text(self.connect_error, CAPTION).tone(TONE_ACCENT).max_width(460))
        items.append(HStack(Spacer(), Button("Cancel", CLOSE_CONNECT, SUBTLE), Button("Connect", CONNECT, PROMINENT), spacing=8).fill())
        return Dialog("Connect", VStack(items^, spacing=12).align(START).fill(), on_close=CLOSE_CONNECT, width=500)

    def view(self) -> View:
        var page = List[View]()
        page.append(self.top_bar())
        if self.engine_error != "":
            page.append(Card(Text(self.engine_error, CAPTION).tone(TONE_ACCENT), spacing=0).fill())
        page.append(self.query_view() if self.tab == QUERY else self.notebook_view())
        if self.connect_open:
            page.append(self.connect_dialog())
        if self.toast != "":
            page.append(Toast(self.toast, on_close=TOAST_GONE, seconds=3))
        return VStack(page^, spacing=14).fill().grow().padding(14, 16)
