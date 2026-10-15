# Mac host: draws a mojoui View with real AppKit controls.
#
# Events: every control's tag packs the host's address and the node index
# ((host << 16) | node), and its target is one MojoTarget object whose methods
# (tap:, submit:, toggle:, select:, slide:, controlTextDidChange:) are Mojo
# functions. AppKit doesn't send actions when we set values ourselves, so there's
# no echo to guard against (unlike GTK).

from std.ffi import c_int
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import (
    TEXT, BUTTON, VSTACK, HSTACK, SPACER, FIELD, TOGGLE, DROPDOWN, SLIDER, PROGRESS, DIVIDER, SCROLL, IMAGE,
    SEGMENTED, RADIO, TEXTAREA, ALERT, TABS, NAVBAR, DATE, ICON, GRID, LAZYLIST, CANVAS, PAN, ZOOM, TAP,
    START, CENTER, END, STRETCH, BETWEEN, Node,
    TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE,
)
from mojoui.diff import Diff, SET_TEXT, SET_VALUE, SET_IMAGE
from mojoui.png import encode_png
from mojoui.app import App, Event, Runtime
from mojoui.canvas import Surface
from mojoui.hosts.apple_canvas import CGPoint, CGRect, cfunc, cg_image, AppleCanvas
from mojoui.hosts.objc import (
    cls, sel, msg, new, ns_string, ns_data, ns_array, ns_number, ns_date, date_text, sf_symbol, from_ns, constrain, prefer,
    new_class, add_method, add_protocol, register_class, pool_push,
)

comptime NODE_BITS = 16


def tag_for(host_addr: Int, node: Int) -> Int:
    return (host_addr << NODE_BITS) | node


