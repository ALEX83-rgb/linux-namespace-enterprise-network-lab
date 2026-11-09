#!/usr/bin/env bash
# firewall.sh - Apply the security policy on router-hq.
#
# Policy: HQ (192.168.1.0/24) may reach Branch (192.168.2.0/24).
#         Branch may NOT start connections to HQ (blocked and logged).
#
# Usage: sudo bash firewall.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run as root: sudo bash $0"
  exit 1
fi

if ! ip netns list | grep -q '^router-hq'; then
  echo "[!] router-hq not found. Run setup.sh first."
  exit 1
fi

IPT="ip netns exec router-hq iptables"

# Best effort: allow LOG target output from inside namespaces (may not exist on all kernels)
sysctl -qw net.netfilter.nf_log_all_netns=1 2>/dev/null || true

echo "[*] Flushing old FORWARD rules..."
$IPT -F FORWARD

echo "[*] Applying rules..."
# 1. Allow replies to connections that were already allowed (stateful)
$IPT -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# 2. Allow HQ -> Branch
$IPT -A FORWARD -s 192.168.1.0/24 -d 192.168.2.0/24 -j ACCEPT
# 3. Log new Branch -> HQ attempts
$IPT -A FORWARD -s 192.168.2.0/24 -d 192.168.1.0/24 -j LOG --log-prefix "BRANCH-TO-HQ-BLOCKED: "
# 4. Drop them
$IPT -A FORWARD -s 192.168.2.0/24 -d 192.168.1.0/24 -j DROP

echo
echo "[+] Current FORWARD rules:"
$IPT -L FORWARD -n -v --line-numbers
echo
echo "[+] Firewall applied. Next: sudo bash verify.sh"
