# shellcheck shell=sh
# Installer preamble: asks the questions, then sets the variables bsdinstall's
# script mode reads to partition and extract.
#
# No shebang on purpose. `bsdinstall script` splits installerconfig at the
# first "#!" line: everything above it is sourced here, in the installer, before
# the disk is touched; everything below runs chrooted into the new system.
# build-image.sh puts deploy.conf above this and installer/setup.sh below.
#
# This is sourced under `set -e` with an EXIT trap that reports failure, so a
# cancelled dialog just ends the install with an error screen.

BACKTITLE="FreeBSD deploy installer"

exec 3>&1
# bsddialog writes the answer to stderr; swap so $(...) captures it
ask() {
    bsddialog --backtitle "$BACKTITLE" "$@" 2>&1 1>&3
}

# ---------------------------------------------------------------------------
# Deploy, or fall back to the stock installer / a shell
# ---------------------------------------------------------------------------
choice="$(ask --title "Install mode" --menu \
    "This stick installs the standard deployed system.\n\nIt will ERASE the disk you pick." 0 0 0 \
    deploy "Standard deployed install" \
    manual "Stock FreeBSD installer (interactive)" \
    shell  "Drop to a shell")"
case "$choice" in
    manual) BSDINSTALL_CONFIGCURRENT=yes; export BSDINSTALL_CONFIGCURRENT; exec bsdinstall ;;
    shell)  exec /bin/sh ;;
esac

# ---------------------------------------------------------------------------
# Hostname
# ---------------------------------------------------------------------------
DEPLOY_HOSTNAME="$DEFAULT_HOSTNAME"
while :; do
    DEPLOY_HOSTNAME="$(ask --title "Hostname" --inputbox \
        "System name (letters, digits, hyphens):" 0 50 "$DEPLOY_HOSTNAME")"
    if echo "$DEPLOY_HOSTNAME" | grep -qE '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'; then
        break
    fi
    ask --title "Hostname" --msgbox "\"$DEPLOY_HOSTNAME\" isn't a valid hostname." 0 0
done

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
# Typical shop-floor box: Wi-Fi to the company network (DHCP, the way out), and
# wired ports on separate local LANs with static IPs that devices are set up to
# expect. Answers are only collected here; they're written to
# $BSDINSTALL_TMPETC after the final confirmation, and `bsdinstall config`
# copies them into the new /etc.
NET_RC=""
NET_SUMMARY=""
WPA_CONF=""
RESOLV_CONF=""
HAVE_DHCP=""

rc_add() {
    NET_RC="$NET_RC$1
"
}
summary_add() {
    NET_SUMMARY="$NET_SUMMARY$1\n"
}

valid_cidr() {
    echo "$1" | grep -qE '^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])/([1-9]|[12][0-9]|3[0-2])$'
}
valid_ipv4() {
    valid_cidr "$1/32"
}

# Prints "DHCP" or "inet a.b.c.d/nn" for $1 (an interface name)
ask_addressing() {
    how="$(ask --title "$1 addressing" --menu "How does $1 get its address?" 0 0 0 \
        static "Static IP (local LAN)" \
        dhcp   "DHCP")"
    if [ "$how" = "dhcp" ]; then
        echo "SYNCDHCP"
        return
    fi
    addr=""
    while :; do
        addr="$(ask --title "$1 static IP" --inputbox \
            "IPv4 address with prefix length, e.g. 192.168.10.5/24:" 0 60 "$addr")"
        valid_cidr "$addr" && break
        ask --title "$1 static IP" --msgbox "\"$addr\" isn't an address/prefix like 192.168.10.5/24." 0 0
    done
    echo "inet $addr"
}

# Reads a value that wpa_supplicant.conf will hold in double quotes
ask_quoted() {
    while :; do
        value="$(ask "$@")"
        case "$value" in
            *\"*) ask --msgbox "Double quotes (\") aren't supported here." 0 0 ;;
            "")   ask --msgbox "This can't be empty." 0 0 ;;
            *)    echo "$value"; return ;;
        esac
    done
}