struct AppKitHost[A: App](Movable):
    var rt: Runtime[Self.A]
    var window: Int
    var target: Int  # MojoTarget object that receives every event
    var widgets: List[Int]
    var focus: Int  # text field to keep focused across the next rebuild (-1: none)
    var canvases: List[AppleCanvas]
    var link: Int  # CADisplayLink: one tick per display frame, for every canvas
    var last_frame: Float64  # the link's last timestamp (seconds)

    def __init__(out self):
        self.rt = Runtime(Self.A())
        self.window = 0
        self.target = 0
        self.widgets = List[Int]()
        self.focus = -1
        self.canvases = List[AppleCanvas]()
        self.link = 0
        self.last_frame = 0

    def submit_field_shown(self) -> Bool:
        """Whether a text field handles Return itself (then no button may also claim it)."""
        for n in self.rt.shown.nodes:
            if n.kind == FIELD and n.msg2 != 0:
                return True
        return False

    def wire(self, w: Int, i: Int, self_addr: Int, action: String):
        _ = msg(w, "setTag:", tag_for(self_addr, i))
        _ = msg(w, "setTarget:", self.target)
        _ = msg(w, "setAction:", sel(action))

    def build(mut self, i: Int, self_addr: Int) -> Int:
        var node = self.rt.shown.nodes[i].copy()  # copy: building children mutates self
        var sized = node.sized_width()  # the app's layout decides this view's width
        var w: Int
        if node.kind == TEXT:
            w = msg(cls("NSTextField"), "labelWithString:", ns_string(node.text))
            _ = msg(w, "setAlignment:", 1)  # NSTextAlignmentCenter (1 on Apple Silicon; 2 is right)
            var size = Float64(13)
            var bold = False
            if node.style == TITLE:
                size, bold = Float64(26), True
            elif node.style == HEADLINE:
                size, bold = Float64(15), True
            elif node.style == CAPTION:
                size = Float64(11)
                _ = msg(w, "setTextColor:", msg(cls("NSColor"), "secondaryLabelColor"))
            _ = msg(w, "setFont:", msg(cls("NSFont"), "boldSystemFontOfSize:" if bold else "systemFontOfSize:", size))
        elif node.kind == BUTTON:
            w = msg(cls("NSButton"), "buttonWithTitle:target:action:", ns_string(node.text), self.target, sel("tap:"))
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            if node.style == PROMINENT:
                if not self.submit_field_shown():  # else Return would fire the field and the button
                    _ = msg(w, "setKeyEquivalent:", ns_string("\r"))  # the blue default button; Return taps it
                _ = msg(w, "setControlSize:", 3)  # NSControlSizeLarge
                _ = msg(w, "setBezelColor:", msg(cls("NSColor"), "controlAccentColor"))
            elif node.style == DESTRUCTIVE:
                _ = msg(w, "setHasDestructiveAction:", 1)
                _ = msg(w, "setContentTintColor:", msg(cls("NSColor"), "systemRedColor"))
        elif node.kind == FIELD:
            w = msg(cls("NSTextField"), "textFieldWithString:", ns_string(node.text))
            _ = msg(w, "setPlaceholderString:", ns_string(node.hint))
            _ = msg(w, "setDelegate:", self.target)  # controlTextDidChange: as you type
            self.wire(w, i, self_addr, "submit:")  # the action fires on Return
            if not sized:  # (the app sized it: its settings decide)
                prefer(w, "widthAnchor", Float64(220))
        elif node.kind == TOGGLE:
            w = msg(cls("NSButton"), "checkboxWithTitle:target:action:", ns_string(node.text), self.target, sel("toggle:"))
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            _ = msg(w, "setState:", node.value)  # NSControlStateValueOn = 1
        elif node.kind == DROPDOWN:
            w = msg(
                msg(cls("NSPopUpButton"), "alloc"),
                "initWithFrame:pullsDown:",
                Float64(0), Float64(0), Float64(160), Float64(28),  # rect as 4 floats (arm64)
                0,  # pop-up, not pull-down
            )
            for o in node.options:
                _ = msg(w, "addItemWithTitle:", ns_string(o))
            _ = msg(w, "selectItemAtIndex:", node.value)
            self.wire(w, i, self_addr, "select:")
        elif node.kind == SLIDER:
            w = msg(
                cls("NSSlider"), "sliderWithValue:minValue:maxValue:target:action:",
                Float64(node.value), Float64(0), Float64(100), self.target, sel("slide:"),
            )
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            _ = msg(w, "setContinuous:", 1)
            if not sized:  # (the app sized it: its settings decide)
                prefer(w, "widthAnchor", Float64(240))
        elif node.kind == PROGRESS:
            w = new("NSProgressIndicator")
            _ = msg(w, "setStyle:", 0)  # bar
            _ = msg(w, "setIndeterminate:", 0)
            _ = msg(w, "setMinValue:", Float64(0))
            _ = msg(w, "setMaxValue:", Float64(100))
            _ = msg(w, "setDoubleValue:", Float64(node.value))
            if not sized:  # (the app sized it: its settings decide)
                prefer(w, "widthAnchor", Float64(240))
        elif node.kind == DIVIDER:
            w = new("NSBox")
            _ = msg(w, "setBoxType:", 2)  # NSBoxSeparator
            if not sized:  # (the app sized it: its settings decide)
                prefer(w, "widthAnchor", Float64(280))
            if not node.sized_height():
                constrain(w, "heightAnchor", Float64(1))
        elif node.kind == CANVAS:
            # A MojoCanvas (an NSImageView whose scrollWheel: is Mojo) showing the app's pixels;
            # pan, pinch and click recognisers call back into it.
            w = msg(msg(cls("MojoCanvas"), "alloc"), "initWithFrame:", Float64(0), Float64(0), Float64(320), Float64(240))
            _ = msg(w, "setImageScaling:", 1)  # NSImageScaleAxesIndependently: the pixels fill the view
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            for orientation in range(2):  # its size comes from the layout, never from its picture
                _ = msg(w, "setContentHuggingPriority:forOrientation:", Float32(1), orientation)
                _ = msg(w, "setContentCompressionResistancePriority:forOrientation:", Float32(1), orientation)
            if not sized:
                prefer(w, "widthAnchor", Float64(320))
            if not node.sized_height():
                prefer(w, "heightAnchor", Float64(240))
            for kind in [("NSPanGestureRecognizer", "canvasPan:"), ("NSMagnificationGestureRecognizer", "canvasPinch:"), ("NSClickGestureRecognizer", "canvasTap:")]:
                var r = msg(msg(cls(kind[0]), "alloc"), "initWithTarget:action:", w, sel(kind[1]))
                _ = msg(w, "addGestureRecognizer:", r)
            # A new size (window resized) wakes the display link.
            _ = msg(w, "setPostsFrameChangedNotifications:", 1)
            _ = msg(msg(cls("NSNotificationCenter"), "defaultCenter"), "addObserver:selector:name:object:", w, sel("canvasResized:"), ns_string("NSViewFrameDidChangeNotification"), w)
            self.canvases.append(AppleCanvas(i, w))
        elif node.kind == IMAGE:
            w = msg(cls("NSImageView"), "imageViewWithImage:", ns_image(node.pixels, node.spacing, node.size))
            if not sized:  # (the app sized it: its settings decide)
                prefer(w, "widthAnchor", Float64(node.spacing))
            if not node.sized_height():
                constrain(w, "heightAnchor", Float64(node.size))
        elif node.kind == SEGMENTED or node.kind == TABS:
            w = msg(cls("NSSegmentedControl"), "segmentedControlWithLabels:trackingMode:target:action:",
                    ns_array(node.options), 0, self.target, sel("segment:"))  # 0 = select one
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            _ = msg(w, "setSelectedSegment:", node.value)
            if node.kind == TABS:
                _ = msg(w, "setControlSize:", 3)  # large
        elif node.kind == RADIO:
            w = new("NSStackView")
            _ = msg(w, "setOrientation:", 1)
            _ = msg(w, "setAlignment:", 1)  # leading
            for j in range(len(node.options)):
                var b = msg(cls("NSButton"), "radioButtonWithTitle:target:action:", ns_string(node.options[j]), self.target, sel("radio:"))
                _ = msg(b, "setTag:", tag_for(self_addr, i))
                _ = msg(b, "setState:", 1 if j == node.value else 0)
                _ = msg(w, "addArrangedSubview:", b)
        elif node.kind == TEXTAREA:
            w = msg(cls("NSTextView"), "scrollableTextView")
            var text = msg(w, "documentView")
            _ = msg(text, "setString:", ns_string(node.text))
            _ = msg(text, "setFont:", msg(cls("NSFont"), "systemFontOfSize:", Float64(13)))
            _ = msg(text, "setRichText:", 0)
            _ = msg(text, "setIdentifier:", ns_string(String(tag_for(self_addr, i))))  # NSTextView has no tag
            _ = msg(text, "setDelegate:", self.target)  # textDidChange:
            if not sized:  # (the app sized it: its settings decide)
                prefer(w, "widthAnchor", Float64(320))
            if not node.sized_height():
                constrain(w, "heightAnchor", Float64(node.size))
            self.widgets[i] = text
        elif node.kind == ALERT:
            # Shown on the next run-loop turn (not inside the event that asked for it).
            _ = msg(self.target, "performSelector:withObject:afterDelay:", sel("showAlert:"), ns_number(tag_for(self_addr, i)), Float64(0))
            w = new("NSView")  # nothing in the layout itself
        elif node.kind == NAVBAR:
            w = new("NSStackView")
            _ = msg(w, "setOrientation:", 0)
            _ = msg(w, "setSpacing:", Float64(8))
            if node.msg != 0:
                var back = msg(cls("NSButton"), "buttonWithTitle:target:action:", ns_string("‹ Back"), self.target, sel("tap:"))
                _ = msg(back, "setTag:", tag_for(self_addr, i))
                _ = msg(w, "addArrangedSubview:", back)
            var title = msg(cls("NSTextField"), "labelWithString:", ns_string(node.text))
            _ = msg(title, "setFont:", msg(cls("NSFont"), "boldSystemFontOfSize:", Float64(17)))
            _ = msg(w, "addArrangedSubview:", title)
        elif node.kind == DATE:
            w = new("NSDatePicker")
            _ = msg(w, "setDatePickerStyle:", 0)  # text field and stepper
            _ = msg(w, "setDatePickerElements:", 0x00E0)  # year, month, day
            _ = msg(w, "setDateValue:", ns_date(node.text))
            self.wire(w, i, self_addr, "date:")
        elif node.kind == ICON:
            var image = msg(cls("NSImage"), "imageWithSystemSymbolName:accessibilityDescription:", ns_string(sf_symbol(node.text)), 0)
            w = msg(cls("NSImageView"), "imageViewWithImage:", image)
            var config = msg(cls("NSImageSymbolConfiguration"), "configurationWithPointSize:weight:", Float64(node.size), Float64(0))
            _ = msg(w, "setSymbolConfiguration:", config)
            _ = msg(w, "setContentTintColor:", msg(cls("NSColor"), "controlAccentColor"))
        elif node.kind == GRID:
            w = new("NSStackView")
            _ = msg(w, "setOrientation:", 1)
            _ = msg(w, "setSpacing:", Float64(node.spacing))
            var row = 0
            for k in range(len(node.children)):
                if k % node.value == 0:
                    row = new("NSStackView")
                    _ = msg(row, "setOrientation:", 0)
                    _ = msg(row, "setDistribution:", 1)  # fill equally
                    _ = msg(row, "setSpacing:", Float64(node.spacing))
                    _ = msg(w, "addArrangedSubview:", row)
                _ = msg(row, "addArrangedSubview:", self.build(node.children[k], self_addr))
        elif node.kind == LAZYLIST:
            var table = new("NSTableView")
            var column = msg(msg(cls("NSTableColumn"), "alloc"), "initWithIdentifier:", ns_string("rows"))
            _ = msg(column, "setWidth:", Float64(320))
            _ = msg(table, "addTableColumn:", column)
            _ = msg(table, "setHeaderView:", 0)
            _ = msg(table, "setRowHeight:", Float64(node.spacing - 4))
            _ = msg(table, "setUsesAlternatingRowBackgroundColors:", 1)
            _ = msg(table, "setTag:", tag_for(self_addr, i))
            _ = msg(table, "setDataSource:", self.target)  # rows are asked for as they scroll into view
            _ = msg(table, "setTarget:", self.target)
            _ = msg(table, "setAction:", sel("rowTap:"))
            w = new("NSScrollView")
            _ = msg(w, "setHasVerticalScroller:", 1)
            _ = msg(w, "setDocumentView:", table)
            if not sized:  # (the app sized it: its settings decide)
                prefer(w, "widthAnchor", Float64(340))
            if not node.sized_height():
                constrain(w, "heightAnchor", Float64(node.size))
            self.widgets[i] = table
        elif node.kind == SPACER:
            w = new("NSView")
        elif node.kind == SCROLL:
            w = new("NSScrollView")
            _ = msg(w, "setHasVerticalScroller:", 1)
            _ = msg(w, "setDrawsBackground:", 0)
            var content = self.build(node.children[0], self_addr)
            _ = msg(content, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
            _ = msg(w, "setDocumentView:", content)
            var clip = msg(w, "contentView")
            for anchor in ["topAnchor", "leadingAnchor", "widthAnchor"]:
                _ = msg(msg(msg(content, anchor), "constraintEqualToAnchor:", msg(clip, anchor)), "setActive:", 1)
            if not node.sized_height():
                constrain(w, "heightAnchor", Float64(node.size))
            if not sized:  # (the app sized it: its settings decide)
                prefer(w, "widthAnchor", Float64(320))
        else:
            w = new("NSStackView")
            var vertical = node.kind == VSTACK
            _ = msg(w, "setOrientation:", 1 if vertical else 0)
            # align → NSStackView alignment (NSLayoutAttribute); STRETCH = per-child constraints below
            var align = 9 if vertical else 10  # centre X / centre Y
            if node.align_items == START:
                align = 5 if vertical else 3  # leading / top
            elif node.align_items == END:
                align = 6 if vertical else 4  # trailing / bottom
            _ = msg(w, "setAlignment:", align)
            _ = msg(w, "setSpacing:", Float64(node.spacing))
            if node.pad_v != 0 or node.pad_h != 0:  # padding = the stack's own edge insets
                _ = msg(w, "setEdgeInsets:", Float64(node.pad_v), Float64(node.pad_h), Float64(node.pad_v), Float64(node.pad_h))
            # justify → distribution (BETWEEN) or flexible spacers (START, CENTER, END), all native
            var grows = False
            for c in node.children:
                grows = grows or self.rt.shown.nodes[c].grows
            if node.justify_items == BETWEEN:
                _ = msg(w, "setDistribution:", 3)  # NSStackViewDistributionEqualSpacing
            elif grows or node.justify_items != 0:
                _ = msg(w, "setDistribution:", 0)  # fill: the lowest-hugging view takes the free space
            var lead = 0
            if (node.justify_items == CENTER or node.justify_items == END) and not grows:  # a growing child takes it all
                lead = flexible_spacer(vertical)
                _ = msg(w, "addArrangedSubview:", lead)
            for c in node.children:
                var child = self.build(c, self_addr)
                _ = msg(w, "addArrangedSubview:", child)
                ref cn = self.rt.shown.nodes[c]
                if cn.grows:  # flex-grow: lowest hugging priority along the stack
                    _ = msg(child, "setContentHuggingPriority:forOrientation:", Float32(1), 1 if vertical else 0)
                if cn.fills or node.align_items == STRETCH:  # stretch across: match the stack minus its insets
                    var side = "widthAnchor" if vertical else "heightAnchor"
                    var inset = Float64(2 * (node.pad_h if vertical else node.pad_v))
                    var c2 = msg(msg(child, side), "constraintEqualToAnchor:constant:", msg(w, side), -inset)
                    _ = msg(c2, "setActive:", 1)
            if node.justify_items == CENTER and not grows:
                var trail = flexible_spacer(vertical)
                _ = msg(w, "addArrangedSubview:", trail)
                var side = "heightAnchor" if vertical else "widthAnchor"
                _ = msg(msg(msg(trail, side), "constraintEqualToAnchor:", msg(lead, side)), "setActive:", 1)
            elif node.justify_items == START and not grows:
                _ = msg(w, "addArrangedSubview:", flexible_spacer(vertical))
        if self.widgets[i] == 0:  # (some branches already stored an inner control)
            self.widgets[i] = w
        return self.apply_layout(i, w)

    def apply_layout(self, i: Int, w: Int) -> Int:
        """Maps node i's own sizes (and, for non-stacks, padding) onto Auto Layout; returns what goes in the parent."""
        ref node = self.rt.shown.nodes[i]
        var outer = w
        var is_stack = node.kind == VSTACK or node.kind == HSTACK
        if (node.pad_v != 0 or node.pad_h != 0) and not is_stack:  # wrap a leaf in a padded stack
            outer = new("NSStackView")
            _ = msg(outer, "setEdgeInsets:", Float64(node.pad_v), Float64(node.pad_h), Float64(node.pad_v), Float64(node.pad_h))
            _ = msg(outer, "addArrangedSubview:", w)
        if node.w != 0:
            _ = msg(msg(msg(outer, "widthAnchor"), "constraintEqualToConstant:", Float64(node.w)), "setActive:", 1)
        if node.h != 0:
            _ = msg(msg(msg(outer, "heightAnchor"), "constraintEqualToConstant:", Float64(node.h)), "setActive:", 1)
        if node.min_w != 0:
            _ = msg(msg(msg(outer, "widthAnchor"), "constraintGreaterThanOrEqualToConstant:", Float64(node.min_w)), "setActive:", 1)
        if node.max_w != 0:
            _ = msg(msg(msg(outer, "widthAnchor"), "constraintLessThanOrEqualToConstant:", Float64(node.max_w)), "setActive:", 1)
            if node.kind == TEXT:  # labels are single-line by default: let it wrap within the width
                _ = msg(w, "setMaximumNumberOfLines:", 0)
                _ = msg(w, "setLineBreakMode:", 0)  # word wrapping
                _ = msg(w, "setPreferredMaxLayoutWidth:", Float64(node.max_w - 2 * node.pad_h))
        return outer

    def show(mut self, self_addr: Int):
        # Old controls are deliberately never released: that keeps a control alive
        # while its window content is replaced in the middle of its own action.
        # (Adding `release` later means delaying it until the handler returns.)
        self.widgets = List[Int](length=len(self.rt.shown.nodes), fill=0)  # 0 = nil: patches become no-ops
        self.canvases = List[AppleCanvas]()
        if self.link != 0:
            _ = msg(self.link, "invalidate")
            self.link = 0
        if len(self.rt.shown.nodes) >= (1 << NODE_BITS):
            var note = msg(cls("NSTextField"), "labelWithString:", ns_string("Too many items to show (limit 65,535)."))
            _ = msg(self.window, "setContentView:", note)  # no stale controls left to use
            return
        var root = self.build(0, self_addr)
        if self.rt.shown.nodes[0].grows or self.rt.shown.nodes[0].fills:  # the screen fills the window
            _ = msg(self.window, "setContentView:", root)
        else:
            var holder = new("NSStackView")  # centres the app's root in the window
            _ = msg(holder, "setOrientation:", 1)
            _ = msg(holder, "setAlignment:", 9)
            _ = msg(holder, "setEdgeInsets:", Float64(32), Float64(32), Float64(32), Float64(32))
            _ = msg(holder, "addArrangedSubview:", root)
            _ = msg(self.window, "setContentView:", holder)
        if len(self.canvases) > 0:  # one display link (macOS 14+) ticks every canvas
            self.link = msg(self.canvases[0].view, "displayLinkWithTarget:selector:", self.canvases[0].view, sel("canvasFrame:"))
            _ = msg(self.link, "addToRunLoop:forMode:", msg(cls("NSRunLoop"), "mainRunLoop"), ns_string("kCFRunLoopCommonModes"))
        if 0 <= self.focus < len(self.widgets) and self.rt.shown.nodes[self.focus].kind == FIELD:
            # Keep typing in the new field, on the next run-loop turn (after AppKit has
            # finished ending the old field's edit), with the cursor at the end.
            _ = msg(self.target, "performSelector:withObject:afterDelay:", sel("focusField:"), self.widgets[self.focus], Float64(0))
        self.focus = -1

    def apply(mut self, d: Diff, self_addr: Int):
        if d.rebuild:
            self.show(self_addr)
            return
        for p in d.patches:
            var w = self.widgets[p.node]
            var kind = self.rt.shown.nodes[p.node].kind
            if p.op == SET_TEXT and kind != TEXTAREA and kind != DATE and kind != NAVBAR:
                if kind == TEXT:
                    _ = msg(w, "setStringValue:", ns_string(p.text))
                elif kind == FIELD:
                    if from_ns(msg(w, "stringValue")) != p.text:  # don't fight the typist
                        _ = msg(w, "setStringValue:", ns_string(p.text))
                else:  # buttons and checkboxes
                    _ = msg(w, "setTitle:", ns_string(p.text))
            elif p.op == SET_VALUE:
                if kind == TOGGLE:
                    _ = msg(w, "setState:", p.number)
                elif kind == DROPDOWN:
                    _ = msg(w, "selectItemAtIndex:", p.number)
                elif kind == SLIDER or kind == PROGRESS:
                    _ = msg(w, "setDoubleValue:", Float64(p.number))
            elif p.op == SET_VALUE and (kind == SEGMENTED or kind == TABS):
                _ = msg(w, "setSelectedSegment:", p.number)
            elif p.op == SET_VALUE and kind == RADIO:
                var buttons = msg(w, "arrangedSubviews")
                for j in range(msg(buttons, "count")):
                    _ = msg(msg(buttons, "objectAtIndex:", j), "setState:", 1 if j == p.number else 0)
            elif p.op == SET_TEXT and kind == TEXTAREA:
                if from_ns(msg(w, "string")) != p.text:  # don't fight the typist
                    _ = msg(w, "setString:", ns_string(p.text))
            elif p.op == SET_TEXT and kind == DATE:
                if date_text(msg(w, "dateValue")) != p.text:  # don't fight someone mid-edit
                    _ = msg(w, "setDateValue:", ns_date(p.text))
            elif p.op == SET_TEXT and kind == NAVBAR:
                var views = msg(w, "arrangedSubviews")
                _ = msg(msg(views, "lastObject"), "setStringValue:", ns_string(p.text))
            elif p.op == SET_IMAGE:
                ref img = self.rt.shown.nodes[p.node]
                _ = msg(w, "setImage:", ns_image(img.pixels, img.spacing, img.size))
            # SET_MSG needs nothing: events look the message up in rt.shown.
        # Ask for the visible rows of every long list again: row text isn't part of the view.
        for k in range(len(self.rt.shown.nodes)):
            if self.rt.shown.nodes[k].kind == LAZYLIST and self.widgets[k] != 0:
                _ = msg(self.widgets[k], "reloadData")
        self.wake()

    # ---------- canvases ----------

    def canvas_at(self, node: Int) -> Int:
        for k in range(len(self.canvases)):
            if self.canvases[k].node == node:
                return k
        return -1

    def canvas_send(mut self, node: Int, kind: Int, x: Float64, y: Float64, dx: Float64, dy: Float64, zoom: Float64, self_addr: Int):
        var d = self.rt.gesture(node, kind, x, y, dx, dy, zoom)
        self.apply(d, self_addr)

    def tick(mut self, seconds: Float64, self_addr: Int):
        """Every display frame: frame events for canvases that asked, then redraws."""
        var micro = Int((seconds - self.last_frame) * 1e6) if self.last_frame > 0 and seconds - self.last_frame < 0.25 else 16667
        self.last_frame = seconds
        var k = 0
        while k < len(self.canvases):
            var node = self.canvases[k].node
            if self.rt.shown.nodes[node].msg2 != 0:
                var d = self.rt.frame(node, micro)
                self.apply(d, self_addr)
                if d.rebuild:
                    return
            self.draw_canvas(k, self_addr)
            k += 1
        if self.link != 0 and self.idle():  # nothing to animate or redraw: stop waking up
            _ = msg(self.link, "setPaused:", 1)

    def idle(self) -> Bool:
        for ref c in self.canvases:
            if self.rt.shown.nodes[c.node].msg2 != 0 or c.drawn != self.rt.shown.nodes[c.node].value or c.wpx == 0:
                return False
        return True

    def wake(self):
        """Something may need drawing (a new version, frames, a new size): tick again."""
        if self.link != 0:
            _ = msg(self.link, "setPaused:", 0)

    def draw_canvas(mut self, k: Int, self_addr: Int):
        """Asks the app to paint canvas k at its real pixel size (if its size or version changed)."""
        var view = self.canvases[k].view
        var node = self.canvases[k].node
        var bounds = msg[CGRect](view, "bounds")
        var scale = msg[Float64](self.window, "backingScaleFactor") if self.window != 0 else 2.0
        var wpx = Int(bounds.width * scale + 0.5)
        var hpx = Int(bounds.height * scale + 0.5)
        var version = self.rt.shown.nodes[node].value
        if wpx <= 0 or hpx <= 0 or (wpx == self.canvases[k].wpx and hpx == self.canvases[k].hpx and version == self.canvases[k].drawn):
            return
        if len(self.canvases[k].pixels) != wpx * hpx:
            self.canvases[k].pixels = List[UInt32](length=wpx * hpx, fill=0)
        var surface = Surface(Int(self.canvases[k].pixels.unsafe_ptr()), wpx, hpx, scale)
        var d = self.rt.draw(node, surface)
        var image = cg_image(self.canvases[k].pixels, wpx, hpx)
        var picture = msg(msg(cls("NSImage"), "alloc"), "initWithCGImage:size:", image, bounds.width, bounds.height)
        _ = msg(view, "setImage:", picture)
        _ = msg(picture, "release")
        cfunc[NoneType]("CGImageRelease", image)
        self.canvases[k].wpx = wpx
        self.canvases[k].hpx = hpx
        self.canvases[k].drawn = version
        self.apply(d, self_addr)

    def send(mut self, node: Int, second: Bool, text: String, number: Int, self_addr: Int):
        """A control changed: build the event, run update(), patch the controls."""
        ref n = self.rt.shown.nodes[node]
        var message = n.msg2 if second else n.msg
        if message == 0:
            return
        self.focus = node if n.kind == FIELD else -1
        var d = self.rt.dispatch(Event(message, text, number))
        self.apply(d, self_addr)


def flexible_spacer(vertical: Bool) -> Int:
    """An empty view that soaks up free space along a stack (for justify)."""
    var v = new("NSView")
    _ = msg(v, "setContentHuggingPriority:forOrientation:", Float32(1), 1 if vertical else 0)
    return v


def ns_image(pixels: List[UInt32], width: Int, height: Int) -> Int:
    """An NSImage from RGBA pixels, via PNG bytes made in Mojo (mojoui/png.mojo)."""
    var data = ns_data(encode_png(pixels, width, height))
    return msg(msg(msg(cls("NSImage"), "alloc"), "initWithData:", data), "autorelease")


def on_focus_field(target: Int, cmd: Int, field: Int) abi("C"):
    """Focuses a text field and puts the cursor at the end (not select-all)."""
    var window = msg(field, "window")
    if window == 0:
        return
    _ = msg(window, "makeFirstResponder:", field)
    var editor = msg(field, "currentEditor")
    if editor != 0:
        var length = msg(msg(field, "stringValue"), "length")
        _ = msg(editor, "setSelectedRange:", length, 0)  # NSRange {location, length} in two registers


def from_tag(control: Int) -> Tuple[Int, Int]:
    var tag = msg(control, "tag")
    return (tag >> NODE_BITS, tag & ((1 << NODE_BITS) - 1))


def host_at[A: App](addr: Int) -> Pointer[AppKitHost[A], MutUntrackedOrigin]:
    return Pointer[AppKitHost[A], MutUntrackedOrigin](unsafe_from_address=addr)


# ---------- MojoTarget methods (AppKit calls these) ----------

# ---------- MojoCanvas methods (self is the canvas view; its tag says host + node) ----------

def in_view(view: Int, p: CGPoint) -> CGPoint:
    """AppKit's y runs upwards; canvases count from the top-left."""
    return CGPoint(p.x, msg[CGRect](view, "bounds").height - p.y)


def on_canvas_frame[A: App](view: Int, cmd: Int, link: Int) abi("C"):
    var t = from_tag(view)
    host_at[A](t[0])[].tick(msg[Float64](link, "timestamp"), t[0])


def on_canvas_resized[A: App](view: Int, cmd: Int, notification: Int) abi("C"):
    var t = from_tag(view)
    host_at[A](t[0])[].wake()


def on_canvas_pan[A: App](view: Int, cmd: Int, recognizer: Int) abi("C"):
    var t = from_tag(view)
    var moved = msg[CGPoint](recognizer, "translationInView:", view)
    _ = msg(recognizer, "setTranslation:inView:", Float64(0), Float64(0), view)  # deltas from here on
    var at = in_view(view, msg[CGPoint](recognizer, "locationInView:", view))
    host_at[A](t[0])[].canvas_send(t[1], PAN, at.x, at.y, moved.x, -moved.y, 1, t[0])


def on_canvas_pinch[A: App](view: Int, cmd: Int, recognizer: Int) abi("C"):
    var t = from_tag(view)
    var host = host_at[A](t[0])
    var k = host[].canvas_at(t[1])
    if k < 0:
        return
    var m = msg[Float64](recognizer, "magnification")  # 0 at the start of each pinch
    if msg(recognizer, "state") == 1:  # began
        host[].canvases[k].pinch = 0
    var factor = (1 + m) / (1 + host[].canvases[k].pinch)
    host[].canvases[k].pinch = m
    var at = in_view(view, msg[CGPoint](recognizer, "locationInView:", view))
    host[].canvas_send(t[1], ZOOM, at.x, at.y, 0, 0, factor, t[0])


def on_canvas_tap[A: App](view: Int, cmd: Int, recognizer: Int) abi("C"):
    var t = from_tag(view)
    var at = in_view(view, msg[CGPoint](recognizer, "locationInView:", view))
    host_at[A](t[0])[].canvas_send(t[1], TAP, at.x, at.y, 0, 0, 1, t[0])


def on_canvas_scroll[A: App](view: Int, cmd: Int, event: Int) abi("C"):
    """Mouse wheel (4 notches = 2×) or trackpad scroll (pixels): zoom around the pointer."""
    var t = from_tag(view)
    var dy = msg[Float64](event, "scrollingDeltaY")
    var precise = (msg(event, "hasPreciseScrollingDeltas") & 0xFF) != 0
    var window_point = msg[CGPoint](event, "locationInWindow")
    var at = in_view(view, msg[CGPoint](view, "convertPoint:fromView:", window_point.x, window_point.y, 0))
    var notches = dy / 100.0 * 4.0 if precise else dy
    host_at[A](t[0])[].canvas_send(t[1], ZOOM, at.x, at.y, 0, 0, 2.0 ** (notches / 4.0), t[0])


def on_tap[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], False, "", 0, t[0])


