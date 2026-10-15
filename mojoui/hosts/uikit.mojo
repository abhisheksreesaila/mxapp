# iPhone host: draws a mojoui View with real UIKit controls.
#
# Start-up: UIApplicationMain → MojoAppDelegate → the scene from Info.plist →
# MojoSceneDelegate.scene:willConnectToSession:options:, which creates the app
# (A()) and its window. Events: each control's tag packs the host's address and
# the node index; its target is the scene delegate (tap:, changed:, submit:,
# toggle:, slide:). Dropdowns are menu buttons whose UIActions call a Mojo-built
# block; each action's identifier carries "<tag>:<option index>".

from std.ffi import external_call, c_int
from std.memory import Pointer
from std.memory.alloc import alloc, Layout

from mojoui.view import (
    TEXT, BUTTON, VSTACK, HSTACK, SPACER, FIELD, TOGGLE, DROPDOWN, SLIDER, PROGRESS, DIVIDER, SCROLL, IMAGE,
    SEGMENTED, RADIO, TEXTAREA, ALERT, TABS, NAVBAR, DATE, ICON, GRID, LAZYLIST,
    TITLE, HEADLINE, CAPTION, PROMINENT, DESTRUCTIVE,
)
from mojoui.diff import Diff, SET_TEXT, SET_VALUE, SET_IMAGE
from mojoui.png import encode_png
from mojoui.app import App, Event, Runtime
from mojoui.hosts.objc import (
    cls, sel, msg, new, ns_string, ns_data, ns_array, ns_number, ns_date, date_text, sf_symbol, from_ns, constrain,
    global_block, data_block, block_data, new_class, add_method, add_protocol,
    register_class, pool_push,
)

comptime NODE_BITS = 16
comptime VALUE_CHANGED = 1 << 12
comptime TOUCH_UP_INSIDE = 1 << 6
comptime EDITING_CHANGED = 1 << 17
comptime EDITING_DID_END_ON_EXIT = 1 << 19  # Return pressed


def tag_for(host_addr: Int, node: Int) -> Int:
    return (host_addr << NODE_BITS) | node


