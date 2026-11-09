#!/usr/bin/env bash
# verify.sh - Run all checks and print PASS/FAIL. Screenshot this output as evidence.
#
# Usage: sudo bash verify.sh

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run as root: sudo bash $0"
  exit 1
fi

PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf "  [PASS] %s\n" "$desc"; PASS=$((PASS+1))
  else
    printf "  [FAIL] %s\n" "$desc"; FAIL=$((FAIL+1))
  fi
}

# Same as check, but success means the command FAILS (used for blocked traffic)
check_blocked() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf "  [FAIL] %s\n" "$desc"; FAIL=$((FAIL+1))
  else
    printf "  [PASS] %s\n" "$desc"; PASS=$((PASS+1))
  fi
}

NS="ip netns exec"

echo "=== 1. Namespaces ==="
for ns in router-hq client-hq router-branch client-branch; do
  check "namespace $ns exists" bash -c "ip netns list | grep -q '^$ns'"
done

echo
echo "=== 2. IP forwarding on routers ==="
check "router-hq ip_forward = 1"     bash -c "$NS router-hq sysctl -n net.ipv4.ip_forward | grep -q 1"
check "router-branch ip_forward = 1" bash -c "$NS router-branch sysctl -n net.ipv4.ip_forward | grep -q 1"

echo
echo "=== 3. Routing tables ==="
check "client-hq default via 192.168.1.1"      bash -c "$NS client-hq ip route | grep -q 'default via 192.168.1.1'"
check "client-branch default via 192.168.2.1"  bash -c "$NS client-branch ip route | grep -q 'default via 192.168.2.1'"
check "router-hq route to 192.168.2.0/24"      bash -c "$NS router-hq ip route | grep -q '192.168.2.0/24 via 10.0.0.2'"
check "router-branch route to 192.168.1.0/24"  bash -c "$NS router-branch ip route | grep -q '192.168.1.0/24 via 10.0.0.1'"

echo
echo "=== 4. Directly connected links ==="
check "client-hq -> router-hq (192.168.1.1)"        $NS client-hq ping -c 1 -W 2 192.168.1.1
check "router-hq -> router-branch (10.0.0.2)"       $NS router-hq ping -c 1 -W 2 10.0.0.2
check "client-branch -> router-branch (192.168.2.1)" $NS client-branch ping -c 1 -W 2 192.168.2.1

echo
echo "=== 5. Firewall policy ==="
check         "HQ -> Branch is ALLOWED (192.168.1.10 -> 192.168.2.10)" $NS client-hq ping -c 2 -W 2 192.168.2.10
check_blocked "Branch -> HQ is BLOCKED (192.168.2.10 -> 192.168.1.10)" $NS client-branch ping -c 2 -W 2 192.168.1.10

DROPPED=$($NS router-hq iptables -L FORWARD -n -v -x 2>/dev/null | awk '$3=="DROP" {print $1}')
if [[ -n "$DROPPED" && "$DROPPED" -gt 0 ]]; then
  printf "  [PASS] DROP rule packet counter = %s (> 0)\n" "$DROPPED"; PASS=$((PASS+1))
else
  printf "  [FAIL] DROP rule packet counter is 0 or rule missing\n"; FAIL=$((FAIL+1))
fi

echo
echo "=== 6. Traceroute HQ -> Branch (expect 2 router hops) ==="
$NS client-hq traceroute -n 192.168.2.10 2>/dev/null || echo "(traceroute not installed: sudo apt install traceroute)"

echo
echo "=== 7. Firewall rules and counters ==="
$NS router-hq iptables -L FORWARD -n -v --line-numbers

echo
echo "=== 8. Firewall log (may be empty on nf_tables systems) ==="
dmesg 2>/dev/null | grep BRANCH-TO-HQ | tail -5 || true
echo "(if empty, namespace logging is unavailable; counters above are the proof)"

echo
echo "==============================="
echo " RESULT: $PASS passed, $FAIL failed"
echo "==============================="
[[ $FAIL -eq 0 ]]