def on_submit[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], True, from_ns(msg(sender, "stringValue")), 0, t[0])


def on_text_change[A: App](target: Int, cmd: Int, notification: Int) abi("C"):
    var field = msg(notification, "object")
    var t = from_tag(field)
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(field, "stringValue")), 0, t[0])


def on_toggle[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], False, "", msg(sender, "state"), t[0])


def on_select[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var index = msg(sender, "indexOfSelectedItem")
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(sender, "titleOfSelectedItem")), index, t[0])


def on_segment[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var index = msg(sender, "selectedSegment")
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(sender, "labelForSegment:", index)), index, t[0])


def on_radio[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var index = msg(msg(msg(sender, "superview"), "arrangedSubviews"), "indexOfObject:", sender)
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(sender, "title")), index, t[0])


def on_text_did_change[A: App](target: Int, cmd: Int, notification: Int) abi("C"):
    var text = msg(notification, "object")
    try:
        var tag = Int(from_ns(msg(text, "identifier")))
        var host_addr = tag >> NODE_BITS
        host_at[A](host_addr)[].send(tag & ((1 << NODE_BITS) - 1), False, from_ns(msg(text, "string")), 0, host_addr)
    except:
        return


def on_date[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], False, date_text(msg(sender, "dateValue")), 0, t[0])


