# Contoso Retail: the made-up retailer behind the analytics and workbook showcases, as typed columns.
# Deterministic (the same rows every run), with seasonality, growth and 4%-a-year inflation.
#
#   day (DATE), category, region, channel, product (TEXT), quantity (INT), cents, cost (DECIMAL), year (INT)

from mojoui.frame import Column, Columns, INT, DECIMAL, TEXT, DATE

comptime DAYS = 1096  # 2023-01-01 … 2025-12-31
comptime EPOCH_2023 = 19358  # 2023-01-01 in days since 1970-01-01

comptime CATEGORIES: List[String] = ["Electronics", "Home", "Fashion", "Outdoor", "Beauty", "Toys", "Grocery", "Sports"]
comptime REGIONS: List[String] = ["North America", "Europe", "Asia Pacific", "Latin America", "Middle East"]
comptime CHANNELS: List[String] = ["Online", "Stores", "Partners"]
comptime PRODUCTS: List[String] = [
    "Noise-cancelling headphones", "4K TV 55\"", "Laptop 14\"", "Smart watch", "Tablet 11\"", "Wireless earbuds", "Game console", "Phone charger",
    "Espresso machine", "Robot vacuum", "Air fryer", "Duvet set", "Desk lamp", "Cookware set", "Office chair", "Bath towels",
    "Rain jacket", "Running shoes", "Denim jeans", "Wool sweater", "Sunglasses", "Leather bag", "Sneakers", "Summer dress",
    "Tent 4-person", "Hiking boots", "Camping stove", "Sleeping bag", "Backpack 40L", "Kayak paddle", "Garden hose", "BBQ grill",
    "Face serum", "Perfume", "Hair dryer", "Sunscreen", "Lipstick set", "Shampoo", "Electric shaver", "Nail kit",
    "Building blocks", "Board game", "RC car", "Plush bear", "Puzzle 1000", "Doll house", "Drone mini", "Art set",
    "Coffee beans", "Olive oil", "Chocolate box", "Green tea", "Pasta pack", "Honey jar", "Spice set", "Snack box",
    "Yoga mat", "Dumbbells", "Bike helmet", "Tennis racket", "Football", "Fitness band", "Water bottle", "Gym bag",
]

# column numbers
comptime DAY = 0
comptime CATEGORY = 1
comptime REGION = 2
comptime CHANNEL = 3
comptime PRODUCT = 4
comptime QUANTITY = 5
comptime CENTS = 6
comptime COST = 7
comptime YEAR = 8


def mix(z0: UInt64) -> UInt64:
    var z = z0 + 0x9E3779B97F4A7C15
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB
    return z ^ (z >> 31)


def uniform(i: Int, salt: Int) -> Float64:
    return Float64(Int(mix(UInt64(i) * 16 + UInt64(salt)) >> 11)) / 9007199254740992.0