struct UIKitHost[A: App](Movable):
    var rt: Runtime[Self.A]
    var window: Int
    var view: Int  # the root view controller's view
    var root: Int  # our top stack view inside it
    var target: Int  # the scene delegate, which receives every control event
    var choose: Int  # the block every dropdown option calls
    var widgets: List[Int]  # the control for each node
    var extras: List[Int]  # a second view for some nodes (a toggle's label)
    var focus: Int  # text field to keep focused across the next rebuild (-1: none)

    def __init__(out self):
        self.rt = Runtime(Self.A())
        self.window = 0
        self.view = 0
        self.root = 0
        self.target = 0
        self.choose = 0
        self.widgets = List[Int]()
        self.extras = List[Int]()
        self.focus = -1

    def wire(self, w: Int, i: Int, self_addr: Int, action: String, events: Int):
        _ = msg(w, "setTag:", tag_for(self_addr, i))
        _ = msg(w, "addTarget:action:forControlEvents:", self.target, sel(action), events)

    def menu(self, options: List[String], selected: Int, tag: Int) -> Int:
        """A UIMenu with one action per option; the selected one is checked."""
        var actions = msg(cls("NSMutableArray"), "array")
        for j in range(len(options)):
            var id = ns_string(String(tag) + ":" + String(j))
            var action = msg(cls("UIAction"), "actionWithTitle:image:identifier:handler:", ns_string(options[j]), 0, id, self.choose)
            if j == selected:
                _ = msg(action, "setState:", 1)  # UIMenuElementStateOn
            _ = msg(actions, "addObject:", action)
        return msg(cls("UIMenu"), "menuWithTitle:children:", ns_string(""), actions)

    def build(mut self, i: Int, self_addr: Int) -> Int:
        var node = self.rt.shown.nodes[i].copy()  # copy: building children mutates self
        var w: Int
        var shown: Int  # what goes into the parent (usually w itself)
        if node.kind == TEXT:
            w = label(node.text, node.style)
            shown = w
        elif node.kind == BUTTON:
            w = make_button(node.text, node.style)
            self.wire(w, i, self_addr, "tap:", TOUCH_UP_INSIDE)
            shown = w
        elif node.kind == FIELD:
            w = new("UITextField")
            _ = msg(w, "setBorderStyle:", 3)  # rounded rect
            _ = msg(w, "setText:", ns_string(node.text))
            _ = msg(w, "setPlaceholder:", ns_string(node.hint))
            _ = msg(w, "setReturnKeyType:", 9)  # Done
            self.wire(w, i, self_addr, "changed:", EDITING_CHANGED)
            _ = msg(w, "addTarget:action:forControlEvents:", self.target, sel("submit:"), EDITING_DID_END_ON_EXIT)
            constrain(w, "widthAnchor", Float64(200))  # leaves room for a button beside it on an iPhone SE
            constrain(w, "heightAnchor", Float64(44))
            shown = w
        elif node.kind == TOGGLE:
            w = new("UISwitch")
            _ = msg(w, "setOn:animated:", node.value, 0)
            self.wire(w, i, self_addr, "toggle:", VALUE_CHANGED)
            var text = label(node.text, 0)
            self.extras[i] = text
            shown = new("UIStackView")  # [label  switch]
            _ = msg(shown, "setAxis:", 0)
            _ = msg(shown, "setAlignment:", 3)  # centre
            _ = msg(shown, "setSpacing:", Float64(12))
            _ = msg(shown, "addArrangedSubview:", text)
            _ = msg(shown, "addArrangedSubview:", w)
        elif node.kind == DROPDOWN:
            var title = node.options[node.value] if node.value < len(node.options) else String("")
            w = make_button(title, 0)
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            _ = msg(w, "setMenu:", self.menu(node.options, node.value, tag_for(self_addr, i)))
            _ = msg(w, "setShowsMenuAsPrimaryAction:", 1)
            _ = msg(w, "setChangesSelectionAsPrimaryAction:", 1)  # shows the chosen option, with a checkmark
            shown = w
        elif node.kind == SLIDER:
            w = new("UISlider")
            _ = msg(w, "setMinimumValue:", Float32(0))
            _ = msg(w, "setMaximumValue:", Float32(100))
            _ = msg(w, "setValue:animated:", Float32(node.value), 0)
            self.wire(w, i, self_addr, "slide:", VALUE_CHANGED)
            constrain(w, "widthAnchor", Float64(260))
            shown = w
        elif node.kind == PROGRESS:
            w = msg(msg(cls("UIProgressView"), "alloc"), "initWithProgressViewStyle:", 0)
            _ = msg(w, "setProgress:animated:", Float32(node.value) / 100.0, 0)
            constrain(w, "widthAnchor", Float64(260))
            shown = w
        elif node.kind == DIVIDER:
            w = new("UIView")
            _ = msg(w, "setBackgroundColor:", msg(cls("UIColor"), "separatorColor"))
            constrain(w, "widthAnchor", Float64(280))
            constrain(w, "heightAnchor", Float64(1))
            shown = w
        elif node.kind == IMAGE:
            w = msg(msg(cls("UIImageView"), "alloc"), "initWithImage:", ui_image(node.pixels, node.spacing, node.size))
            _ = msg(w, "setContentMode:", 1)  # scale aspect fit
            # At most its pixel width (shrinks on narrow screens), always its own aspect ratio.
            var most = msg(msg(w, "widthAnchor"), "constraintLessThanOrEqualToConstant:", Float64(node.spacing))
            _ = msg(most, "setActive:", 1)
            var want = msg(msg(w, "widthAnchor"), "constraintEqualToConstant:", Float64(node.spacing))
            _ = msg(want, "setPriority:", Float32(750))  # preferred, but the screen width wins
            _ = msg(want, "setActive:", 1)
            var ratio = Float64(node.size) / Float64(max(node.spacing, 1))
            var aspect = msg(msg(w, "heightAnchor"), "constraintEqualToAnchor:multiplier:", msg(w, "widthAnchor"), ratio)
            _ = msg(aspect, "setActive:", 1)
            shown = w
        elif node.kind == SEGMENTED or node.kind == TABS:
            w = msg(msg(cls("UISegmentedControl"), "alloc"), "initWithItems:", ns_array(node.options))
            _ = msg(w, "setSelectedSegmentIndex:", node.value)
            self.wire(w, i, self_addr, "segment:", VALUE_CHANGED)
            constrain(w, "heightAnchor", Float64(40 if node.kind == TABS else 34))
            shown = w
        elif node.kind == RADIO:
            w = new("UIStackView")
            _ = msg(w, "setAxis:", 1)
            _ = msg(w, "setAlignment:", 1)  # leading
            for j in range(len(node.options)):
                var b = radio_button(node.options[j], j == node.value)
                self.wire(b, i, self_addr, "radio:", TOUCH_UP_INSIDE)
                _ = msg(w, "addArrangedSubview:", b)
            shown = w
        elif node.kind == TEXTAREA:
            w = new("UITextView")
            _ = msg(w, "setText:", ns_string(node.text))
            _ = msg(w, "setFont:", msg(cls("UIFont"), "preferredFontForTextStyle:", ns_string("UICTFontTextStyleBody")))
            _ = msg(w, "setAdjustsFontForContentSizeCategory:", 1)
            _ = msg(w, "setBackgroundColor:", msg(cls("UIColor"), "secondarySystemBackgroundColor"))
            _ = msg(msg(w, "layer"), "setCornerRadius:", Float64(12))
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            _ = msg(w, "setDelegate:", self.target)  # textViewDidChange:
            constrain(w, "widthAnchor", Float64(300))
            constrain(w, "heightAnchor", Float64(node.size))
            shown = w
        elif node.kind == ALERT:
            # Presented on the next run-loop turn (not inside the event that asked for it).
            _ = msg(self.target, "performSelector:withObject:afterDelay:", sel("presentAlert:"), ns_number(tag_for(self_addr, i)), Float64(0))
            w = new("UIView")  # nothing in the layout itself
            shown = w
        elif node.kind == NAVBAR:
            w = new("UINavigationBar")
            var item = msg(msg(msg(cls("UINavigationItem"), "alloc"), "initWithTitle:", ns_string(node.text)), "autorelease")
            if node.msg != 0:
                var chevron = msg(cls("UIImage"), "systemImageNamed:", ns_string("chevron.backward"))
                var back = msg(msg(cls("UIBarButtonItem"), "alloc"), "initWithImage:style:target:action:", chevron, 0, self.target, sel("tap:"))
                _ = msg(back, "setTag:", tag_for(self_addr, i))
                _ = msg(back, "setAccessibilityLabel:", ns_string("Back"))
                _ = msg(item, "setLeftBarButtonItem:", back)
            _ = msg(w, "setItems:animated:", msg(cls("NSArray"), "arrayWithObject:", item), 0)
            constrain(w, "widthAnchor", Float64(340))
            shown = w
        elif node.kind == DATE:
            w = new("UIDatePicker")
            _ = msg(w, "setDatePickerMode:", 1)  # date only
            _ = msg(w, "setPreferredDatePickerStyle:", 2)  # compact
            _ = msg(w, "setDate:", ns_date(node.text))
            self.wire(w, i, self_addr, "date:", VALUE_CHANGED)
            shown = w
        elif node.kind == ICON:
            var config = msg(cls("UIImageSymbolConfiguration"), "configurationWithPointSize:", Float64(node.size))
            var image = msg(cls("UIImage"), "systemImageNamed:withConfiguration:", ns_string(sf_symbol(node.text)), config)
            w = msg(msg(cls("UIImageView"), "alloc"), "initWithImage:", image)
            shown = w
        elif node.kind == GRID:
            w = new("UIStackView")
            _ = msg(w, "setAxis:", 1)
            _ = msg(w, "setSpacing:", Float64(node.spacing))
            var row = 0
            for k in range(len(node.children)):
                if k % node.value == 0:
                    row = new("UIStackView")
                    _ = msg(row, "setAxis:", 0)
                    _ = msg(row, "setDistribution:", 1)  # fill equally
                    _ = msg(row, "setSpacing:", Float64(node.spacing))
                    _ = msg(w, "addArrangedSubview:", row)
                _ = msg(row, "addArrangedSubview:", self.build(node.children[k], self_addr))
            shown = w
        elif node.kind == LAZYLIST:
            w = msg(msg(cls("UITableView"), "alloc"), "initWithFrame:style:", Float64(0), Float64(0), Float64(340), Float64(node.size), 2)  # inset grouped
            _ = msg(w, "registerClass:forCellReuseIdentifier:", cls("UITableViewCell"), ns_string("row"))
            _ = msg(w, "setRowHeight:", Float64(node.spacing))
            _ = msg(w, "setTag:", tag_for(self_addr, i))
            _ = msg(w, "setDataSource:", self.target)  # rows are asked for as they scroll into view
            _ = msg(w, "setDelegate:", self.target)
            constrain(w, "widthAnchor", Float64(340))
            constrain(w, "heightAnchor", Float64(node.size))
            shown = w
        elif node.kind == SPACER:
            w = new("UIView")
            shown = w
        elif node.kind == SCROLL:
            w = new("UIScrollView")
            var content = self.build(node.children[0], self_addr)
            _ = msg(content, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
            _ = msg(w, "addSubview:", content)
            var inner = msg(w, "contentLayoutGuide")
            for anchor in ["topAnchor", "bottomAnchor", "leadingAnchor", "trailingAnchor"]:
                _ = msg(msg(msg(content, anchor), "constraintEqualToAnchor:", msg(inner, anchor)), "setActive:", 1)
            var frame = msg(w, "frameLayoutGuide")
            _ = msg(msg(msg(content, "widthAnchor"), "constraintEqualToAnchor:", msg(frame, "widthAnchor")), "setActive:", 1)
            constrain(w, "heightAnchor", Float64(node.size))
            constrain(w, "widthAnchor", Float64(320))
            shown = w
        else:
            w = new("UIStackView")
            _ = msg(w, "setAxis:", 1 if node.kind == VSTACK else 0)
            _ = msg(w, "setAlignment:", 3)  # centre
            _ = msg(w, "setSpacing:", Float64(node.spacing))
            for c in node.children:
                _ = msg(w, "addArrangedSubview:", self.build(c, self_addr))
            shown = w
        self.widgets[i] = w
        return shown

    def show(mut self, self_addr: Int):
        # Old controls are deliberately never released: that keeps a control alive
        # while the screen is replaced in the middle of its own action.
        if self.root != 0:
            _ = msg(self.root, "removeFromSuperview")
        var has_alert = False
        for n in self.rt.shown.nodes:
            if n.kind == ALERT:
                has_alert = True
        var root_vc = msg(self.window, "rootViewController")
        if not has_alert and root_vc != 0 and is_alert(msg(root_vc, "presentedViewController")):
            _ = msg(root_vc, "dismissViewControllerAnimated:completion:", 1, 0)  # our alert left the view
        self.widgets = List[Int](length=len(self.rt.shown.nodes), fill=0)  # 0 = nil: patches become no-ops
        self.extras = List[Int](length=len(self.rt.shown.nodes), fill=0)
        if len(self.rt.shown.nodes) >= (1 << NODE_BITS):
            self.root = label("Too many items to show (limit 65,535).", 0)  # no stale controls left to use
        else:
            self.root = self.build(0, self_addr)
        _ = msg(self.view, "addSubview:", self.root)
        pin_center(self.root, self.view)
        if 0 <= self.focus < len(self.widgets) and self.rt.shown.nodes[self.focus].kind == FIELD:
            # Keep the keyboard up on the new field, on the next run-loop turn (after
            # UIKit has finished with the old field).
            _ = msg(self.widgets[self.focus], "performSelector:withObject:afterDelay:", sel("becomeFirstResponder"), 0, Float64(0))
        self.focus = -1

    def apply(mut self, d: Diff, self_addr: Int):
        if d.rebuild:
            self.show(self_addr)
            return
        for p in d.patches:
            var w = self.widgets[p.node]
            ref node = self.rt.shown.nodes[p.node]
            if p.op == SET_TEXT and node.kind == TEXTAREA:
                if from_ns(msg(w, "text")) != p.text:  # don't fight the typist
                    _ = msg(w, "setText:", ns_string(p.text))
            elif p.op == SET_TEXT and node.kind == DATE:
                _ = msg(w, "setDate:", ns_date(p.text))
            elif p.op == SET_TEXT and node.kind == NAVBAR:
                _ = msg(msg(w, "topItem"), "setTitle:", ns_string(p.text))
            elif p.op == SET_VALUE and (node.kind == SEGMENTED or node.kind == TABS):
                _ = msg(w, "setSelectedSegmentIndex:", p.number)
            elif p.op == SET_VALUE and node.kind == RADIO:
                var buttons = msg(w, "arrangedSubviews")
                for j in range(msg(buttons, "count")):
                    set_radio(msg(buttons, "objectAtIndex:", j), j == p.number)
            elif p.op == SET_TEXT:
                if node.kind == TEXT:
                    _ = msg(w, "setText:", ns_string(p.text))
                elif node.kind == FIELD:
                    if from_ns(msg(w, "text")) != p.text:  # don't fight the typist
                        _ = msg(w, "setText:", ns_string(p.text))
                elif node.kind == TOGGLE:
                    _ = msg(self.extras[p.node], "setText:", ns_string(p.text))
                elif node.kind == BUTTON:
                    var config = msg(msg(w, "configuration"), "copy")
                    _ = msg(config, "setTitle:", ns_string(p.text))
                    _ = msg(w, "setConfiguration:", config)
            elif p.op == SET_VALUE:
                if node.kind == TOGGLE:
                    _ = msg(w, "setOn:animated:", p.number, 1)
                elif node.kind == DROPDOWN:
                    _ = msg(w, "setMenu:", self.menu(node.options, p.number, tag_for(self_addr, p.node)))
                elif node.kind == SLIDER:
                    _ = msg(w, "setValue:animated:", Float32(p.number), 1)
                elif node.kind == PROGRESS:
                    _ = msg(w, "setProgress:animated:", Float32(p.number) / 100.0, 1)
            elif p.op == SET_IMAGE:
                _ = msg(w, "setImage:", ui_image(node.pixels, node.spacing, node.size))
            # SET_MSG needs nothing: events look the message up in rt.shown.
        # Ask for the visible rows of every long list again: row text isn't part of the view.
        for k in range(len(self.rt.shown.nodes)):
            if self.rt.shown.nodes[k].kind == LAZYLIST and self.widgets[k] != 0:
                _ = msg(self.widgets[k], "reloadData")

    def send(mut self, node: Int, second: Bool, text: String, number: Int, self_addr: Int):
        """A control changed: build the event, run update(), patch the controls."""
        ref n = self.rt.shown.nodes[node]
        var message = n.msg2 if second else n.msg
        if message == 0:
            return
        self.focus = node if n.kind == FIELD else -1
        var d = self.rt.dispatch(Event(message, text, number))
        self.apply(d, self_addr)


def ui_image(pixels: List[UInt32], width: Int, height: Int) -> Int:
    """A UIImage from RGBA pixels, via PNG bytes made in Mojo (mojoui/png.mojo)."""
    return msg(cls("UIImage"), "imageWithData:", ns_data(encode_png(pixels, width, height)))


def is_alert(controller: Int) -> Bool:
    """Whether a presented view controller is an alert (not, say, the date picker's calendar)."""
    return controller != 0 and msg[Int8](controller, "isKindOfClass:", cls("UIAlertController")) != 0


def radio_button(title: String, selected: Bool) -> Int:
    """iOS has no radio button: a plain button with a circle / filled-circle symbol."""
    var config = msg(cls("UIButtonConfiguration"), "plainButtonConfiguration")
    _ = msg(config, "setTitle:", ns_string(title))
    _ = msg(config, "setImagePadding:", Float64(10))
    _ = msg(config, "setButtonSize:", 3)  # large touch target
    var b = msg(cls("UIButton"), "buttonWithConfiguration:primaryAction:", config, 0)
    set_radio(b, selected)
    return b


def set_radio(button: Int, selected: Bool):
    var config = msg(msg(button, "configuration"), "copy")
    var symbol = "largecircle.fill.circle" if selected else "circle"
    _ = msg(config, "setImage:", msg(cls("UIImage"), "systemImageNamed:", ns_string(symbol)))
    _ = msg(button, "setConfiguration:", config)
    _ = msg(button, "setSelected:", 1 if selected else 0)


def label(text: String, style: Int) -> Int:
    var l = new("UILabel")
    _ = msg(l, "setText:", ns_string(text))
    var font = "UICTFontTextStyleBody"  # Dynamic Type: follows the user's text size
    if style == TITLE:
        font = "UICTFontTextStyleTitle0"  # large title
    elif style == HEADLINE:
        font = "UICTFontTextStyleHeadline"
    elif style == CAPTION:
        font = "UICTFontTextStyleFootnote"
        _ = msg(l, "setTextColor:", msg(cls("UIColor"), "secondaryLabelColor"))
    _ = msg(l, "setFont:", msg(cls("UIFont"), "preferredFontForTextStyle:", ns_string(font)))
    _ = msg(l, "setAdjustsFontForContentSizeCategory:", 1)
    _ = msg(l, "setTextAlignment:", 1)  # centre
    _ = msg(l, "setNumberOfLines:", 0)
    return l


def make_button(title: String, style: Int) -> Int:
    """Liquid Glass on iOS 26+, filled/gray buttons before that; always large touch targets."""
    var config_cls = cls("UIButtonConfiguration")
    var glass = msg[Int8](config_cls, "respondsToSelector:", sel("prominentGlassButtonConfiguration")) != 0
    var maker: String
    if style == PROMINENT:
        maker = "prominentGlassButtonConfiguration" if glass else "filledButtonConfiguration"
    else:
        maker = "glassButtonConfiguration" if glass else "grayButtonConfiguration"
    var config = msg(config_cls, maker)
    _ = msg(config, "setTitle:", ns_string(title))
    _ = msg(config, "setButtonSize:", 3)  # large
    _ = msg(config, "setCornerStyle:", 4)  # capsule
    if style == DESTRUCTIVE:
        _ = msg(config, "setBaseForegroundColor:", msg(cls("UIColor"), "systemRedColor"))
    return msg(cls("UIButton"), "buttonWithConfiguration:primaryAction:", config, 0)


def pin_center(view: Int, inside: Int):
    """Auto Layout: centre `view` in the safe area (clear of the Dynamic Island and
    home indicator), at most its width minus margins."""
    var guide = msg(inside, "safeAreaLayoutGuide")
    _ = msg(view, "setTranslatesAutoresizingMaskIntoConstraints:", 0)
    for anchor in ["centerXAnchor", "centerYAnchor"]:
        var c = msg(msg(view, anchor), "constraintEqualToAnchor:", msg(guide, anchor))
        _ = msg(c, "setActive:", 1)
    var w = msg(
        msg(view, "widthAnchor"), "constraintLessThanOrEqualToAnchor:constant:", msg(guide, "widthAnchor"), Float64(-48)
    )
    _ = msg(w, "setActive:", 1)
    # Keeps content inside the safe area. Long content belongs in a Scroll; without
    # one, very tall screens get squashed rather than running off-screen.
    var h = msg(msg(view, "heightAnchor"), "constraintLessThanOrEqualToAnchor:", msg(guide, "heightAnchor"))
    _ = msg(h, "setActive:", 1)


def from_tag(control: Int) -> Tuple[Int, Int]:
    var tag = msg(control, "tag")
    return (tag >> NODE_BITS, tag & ((1 << NODE_BITS) - 1))


def host_at[A: App](addr: Int) -> Pointer[UIKitHost[A], MutUntrackedOrigin]:
    return Pointer[UIKitHost[A], MutUntrackedOrigin](unsafe_from_address=addr)


# ---------- scene delegate methods and the dropdown block (UIKit calls these) ----------

def on_tap[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], False, "", 0, t[0])


