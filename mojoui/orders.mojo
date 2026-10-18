# The planted-story orders ledger (docs/mx-studio/SCREENS.md, "The story every screen shares"), as typed
# columns. Deterministic: the same rows every run, at any size. The planted problems:
#   1. Acme's orders under three spellings: "Acme Corp", "Acme Corp." and "ACME Corporation" (merged, Acme is
#      the top customer).
#   2. Carrier A's rate table v7: from Jul 14 a flat $14.20 freight on parcels over 4 kg (before: ~$2 + 45¢/kg).
#      Heavy, cheap items (SKU OUT-4471, the $48 Cooler 45L) go to negative margin.
#   3. So Q3's gross margin falls about 3 points against Q2.
#   4. 412 orders imported twice, every copy at ZIP 94110 (a double import).
#
# Columns: order, day, customer, region, product, qty, revenue, cost, freight, carrier, weight_g, zip.

from mojoui.frame import Column, Columns, INT, DECIMAL, TEXT, DATE
from mojoui.contoso import uniform

comptime YEAR_START = 20089  # 2025-01-01, days since 1970-01-01
comptime RATE_CHANGE = 194  # day of the year of Jul 14 (Carrier A's v7)
comptime DAYS = 289  # Jan 1 … Oct 16
comptime DUPLICATES = 412
comptime DUP_ZIP = 94110
comptime FLAT_FREIGHT = 1420  # cents

comptime CUSTOMERS: List[String] = [
    "Acme Corp", "Acme Corp.", "ACME Corporation", "Northwind", "Globex", "Initech", "Umbrella Outdoor", "Stark Supply",
    "Wayne Trading", "Hooli Gear", "Vandelay Imports", "Soylent Retail", "Tyrell Goods", "Cyberdyne Camp", "Gringotts Co",
    "Wonka Trails", "Pied Piper Sport", "Duff Outfitters", "Oceanic Rentals", "Massive Dynamic",
]
comptime REGIONS: List[String] = ["West", "East", "Central", "South"]
comptime PRODUCTS: List[String] = ["Trail Pack", "Tent 2P", "Camp Stove", "Sleeping Bag", "Cooler 45L", "Kayak Paddle", "Water Jug 20L", "Headlamp"]
comptime SKUS: List[String] = ["OUT-1102", "OUT-2210", "OUT-3305", "OUT-3390", "OUT-4471", "OUT-5120", "OUT-6031", "OUT-7007"]
comptime PRICE: List[Int] = [12000, 28000, 12000, 9000, 4800, 15000, 3600, 3000]  # cents a unit
comptime GRAMS: List[Int] = [1400, 4600, 2100, 1800, 5200, 1200, 4400, 200]  # a unit's weight
comptime COST_PCT: List[Int] = [56, 58, 57, 55, 60, 54, 58, 50]
comptime MIX: List[Int] = [10, 6, 10, 10, 24, 6, 24, 10]  # how often each product sells (heavy, cheap ones are common)
comptime CARRIERS: List[String] = ["Carrier A", "Carrier B", "Carrier C"]

# column numbers
comptime ORDER = 0
comptime DAY = 1
comptime CUSTOMER = 2
comptime REGION = 3
comptime PRODUCT = 4
comptime QTY = 5
comptime REVENUE = 6
comptime COST = 7
comptime FREIGHT = 8
comptime CARRIER = 9
comptime WEIGHT = 10
comptime ZIP = 11


def customer_of(i: Int) -> Int:
    """Acme ~20% of orders across its three spellings (60/25/15), then the named accounts, then a long tail."""
    var u = uniform(i, 11)
    if u < 0.20:
        var s = uniform(i, 12)
        return 0 if s < 0.60 else (1 if s < 0.85 else 2)
    if u < 0.32:
        return 3
    if u < 0.43:
        return 4
    if u < 0.52:
        return 5
    return 6 + Int(uniform(i, 13) * 14.0)


