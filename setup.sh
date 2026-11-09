#!/usr/bin/env bash
# setup.sh - Build the HQ <-> Branch enterprise network using Linux network namespaces.
#
# Topology:
#   [client-hq]--[router-hq]==WAN 10.0.0.0/30==[router-branch]--[client-branch]
#   192.168.1.10  .1    10.0.0.1          10.0.0.2    .1      192.168.2.10
#
# Usage: sudo bash setup.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run as root: sudo bash $0"
  exit 1
fi

NAMESPACES=(router-hq client-hq router-branch client-branch)

echo "[*] Removing any old lab..."
for ns in "${NAMESPACES[@]}"; do
  ip netns del "$ns" 2>/dev/null || true
done

echo "[1/5] Creating namespaces..."
for ns in "${NAMESPACES[@]}"; do
  ip netns add "$ns"
done

echo "[2/5] Creating virtual cables (veth pairs)..."
# Client HQ <-> Router HQ
ip link add veth-c-hq type veth peer name veth-r-hq
ip link set veth-c-hq netns client-hq
ip link set veth-r-hq netns router-hq

# Router HQ <-> Router Branch (WAN)
ip link add veth-hq-wan type veth peer name veth-branch-wan
ip link set veth-hq-wan netns router-hq
ip link set veth-branch-wan netns router-branch

# Client Branch <-> Router Branch
ip link add veth-c-branch type veth peer name veth-r-branch
ip link set veth-c-branch netns client-branch
ip link set veth-r-branch netns router-branch

echo "[3/5] Assigning IP addresses and bringing interfaces up..."
# HQ LAN: 192.168.1.0/24
ip netns exec client-hq ip addr add 192.168.1.10/24 dev veth-c-hq
ip netns exec client-hq ip link set veth-c-hq up
ip netns exec client-hq ip link set lo up
ip netns exec router-hq ip addr add 192.168.1.1/24 dev veth-r-hq
ip netns exec router-hq ip link set veth-r-hq up
ip netns exec router-hq ip link set lo up

# WAN link: 10.0.0.0/30
ip netns exec router-hq ip addr add 10.0.0.1/30 dev veth-hq-wan
ip netns exec router-hq ip link set veth-hq-wan up
ip netns exec router-branch ip addr add 10.0.0.2/30 dev veth-branch-wan
ip netns exec router-branch ip link set veth-branch-wan up
ip netns exec router-branch ip link set lo up

# Branch LAN: 192.168.2.0/24
ip netns exec client-branch ip addr add 192.168.2.10/24 dev veth-c-branch
ip netns exec client-branch ip link set veth-c-branch up
ip netns exec client-branch ip link set lo up
ip netns exec router-branch ip addr add 192.168.2.1/24 dev veth-r-branch
ip netns exec router-branch ip link set veth-r-branch up

echo "[4/5] Enabling IP forwarding on routers..."
ip netns exec router-hq sysctl -qw net.ipv4.ip_forward=1
ip netns exec router-branch sysctl -qw net.ipv4.ip_forward=1

echo "[5/5] Adding routes..."
# Clients send everything to their router
ip netns exec client-hq ip route add default via 192.168.1.1
ip netns exec client-branch ip route add default via 192.168.2.1
# Routers learn each other's LAN
ip netns exec router-hq ip route add 192.168.2.0/24 via 10.0.0.2
ip netns exec router-branch ip route add 192.168.1.0/24 via 10.0.0.1

echo
echo "[+] Network built. Quick connectivity test (no firewall yet):"
ip netns exec client-hq ping -c 2 -W 2 192.168.2.10
echo
echo "[+] Done. Next: sudo bash firewall.sh   then   sudo bash verify.sh"
