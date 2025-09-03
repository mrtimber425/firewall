#!/usr/bin/env python3
"""
Elastic Defend — Safe Lab Tester (Linux, Python)
Run: sudo python3 edr_lab.py
Tests:
  1) File create/delete  2) Process+Network (HTTPS)  3) SSH failed logins
"""

import os, sys, time, socket, ssl, urllib.request, shutil, subprocess, textwrap

PURPLE = "\033[35m"; GREEN = "\033[32m"; YELLOW = "\033[33m"; RED = "\033[31m"; NC = "\033[0m"
log  = lambda s: print(f"{GREEN}[+]{NC} {s}")
warn = lambda s: print(f"{YELLOW}[!]{NC} {s}")
err  = lambda s: print(f"{RED}[-]{NC} {s}", file=sys.stderr)

def run(cmd, check=False, capture=False):
    return subprocess.run(cmd, check=check, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT)

def which(bin_name): return shutil.which(bin_name) is not None
def is_root(): return os.geteuid() == 0

# ---------- apt helpers (robust, handles full cache) ----------
def apt_install(pkgs):
    if not is_root():
        err(f"Need root to install: {' '.join(pkgs)}. Re-run the script with sudo.")
        return False
    log(f"Installing packages: {' '.join(pkgs)}")
    r = run(["apt-get","update","-y"])
    r = run(["apt-get","install","-y", *pkgs])
    if r.returncode == 0: return True
    warn("apt install failed; cleaning cache and retrying via /tmp…")
    run(["apt-get","clean"])
    r = run(["apt-get","-o","dir::cache::archives=/tmp","install","-y", *pkgs])
    if r.returncode != 0:
        err("apt install still failed.")
        return False
    return True

def ensure_service_running(*svc_names):
    for svc in svc_names:
        # enable if present
        run(["systemctl","enable","--now",svc], check=False)

# ---------- Tests ----------
def test_file():
    log("FILE create/delete test…")
    target = "/etc/cron.d/edr_test" if is_root() else "/tmp/edr_test"
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(target, "w") as f: f.write(f"# edr test {ts}\n")
    time.sleep(2)
    os.remove(target)
    log(f"Created and removed: {target}")
    print_kql(textwrap.dedent(f"""
    KQL (Security → Explore → Events):
      event.dataset : "endpoint.events.file" and file.path : "{target}"
    """))

def test_proc_net():
    log("PROCESS + NETWORK test using Python HTTPS → example.com…")
    # Use urllib so the process is python3 (nice to show non-curl)
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen("https://example.com", context=ctx, timeout=6) as r:
            _ = r.read(128)  # touch the socket
        log("HTTPS request completed.")
    except Exception as e:
        warn(f"HTTPS request encountered: {e} (still fine for network visibility)")

    print_kql(textwrap.dedent("""
    KQL (Security → Explore → Events):
      Process:
        host.name : "<your-host>" and event.dataset : "endpoint.events.process" and process.name : "python3"
      Network (if not present, also try process.name : "python*"):
        host.name : "<your-host>" and event.dataset : "endpoint.events.network" and process.name : "python3"
    Tip: From a python3 process event → … → Investigate in → Session view.
    """))

def test_ssh_fail():
    log("SSH AUTH-FAIL test (12 rapid wrong passwords to localhost)…")
    missing = []
    if not which("ssh"):     missing.append("openssh-client")
    # Need server to accept/reject passwords
    # The package is 'openssh-server'; service name is usually 'ssh'
    out = run(["dpkg","-s","openssh-server"], capture=True)
    if out.returncode != 0:  missing.append("openssh-server")
    if not which("sshpass"): missing.append("sshpass")

    if missing:
        warn(f"Missing: {' '.join(missing)}")
        ans = input("Install them now with apt-get? [y/N] ").strip().lower()
        if ans == "y":
            if not apt_install(missing): return
        else:
            err("Cannot run SSH test without required packages."); return

    ensure_service_running("ssh", "sshd")

    user = os.environ.get("SUDO_USER") or os.environ.get("USER") or "user"
    wrong = "not-the-password"
    for i in range(12):
        run([
            "sshpass","-p",wrong,"ssh",
            "-o","StrictHostKeyChecking=no",
            "-o","PreferredAuthentications=password",
            "-o","PubkeyAuthentication=no",
            "-o","ConnectTimeout=2",
            f"{user}@localhost","true"
        ], check=False)
        time.sleep(0.2)
    log(f"Generated 12 failed SSH password attempts to {user}@localhost.")

    print_kql(textwrap.dedent("""
    KQL (Discover — requires System → Authentication logs enabled on the policy):
      data_stream.dataset : "system.auth" and message : "Failed password" and host.name : "<your-host>"

    Optional alert:
      Enable prebuilt rule "Potential Linux SSH Brute Force Detected"
      OR create a Threshold rule:
        Query: data_stream.dataset:"system.auth" AND event.category:"authentication" AND event.outcome:"failure"
        Count ≥ 6, Group by: source.ip, user.name, Timeframe: 1 minute
    """))

def print_kql(s): print(PURPLE + s.strip() + NC + "\n")

# ---------- Menu ----------
def menu():
    print(PURPLE + "Elastic Defend — Safe Test Menu (Python)" + NC)
    print("1) File modification test (create/delete)")
    print("2) Process + network test (HTTPS via python3)")
    print("3) Repeated SSH login failures (needs System/Auth integration)")
    print("4) Run ALL tests")
    print("5) Quit\n")

def main():
    while True:
        menu()
        choice = input("Choose an option [1-5]: ").strip()
        if choice == "1": test_file()
        elif choice == "2": test_proc_net()
        elif choice == "3": test_ssh_fail()
        elif choice == "4": test_file(); test_proc_net(); test_ssh_fail()
        elif choice == "5": log("Done. Use the printed KQL in Kibana for screenshots."); return
        else: warn("Invalid choice.")

if __name__ == "__main__":
    main()
