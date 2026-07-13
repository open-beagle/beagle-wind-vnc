#!/bin/bash
set -e

. /etc/beagle-wind-vnc/runtime-env.sh

if [ "${BDWIND_KDE6_CAPTURED_PANEL:-true}" != "true" ]; then
    echo "[kde6] captured output panel ensure disabled"
    exit 0
fi

target_screen="${BDWIND_KDE6_CAPTURED_PANEL_SCREEN:-1}"
retries="${BDWIND_KDE6_CAPTURED_PANEL_RETRIES:-3}"
delay="${BDWIND_KDE6_CAPTURED_PANEL_RETRY_DELAY:-1}"
runtime_timeout="${BDWIND_KDE6_CAPTURED_PANEL_RUNTIME_TIMEOUT:-5}"

case "${target_screen}" in
    ''|*[!0-9]*)
        echo "[kde6] invalid BDWIND_KDE6_CAPTURED_PANEL_SCREEN=${target_screen}" >&2
        exit 0
        ;;
esac
case "${retries}" in
    ''|*[!0-9]*)
        echo "[kde6] invalid BDWIND_KDE6_CAPTURED_PANEL_RETRIES=${retries}; using 30" >&2
        retries=30
        ;;
esac

ensure_config_panel() {
    python3 - "${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc" "${target_screen}" <<'PY'
import os
import re
import shutil
import sys
import time

path = sys.argv[1]
target_screen = sys.argv[2]

if not os.path.exists(path):
    print("[kde6] plasma applet config not found; runtime busctl ensure will be attempted")
    sys.exit(1)

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

containment_re = re.compile(r"^\[Containments\]\[(\d+)\]$", re.M)
applet_re = re.compile(r"\[Applets\]\[(\d+)\]")

backup = None
changed = False

def ensure_backup():
    global backup
    if backup is None:
        backup = "%s.bdwind-panel-%s.bak" % (path, time.strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(path, backup)
    return backup

taskmanager_so = "/usr/lib/x86_64-linux-gnu/qt6/plugins/plasma/applets/org.kde.plasma.taskmanager.so"
if "plugin=org.kde.plasma.icontasks" in text and os.path.exists(taskmanager_so):
    ensure_backup()
    text = text.replace("plugin=org.kde.plasma.icontasks", "plugin=org.kde.plasma.taskmanager")
    changed = True
    print("[kde6] migrated org.kde.plasma.icontasks to org.kde.plasma.taskmanager backup=%s" % backup)

data_dirs = []
xdg_data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")
data_dirs.append(os.path.join(xdg_data_home, "applications"))
for data_dir in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
    if data_dir:
        data_dirs.append(os.path.join(data_dir, "applications"))

def desktop_exists(launcher):
    if not launcher.startswith("applications:"):
        return True
    desktop_name = launcher.split(":", 1)[1]
    return any(os.path.exists(os.path.join(data_dir, desktop_name)) for data_dir in data_dirs)

preferred_launchers = [
    "applications:org.kde.dolphin.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:systemsettings.desktop",
]
valid_launchers = [launcher for launcher in preferred_launchers if desktop_exists(launcher)]
if not valid_launchers:
    valid_launchers = ["applications:org.kde.dolphin.desktop", "applications:org.kde.konsole.desktop"]
launcher_line = "launchers=%s" % ",".join(valid_launchers)

def normalize_launchers(match):
    global changed
    current_line = match.group(0)
    current_value = current_line.split("=", 1)[1]
    entries = [entry.strip() for entry in current_value.split(",") if entry.strip()]
    if entries and all(desktop_exists(entry) for entry in entries):
        return current_line
    ensure_backup()
    changed = True
    print("[kde6] normalized invalid taskmanager launchers to %s backup=%s" % (",".join(valid_launchers), backup))
    return launcher_line

text = re.sub(r"^launchers=.*$", normalize_launchers, text, flags=re.M)

stats_path = os.path.join(os.path.dirname(path), "kactivitymanagerd-statsrc")
if os.path.exists(stats_path):
    favorite_ids = [launcher.split(":", 1)[1] for launcher in valid_launchers if launcher.startswith("applications:")]
    favorite_line = "ordering=%s" % ",".join(favorite_ids)

    with open(stats_path, "r", encoding="utf-8") as f:
        stats_text = f.read()

    def normalize_ordering(match):
        current_line = match.group(0)
        current_value = current_line.split("=", 1)[1]
        entries = [entry.strip() for entry in current_value.split(",") if entry.strip()]
        if entries and all(desktop_exists("applications:" + entry) for entry in entries if not entry.startswith("preferred://")):
            if not any(entry.startswith("preferred://") for entry in entries):
                return current_line
        return favorite_line

    new_stats_text = re.sub(r"^ordering=.*$", normalize_ordering, stats_text, flags=re.M)
    if new_stats_text != stats_text:
        stats_backup = "%s.bdwind-favorites-%s.bak" % (stats_path, time.strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(stats_path, stats_backup)
        with open(stats_path, "w", encoding="utf-8") as f:
            f.write(new_stats_text)
        print("[kde6] normalized invalid kickoff favorites to %s backup=%s" % (",".join(favorite_ids), stats_backup))

sections = {}
for match in containment_re.finditer(text):
    cid = match.group(1)
    start = match.end()
    next_match = re.search(r"^\[", text[start:], re.M)
    end = start + next_match.start() if next_match else len(text)
    body = text[start:end]
    props = {}
    for line in body.splitlines():
        if "=" in line and not line.startswith("["):
            key, value = line.split("=", 1)
            props[key.strip()] = value.strip()
    sections[cid] = props

for cid, props in sections.items():
    if props.get("plugin") == "org.kde.panel" and props.get("lastScreen") == target_screen:
        if changed:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
        print("[kde6] captured output panel already exists containment=%s screen=%s" % (cid, target_screen))
        sys.exit(0)

max_containment = max([int(x) for x in containment_re.findall(text)] or [0])
max_applet = max([int(x) for x in applet_re.findall(text)] or [max_containment])
new_containment = max_containment + 1
applets = list(range(max_applet + 1, max_applet + 7))

ensure_backup()

panel = """

[Containments][{c}]
activityId=
formfactor=2
immutability=1
lastScreen={screen}
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][{c}][Applets][{kickoff}]
immutability=1
plugin=org.kde.plasma.kickoff

[Containments][{c}][Applets][{pager}]
immutability=1
plugin=org.kde.plasma.pager

[Containments][{c}][Applets][{tasks}]
immutability=1
plugin=org.kde.plasma.taskmanager

[Containments][{c}][Applets][{tasks}][Configuration][General]
{launchers}

[Containments][{c}][Applets][{separator}]
immutability=1
plugin=org.kde.plasma.marginsseparator

[Containments][{c}][Applets][{tray}]
activityId=
formfactor=0
immutability=1
lastScreen=-1
location=0
plugin=org.kde.plasma.systemtray
popupHeight=432
popupWidth=432
wallpaperplugin=org.kde.image

[Containments][{c}][Applets][{clock}]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][{c}][General]
AppletOrder={kickoff};{pager};{tasks};{separator};{tray};{clock}
""".format(
    c=new_containment,
    screen=target_screen,
    kickoff=applets[0],
    pager=applets[1],
    tasks=applets[2],
    separator=applets[3],
    tray=applets[4],
    clock=applets[5],
    launchers=launcher_line,
)

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
    f.write(panel)

print("[kde6] appended captured output panel containment=%s screen=%s backup=%s" % (new_containment, target_screen, backup))
PY
}

config_panel_ready=false
if ensure_config_panel; then
    config_panel_ready=true
fi
if [ "${1:-}" = "--config-only" ]; then
    exit 0
fi

if [ "${BDWIND_KDE6_CAPTURED_PANEL_RUNTIME:-true}" != "true" ]; then
    echo "[kde6] runtime panel ensure disabled"
    exit 0
fi

wait_captured_output() {
    if [ "${BDWIND_KDE6_CAPTURED_PANEL_WAIT_OUTPUT:-true}" != "true" ]; then
        return 0
    fi

    timeout_s="${BDWIND_KDE6_CAPTURED_PANEL_WAIT_OUTPUT_TIMEOUT:-90}"
    case "${timeout_s}" in
        ''|*[!0-9]*)
            timeout_s=90
            ;;
    esac

    i=0
    while [ "${i}" -lt "${timeout_s}" ]; do
        if command -v pw-link >/dev/null 2>&1 \
            && pw-link -oI 2>/dev/null | grep -q "kwin_wayland:output_${target_screen}\\b"; then
            echo "[kde6] captured output ready via PipeWire output_${target_screen}"
            return 0
        fi
        if command -v kscreen-doctor >/dev/null 2>&1 \
            && kscreen-doctor -j 2>/dev/null | python3 -c 'import json, sys; target = int(sys.argv[1]); data = json.load(sys.stdin); outputs = [o for o in data.get("outputs", []) if o.get("enabled")]; sys.exit(0 if len(outputs) > target else 1)' "${target_screen}"
        then
            echo "[kde6] captured output ready via KScreen screen ${target_screen}"
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done

    echo "[kde6] captured output screen ${target_screen} not ready after ${timeout_s}s" >&2
    return 1
}

if ! wait_captured_output; then
    exit 0
fi

if ! command -v busctl >/dev/null 2>&1; then
    echo "[kde6] busctl not found; runtime panel ensure skipped" >&2
    exit 0
fi

tmp_js="$(mktemp /tmp/bdwind-captured-panel.XXXXXX.js)"
trap 'rm -f "${tmp_js}"' EXIT

cat >"${tmp_js}" <<EOF
var targetScreen = ${target_screen};
var panel = null;
var detachedPanel = null;
var ps = panels();
for (var i = 0; i < ps.length; i++) {
    print("panel " + i + " screen=" + ps[i].screen + " id=" + ps[i].id + " loc=" + ps[i].location);
    if (ps[i].screen == targetScreen) {
        panel = ps[i];
    } else if (!detachedPanel && ps[i].screen < 0) {
        detachedPanel = ps[i];
    }
}
if (!panel && detachedPanel) {
    panel = detachedPanel;
    panel.screen = targetScreen;
    print("reassigned detached panel id=" + panel.id + " screen=" + panel.screen);
}
if (!panel) {
    var unit = (typeof gridUnit === "number" && gridUnit > 0) ? gridUnit : 18;
    panel = new Panel;
    panel.screen = targetScreen;
    panel.location = "bottom";
    panel.height = Math.max(32, unit * 2);
    print("created panel id=" + panel.id + " screen=" + panel.screen);
}
panel.location = "bottom";
panel.height = Math.max(panel.height || 0, 48);
function hasWidget(panel, plugin) {
    var widgets = panel.widgets();
    for (var i = 0; i < widgets.length; i++) {
        if (widgets[i].type == plugin) {
            return true;
        }
    }
    return false;
}
function ensureWidget(panel, plugin) {
    if (!hasWidget(panel, plugin)) {
        try {
            panel.addWidget(plugin);
            print("added widget " + plugin + " panel=" + panel.id);
        } catch (e) {
            print("failed widget " + plugin + " panel=" + panel.id + " error=" + e);
        }
    }
}
ensureWidget(panel, "org.kde.plasma.kickoff");
ensureWidget(panel, "org.kde.plasma.pager");
ensureWidget(panel, "org.kde.plasma.taskmanager");
ensureWidget(panel, "org.kde.plasma.marginsseparator");
ensureWidget(panel, "org.kde.plasma.systemtray");
ensureWidget(panel, "org.kde.plasma.digitalclock");
ensureWidget(panel, "org.kde.plasma.showdesktop");
EOF

i=0
while [ "${i}" -lt "${retries}" ]; do
    if busctl --user --timeout="${runtime_timeout}" call \
        org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript \
        s "$(cat "${tmp_js}")"; then
        echo "[kde6] captured output panel ensured on screen ${target_screen}"
        exit 0
    fi
    i=$((i + 1))
    sleep "${delay}"
done

echo "[kde6] failed to ensure captured output panel after ${retries} attempts" >&2
exit 0
