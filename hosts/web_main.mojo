# Web entry point: builds the app module (`app.mojo`, chosen with -I) as a Python
# extension module, `mojoui_app`, which mojoui/hosts/web.py serves with FastHTML.
from std.os import abort
from std.python import PythonObject
from std.python.bindings import PythonModuleBuilder

from app import Main
from mojoui.hosts.web import web_new, web_title, web_view, web_event, web_close


@export
def PyInit_mojoui_app() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("mojoui_app")
        m.def_function[new_session]("new_session", docstring="Start an app session; returns its handle.")
        m.def_function[title]("title", docstring="The app's title.")
        m.def_function[view]("view", docstring="The current screen as JSON.")
        m.def_function[event]("event", docstring="Send an event (message, text, number); returns what changed as JSON.")
        m.def_function[close]("close", docstring="End a session.")
        return m.finalize()
    except e:
        abort(String("mojoui: couldn't create the Python module: ", e))


def new_session() raises -> PythonObject:
    return PythonObject(web_new[Main]())


def title(handle: PythonObject) raises -> PythonObject:
    return PythonObject(web_title[Main](Int(py=handle)))


def view(handle: PythonObject) raises -> PythonObject:
    return PythonObject(web_view[Main](Int(py=handle)))


def event(handle: PythonObject, message: PythonObject, text: PythonObject, number: PythonObject) raises -> PythonObject:
    return PythonObject(web_event[Main](Int(py=handle), Int(py=message), String(py=text), Int(py=number)))


def close(handle: PythonObject) raises -> PythonObject:
    web_close[Main](Int(py=handle))
    return PythonObject(None)
