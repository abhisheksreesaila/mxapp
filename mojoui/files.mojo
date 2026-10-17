# mojoui.files: small file helpers every document app needs: names from paths, and the recent-files list
# (one path per line in <config>/recent.txt, newest first, at most 10).

from mojoui.shared import environment, make_dir


def file_name(path: String) -> String:
    var i = path.rfind("/")
    return String(path[byte = i + 1 :]) if i >= 0 else path


def file_stem(path: String) -> String:
    var name = file_name(path)
    var dot = name.rfind(".")
    return String(name[byte=:dot]) if dot > 0 else name


def config_dir(app: String) -> String:
    """Where an app keeps its settings: $OMX_CONFIG if set (tests), else ~/.config/<app>."""
    return environment("OMX_CONFIG", environment("HOME", ".") + "/.config/" + app)


def read_recent(app: String) -> List[String]:
    var out = List[String]()
    try:
        with open(config_dir(app) + "/recent.txt", "r") as f:
            for line in f.read().split("\n"):
                var p = String(line.strip())
                if p != "":
                    out.append(p)
    except:
        pass
    return out^


def remember(app: String, path: String, mut recent: List[String]):
    """Puts path first in the list (and on disk)."""
    var out = List[String]()
    out.append(path)
    for p in recent:
        if p != path and len(out) < 10:
            out.append(p)
    recent = out^
    try:
        make_dir(config_dir(app))
        with open(config_dir(app) + "/recent.txt", "w") as f:
            for p in recent:
                f.write(p + "\n")
    except:
        pass
