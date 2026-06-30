#!/bin/bash
set -e

. /etc/beagle-wind-vnc/runtime-env.sh

portal_kde_bin="${1:-}"
if [ -z "${portal_kde_bin}" ]; then
    portal_kde_bin="$(command -v xdg-desktop-portal-kde || true)"
fi
if [ -z "${portal_kde_bin}" ] && [ -x /usr/lib/x86_64-linux-gnu/libexec/xdg-desktop-portal-kde ]; then
    portal_kde_bin=/usr/lib/x86_64-linux-gnu/libexec/xdg-desktop-portal-kde
fi
if [ -z "${portal_kde_bin}" ] && [ -x /usr/libexec/xdg-desktop-portal-kde ]; then
    portal_kde_bin=/usr/libexec/xdg-desktop-portal-kde
fi

if [ -z "${portal_kde_bin}" ]; then
    echo "[kde6] xdg-desktop-portal-kde binary is missing; cannot prepare KDE Wayland interface grants" >&2
    exit 66
fi

user_desktop_dir="${XDG_DATA_HOME}/applications"
system_desktop_dir="/usr/local/share/applications"
desktop_dirs=("${user_desktop_dir}")
if [ "${BDWIND_KDE_PORTAL_INSTALL_SYSTEM_DESKTOP}" = "true" ]; then
    desktop_dirs+=("${system_desktop_dir}")
fi

for desktop_dir in "${desktop_dirs[@]}"; do
    if [ -w "$(dirname "${desktop_dir}")" ] || [ -w "${desktop_dir}" ]; then
        mkdir -p "${desktop_dir}"
    else
        sudo mkdir -p "${desktop_dir}"
        sudo chown "${USER}:${USER}" "${desktop_dir}" 2>/dev/null || true
    fi
done

find_source_desktop() {
    local preferred_name="$1"
    local candidate

    for candidate in \
        "/usr/share/applications/${preferred_name}" \
        "/usr/local/share/applications/${preferred_name}" \
        /usr/share/applications/org.freedesktop.impl.portal.desktop.kde.desktop \
        /usr/share/applications/xdg-desktop-portal-kde.desktop \
        /usr/local/share/applications/org.freedesktop.impl.portal.desktop.kde.desktop \
        /usr/local/share/applications/xdg-desktop-portal-kde.desktop
    do
        if [ -f "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

ensure_desktop_file() {
    local desktop_dir="$1"
    local desktop_name="$2"
    local desktop_file="${desktop_dir}/${desktop_name}"
    local source_desktop=""
    local current_interfaces=""
    local required_interface=""

    if [ ! -f "${desktop_file}" ]; then
        source_desktop="$(find_source_desktop "${desktop_name}" || true)"

        if [ -n "${source_desktop}" ]; then
            cp "${source_desktop}" "${desktop_file}"
        else
            cat >"${desktop_file}" <<EOF
[Desktop Entry]
Type=Application
Name=KDE Portal Backend
NoDisplay=true
Exec=${portal_kde_bin}
EOF
        fi
    fi

    if grep -q '^Exec=' "${desktop_file}"; then
        sed -i "s#^Exec=.*#Exec=${portal_kde_bin}#" "${desktop_file}"
    else
        printf 'Exec=%s\n' "${portal_kde_bin}" >>"${desktop_file}"
    fi

    if grep -q '^X-KDE-Wayland-Interfaces=' "${desktop_file}"; then
        current_interfaces="$(grep '^X-KDE-Wayland-Interfaces=' "${desktop_file}" | tail -n 1 | cut -d= -f2-)"
    else
        current_interfaces=""
    fi

    IFS=',' read -r -a required_interfaces <<<"${BDWIND_KDE_PORTAL_WAYLAND_INTERFACES}"
    for required_interface in "${required_interfaces[@]}"; do
        required_interface="$(printf '%s' "${required_interface}" | xargs)"
        if [ -z "${required_interface}" ]; then
            continue
        fi
        if ! printf ',%s,' "${current_interfaces}" | grep -Fq ",${required_interface},"; then
            if [ -n "${current_interfaces}" ]; then
                current_interfaces="${current_interfaces},${required_interface}"
            else
                current_interfaces="${required_interface}"
            fi
        fi
    done

    if grep -q '^X-KDE-Wayland-Interfaces=' "${desktop_file}"; then
        sed -i "s#^X-KDE-Wayland-Interfaces=.*#X-KDE-Wayland-Interfaces=${current_interfaces}#" "${desktop_file}"
    else
        printf 'X-KDE-Wayland-Interfaces=%s\n' "${current_interfaces}" >>"${desktop_file}"
    fi
}

for desktop_dir in "${desktop_dirs[@]}"; do
    ensure_desktop_file "${desktop_dir}" org.freedesktop.impl.portal.desktop.kde.desktop
    ensure_desktop_file "${desktop_dir}" xdg-desktop-portal-kde.desktop
done

if [ "${BDWIND_KDE_PORTAL_REFRESH_SYCOCA}" = "true" ] && command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/tmp/kbuildsycoca6.log 2>&1 || {
        echo "[kde6] kbuildsycoca6 failed; continuing with desktop file on disk" >&2
        tail -n 80 /tmp/kbuildsycoca6.log >&2 || true
    }
fi

for desktop_dir in "${desktop_dirs[@]}"; do
    for desktop_file in \
        "${desktop_dir}/org.freedesktop.impl.portal.desktop.kde.desktop" \
        "${desktop_dir}/xdg-desktop-portal-kde.desktop"
    do
        echo "[kde6] KDE portal desktop file=${desktop_file}"
        grep -E '^(Exec|X-KDE-Wayland-Interfaces)=' "${desktop_file}" || true
    done
done