# --- Wi-Fi ---------------------------------------------------------------
WLAN_DEVS="$(sysctl -n net.wlan.devices 2>/dev/null)"
if [ -n "$WLAN_DEVS" ]; then
    wifi_mode="$(ask --title "Wi-Fi" --menu "How should Wi-Fi be set up?" 0 0 0 \
        psk  "WPA2/WPA3 Personal (shared password)" \
        eap  "WPA2 Enterprise (username + password, PEAP)" \
        open "Open network (no password)" \
        none "No Wi-Fi")"
else
    wifi_mode="none"
fi

if [ "$wifi_mode" != "none" ]; then
    set --
    for dev in $WLAN_DEVS; do
        set -- "$@" "$dev" "$(sysctl -n "dev.$(echo "$dev" | sed -E 's/([a-z]+)([0-9]+)/\1.\2/').%desc" 2>/dev/null)"
    done
    if [ $# -gt 2 ]; then
        wlan_dev="$(ask --title "Wi-Fi" --menu "Which Wi-Fi adapter?" 0 0 0 "$@")"
    else
        wlan_dev="$1"
    fi

    # Scanning needs the adapter's firmware in the installer; when that's
    # missing, fall back to typing the network name.
    set --
    if ifconfig wlan0 create wlandev "$wlan_dev" >/dev/null 2>&1 \
        && ifconfig wlan0 up >/dev/null 2>&1; then
        ask --title "Wi-Fi" --infobox "Scanning for networks..." 0 0
        sleep 5
        # SSIDs are printed in a fixed 33-column field, so cut rather than
        # split; spaces ride through the loop as \001, and -f keeps a "*" in a
        # network name from globbing.
        set -f
        for net in $(ifconfig wlan0 list scan 2>/dev/null | sed 1d | cut -c1-33 \
            | sed 's/ *$//' | grep . | sort -u | tr ' ' '\001'); do
            set -- "$@" "$(echo "$net" | tr '\001' ' ')" ""
        done
        set +f
    fi
    set -- "$@" "<other>" "Type the network name"
    ssid="$(ask --title "Wi-Fi network" --menu "Which network?" 0 0 0 "$@")"
    if [ "$ssid" = "<other>" ]; then
        ssid="$(ask_quoted --title "Wi-Fi network" --inputbox "Network name (SSID):" 0 50)"
    fi

    WPA_CONF="ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=wheel

network={
	ssid=\"$ssid\"
	scan_ssid=1"
    case "$wifi_mode" in
        psk)
            while :; do
                psk="$(ask_quoted --title "Wi-Fi password" --insecure --passwordbox \
                    "Password for $ssid:" 0 50)"
                [ ${#psk} -ge 8 ] && [ ${#psk} -le 63 ] && break
                ask --msgbox "WPA passwords are 8 to 63 characters." 0 0
            done
            WPA_CONF="$WPA_CONF
	psk=\"$psk\""
            ;;
        eap)
            eap_user="$(ask_quoted --title "Wi-Fi login" --inputbox "Username for $ssid:" 0 50)"
            eap_pass="$(ask_quoted --title "Wi-Fi login" --insecure --passwordbox \
                "Password for $eap_user:" 0 50)"
            # No ca_cert yet, so the RADIUS server isn't verified (openItems.md)
            WPA_CONF="$WPA_CONF
	key_mgmt=WPA-EAP
	eap=PEAP
	identity=\"$eap_user\"
	password=\"$eap_pass\"
	phase2=\"auth=MSCHAPV2\""
            ;;
        open)
            WPA_CONF="$WPA_CONF
	key_mgmt=NONE"
            ;;
    esac
    WPA_CONF="$WPA_CONF
}"

    wifi_addr="$(ask_addressing "Wi-Fi ($ssid)")"
    rc_add "wlans_$wlan_dev=\"wlan0\""
    rc_add "ifconfig_wlan0=\"WPA $wifi_addr\""
    [ "$wifi_addr" = "SYNCDHCP" ] && HAVE_DHCP=yes
    summary_add "Wi-Fi:    $ssid ($wifi_mode), ${wifi_addr#inet }"