def month_of(day: Int) -> Int:
    """Month 0–35 of day 0–1095 (2024 is a leap year)."""
    var lengths: List[Int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    var d = day
    for y in range(3):
        for m in range(12):
            var n = lengths[m] + (1 if y == 1 and m == 1 else 0)
            if d < n:
                return y * 12 + m
            d -= n
    return 35


def season(m: Int) -> Float64:
    """How busy each calendar month is (holiday peak, January dip)."""
    var s: List[Float64] = [0.78, 0.8, 0.92, 0.95, 1.0, 1.02, 0.98, 1.0, 0.96, 1.05, 1.42, 1.75]
    return s[m]


def generate_columns(n: Int) -> Columns:
    """n order lines as typed columns."""
    var cdf = List[Float64](length=DAYS, fill=0)
    var total = 0.0
    for d in range(DAYS):
        var weekend = 1.28 if (d + 6) % 7 >= 5 else 1.0  # 2023-01-01 was a Sunday
        total += (1.0 + 0.32 * Float64(d) / Float64(DAYS)) * weekend * season(month_of(d) % 12)
        cdf[d] = total
    var month_table = List[Int](length=DAYS, fill=0)
    for d in range(DAYS):
        month_table[d] = month_of(d)
    var price = List[Int](length=64, fill=0)  # cents per product
    var base: List[Int] = [24000, 9000, 7000, 12000, 4500, 3500, 1800, 5500]
    for p in range(64):
        price[p] = Int(Float64(base[p // 8]) * (0.45 + 1.7 * uniform(p, 99)))
    var cols = List[List[Int64]]()
    for _ in range(9):
        cols.append(List[Int64](length=n, fill=0))
    for i in range(n):
        var u = uniform(i, 0) * total
        var lo = 0
        var hi = DAYS - 1
        while lo < hi:
            var mid = (lo + hi) // 2
            if cdf[mid] < u:
                lo = mid + 1
            else:
                hi = mid
        var day = lo
        var m = month_table[day] % 12
        var t = Float64(day) / Float64(DAYS)
        var w: List[Float64] = [1.25, 1.0, 1.1, 0.75, 0.7, 0.55, 0.9, 0.7]
        if 4 <= m <= 7:
            w[3] = 1.6
            w[7] = 1.0
        if m >= 10:
            w[5] = 1.7
            w[0] = 1.8
        var wt = 0.0
        for x in w:
            wt += x
        var c = 0
        var pick = uniform(i, 1) * wt
        while c < 7 and pick >= w[c]:
            pick -= w[c]
            c += 1
        var rw: List[Float64] = [0.34, 0.27, 0.19 + 0.08 * t, 0.10, 0.07]
        var rt = 0.0
        for x in rw:
            rt += x
        var region = 0
        var pr = uniform(i, 2) * rt
        while region < 4 and pr >= rw[region]:
            pr -= rw[region]
            region += 1
        var online = 0.42 + 0.2 * t
        var pc = uniform(i, 3)
        var channel = 0 if pc < online else (1 if pc < 0.88 else 2)
        var product = c * 8 + min(Int(8.0 * uniform(i, 4) * uniform(i, 5) * 1.6), 7)
        var q = uniform(i, 6)
        var qty = 1 if q < 0.62 else (2 if q < 0.86 else (3 if q < 0.95 else 4 + Int(uniform(i, 7) * 3)))
        var discount = 0 if uniform(i, 8) < (0.55 if m >= 10 else 0.78) else (10 if uniform(i, 9) < 0.7 else 25)
        var inflation = 100 + 4 * (month_table[day] // 12)  # prices rise 4% a year
        var cents = qty * price[product] * (100 - discount) // 100 * inflation // 100
        var cost = qty * price[product] * (52 + (product * 7) % 21) // 100  # 52–72% of list price
        cols[DAY][i] = Int64(EPOCH_2023 + day)
        cols[CATEGORY][i] = Int64(c)
        cols[REGION][i] = Int64(region)
        cols[CHANNEL][i] = Int64(channel)
        cols[PRODUCT][i] = Int64(product)
        cols[QUANTITY][i] = Int64(qty)
        cols[CENTS][i] = Int64(cents)
        cols[COST][i] = Int64(cost)
        cols[YEAR][i] = Int64(2023 + month_table[day] // 12)
    var out = Columns()
    var names: List[String] = ["day", "category", "region", "channel", "product", "quantity", "cents", "cost", "year"]
    var kinds: List[Int] = [DATE, TEXT, TEXT, TEXT, TEXT, INT, DECIMAL, DECIMAL, INT]
    for k in range(9):
        var col = Column(names[k], kinds[k], 2 if kinds[k] == DECIMAL else 0)
        col.values = cols[k].copy()
        if k == CATEGORY:
            col.dictionary = materialize[CATEGORIES]()
        elif k == REGION:
            col.dictionary = materialize[REGIONS]()
        elif k == CHANNEL:
            col.dictionary = materialize[CHANNELS]()
        elif k == PRODUCT:
            col.dictionary = materialize[PRODUCTS]()
        out.add(col^)
    return out^
