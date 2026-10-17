const OPTIONS = [
  ["ledger", "A · Ledger", "Light and classic, like Excel or Numbers: white sheet, quiet grey chrome, one deep teal accent. The safest choice for long sessions and for screenshots in slides and docs."],
  ["graphite", "B · Graphite", "Dark and neutral, for people who live in VS Code and Jupyter: no blue tint, crisp white figures, a warm amber accent that is easy to find on dark."],
  ["blueprint", "C · Blueprint", "Light with a branded navy band, the way Office apps carry a coloured title bar: instantly recognisable as omxplorer on any desktop, the sheet itself stays white and calm."],
];
const I = {
  open:'<path d="M3 7h6l2 2h10v10H3z"/>', save:'<path d="M5 3h11l3 3v15H5z M8 3v6h8 M8 21v-7h8v7"/>', undo:'<path d="M9 14 4 9l5-5 M4 9h10a6 6 0 0 1 0 12h-3"/>', redo:'<path d="m15 14 5-5-5-5 M20 9H10a6 6 0 0 0 0 12h3"/>',
  table:'<path d="M3 4h18v16H3z M3 10h18 M3 15h18 M9 4v16"/>', chart:'<path d="M4 20V10 M10 20V4 M16 20v-7 M3 20h18"/>', pivot:'<path d="M3 3h18v18H3z M3 9h18 M9 3v18 M13 13h5 M13 16h5"/>',
  formula:'<path d="M9 20c2 0 2-3 3-8s1-8 3-8 M8 11h8"/>', row:'<path d="M3 5h18v6H3z M12 15v6 M9 18h6"/>', sort:'<path d="M7 4v16 M3 16l4 4 4-4 M17 20V4 M13 8l4-4 4 4"/>',
  search:'<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>', plus:'<path d="M12 5v14 M5 12h14"/>', x:'<path d="M6 6l12 12 M18 6 6 18"/>',
  check:'<path d="m5 12 5 5 9-10"/>', right:'<path d="m9 6 6 6-6 6"/>', down:'<path d="m6 9 6 6 6-6"/>', upload:'<path d="M12 16V4 M7 9l5-5 5 5 M4 16v4h16v-4"/>',
  file:'<path d="M6 3h8l5 5v13H6z M14 3v5h5"/>', gear:'<circle cx="12" cy="12" r="3"/><path d="M12 2v3 M12 19v3 M2 12h3 M19 12h3 M5 5l2 2 M17 17l2 2 M5 19l2-2 M17 7l2-2"/>',
  info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6 M12 7.5v.5"/>', alert:'<path d="M12 3 2 20h20z M12 10v4 M12 17v.5"/>', trash:'<path d="M4 7h16 M9 7V4h6v3 M6 7l1 13h10l1-13"/>',
  copy:'<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V4H4v12h4"/>', eyeoff:'<path d="M3 3l18 18 M10.6 6.1A9.7 9.7 0 0 1 12 6c6 0 9 6 9 6a15 15 0 0 1-2.4 3.2 M6.6 6.6C4.1 8.2 3 12 3 12s3 6 9 6c1.6 0 3-.4 4.2-1"/>',
  rename:'<path d="M4 20h16 M14 4l4 4-9 9H5v-4z"/>', db:'<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5 M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>',
  sparkle:'<path d="M12 3v4 M12 17v4 M3 12h4 M17 12h4 M6 6l2.5 2.5 M15.5 15.5 18 18 M6 18l2.5-2.5 M15.5 8.5 18 6"/>', group:'<path d="M3 6h7 M3 12h7 M3 18h7 M14 6h7v12h-7z"/>',
  filter:'<path d="M3 4h18l-7 9v6l-4 2v-8z"/>', format:'<path d="M4 20h4L19 9l-4-4L4 16z M13 7l4 4"/>', kpi:'<path d="M4 18h16 M6 14l4-5 4 3 5-7"/>', text:'<path d="M5 6V4h14v2 M12 4v16 M9 20h6"/>',
};
const svg = k => `<svg viewBox="0 0 24 24">${I[k]}</svg>`;
const tool = (k, label, cls="") => `<div class="tool ${cls}">${svg(k)}${label}</div>`;
// deterministic data
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const REG = ["West","East","North","South","Central"], PROD = ["Desk Chair","Monitor Arm","Standing Desk","Lamp","Keyboard","Webcam"], CAR = ["UPS","FedEx","DHL","USPS"];
const CUST = ["Acme Labs","Northwind","Globex","Initech","Umbrella Co","Hooli","Stark Ind.","Wayne Ent.","Vandelay","Soylent"];
const money = v => "$" + v.toLocaleString("en-US", {minimumFractionDigits:2, maximumFractionDigits:2});
const rows = Array.from({length:22}, (_, i) => {
  const qty = 1 + Math.floor(rnd()*9), rev = Math.round((40 + rnd()*1900) * 100) / 100, cost = Math.round(rev * (0.55 + rnd()*0.2) * 100) / 100;
  return [String(1048213 + i*37), `2026-07-${String(1 + Math.floor(rnd()*28)).padStart(2,"0")}`, REG[Math.floor(rnd()*5)], CUST[Math.floor(rnd()*10)], PROD[Math.floor(rnd()*6)], CAR[Math.floor(rnd()*4)], qty, rev, cost];
});
const hist = n => Array.from({length:n}, (_, k) => `<i style="height:${Math.round(18 + 80*Math.exp(-((k - n*0.32)**2)/(n*1.4)) + rnd()*10)}%"></i>`).join("");
const flat = n => Array.from({length:n}, () => `<i style="height:${Math.round(40 + rnd()*55)}%"></i>`).join("");

