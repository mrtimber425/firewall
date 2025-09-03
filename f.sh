#!/usr/bin/env bash
set -euo pipefail

# Elastic Defend lab tester (Linux)
# Safe, reversible tests with a simple menu.

PURPLE="\033[35m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; NC="\033[0m"

log() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err() { echo -e "${RED}[-]${NC} $*" >&2; }

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
}

is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

kql_banner() {
  echo -e "\n${PURPLE}KQL to verify in Kibana → Security → Explore → Events:${NC}"
  echo -e "$1\n"
}

file_test() {
  log "Running file create/delete test..."
  local target
  if is_root; then
    target="/etc/cron.d/edr_test"
    echo "# edr test $(date -u +%FT%TZ)" | tee "${target}" >/dev/null
    sleep 2
    rm -f "${target}"
  else
    warn "Not running as root; using user-writable fallback in /tmp."
    target="/tmp/edr_test"
    echo "# edr test $(date -u +%FT%TZ)" > "${target}"
    sleep 2
    rm -f "${target}"
  fi
  log "Created then removed: ${target}"
  kql_banner "event.dataset : \"endpoint.events.file\" and file.path : \"${target}\""
}

netproc_test() {
  log "Running process + network test with curl..."
  if ! need_cmd curl; then
    err "curl not found. Install it (e.g., sudo apt-get update && sudo apt-get install -y curl) and rerun."
    return
  fi
  curl -I https://example.com >/dev/null 2>&1 || true
  log "curl executed."
  kql_banner $'Process events:\n  event.dataset : "endpoint.events.process" and process.name : "curl"\nNetwork events:\n  event.dataset : "endpoint.events.network" and process.name : "curl"'
}

ssh_fail_test() {
  log "Simulating repeated SSH login failures to localhost (6 attempts)..."

  # Check/offer to install requirements
  local need_install=()
  need_cmd ssh || need_install+=(openssh-client)
  # We want an SSH server to accept and reject passwords
  if ! systemctl list-unit-files | grep -q -E '^(ssh|sshd)\.service'; then
    need_install+=(openssh-server)
  fi
  need_cmd sshpass || need_install+=(sshpass)

  if (( ${#need_install[@]} )); then
    warn "Missing packages: ${need_install[*]}"
    read -r -p "Install them now with apt-get? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
      sudo apt-get update -y
      sudo apt-get install -y "${need_install[@]}"
    else
      err "Cannot proceed with SSH failure test without required packages."
      return
    fi
  fi

  # Ensure ssh service is running if present
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    sudo systemctl start ssh || true
  elif systemctl list-unit-files | grep -q '^sshd\.service'; then
    sudo systemctl start sshd || true
  fi

  local user="${SUDO_USER:-$USER}"
  warn "Using username '${user}' and a WRONG password to generate failures."
  local WRONG="definitely-wrong-password"

  for i in {1..6}; do
    sshpass -p "${WRONG}" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no -o ConnectTimeout=3 "${user}"@localhost true 2>/dev/null || true
    sleep 1
  done

  log "Generated failed SSH logins."
  echo -e "\n${PURPLE}If you enabled the System/Auth integration, check Discover with:${NC}"
  echo -e '  data_stream.dataset: "system.auth" and message: "Failed password"\n'
  echo -e "${PURPLE}If you enabled a brute-force rule, check Security → Alerts.${NC}\n"
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
  echo "3) Repeated SSH login failures (needs System/Auth + ssh/sshpass)"
  echo "4) Run ALL tests"
  echo "5) Quit"
  echo
}

while true; do
  menu
  read -r -p "Choose an option [1-5]: " choice
  case "${choice}" in
    1) file_test ;;
    2) netproc_test ;;
    3) ssh_fail_test ;;
    4) run_all ;;
    5) log "Done. Capture your Kibana screenshots for the assignment."; exit 0 ;;
    *) warn "Invalid choice."; ;;
  esac
done