fi

# --- Wired ports ---------------------------------------------------------
# Bring every port up so the menu can show which ones have a cable in.
WIRED=""
for nic in $(ifconfig -l ether); do
    case "$nic" in wlan*) continue ;; esac
    ifconfig "$nic" up >/dev/null 2>&1 || true
    WIRED="$WIRED $nic"
done
[ -n "$WIRED" ] && sleep 3

for nic in $WIRED; do
    mac="$(ifconfig "$nic" | awk '/ether/ {print $2}')"
    link="$(ifconfig "$nic" | awk '/status:/ {$1=""; print substr($0, 2)}')"
    descr="$(sysctl -n "dev.$(echo "$nic" | sed -E 's/([a-z]+)([0-9]+)/\1.\2/').%desc" 2>/dev/null)"
    use="$(ask --title "Wired port $nic" --menu \
        "$nic: ${descr:-ethernet}\nMAC $mac, link: ${link:-unknown}\n\nSet up this port?" 0 0 0 \
        yes "Configure it" \
        no  "Leave it unused")"
    [ "$use" = "yes" ] || continue
    nic_addr="$(ask_addressing "$nic")"
    rc_add "ifconfig_$nic=\"$nic_addr\""
    [ "$nic_addr" = "SYNCDHCP" ] && HAVE_DHCP=yes
    summary_add "$nic:     ${nic_addr#inet }"
done

# --- Way out, when nothing hands one out ---------------------------------
# With DHCP anywhere, that supplies the gateway and DNS. Static-only boxes are
# asked; both stay blank for a box that only talks to its local LANs.
if [ -n "$NET_RC" ] && [ -z "$HAVE_DHCP" ]; then
    while :; do
        gw="$(ask --title "Default gateway" --inputbox \
            "Default gateway (blank for none: local LANs only):" 0 60 "${gw:-}")"
        [ -z "$gw" ] || valid_ipv4 "$gw" && break
        ask --msgbox "\"$gw\" isn't an IPv4 address." 0 0
    done
    if [ -n "$gw" ]; then
        rc_add "defaultrouter=\"$gw\""
        summary_add "Gateway:  $gw"
        dns="$(ask --title "DNS" --inputbox "DNS servers (space separated):" 0 60)"
        for ns in $dns; do
            valid_ipv4 "$ns" && RESOLV_CONF="${RESOLV_CONF}nameserver $ns
"
        done
        summary_add "DNS:      ${dns:-none}"
    fi
fi
[ -n "$NET_RC" ] || summary_add "Network:  none chosen; DHCP on every port"

# ---------------------------------------------------------------------------
# Target disk
# ---------------------------------------------------------------------------
# The stick itself carries the ufs/FreeBSD_Install label; leave it off the list
# so it can't be picked (da0s2a -> da0).
install_disk="$(glabel status -s 2>/dev/null \
    | awk '$1 ~ /FreeBSD_Install/ {print $3}' \
    | sed -E 's/(s[0-9]+[a-h]?|p[0-9]+)$//')"

set --
for d in $(sysctl -n kern.disks); do
    case "$d" in cd*|"$install_disk") continue ;; esac
    size="$(diskinfo "$d" | awk '{printf "%.0f GB", $3 / 1000000000}')"
    descr="$(geom disk list "$d" | sed -n 's/^ *descr: //p' | head -1)"
    set -- "$@" "$d" "$size  ${descr:-unknown}"