def on_changed[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(sender, "text")), 0, t[0])


def on_submit[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], True, from_ns(msg(sender, "text")), 0, t[0])


def on_toggle[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var on = Int(msg[Int8](sender, "isOn"))
    host_at[A](t[0])[].send(t[1], False, "", 1 if on != 0 else 0, t[0])


def on_segment[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var index = msg(sender, "selectedSegmentIndex")
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(sender, "titleForSegmentAtIndex:", index)), index, t[0])


def on_radio[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var index = msg(msg(msg(sender, "superview"), "arrangedSubviews"), "indexOfObject:", sender)
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(msg(sender, "configuration"), "title")), index, t[0])


def on_text_view_change[A: App](target: Int, cmd: Int, view: Int) abi("C"):
    var t = from_tag(view)
    host_at[A](t[0])[].send(t[1], False, from_ns(msg(view, "text")), 0, t[0])


def on_date[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    host_at[A](t[0])[].send(t[1], False, date_text(msg(sender, "date")), 0, t[0])


def on_alert_action[A: App](block: Int, action: Int) abi("C"):
    """An alert button was tapped: the block carries "(host << 16) | node"; the action's title says which."""
    var tag = block_data(block)
    var host_addr = tag >> NODE_BITS
    var node = tag & ((1 << NODE_BITS) - 1)
    var host = host_at[A](host_addr)
    if node >= len(host[].rt.shown.nodes) or host[].rt.shown.nodes[node].kind != ALERT:
        return
    var title = from_ns(msg(action, "title"))
    ref opts = host[].rt.shown.nodes[node].options
    for j in range(len(opts)):
        if opts[j] == title:
            host[].send(node, False, title, j, host_addr)
            return


def on_present_alert[A: App](target: Int, cmd: Int, number: Int) abi("C"):
    var tag = msg(number, "longValue")
    var host_addr = tag >> NODE_BITS
    var node = tag & ((1 << NODE_BITS) - 1)
    var host = host_at[A](host_addr)
    if node >= len(host[].rt.shown.nodes) or host[].rt.shown.nodes[node].kind != ALERT:
        return  # the screen changed before it could be shown
    var n = host[].rt.shown.nodes[node].copy()
    var alert = msg(cls("UIAlertController"), "alertControllerWithTitle:message:preferredStyle:", ns_string(n.text), ns_string(n.hint), 1)
    var handler = data_block(on_alert_action[A], "v16@?0@8", tag)
    for j in range(len(n.options)):
        var lower = n.options[j].lower()
        var style = 1 if (j == 0 and len(n.options) > 1) else 0  # the first of several is Cancel
        if j > 0 and (lower.startswith("delete") or lower.startswith("remove")):
            style = 2  # destructive: shown in red
        var action = msg(cls("UIAlertAction"), "actionWithTitle:style:handler:", ns_string(n.options[j]), style, handler)
        _ = msg(alert, "addAction:", action)
    var root = msg(host[].window, "rootViewController")
    if is_alert(msg(root, "presentedViewController")):
        return  # already showing it (the screen was rebuilt twice while the alert was in the view)
    _ = msg(root, "presentViewController:animated:completion:", alert, 1, 0)


def on_row_count[A: App](target: Int, cmd: Int, table: Int, section: Int) abi("C") -> Int:
    var t = from_tag(table)
    var host = host_at[A](t[0])
    if t[1] >= len(host[].rt.shown.nodes) or host[].rt.shown.nodes[t[1]].kind != LAZYLIST:
        return 0
    return host[].rt.shown.nodes[t[1]].value


def on_row_cell[A: App](target: Int, cmd: Int, table: Int, index_path: Int) abi("C") -> Int:
    """UITableView asks for a row's cell only when it scrolls into view."""
    var t = from_tag(table)
    var host = host_at[A](t[0])
    var cell = msg(table, "dequeueReusableCellWithIdentifier:forIndexPath:", ns_string("row"), index_path)
    if t[1] < len(host[].rt.shown.nodes) and host[].rt.shown.nodes[t[1]].kind == LAZYLIST:
        var row = msg(index_path, "row")
        var config = msg(cell, "defaultContentConfiguration")
        _ = msg(config, "setText:", ns_string(host[].rt.app.row(host[].rt.shown.nodes[t[1]].msg2, row)))
        _ = msg(cell, "setContentConfiguration:", config)
    return cell


def on_row_select[A: App](target: Int, cmd: Int, table: Int, index_path: Int) abi("C"):
    _ = msg(table, "deselectRowAtIndexPath:animated:", index_path, 1)
    var t = from_tag(table)
    host_at[A](t[0])[].send(t[1], False, "", msg(index_path, "row"), t[0])


def on_slide[A: App](target: Int, cmd: Int, sender: Int) abi("C"):
    var t = from_tag(sender)
    var value = Int(msg[Float32](sender, "value") + 0.5)
    host_at[A](t[0])[].send(t[1], False, "", value, t[0])


def on_choose[A: App](block: Int, action: Int) abi("C"):
    """A dropdown option was chosen: its identifier is "<tag>:<index>"."""
    var id = from_ns(msg(action, "identifier"))
    var colon = id.find(":")
    if colon < 0:
        return
    try:
        var tag = Int(String(id[byte=:colon]))
        var index = Int(String(id[byte = colon + 1 :]))
        var host_addr = tag >> NODE_BITS
        var node = tag & ((1 << NODE_BITS) - 1)
        host_at[A](host_addr)[].send(node, False, from_ns(msg(action, "title")), index, host_addr)
    except:
        return


def did_finish_launching(target: Int, cmd: Int, app: Int, options: Int) abi("C") -> Int8:
    return 1  # YES; the scene builds the UI


def scene_will_connect[A: App](delegate: Int, cmd: Int, scene: Int, session: Int, options: Int) abi("C"):
    """Creates the app and its window when UIKit connects the scene."""
    var host = alloc(Layout[UIKitHost[A]].single()).unsafe_leak()  # lives as long as the app
    host.unsafe_write(UIKitHost[A]())
    var addr = Int(host)
    if (addr >> (63 - NODE_BITS)) != 0:
        print("mojoui: can't pack host address into a control tag")
        return
    host[].target = delegate
    host[].choose = global_block(on_choose[A], "v16@?0@8")  # void (^)(UIAction *)
    host[].window = msg(msg(cls("UIWindow"), "alloc"), "initWithWindowScene:", scene)  # kept for the app's life
    var controller = new("UIViewController")
    host[].view = msg(controller, "view")
    _ = msg(host[].view, "setBackgroundColor:", msg(cls("UIColor"), "systemBackgroundColor"))
    host[].show(addr)
    _ = msg(host[].window, "setRootViewController:", controller)
    _ = msg(host[].window, "makeKeyAndVisible")


def run[A: App](argc: c_int, argv: Int) -> c_int:
    """Starts UIKit; the scene delegate then creates the app. Never returns."""
    _ = pool_push()
    var app_delegate = new_class("MojoAppDelegate", "UIResponder")
    add_protocol(app_delegate, "UIApplicationDelegate")
    add_method(app_delegate, "application:didFinishLaunchingWithOptions:", did_finish_launching, "B@:@@")
    register_class(app_delegate)

    var scene_delegate = new_class("MojoSceneDelegate", "UIResponder")
    add_protocol(scene_delegate, "UIWindowSceneDelegate")
    add_method(scene_delegate, "scene:willConnectToSession:options:", scene_will_connect[A], "v@:@@@")
    add_method(scene_delegate, "tap:", on_tap[A], "v@:@")
    add_method(scene_delegate, "changed:", on_changed[A], "v@:@")
    add_method(scene_delegate, "submit:", on_submit[A], "v@:@")
    add_method(scene_delegate, "toggle:", on_toggle[A], "v@:@")
    add_method(scene_delegate, "slide:", on_slide[A], "v@:@")
    add_method(scene_delegate, "segment:", on_segment[A], "v@:@")
    add_method(scene_delegate, "radio:", on_radio[A], "v@:@")
    add_method(scene_delegate, "date:", on_date[A], "v@:@")
    add_method(scene_delegate, "textViewDidChange:", on_text_view_change[A], "v@:@")
    add_method(scene_delegate, "presentAlert:", on_present_alert[A], "v@:@")
    add_method(scene_delegate, "tableView:numberOfRowsInSection:", on_row_count[A], "q@:@q")
    add_method(scene_delegate, "tableView:cellForRowAtIndexPath:", on_row_cell[A], "@@:@@")
    add_method(scene_delegate, "tableView:didSelectRowAtIndexPath:", on_row_select[A], "v@:@@")
    add_protocol(scene_delegate, "UITextViewDelegate")
    add_protocol(scene_delegate, "UITableViewDataSource")
    add_protocol(scene_delegate, "UITableViewDelegate")
    register_class(scene_delegate)
    return external_call["UIApplicationMain", c_int](argc, argv, 0, ns_string("MojoAppDelegate"))