def on_show_alert[A: App](target: Int, cmd: Int, number: Int) abi("C"):
    """Runs the alert for an Alert node (if it's still on screen) and sends the answer."""
    var tag = msg(number, "longValue")
    var host_addr = tag >> NODE_BITS
    var node = tag & ((1 << NODE_BITS) - 1)
    var host = host_at[A](host_addr)
    if node >= len(host[].rt.shown.nodes) or host[].rt.shown.nodes[node].kind != ALERT:
        return  # the screen changed before it could be shown
    var n = host[].rt.shown.nodes[node].copy()
    var alert = msg(msg(cls("NSAlert"), "new"), "autorelease")
    _ = msg(alert, "setMessageText:", ns_string(n.text))
    _ = msg(alert, "setInformativeText:", ns_string(n.hint))
    for o in n.options:
        _ = msg(alert, "addButtonWithTitle:", ns_string(o))
    var index = msg(alert, "runModal") - 1000  # NSAlertFirstButtonReturn = 1000
    if 0 <= index < len(n.options):
        host[].send(node, False, n.options[index], index, host_addr)


def on_row_count[A: App](target: Int, cmd: Int, table: Int) abi("C") -> Int:
    var t = from_tag(table)
    var host = host_at[A](t[0])
    if t[1] >= len(host[].rt.shown.nodes) or host[].rt.shown.nodes[t[1]].kind != LAZYLIST:
        return 0
    return host[].rt.shown.nodes[t[1]].value