done
if [ $# -eq 0 ]; then
    ask --title "No disks" --msgbox "No installable disk found (the USB stick is excluded)." 0 0
    exit 1
fi

DEPLOY_DISK="$(ask --title "Target disk" --menu "Install to which disk?" 0 0 0 "$@")"

ask --title "Last chance" --defaultno --yesno \
    "Hostname: $DEPLOY_HOSTNAME\n${NET_SUMMARY}Disk:     $DEPLOY_DISK ($FS_TYPE)\n\nEVERYTHING on $DEPLOY_DISK will be destroyed.\n\nContinue?" 0 0

# `bsdinstall config` merges rc.conf.* into the new rc.conf and copies the rest
# of this directory into the new /etc. An empty rc.conf.net leaves setup.sh to
# fall back to DHCP everywhere.
printf '%s' "$NET_RC" > "$BSDINSTALL_TMPETC/rc.conf.net"
if [ -n "$WPA_CONF" ]; then
    (umask 077; printf '%s\n' "$WPA_CONF" > "$BSDINSTALL_TMPETC/wpa_supplicant.conf")
fi
if [ -n "$RESOLV_CONF" ]; then
    printf '%s' "$RESOLV_CONF" > "$BSDINSTALL_TMPETC/resolv.conf"
fi

# ---------------------------------------------------------------------------
# What bsdinstall script reads
# ---------------------------------------------------------------------------
# Exported because zfsboot runs as a child process, and the setup half runs in
# a chroot that inherits this environment.
export nonInteractive="YES"
export DEPLOY_HOSTNAME

# pkgbase from the stick's offline base repo. DISTRIBUTIONS must stay unset:
# that's what selects pkgbase over the old tarballs. "base" alone skips the
# defaults' 600 MB debug kernel; minimal, kernel and pkg are always added.
export BSDINSTALL_PKG_REPOS_DIR="/usr/freebsd-packages/repos/"
export COMPONENTS="base"

# setup.sh installs packages.txt and firmware from the stick's "deploy" repo,
# but runs chrooted where the stick isn't visible, so the repo is nullfs-mounted
# into the new system for it. `bsdinstall script` has no hook between "config"
# (the last step before the chroot) and the chroot, so this wraps its
# bsdinstall calls: this file is sourced into that script, and a shell
# function wins over the command of the same name.
DEPLOY_REPO_SRC="/usr/freebsd-packages/deploy"
export DEPLOY_REPO_MNT="/tmp/deploy-repo"
bsdinstall() {
    # entropy runs right after the chroot step and before umount
    if [ "$1" = "entropy" ]; then
        umount "$BSDINSTALL_CHROOT$DEPLOY_REPO_MNT" 2>/dev/null || true
    fi
    command bsdinstall "$@" || return
    if [ "$1" = "config" ] && [ -d "$DEPLOY_REPO_SRC" ]; then
        mkdir -p "$BSDINSTALL_CHROOT$DEPLOY_REPO_MNT"
        mount_nullfs -o ro "$DEPLOY_REPO_SRC" "$BSDINSTALL_CHROOT$DEPLOY_REPO_MNT"
    fi
}

if [ "$FS_TYPE" = "ufs" ]; then
    # Swap first: "auto" takes everything left, so nothing can follow it
    PARTITIONS="$DEPLOY_DISK GPT { $SWAP_SIZE freebsd-swap, auto freebsd-ufs / }"
else
    export ZFSBOOT_DISKS="$DEPLOY_DISK"
    export ZFSBOOT_VDEV_TYPE="stripe"
    export ZFSBOOT_PARTITION_SCHEME="GPT"
    # Both, so the same disk boots whichever way the next box's firmware is set
    export ZFSBOOT_BOOT_TYPE="BIOS+UEFI"
    export ZFSBOOT_SWAP_SIZE="$SWAP_SIZE"
    export ZFSBOOT_POOL_NAME="zroot"
fi
