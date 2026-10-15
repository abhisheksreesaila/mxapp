# Linux entry point: runs the app module (`app.mojo`, chosen with -I) in GTK.
from app import Main
from mojoui.hosts.gtk import run


def main():
    _ = run[Main]()
