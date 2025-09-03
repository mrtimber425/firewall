#!/usr/bin/env bash
# Elastic Defend — Safe Lab Tester (Linux)
# Works on Ubuntu/Debian/Kali/Parrot. Run with:  chmod +x elastic_edr_lab.sh && bash ./elastic_edr_lab.sh

# Re-exec with bash if invoked via sh/dash
[ -z "${BASH_VERSION:-}" ] && exec bash "$0" "$@"

set -Eeuo pipefail
IFS=$'\n\t'

# ---------- styling ----------
PURPLE="\033[35m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; NC="\033[0m"
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*" >&2; }

is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

# ---------- helpers ----------
apt_install() {
  # Robust apt install with fallback if cache is full
  local pkgs=("$@")
  log "Installing packages: ${pkgs[*]}"
  sudo apt-get update -y
  if ! sudo apt-get install -y "${pkgs[@]}"; then
    warn "apt install failed, cleaning cache and retrying via /tmp…"
    sudo apt-get clean || true
    if ! sudo apt-get -o dir::cache::archives=/tmp install -y "${pkgs[@]}"; then
      err "apt install still failed. Install manually: sudo apt-get install -y ${pkgs[*]}"
      return 1
    fi
  fi
  return 0
}

ensure_service_running() {
  local svc1="$1" svc2="${2:-}"
  if systemctl list-unit-files | grep -q "^${svc1}\.service"; then
    sudo systemctl enable --now "$svc1" >/dev/null 2>&1 || true
  elif [[ -n "$svc2" ]] && systemctl list-unit-files | grep -q "^${svc2}\.service"; then
    sudo systemctl enable --now "$svc2" >/dev/null 2>&1 || true
  fi
}

kql_banner() {
  echo -e "\n${PURPLE}$1${NC}\n"
}

# ---------- tests ----------
file_test() {
  log "Running FILE create/delete test…"
  local target
  if is_root; then
    target="/etc/cron.d/edr_test"
    echo "# edr test $(date -u +%FT%TZ)" | tee "$target" >/dev/null
    sleep 2
    rm -f "$target"
  else
    target="/tmp/edr_test"
    echo "# edr test $(date -u +%FT%TZ)" > "$target"
    sleep 2
    rm -f "$target"
  fi
  log "Created and removed: $target"

  kql_banner 'KQL (Security → Explore → Events):
  event.dataset : "endpoint.events.file" and file.path : "'"$target"'"'
}

netproc_test() {
  log "Running PROCESS + NETWORK test with curl…"
  command -v curl >/dev/null 2>&1 || apt_install curl || { err "curl missing; aborting this test."; return; }
  curl -I https://example.com >/dev/null 2>&1 || true
  log "curl executed."

  kql_banner 'KQL (Security → Explore → Events):
  Process:
    host.name : "<your-host>" and event.dataset : "endpoint.events.process" and process.name : "curl"
  Network:
    host.name : "<your-host>" and event.dataset : "endpoint.events.network" and process.name : "curl"
  Tip: From a curl process event → … → Investigate in → Session view.'
}

ssh_fail_test() {
  log "Running SSH AUTH-FAIL test (12 rapid failures)…"
  # Packages
  local missing=()
  dpkg -s openssh-server >/dev/null 2>&1 || missing+=(openssh-server)
  command -v ssh >/dev/null 2>&1       || missing+=(openssh-client)
  command -v sshpass >/dev/null 2>&1   || missing+=(sshpass)
  if ((${#missing[@]})); then
    warn "Missing: ${missing[*]}"
    read -r -p "Install them now? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
      apt_install "${missing[@]}" || { err "Install failed."; return; }
    else
      err "Cannot run SSH test without: ${
