#!/usr/bin/env bash
# Install the dev build (ru.pdd.pdd_app.dev) on the Pixel over Wi-Fi without
# typing the address every time.
#
#   ./scripts/install_dev.sh              # find the phone, install, launch
#   ./scripts/install_dev.sh IP:PORT      # first time / after the port changed
#   ./scripts/install_dev.sh --build      # rebuild the ru dev APK first
#
# How it finds the phone, in order: an already connected device; mDNS
# (Wireless debugging on, same Wi-Fi as the Mac); the fixed port 5555 on the
# last known IP (enabled once via `adb tcpip 5555`, survives until the phone
# reboots); the last IP:PORT stored in .dev-device (git-ignored); finally a
# ~20 s scan of ports 30000-49999 on that IP (Wireless debugging picks a new
# random port every time it is switched on). The adb server is restarted
# first: one started inside a sandbox has no network at all.
# Only requirement on the phone: Wireless debugging ON, same Wi-Fi.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/flutter/bin:$HOME/Library/Android/sdk/platform-tools:$HOME/.local/android-env/sdk/platform-tools:$PATH"
if [[ -z "${JAVA_HOME:-}" || ! -d "$JAVA_HOME" ]]; then
  if [[ -d "/opt/homebrew/opt/openjdk@17" ]]; then
    export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
  elif [[ -d "$HOME/.local/android-env/jdk" ]]; then
    export JAVA_HOME="$HOME/.local/android-env/jdk"
  fi
fi
if [[ -z "${ANDROID_HOME:-}" && -d "$HOME/.local/android-env/sdk" ]]; then
  export ANDROID_HOME="$HOME/.local/android-env/sdk"
fi
APK=build/app/outputs/flutter-apk/app-ru-release.apk
PKG=ru.pdd.pdd_app.dev
STATE=.dev-device

build=0; addr=""
for arg in "$@"; do
  case "$arg" in
    --build) build=1 ;;
    *:*) addr="$arg" ;;
  esac
done

if [[ $build -eq 1 || ! -f $APK ]]; then
  # App key (secrets/, not in git) so rating, sync and AI work in the test build too.
  key_define=()
  [[ -f secrets/install_notify_secret.txt ]] && key_define=(--dart-define=INSTALL_NOTIFY_SECRET="$(cat secrets/install_notify_secret.txt)")
  # Dev builds get a date-hour build number (yyMMddHH) so a newer dev APK
  # always installs over an older one, whoever built it; the dev app is a
  # separate package (.dev), store versions are unaffected.
  # DEVICE_REGION=RU ./scripts/install_dev.sh --build — показать российский
  # пейволл (СБП + Google Play на выбор), когда телефон не в России.
  region_define=()
  [[ -n "${DEVICE_REGION:-}" ]] && region_define=(--dart-define=DEVICE_REGION="$DEVICE_REGION")
  flutter build apk --flavor ru --release --dart-define=COUNTRY=ru --dart-define=GAME_DEBUG=true "${key_define[@]}" ${region_define[@]+"${region_define[@]}"} -Pdev --build-number="$(date +%y%m%d%H)"
fi

connected() { adb devices | awk 'NR>1 && $2=="device" {print $1; exit}'; }
try_connect() { adb connect "$1" >/dev/null 2>&1 || true; sleep 1; connected; }
# Wireless debugging picks a new random port (30000-49999) every time it is
# switched on; the phone's IP stays. Find the open adb port by a quick scan.
scan_ports() {
  ulimit -n 4096 2>/dev/null || true
  python3 - "$1" <<'PY'
import asyncio, sys
ip = sys.argv[1]
async def probe(port, sem):
    async with sem:
        try:
            r, w = await asyncio.wait_for(asyncio.open_connection(ip, port), 0.8)
            w.close(); return port
        except Exception:
            return None
async def main():
    sem = asyncio.Semaphore(800)
    found = await asyncio.gather(*(probe(p, sem) for p in range(30000, 50000)))
    print(" ".join(str(p) for p in found if p))
asyncio.run(main())
PY
}

