# omxqua as a mojoui theme: the Developer family ("Graphite"), night or light. Material texture (opaque tonal
# surfaces, one soft shadow, no glass, blur or gradients), pills for what's tappable, Geist and Geist Mono.
# The values are omxqua's tokens (docs/omxqua/src/tokens.css, .oq-family-dev), so a native window matches a page.
#
#   def theme(self) -> Theme: return omxqua(dark=True)

from mojoui.text import REGULAR, MEDIUM
from mojoui.theme import Palette, Theme, hx, mix, hex_of


def omxqua_palette(dark: Bool) -> Palette:
    var p: Palette
    if dark:
        p = Palette(True, hx("#0b0b0d"), hx("#151518"), hx("#1d1d21"), hx("#ededef"), hx("#a9a9b1"), hx("#8a8a93"),
                    hx("#202025"), hx("#2a2a30"), hx("#ededef"), hx("#0b0b0d"), mix(hx("#151518"), hx("#ededef"), 0.40),
                    mix(hx("#151518"), hx("#ededef"), 0.10), hx("#8b7bff"), hx("#3ccf6e"), hx("#f2555a"), hx("#f5a524"), REGULAR, MEDIUM)
        p.series = [hx("#8b7bff"), hx("#3aa0ff"), hx("#2bc3ad"), hx("#ff8a3d"), hx("#f2555a"), hx("#e0b400")]
    else:
        p = Palette(False, hx("#eeeef1"), hx("#ffffff"), hx("#ffffff"), hx("#0b0b0d"), hx("#5b5b63"), hx("#6b6b73"),
                    hx("#efeff2"), hx("#e3e3e8"), hx("#0b0b0d"), hx("#ffffff"), mix(hx("#ffffff"), hx("#0b0b0d"), 0.40),
                    mix(hx("#ffffff"), hx("#0b0b0d"), 0.06), hx("#6d5cf0"), hx("#137036"), hx("#c01f25"), hx("#8f5400"), REGULAR, MEDIUM)
        p.series = [hx("#6d5cf0"), hx("#0a7fe0"), hx("#0f9483"), hx("#e0661a"), hx("#d42a2f"), hx("#a88400")]
    return p^