const MENUS = ["File","Edit","View","Insert","Data","Format","Window","Help"];
function chrome(doc, report, open = "") {
  return `
  <div class="titlebar"><div class="dots"><i></i><i></i><i></i></div><span class="brand">o<b>mx</b>plorer</span>
    <nav class="menus">${MENUS.map(m => `<span class="${m === open ? "open" : ""}">${m}</span>`).join("")}</nav>
    <span class="doc"><strong>${doc}</strong> — 1,000,000 rows</span><button class="tbtn">Share</button><button class="tbtn primary">Save</button></div>
  <div class="toolbar">
    <div class="group">${tool("open","Open")}${tool("save","Save")}${tool("undo","Undo")}${tool("redo","Redo")}</div>
    <div class="group">${tool("table","Table")}${tool("chart","Chart", report ? "" : "hover")}${tool("pivot","Pivot")}${tool("formula","Formula", report ? "" : "on")}${report ? tool("kpi","KPI","on") + tool("text","Text") : tool("row","Add row")}</div>
    <div class="group">${tool("sort","Sort")}${tool("filter","Filter", report ? "on" : "")}</div>
    <div class="spacer"></div><div class="group">${tool("format","Format","on")}</div>
  </div>`;
}
function bottom(report) {
  return `<div class="bottom"><div class="stabs"><span class="stab ${report ? "" : "on"}">Orders</span><span class="stab ${report ? "on" : ""}">Report</span><span class="stab plus">+</span></div>
    <div class="status num">${report ? `<span>Filtered <b>255,102</b> of 1,000,000 rows</span>` :
      `<span>Sum <b>$72,061,236.00</b></span><span>Average <b>$72.06</b></span><span>Count <b>1,000,000</b></span>`}
      <span class="gpu"><i></i>RTX 4090 · <b>${report ? "4.1" : "0.3"} ms</b></span></div></div>`;
}
function sheet(doc="orders.csv") {
  const cols = [["order_id","#"],["date","📅"],["region","Aa"],["customer","Aa"],["product","Aa"],["carrier","Aa"],["qty","#"],["revenue","$"],["cost","$"],["margin","ƒx"]];
  const widths = [84,98,92,104,112,72,84,134,134,134];
  const head = cols.map(([n,b], c) => `<th class="${c===7?"selcol":""}" style="width:${widths[c]}px">${n}<span class="badge ${b==="ƒx"?"fx2":""}">${b==="📅"?"date":b}</span><div class="hist">${b==="Aa"? flat(c===2?5:c===5?4:12) : hist(16)}</div></th>`).join("");
  const body = rows.map((r, i) => `<tr><td class="rn num">${i+1}</td>
    <td class="num">${r[0]}</td><td class="num">${r[1]}</td><td>${r[2]}</td><td>${r[3]}</td><td>${r[4]}</td><td>${r[5]}</td>
    <td class="n num">${r[6]}</td><td class="n num selcol ${i===11?"cur":""}">${money(r[7])}</td><td class="n num">${money(r[8])}</td><td class="n num f">${money(Math.round((r[7]-r[8])*100)/100)}</td></tr>`).join("");
  return `<div class="app">${chrome(doc,false)}
  <div class="fbar"><span class="ref num">J12</span><span class="fx">fx</span><div class="finput num"><span class="c">margin</span> <span class="op">=</span> <span class="c">revenue</span> <span class="op">−</span> <span class="c">cost</span></div><span class="iconbtn">✕</span><span class="iconbtn ok">✓</span></div>
  <div class="work"><div class="gridwrap"><table class="grid"><thead><tr><th class="rn"></th>${head}</tr></thead><tbody>${body}
    <tr class="total"><td class="rn"></td><td colspan="6">Total · 1,000,000 rows</td><td class="n num">5,002,114</td><td class="n num">$72,061,236.00</td><td class="n num">$46,124,980.12</td><td class="n num f" style="color:var(--formula)">$25,936,255.88</td></tr></tbody></table></div>
  <div class="insp"><div class="itabs"><span class="on">Format</span><span>Column</span><span>Table</span></div>
    <div class="sec"><h4>Number</h4><div class="segc"><span>Auto</span><span>Number</span><span class="on">Currency</span><span>Percent</span></div>
      <div class="prow">Decimals<div class="stepper num"><span>−</span><span>2</span><span>+</span></div></div>
      <div class="prow">Thousands separator<div class="switch"></div></div>
      <div class="prow">Negatives<div class="segc num" style="width:150px"><span class="on">−1,234</span><span>(1,234)</span></div></div>
      <div class="prow">Symbol<div class="dd">$ USD</div></div></div>
    <div class="sec"><h4>Column stats · revenue</h4><div class="stats"><span>Count</span><span>1,000,000</span><span>Empty</span><span>0</span><span>Distinct</span><span>812,441</span><span>Min</span><span>$4.20</span><span>Max</span><span>$9,980.00</span><span>Mean</span><span>$72.06</span></div>
      <div class="bighist">${hist(28)}</div><div class="prow" style="font-size:11px;color:var(--sub)"><span class="num">$0</span><span>computed on the GPU in 0.3 ms</span><span class="num">$10k</span></div></div>
  </div></div>${bottom(false)}</div>`;
}
function spark(up) {
  let y = 20, pts = []; for (let i = 0; i < 16; i++) { y += (rnd() - (up ? .62 : .4)) * 6; y = Math.max(3, Math.min(25, y)); pts.push(`${i*6},${y.toFixed(1)}`); }
  return `<svg width="92" height="28"><polyline points="${pts.join(" ")}" fill="none" stroke="var(--s1)" stroke-width="1.6"/></svg>`;
}
function report() {
  const kpi = (l, v, d, up, sel) => `<div class="kpi ${sel?"sel":""}"><span class="l">${l}</span><span class="v">${v}</span><div class="foot"><span class="delta ${up?"up":"dn"}">${d}</span>${spark(up)}</div></div>`;
  const months = [4.9,5.2,5.0,5.6,5.9,5.7,6.1,6.3,6.0], W = 560, H = 170;
  const px = i => 40 + i * (W - 60) / 8, py = v => H - 22 - (v - 4.5) / 2.1 * (H - 40);
  const line = `<svg width="100%" viewBox="0 0 ${W} ${H}">${[5,5.5,6,6.5].map(v=>`<line x1="40" x2="${W-10}" y1="${py(v)}" y2="${py(v)}" stroke="var(--line)"/><text x="4" y="${py(v)+3}">$${v}M</text>`).join("")}
    <polyline points="${months.map((v,i)=>`${px(i)},${py(v)}`).join(" ")}" fill="none" stroke="var(--s1)" stroke-width="2"/>
    ${months.map((v,i)=>`<text x="${px(i)-8}" y="${H-4}">${"JFMAMJJAS"[i]}</text>`).join("")}
    <circle cx="${px(7)}" cy="${py(6.3)}" r="5" fill="var(--surface)" stroke="var(--s1)" stroke-width="2"/>
    <rect x="${px(7)-46}" y="${py(6.3)-32}" width="92" height="20" rx="4" fill="var(--ink)"/><text x="${px(7)-40}" y="${py(6.3)-18}" style="fill:var(--surface)">Aug · $6.3M</text></svg>`;
  const car = [["UPS",7.1],["FedEx",5.4],["DHL",3.6],["USPS",2.3]];
  const bars = `<svg width="100%" viewBox="0 0 ${W} ${H}">${car.map(([n,v],i)=>`<text x="4" y="${30+i*36}">${n}</text><rect x="60" y="${17+i*36}" width="${v/7.1*400}" height="20" rx="3" fill="var(--s${i+1})"/><text x="${68+v/7.1*400}" y="${31+i*36}" style="fill:var(--ink)">$${v}M</text>`).join("")}</svg>`;
  const P = ["Desk Chair","Monitor Arm","Standing Desk","Lamp","Keyboard"];
  const pv = `<table class="pv"><tr><th>region</th>${P.map(p=>`<th>${p}</th>`).join("")}<th>Total</th></tr>
    ${REG.map(r=>{ const v = P.map(()=>0.4+rnd()*1.2); return `<tr><td>${r}</td>${v.map(x=>`<td>$${x.toFixed(2)}M</td>`).join("")}<td class="t">$${v.reduce((a,b)=>a+b).toFixed(2)}M</td></tr>`}).join("")}
    <tr class="t"><td>Total</td>${P.map(()=>`<td>$${(3+rnd()*3).toFixed(2)}M</td>`).join("")}<td>$18.40M</td></tr></table>`;
  return `<div class="app">${chrome("orders.omx",true)}
  <div class="fbar"><span class="ref num">Tile 1</span><span class="fx">fx</span><div class="finput num" style="border-color:var(--line);box-shadow:none"><span class="c">sum</span>(<span class="c">revenue</span>) <span class="op">where</span> <span class="c">region</span> <span class="op">=</span> "West"</div></div>
  <div class="work"><div class="rwrap"><div class="rpage">
    <div class="rhead"><h1>Q3 orders</h1><span>Updated just now · 1,000,000 rows · 4.1 ms on the GPU</span></div>
    <div class="chips"><span class="chip on">region = West</span><span class="chip on">date: Jul–Sep 2026</span><span class="chip">carrier: all</span><span class="chip add">+ Filter</span></div>
    <div class="kpis">${kpi("Revenue","$18.4M","+4.2%",1,1)}${kpi("Orders","255,102","+1.1%",1)}${kpi("Average order","$72.06","−0.8%",0)}${kpi("Margin","31.4%","+0.6 pts",1)}</div>
    <div class="charts"><div class="card"><h3>Revenue by month</h3>${line}</div><div class="card"><h3>Revenue by carrier</h3>${bars}</div></div>
    <div class="card"><h3>Revenue · region × product</h3>${pv}</div>
  </div></div>
  <div class="insp"><div class="itabs"><span class="on">Tile</span><span>Data</span></div>
    <div class="sec"><h4>Value</h4><div class="prow">Column<div class="dd">revenue</div></div><div class="segc"><span class="on">Sum</span><span>Average</span><span>Count</span></div></div>
    <div class="sec"><h4>Compare</h4><div class="prow">Compare to<div class="dd">previous quarter</div></div><div class="prow">Show sparkline<div class="switch"></div></div></div>
    <div class="sec"><h4>Format</h4><div class="segc"><span>Auto</span><span>Number</span><span class="on">Compact</span></div><div class="prow">Symbol<div class="dd">$ USD</div></div></div>
  </div></div>${bottom(true)}</div>`;
}
function phone(custom = "", h = 330) {
  const t = (k,l) => `<span>${svg(k)}${l}</span>`;
  const body = rows.slice(0,9).map((r,i)=>`<tr><td class="rn num">${i+1}</td><td class="num">${r[0]}</td><td>${r[2]}</td><td class="n num selcol">${money(r[7])}</td></tr>`).join("");
  return `<div class="ph"><div class="top">‹<span>orders.csv</span>⋯</div>
    <div class="tools">${t("chart","Chart")}${t("pivot","Pivot")}${t("formula","Formula")}${t("sort","Sort")}${t("filter","Filter")}${t("format","Format")}</div>
    <table class="grid" style="background:var(--surface)"><thead><tr><th class="rn" style="width:34px"></th><th style="width:96px">order_id<div class="hist">${hist(10)}</div></th><th style="width:84px">region<div class="hist">${flat(5)}</div></th><th class="selcol">revenue<span class="badge">$</span><div class="hist">${hist(12)}</div></th></tr></thead><tbody>${body}</tbody></table>
    <div class="sheet" style="height:${h}px"><div class="grab"></div>${custom || `<div style="display:flex;justify-content:space-between;align-items:baseline"><b style="font-size:16px">revenue</b><span style="color:var(--sub);font-size:12px">Currency · 2 decimals</span></div>
      <div class="stats" style="font-size:13px"><span>Sum</span><span>$72,061,236.00</span><span>Average</span><span>$72.06</span><span>Count</span><span>1,000,000</span></div>
      <div class="bighist">${hist(22)}</div>`}</div>
    <div class="tabbar"><span class="on">Sheet</span><span>Report</span><span>+</span></div></div>`;
}
