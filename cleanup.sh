#!/usr/bin/env bash
# cleanup.sh - Remove the whole lab. Deleting a namespace also deletes its veth interfaces
# and iptables rules.
#
# Usage: sudo bash cleanup.sh

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run as root: sudo bash $0"
  exit 1
fi

for ns in router-hq client-hq router-branch client-branch; do
  if ip netns del "$ns" 2>/dev/null; then
    echo "[-] removed $ns"
  else
    echo "[ ] $ns not found (already clean)"
  fi
done

echo "[+] Lab removed."