def omxqua_gtk(p: Palette) -> String:
    var page = hex_of(p.page)
    var s1 = hex_of(p.card)
    var s2 = hex_of(p.raised) if p.dark else hex_of(mix(p.page, p.card, 0.5))
    var s3 = hex_of(mix(p.raised, p.ink, 0.06))
    var ink = hex_of(p.ink)
    var ink2 = hex_of(p.ink2)
    var line = hex_of(p.line_strong)
    var line2 = hex_of(p.line)
    var accent = hex_of(p.accent)
    var on_accent = hex_of(p.accent_ink)
    var hover = hex_of(mix(p.card, p.ink, 0.08))
    var press = hex_of(mix(p.card, p.ink, 0.12))
    var fill_hover = hex_of(mix(p.accent, p.page, 0.10))
    var bad = hex_of(p.bad)
    var shadow1 = String("0 1px 2px rgba(0,0,0,.5)") if p.dark else String("0 1px 2px rgba(20,16,10,.06), 0 0 0 1px rgba(20,16,10,.045)")
    var shadow3 = String("0 18px 48px rgba(0,0,0,.6)") if p.dark else String("0 18px 48px rgba(20,16,10,.18), 0 0 0 1px rgba(20,16,10,.06)")
    var w = String("window.omxqua ")
    var ease = String("cubic-bezier(.2,0,0,1)")
    return (
        ":root { --accent-bg-color: " + accent + "; --accent-color: " + accent + "; --accent-fg-color: " + on_accent + "; }\n"
        + w + "{ background-color: " + page + "; color: " + ink + "; font-family: 'Geist', sans-serif; font-size: 13.5px; }\n"
        + w + "label { color: " + ink + "; }\n"
        + w + "label.title-1 { font-size: 20px; font-weight: 600; letter-spacing: -0.2px; }\n"
        + w + "label.title-4 { font-size: 14px; font-weight: 600; }\n"
        + w + "label.caption { font-size: 12px; color: " + ink2 + "; } " + w + ".dim-label { opacity: 1; color: " + ink2 + "; }\n"
        + w + "label.mui-tone-warn { color: " + hex_of(p.warn) + "; } " + w + "label.mui-tone-good { color: " + hex_of(p.good) + "; }\n"
        + w + "label.mui-tone-strong { font-weight: 600; } " + w + "label.mui-tone-accent { color: " + hex_of(p.bad) + "; }\n"
        + w + ".mui-tag-mono, " + w + ".mui-tag-mono label { font-family: 'Geist Mono', monospace; font-size: 12px; }\n"
        + w + ".mui-tag-src, " + w + ".mui-tag-src label { font-family: 'Geist Mono', monospace; font-size: 11.5px; color: " + ink2 + "; }\n"
        # cards: one tone up from the page, one soft shadow, 12px corners
        + w + ".mui-card { background-color: " + s1 + "; border-radius: 12px; padding: 14px 16px; box-shadow: " + shadow1 + ", inset 0 0 0 1px " + line2 + "; }\n"
        + w + ".mui-card.mui-warn { box-shadow: inset 0 0 0 1px " + hex_of(mix(p.card, p.warn, 0.55)) + "; }\n"
        + w + ".mui-card.mui-good { box-shadow: inset 0 0 0 1px " + hex_of(mix(p.card, p.good, 0.50)) + "; }\n"
        + w + ".mui-island { background-color: " + s2 + "; border-radius: 999px; padding: 4px 8px; min-height: 34px; box-shadow: " + shadow1 + "; }\n"
        # buttons: pills; PLAIN is tonal, PROMINENT the one filled button, SUBTLE text only
        + w + "button { border-radius: 999px; min-height: 30px; padding: 0 14px; font-weight: 550; background: " + s2 + "; color: " + ink + "; box-shadow: " + shadow1 + "; transition: background 150ms " + ease + "; }\n"
        + w + "button:hover { background: " + s3 + "; } " + w + "button:active { background: " + press + "; }\n"
        + w + "button label, " + w + "button image { color: inherit; }\n"
        + w + "button.suggested-action { background: " + accent + "; color: " + on_accent + "; }\n"
        + w + "button.suggested-action:hover { background: " + fill_hover + "; }\n"
        + w + "button.destructive-action { background: transparent; color: " + bad + "; box-shadow: inset 0 0 0 1px " + hex_of(mix(p.card, p.bad, 0.4)) + "; }\n"
        + w + "button.flat { background: transparent; box-shadow: none; color: " + ink2 + "; }\n"
        + w + "button.flat:hover { background: " + hover + "; color: " + ink + "; }\n"
        + w + "button.image-button { min-width: 30px; padding: 0 6px; }\n"
        + w + ".mui-tag-row button, " + w + "button.mui-tag-row { border-radius: 8px; min-height: 28px; padding: 0 8px; }\n"
        + w + ".mui-tag-chip button, " + w + "button.mui-tag-chip { min-height: 24px; padding: 0 10px; font-family: 'Geist Mono', monospace; font-size: 12px; }\n"
        # fields: 10px corners, a hairline, a 2px accent ring when focused
        + w + "entry, " + w + "dropdown > button { border-radius: 10px; min-height: 34px; background: " + s1 + "; color: " + ink + "; box-shadow: inset 0 0 0 1px " + line + "; }\n"
        + w + "entry:hover { box-shadow: inset 0 0 0 1px " + ink2 + "; }\n"
        + w + "entry:focus-within { box-shadow: inset 0 0 0 2px " + accent + "; outline: none; }\n"
        + w + "textview { border-radius: 10px; background: " + page + "; box-shadow: inset 0 0 0 1px " + line + "; padding: 10px; font-family: 'Geist Mono', monospace; font-size: 13px; }\n"
        + w + "textview text { background: " + page + "; color: " + ink + "; }\n"
        + w + "textview:focus-within { box-shadow: inset 0 0 0 2px " + accent + "; }\n"
        # segmented and tabs: a sliding thumb on a tonal track
        + w + "toggle-group { background: " + page + "; border-radius: 999px; padding: 3px; box-shadow: inset 0 0 0 1px " + line2 + "; }\n"
        + w + "toggle-group > toggle { border-radius: 999px; min-height: 26px; padding: 0 14px; color: " + ink2 + "; font-weight: 550; transition: background 200ms " + ease + "; }\n"
        + w + "toggle-group > toggle:checked { background: " + s3 + "; color: " + ink + "; box-shadow: " + shadow1 + "; }\n"
        # dialogs, popovers, toasts
        + w + "dialog > sheet, " + w + "dialog.mui-dialog-surface, .mui-dialog { border-radius: 14px; background: " + s2 + "; color: " + ink + "; }\n"
        + w + "dialog > sheet { box-shadow: " + shadow3 + "; }\n"
        + w + ".mui-dialog-head label { font-size: 16px; font-weight: 600; color: " + ink + "; }\n"
        + w + "dimming { background-color: rgba(0,0,0,.5); }\n"
        + w + "popover > contents { background: " + s2 + "; color: " + ink + "; border-radius: 14px; box-shadow: " + shadow3 + "; }\n"
        + w + "toast { border-radius: 999px; background: " + s3 + "; color: " + ink + "; }\n"
        + w + "scrollbar slider { min-width: 6px; min-height: 6px; background-color: " + line + "; border-radius: 3px; }\n"
        + w + "separator { background: " + line2 + "; }\n"
        + w + "progressbar trough { background: " + line2 + "; border-radius: 3px; min-height: 4px; } " + w + "progressbar progress { background: " + accent + "; border-radius: 3px; min-height: 4px; }\n"
    )