def freight_of(carrier: Int, grams: Int, day: Int) -> Int:
    """Cents. Carrier A's v7 (from Jul 14): a flat $14.20 on parcels over 4 kg."""
    if carrier == 0 and day >= RATE_CHANGE and grams > 4000:
        return FLAT_FREIGHT
    if carrier == 0:
        return 200 + grams * 45 // 1000
    return 250 + grams * 50 // 1000


def order_row(i: Int) -> SIMD[DType.int64, 16]:
    """Order i (before the double import is applied): a value per column, in column order (the other four lanes are 0)."""
    var day = Int(uniform(i, 1) * Float64(DAYS))
    var pick = uniform(i, 2) * 100.0
    var product = 0
    var mix = materialize[MIX]()
    while product < 7 and pick >= Float64(mix[product]):
        pick -= Float64(mix[product])
        product += 1
    var qty = 1 if uniform(i, 3) < 0.7 else (2 if uniform(i, 4) < 0.7 else 3)
    var grams = materialize[GRAMS]()[product] * qty
    var region = Int(uniform(i, 7) * 4.0)
    # Carrier A carries most heavy parcels, nearly all of them in the West (where the story's margin falls)
    var a_share = (0.92 if region == 0 else 0.68) if grams > 4000 else 0.45
    var carrier = 0 if uniform(i, 5) < a_share else (1 if uniform(i, 6) < 0.6 else 2)
    var revenue = materialize[PRICE]()[product] * qty
    var cost = revenue * materialize[COST_PCT]()[product] // 100
    var row = SIMD[DType.int64, 16](0)
    row[ORDER] = Int64(100000 + i)
    row[DAY] = Int64(YEAR_START + day)
    row[CUSTOMER] = Int64(customer_of(i))
    row[REGION] = Int64(region)
    row[PRODUCT] = Int64(product)
    row[CARRIER] = Int64(carrier)
    row[ZIP] = Int64(10001 + Int(uniform(i, 8) * 89000.0))
    if row[ZIP] == DUP_ZIP:
        row[ZIP] = Int64(DUP_ZIP + 1)  # (only the double import uses 94110)
    row[WEIGHT] = Int64(grams)
    row[QTY] = Int64(qty)
    row[REVENUE] = Int64(revenue)
    row[COST] = Int64(cost)
    row[FREIGHT] = Int64(freight_of(carrier, grams, day))
    return row


def order_columns(n: Int) -> Columns:
    """n rows: n - 412 orders, then 412 of them again (the double import, all at ZIP 94110)."""
    var originals = max(n - DUPLICATES, DUPLICATES)
    var total = originals + DUPLICATES
    var cols = List[List[Int64]]()
    for _ in range(12):
        cols.append(List[Int64](length=total, fill=0))
    for i in range(originals):
        var row = order_row(i)
        for c in range(12):
            cols[c][i] = row[c]
    # the double import: 412 orders from late September, copied whole, their ZIP set to 94110 in both copies
    var start = originals - DUPLICATES * 7
    for d in range(DUPLICATES):
        var src = start + d * 7
        cols[ZIP][src] = DUP_ZIP
        for c in range(12):
            cols[c][originals + d] = cols[c][src]
    var out = Columns()
    var names: List[String] = ["order", "day", "customer", "region", "product", "qty", "revenue", "cost", "freight", "carrier", "weight_g", "zip"]
    var kinds: List[Int] = [INT, DATE, TEXT, TEXT, TEXT, INT, DECIMAL, DECIMAL, DECIMAL, TEXT, INT, INT]
    for k in range(12):
        var col = Column(names[k], kinds[k], 2 if kinds[k] == DECIMAL else 0)
        col.values = cols[k].copy()
        if k == CUSTOMER:
            col.dictionary = materialize[CUSTOMERS]()
        elif k == REGION:
            col.dictionary = materialize[REGIONS]()
        elif k == PRODUCT:
            col.dictionary = materialize[PRODUCTS]()
        elif k == CARRIER:
            col.dictionary = materialize[CARRIERS]()
        out.add(col^)
    return out^
