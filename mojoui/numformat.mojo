# mojoui.numformat: how a column's values read (Numbers' "Data Format"): number, currency, percent, compact,
# dates. One format per column, never per cell (docs/plans/formatting.md): it's applied only to what's on screen,
# so it costs nothing on 100M rows. Values arrive as the engine stores them: integers scaled by 10^scale.

comptime AUTO = 0  # as the column's type says (the engine's own text)
comptime NUMBER = 1  # 1,234.50
comptime CURRENCY = 2  # $1,234.50
comptime PERCENT = 3  # 0.364 → 36.4%
comptime COMPACT = 4  # 1.2M, $3.4K
comptime DATE_LONG = 5  # 9 Oct 2025
comptime DATE_MONTH = 6  # Oct 2025
comptime DATE_ISO = 7  # 2025-10-09

comptime NUMBER_STYLES: List[String] = ["Automatic", "Number", "Currency", "Percent", "Compact (1.2M)"]
comptime DATE_STYLES: List[String] = ["Automatic", "9 Oct 2025", "Oct 2025", "2025-10-09"]
comptime MONTHS: List[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


@fieldwise_init
struct ColumnFormat(Copyable, Movable):
    var style: Int  # AUTO, NUMBER, CURRENCY, PERCENT, COMPACT, DATE_*
    var decimals: Int  # digits after the point (-1: the column's own)
    var thousands: Bool  # 1,234 rather than 1234
    var parens: Bool  # negatives as (1,234) rather than −1,234
    var symbol: String  # currency symbol

    @staticmethod
    def auto() -> ColumnFormat:
        return ColumnFormat(AUTO, -1, True, False, "$")

    def is_auto(self) -> Bool:
        return self.style == AUTO

    def summary(self) -> String:
        """What it does, in words (the inspector, tests)."""
        var names = materialize[NUMBER_STYLES]()
        if self.style >= DATE_LONG:
            return "Date " + materialize[DATE_STYLES]()[self.style - DATE_LONG + 1]
        return names[self.style] + (", " + String(self.decimals) + " decimals" if self.decimals >= 0 else "")


def pow10(n: Int) -> Int64:
    var p = Int64(1)
    for _ in range(n):
        p *= 10
    return p


def group_digits(digits: String) -> String:
    var out = String("")
    var n = digits.byte_length()
    for i in range(n):
        if i > 0 and (n - i) % 3 == 0:
            out += ","
        out += String(digits[byte = i : i + 1])
    return out


def fixed(v: Int64, scale: Int, decimals: Int, thousands: Bool) -> String:
    """|v| / 10^scale with `decimals` digits (rounded half away from zero), no sign."""
    var a = v if v >= 0 else -v
    var d = decimals if decimals >= 0 else scale
    var scaled: Int64
    if d >= scale:
        scaled = a * pow10(d - scale)
    else:
        var div = pow10(scale - d)
        scaled = (a + div // 2) // div
    var p = pow10(d)
    var whole = String(scaled // p)
    var text = group_digits(whole) if thousands else whole
    if d > 0:
        var frac = String(scaled % p)
        while frac.byte_length() < d:
            frac = "0" + frac
        text += "." + frac
    return text


def signed(text: String, negative: Bool, parens: Bool) -> String:
    var zero = True  # (−0.00 reads as 0.00)
    for ch in text.codepoint_slices():
        var c = String(ch)
        if c >= "1" and c <= "9":
            zero = False
    if not negative or zero:
        return text
    return "(" + text + ")" if parens else "−" + text


def compact_text(v: Int64, scale: Int, decimals: Int) -> String:
    var x = Float64(v if v >= 0 else -v) / Float64(pow10(scale))
    var unit = String("")
    if x >= 1e9:
        x /= 1e9
        unit = "B"
    elif x >= 1e6:
        x /= 1e6
        unit = "M"
    elif x >= 1e3:
        x /= 1e3
        unit = "K"
    var d = decimals if decimals >= 0 else (1 if unit != "" else 0)
    var tenth = Int64(x * Float64(pow10(d)) + 0.5)
    return fixed(tenth, d, d, True) + unit


def civil(days: Int) -> Tuple[Int, Int, Int]:
    """Days since 1970-01-01 → (year, month, day)."""
    var z = days + 719468
    var era = (z if z >= 0 else z - 146096) // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var y = yoe + era * 400
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var d = doy - (153 * mp + 2) // 5 + 1
    var m = mp + (3 if mp < 10 else -9)
    return (y + (1 if m <= 2 else 0), m, d)


def format_number(v: Int64, scale: Int, f: ColumnFormat) -> String:
    """A number column's value (scaled by 10^scale) in format f."""
    var neg = v < 0
    if f.style == PERCENT:
        var d = f.decimals if f.decimals >= 0 else max(scale - 2, 0)
        var text = fixed(v, scale - 2, d, f.thousands) if scale >= 2 else fixed(v * pow10(2 - scale), 0, d, f.thousands)
        return signed(text, neg, f.parens) + "%"
    if f.style == COMPACT:
        return signed(compact_text(v, scale, f.decimals), neg, f.parens)
    if f.style == CURRENCY:
        var d = f.decimals if f.decimals >= 0 else 2
        return signed(f.symbol + fixed(v, scale, d, f.thousands), neg, f.parens)
    return signed(fixed(v, scale, f.decimals, f.thousands), neg, f.parens)


def format_date(days: Int64, f: ColumnFormat) -> String:
    var ymd = civil(Int(days))
    var months = materialize[MONTHS]()
    if f.style == DATE_LONG:
        return String(ymd[2]) + " " + months[ymd[1] - 1] + " " + String(ymd[0])
    if f.style == DATE_MONTH:
        return months[ymd[1] - 1] + " " + String(ymd[0])
    return String(ymd[0]) + "-" + ("0" if ymd[1] < 10 else "") + String(ymd[1]) + "-" + ("0" if ymd[2] < 10 else "") + String(ymd[2])