# The phone's IP changes with DHCP; its Wi-Fi MAC (stored in .dev-mac) does
# not. A quick ping sweep fills the ARP table, then the MAC gives the IP.
MACFILE=.dev-mac
find_ip_by_mac() {
  local mac=$1 subnet
  subnet=$(ipconfig getifaddr en0 2>/dev/null | cut -d. -f1-3)
  [[ -z $subnet ]] && return 0
  for i in $(seq 1 254); do ping -c 1 -W 300 "$subnet.$i" >/dev/null 2>&1 & done; wait
  arp -an | awk -v m="$mac" '{gsub(/[()]/,"",$2); if (tolower($4)==tolower(m)) {print $2; exit}}'
}
remember_mac() { local ip=$1; arp -n "$ip" 2>/dev/null | awk '{print $4; exit}' | grep -E '^([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}$' > "$MACFILE" || true; }

# An adb server started inside a sandbox has no network: always restart it.
adb kill-server >/dev/null 2>&1 || true
adb start-server >/dev/null 2>&1 || true

dev=$(connected || true)
if [[ -z $dev && -n $addr ]]; then dev=$(try_connect "$addr"); fi
if [[ -z $dev ]]; then
  for _ in 1 2 3; do
    m=$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect/ {print $3; exit}')
    [[ -n $m ]] && { dev=$(try_connect "$m"); break; }
    sleep 2
  done
fi
if [[ -z $dev && -f $STATE ]]; then
  ip=$(cut -d: -f1 "$STATE")
  if [[ -s $MACFILE ]]; then
    echo "Ищу телефон в сети по MAC $(cat "$MACFILE")…"
    found=$(find_ip_by_mac "$(cat "$MACFILE")")
    [[ -n $found ]] && ip=$found && echo "Телефон: $ip"
  fi
  dev=$(try_connect "$ip:5555")
  [[ -z $dev ]] && dev=$(try_connect "$(cat "$STATE")")
  if [[ -z $dev ]]; then
    echo "Ищу порт отладки на $ip…"
    for port in $(scan_ports "$ip"); do
      dev=$(try_connect "$ip:$port"); [[ -n $dev ]] && break
    done
  fi
fi
if [[ -z $dev ]]; then
  echo "Телефон не найден. Включите «Отладка по Wi‑Fi» (та же сеть, что и Mac)" >&2
  echo "или запустите: ./scripts/install_dev.sh IP:PORT (адрес с экрана телефона)" >&2
  exit 1
fi
echo "Устройство: $dev"
echo "$dev" > "$STATE"
remember_mac "${dev%%:*}"
# Fixed port: after this, `adb connect IP:5555` works without a new pairing
# code until the phone reboots.
# Only for an IP:PORT address: an mDNS name (adb-…._adb-tls-connect._tcp)
# would leave a dead «name:5555» entry that adb then confuses with the live one.
if [[ $dev != *:5555 && $dev =~ ^[0-9.]+: ]]; then
  ip=${dev%%:*}
  if adb -s "$dev" tcpip 5555 >/dev/null 2>&1; then
    sleep 3
    adb disconnect "$dev" >/dev/null 2>&1 || true
    adb connect "$ip:5555" >/dev/null 2>&1 || true
    sleep 1
    if adb devices | grep -q "^$ip:5555[[:space:]]*device"; then dev="$ip:5555"; echo "$dev" > "$STATE"; fi
  fi
fi
# Drop dead entries, then address the live one by its transport id: two
# entries may share a serial prefix and `adb -s` refuses to choose.
adb devices | awk 'NR>1 && $2=="offline" {print $1}' | while read -r gone; do adb disconnect "$gone" >/dev/null 2>&1 || true; done
tid=$(adb devices -l | awk -v d="$dev" '$1==d && $2=="device" {for (i=3;i<=NF;i++) if ($i ~ /^transport_id:/) {sub("transport_id:","",$i); print $i; exit}}')
[[ -z $tid ]] && tid=$(adb devices -l | awk '$2=="device" {for (i=3;i<=NF;i++) if ($i ~ /^transport_id:/) {sub("transport_id:","",$i); print $i; exit}}')
adb -t "$tid" install -r "$APK"
adb -t "$tid" shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && echo "Запущено на $dev"