def on_row_value[A: App](target: Int, cmd: Int, table: Int, column: Int, row: Int) abi("C") -> Int:
    """NSTableView asks for one row's text only when it scrolls into view."""
    var t = from_tag(table)
    var host = host_at[A](t[0])
    if t[1] >= len(host[].rt.shown.nodes) or host[].rt.shown.nodes[t[1]].kind != LAZYLIST:
        return 0
    return ns_string(host[].rt.app.row(host[].rt.shown.nodes[t[1]].msg2, row))


def on_row_tap[A: App](target: Int, cmd: Int, table: Int) abi("C"):
    var row = msg(table, "clickedRow")
    if row < 0:
        return
    var t = from_tag(table)
    host_at[A](t[0])[].send(t[1], False, "", row, t[0])


def on_slide[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var value = Int(msg[Float64](sender, "doubleValue") + 0.5)
    host_at[A](t[0])[].send(t[1], False, "", value, t[0])


def quit_when_closed(target: Int, cmd: Int, app: Int) abi("C") -> Int8:
    return 1  # YES to applicationShouldTerminateAfterLastWindowClosed:


def make_menu(app: Int, title: String):
    var bar = new("NSMenu")
    var app_item = new("NSMenuItem")
    _ = msg(bar, "addItem:", app_item)
    var app_menu = new("NSMenu")
    _ = msg(app_menu, "addItemWithTitle:action:keyEquivalent:", ns_string("Close Window"), sel("performClose:"), ns_string("w"))
    _ = msg(app_menu, "addItemWithTitle:action:keyEquivalent:", ns_string("Quit " + title), sel("terminate:"), ns_string("q"))
    _ = msg(app_item, "setSubmenu:", app_menu)
    # Edit menu: gives text fields their Cut/Copy/Paste/Select All shortcuts.
    var edit_item = new("NSMenuItem")
    _ = msg(bar, "addItem:", edit_item)
    var edit = msg(msg(cls("NSMenu"), "alloc"), "initWithTitle:", ns_string("Edit"))
    _ = msg(edit, "addItemWithTitle:action:keyEquivalent:", ns_string("Cut"), sel("cut:"), ns_string("x"))
    _ = msg(edit, "addItemWithTitle:action:keyEquivalent:", ns_string("Copy"), sel("copy:"), ns_string("c"))
    _ = msg(edit, "addItemWithTitle:action:keyEquivalent:", ns_string("Paste"), sel("paste:"), ns_string("v"))
    _ = msg(edit, "addItemWithTitle:action:keyEquivalent:", ns_string("Select All"), sel("selectAll:"), ns_string("a"))
    _ = msg(edit_item, "setSubmenu:", edit)
    _ = msg(app, "setMainMenu:", bar)


def run[A: App]() -> c_int:
    """Opens the app in a native AppKit window and runs until it's closed."""
    _ = pool_push()
    var host = alloc(Layout[AppKitHost[A]].single()).unsafe_leak()  # lives as long as the app
    host.unsafe_write(AppKitHost[A]())
    var addr = Int(host)
    if (addr >> (63 - NODE_BITS)) != 0:
        print("mojoui: can't pack host address into a control tag")
        return 1

    var app = msg(cls("NSApplication"), "sharedApplication")
    _ = msg(app, "setActivationPolicy:", 0)  # a regular app: Dock icon and menu bar
    var title = host[].rt.app.title()
    make_menu(app, title)

    var c = new_class("MojoTarget", "NSObject")
    add_method(c, "tap:", on_tap[A], "v@:@")
    add_method(c, "submit:", on_submit[A], "v@:@")
    add_method(c, "toggle:", on_toggle[A], "v@:@")
    add_method(c, "select:", on_select[A], "v@:@")
    add_method(c, "slide:", on_slide[A], "v@:@")
    add_method(c, "controlTextDidChange:", on_text_change[A], "v@:@")
    add_method(c, "focusField:", on_focus_field, "v@:@")
    add_method(c, "segment:", on_segment[A], "v@:@")
    add_method(c, "radio:", on_radio[A], "v@:@")
    add_method(c, "textDidChange:", on_text_did_change[A], "v@:@")
    add_method(c, "date:", on_date[A], "v@:@")
    add_method(c, "showAlert:", on_show_alert[A], "v@:@")
    add_method(c, "rowTap:", on_row_tap[A], "v@:@")
    add_method(c, "numberOfRowsInTableView:", on_row_count[A], "q@:@")
    add_method(c, "tableView:objectValueForTableColumn:row:", on_row_value[A], "@@:@@q")
    add_protocol(c, "NSTableViewDataSource")
    add_method(c, "applicationShouldTerminateAfterLastWindowClosed:", quit_when_closed, "B@:@")
    register_class(c)
    var canvas = new_class("MojoCanvas", "NSImageView")
    add_method(canvas, "canvasFrame:", on_canvas_frame[A], "v@:@")
    add_method(canvas, "canvasResized:", on_canvas_resized[A], "v@:@")
    add_method(canvas, "canvasPan:", on_canvas_pan[A], "v@:@")
    add_method(canvas, "canvasPinch:", on_canvas_pinch[A], "v@:@")
    add_method(canvas, "canvasTap:", on_canvas_tap[A], "v@:@")
    add_method(canvas, "scrollWheel:", on_canvas_scroll[A], "v@:@")
    register_class(canvas)
    host[].target = msg(c, "new")
    _ = msg(app, "setDelegate:", host[].target)

    host[].window = msg(
        msg(cls("NSWindow"), "alloc"),
        "initWithContentRect:styleMask:backing:defer:",
        Float64(0), Float64(0), Float64(host[].rt.app.window_size()[0]), Float64(host[].rt.app.window_size()[1]),  # rect as 4 floats (arm64)
        1 | 2 | 4 | 8,  # titled, closable, miniaturizable, resizable
        2,  # NSBackingStoreBuffered
        0,  # defer: NO
    )
    _ = msg(host[].window, "setTitle:", ns_string(title))
    _ = msg(host[].window, "setReleasedWhenClosed:", 0)
    host[].show(addr)
    _ = msg(host[].window, "center")
    _ = msg(host[].window, "makeKeyAndOrderFront:", 0)
    _ = msg(app, "activateIgnoringOtherApps:", 1)
    _ = msg(app, "run")
    return 0
