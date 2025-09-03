cat > elastic_edr_lab.sh <<'BASH'
#!/usr/bin/env bash
# Elastic Defend — Safe Lab Tester (Linux)
# Usage: chmod +x elastic_edr_lab.sh && bash ./elastic_edr_lab.sh

[ -z "${BASH_VERSION:-}" ] && exec bash "$0" "$@"
set -Eeuo pipefail
IFS=$'\n\t'

# ---- styling & helpers ----
PURPLE="\033[35m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; NC="\033[0m"
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*" >&2; }
is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }

apt_install() {
  local pkgs=("$@")
  sudo apt-get update -y
  if ! sudo apt-get install -y "${pkgs[@]}"; then
    warn "apt failed; cleaning cache and retrying via /tmp…"
    sudo apt-get clean || true
    sudo apt-get -o dir::cache::archives=/tmp install -y "${pkgs[@]}"
  fi
}

ensure_service_running() {
  local svc1="$1" svc2="${2:-}"
  if systemctl list-unit-files | grep -q "^${svc1}\.service"; then
    sudo systemctl enable --now "$svc1" >/dev/null 2>&1 || true
  elif [ -n "$svc2" ] && systemctl list-unit-files | grep -q "^${svc2}\.service"; then
    sudo systemctl enable --now "$svc2" >/dev/null 2>&1 || true
  fi
}

# ---- tests ----
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
  echo -e "\n${PURPLE}KQL (Security → Explore → Events):${NC}
event.dataset : \"endpoint.events.file\" and file.path : \"$target\"\n"
}

netproc_test() {
  log "Running PROCESS + NETWORK test with curl…"
  command -v curl >/dev/null 2>&1 || apt_install curl
  curl -I https://example.com >/dev/null 2>&1 || true
  log "curl executed."
  echo -e "\n${PURPLE}KQL (Security → Explore → Events):${NC}
Process:
  host.name : \"<your-host>\" and event.dataset : \"endpoint.events.process\" and process.name : \"curl\"
Network:
  host.name : \"<your-host>\" and event.dataset : \"endpoint.events.network\" and process.name : \"curl\"
Tip: From a curl process event → … → Investigate in → Session view.\n"
}

ssh_fail_test() {
  log "Running SSH AUTH-FAIL test (12 rapid failures)…"
  local missing=()
  dpkg -s openssh-server >/dev/null 2>&1 || missing+=(openssh-server)
  command -v ssh       >/dev/null 2>&1 || missing+=(openssh-client)
  command -v sshpass   >/dev/null 2>&1 || missing+=(sshpass)
  if [ ${#missing[@]} -gt 0 ]; then
    warn "Missing: ${missing[*]}"
    read -r -p "Install them now? [y/N] " ans
    if [ "${ans,,}" = "y" ]; then
      apt_install "${missing[@]}"
    else
      err "Cannot run SSH test without: ${missing[*]}"; return
    fi
  fi

  ensure_service_running ssh sshd

  local user="${SUDO_USER:-$USER}" WRONG="not-the-password"
  for i in $(seq 1 12); do
    sshpass -p "$WRONG" ssh -o StrictHostKeyChecking=no \
      -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      -o ConnectTimeout=2 "$user"@localhost true 2>/dev/null || true
  done
  log "Generated 12 failed SSH password attempts to $user@localhost."

  echo -e "\n${PURPLE}KQL (Discover — requires System → Authentication logs in the policy):${NC}
data_stream.dataset : \"system.auth\" and message : \"Failed password\" and host.name : \"<your-host>\"

Optional alert:
  Enable prebuilt rule \"Potential Linux SSH Brute Force Detected\"
  OR make a Threshold rule:
    Query: data_stream.dataset:\"system.auth\" AND event.category:\"authentication\" AND event.outcome:\"failure\"
    Count ≥ 6, Group by: source.ip, user.name, Timeframe: 1 minute\n"
}

run_all() {
  file_test
  netproc_test
  ssh_fail_test
}

menu() {
  echo -e "${PURPLE}Elastic Defend — Safe Test Menu${NC}"
  echo "1) File modification test (create/delete)"
  echo "2) Process + network test (curl)"
  echo "3) Repeated SSH login failures (needs System/Auth integration)"
  echo "4) Run ALL tests"
  echo "5) Quit"
  echo
}

while true; do
  menu
  read -r -p "Choose an option [1-5]: " choice
  case "$choice" in
    1) file_test ;;
    2) netproc_test ;;
    3) ssh_fail_test ;;
    4) run_all ;;
    5) log "Done. Use the printed KQL in Kibana for screenshots."; exit 0 ;;
    *) warn "Invalid choice." ;;
  esac
done
BASH