comptime OMXQUA_WEB = """
@font-face { font-family: Geist; font-weight: 400; src: url(/static/fonts/Geist-Regular.ttf) format("truetype"); }
@font-face { font-family: Geist; font-weight: 500; src: url(/static/fonts/Geist-Medium.ttf) format("truetype"); }
@font-face { font-family: Geist; font-weight: 600; src: url(/static/fonts/Geist-SemiBold.ttf) format("truetype"); }
@font-face { font-family: "Geist Mono"; font-weight: 400; src: url(/static/fonts/GeistMono-Regular.ttf) format("truetype"); }
@font-face { font-family: "Geist Mono"; font-weight: 500; src: url(/static/fonts/GeistMono-Medium.ttf) format("truetype"); }
body.omxqua { background: var(--o-page); color: var(--o-ink); --accent: var(--o-accent); --line: var(--o-strong); --muted: var(--o-ink2);
  --surface: var(--o-raised); --danger: var(--o-bad); font: 13.5px/1.45 Geist, system-ui, sans-serif; -webkit-font-smoothing: antialiased; }
body.omxqua .text { color: var(--o-ink); text-align: left; }
body.omxqua .text.title { font-size: 20px; font-weight: 600; letter-spacing: -.01em; }
body.omxqua .text.headline { font-size: 14px; font-weight: 600; }
body.omxqua .text.caption { font-size: 12px; color: var(--o-ink2); }
body.omxqua .text.tone-strong { font-weight: 600; } body.omxqua .text.tone-accent { color: var(--o-bad); }
body.omxqua .text.tone-good { color: var(--o-good); } body.omxqua .text.tone-warn { color: var(--o-warn); }
body.omxqua [data-tag=mono], body.omxqua [data-tag=mono] * { font-family: "Geist Mono", ui-monospace, monospace; font-size: 12px; }
body.omxqua [data-tag=src], body.omxqua [data-tag=src] * { font-family: "Geist Mono", ui-monospace, monospace; font-size: 11.5px; color: var(--o-ink2); }
body.omxqua .vstack.card { background: var(--o-card); border-radius: 12px; padding: 14px 16px; box-sizing: border-box;
  box-shadow: 0 1px 0 rgba(255,255,255,.035) inset, 0 1px 2px rgba(0,0,0,.5), inset 0 0 0 1px var(--o-line); }
body.omxqua .island > * { background: var(--o-raised); border-radius: 999px; padding: 4px 8px; min-height: 34px; align-items: center;
  box-shadow: 0 1px 2px rgba(0,0,0,.5); }
body.omxqua button { border-radius: 999px; min-height: 30px; padding: 0 14px; font: 550 13px Geist, sans-serif; border: 0;
  background: var(--o-raised); color: var(--o-ink); box-shadow: 0 1px 2px rgba(0,0,0,.35); transition: background .15s cubic-bezier(.2,0,0,1); cursor: pointer; }
body.omxqua button:hover { filter: none; background: color-mix(in srgb, var(--o-ink) 8%, var(--o-raised)); }
body.omxqua button:active { transform: none; background: color-mix(in srgb, var(--o-ink) 12%, var(--o-raised)); }
body.omxqua button.prominent { background: var(--o-accent); color: var(--o-on-accent); }
body.omxqua button.prominent:hover { background: color-mix(in srgb, var(--o-page) 10%, var(--o-accent)); }
body.omxqua button.destructive { background: none; color: var(--o-bad); box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--o-bad) 40%, transparent); }
body.omxqua button.subtle { background: none; box-shadow: none; color: var(--o-ink2); }
body.omxqua button.subtle:hover { background: color-mix(in srgb, var(--o-ink) 8%, transparent); color: var(--o-ink); }
body.omxqua [data-tag=row] { border-radius: 8px; min-height: 28px; padding: 0 8px; justify-content: flex-start; }
body.omxqua [data-tag=chip] { min-height: 24px; padding: 0 10px; font: 12px "Geist Mono", monospace; }
body.omxqua select, body.omxqua input[type=text], body.omxqua input[type=password], body.omxqua input[type=date] {
  border-radius: 10px; min-height: 34px; border: 0; box-shadow: inset 0 0 0 1px var(--o-strong); background: var(--o-card); color: var(--o-ink);
  font: inherit; padding: 0 12px; box-sizing: border-box; }
body.omxqua input:hover { box-shadow: inset 0 0 0 1px var(--o-ink2); }
body.omxqua input:focus, body.omxqua select:focus, body.omxqua textarea:focus { outline: none; box-shadow: inset 0 0 0 2px var(--o-accent); }
body.omxqua textarea { border-radius: 10px; border: 0; box-shadow: inset 0 0 0 1px var(--o-strong); background: var(--o-page); color: var(--o-ink);
  font: 13px/1.6 "Geist Mono", ui-monospace, monospace; padding: 10px 12px; box-sizing: border-box; resize: none; }
body.omxqua .segmented, body.omxqua .tabs { background: var(--o-page); border-radius: 999px; padding: 3px; box-shadow: inset 0 0 0 1px var(--o-line); border: 0; }
body.omxqua .segmented span, body.omxqua .tabs span { border-radius: 999px; min-height: 26px; padding: 0 14px; color: var(--o-ink2); font-weight: 550; border: 0; }
body.omxqua .segmented input:checked + span, body.omxqua .tabs input:checked + span { background: color-mix(in srgb, var(--o-ink) 10%, var(--o-raised)); color: var(--o-ink);
  box-shadow: 0 1px 2px rgba(0,0,0,.5); }
body.omxqua .dialog { border-radius: 14px; background: var(--o-raised); color: var(--o-ink); box-shadow: 0 18px 48px rgba(0,0,0,.6); }
body.omxqua .dialog-layer .scrim { background: rgba(0,0,0,.5); }
body.omxqua .dialog-head h3 { font-size: 16px; font-weight: 600; }
body.omxqua .toast { border-radius: 999px; background: color-mix(in srgb, var(--o-ink) 10%, var(--o-raised)); color: var(--o-ink); }
body.omxqua .popover { background: var(--o-raised); border-radius: 14px; box-shadow: 0 18px 48px rgba(0,0,0,.6); }
body.omxqua hr { border-top-color: var(--o-line); } body.omxqua .hstack > hr { border-left-color: var(--o-line); }
body.omxqua .canvas { background: transparent; }
body.omxqua iframe { border: 0; border-radius: 10px; background: var(--o-card); }
body.omxqua ::-webkit-scrollbar { width: 10px; height: 10px; } body.omxqua ::-webkit-scrollbar-thumb { background: var(--o-strong); border-radius: 5px; }
body.omxqua ::-webkit-scrollbar-track { background: transparent; }
"""


def omxqua(dark: Bool = True) -> Theme:
    var pal = omxqua_palette(dark)
    return Theme("omxqua" + ("-night" if dark else "-light"), "omxqua", pal.copy(), omxqua_gtk(pal), String(OMXQUA_WEB), pal.ink, pal.accent_ink, True)
