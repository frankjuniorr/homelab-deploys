#!/bin/bash
# proxmox-vm-metrics.sh
# Collects per-VM/LXC resource metrics from the Proxmox API (pvesh) and writes
# them in Prometheus textfile format so node_exporter can expose them via :9100.
#
# Run by proxmox-vm-metrics.timer every 30 seconds.
# Output: /var/lib/node_exporter/textfile/proxmox_guests.prom
#
# This file is NOT a log — it is a fixed-size snapshot overwritten on every run.
# Size is bounded: ~4KB for 9 guests (6 VMs + 3 LXCs) regardless of uptime.
#
# Requires: jq (installed by proxmox-node Ansible role), pvesh (Proxmox built-in)

set -euo pipefail

OUTFILE="/var/lib/node_exporter/textfile/proxmox_guests.prom"
TMPFILE="${OUTFILE}.$$"

emit() { printf '%s\n' "$@" >> "$TMPFILE"; }

trap 'rm -f "$TMPFILE"' EXIT

> "$TMPFILE"

emit '# HELP proxmox_guest_status Guest running state (1=running, 0=stopped/paused)'
emit '# TYPE proxmox_guest_status gauge'
emit '# HELP proxmox_guest_cpu_usage CPU usage ratio (0-1, relative to allocated CPUs)'
emit '# TYPE proxmox_guest_cpu_usage gauge'
emit '# HELP proxmox_guest_memory_used_bytes Memory currently in use (bytes)'
emit '# TYPE proxmox_guest_memory_used_bytes gauge'
emit '# HELP proxmox_guest_memory_max_bytes Total memory allocated to guest (bytes)'
emit '# TYPE proxmox_guest_memory_max_bytes gauge'
emit '# HELP proxmox_guest_netin_bytes_total Cumulative bytes received by guest'
emit '# TYPE proxmox_guest_netin_bytes_total counter'
emit '# HELP proxmox_guest_netout_bytes_total Cumulative bytes transmitted by guest'
emit '# TYPE proxmox_guest_netout_bytes_total counter'
emit '# HELP proxmox_guest_disk_read_bytes_total Cumulative bytes read from disk by guest'
emit '# TYPE proxmox_guest_disk_read_bytes_total counter'
emit '# HELP proxmox_guest_disk_write_bytes_total Cumulative bytes written to disk by guest'
emit '# TYPE proxmox_guest_disk_write_bytes_total counter'

collect_guest() {
  local vmid="$1" name="$2" type="$3"
  local json
  json=$(pvesh --noproxy get "/nodes/$(hostname)/${type}/${vmid}/status/current" --output-format json 2>/dev/null) || return 0

  local status cpu mem maxmem netin netout diskread diskwrite running
  status=$(printf '%s' "$json"    | jq -r '.status    // "stopped"')
  cpu=$(printf '%s' "$json"       | jq -r '.cpu       // 0')
  mem=$(printf '%s' "$json"       | jq -r '.mem       // 0')
  maxmem=$(printf '%s' "$json"    | jq -r '.maxmem    // 0')
  netin=$(printf '%s' "$json"     | jq -r '.netin     // 0')
  netout=$(printf '%s' "$json"    | jq -r '.netout    // 0')
  diskread=$(printf '%s' "$json"  | jq -r '.diskread  // 0')
  diskwrite=$(printf '%s' "$json" | jq -r '.diskwrite // 0')

  running=0
  [ "$status" = "running" ] && running=1

  local l="vmid=\"${vmid}\",name=\"${name}\",type=\"${type}\""
  emit "proxmox_guest_status{${l}} ${running}"
  emit "proxmox_guest_cpu_usage{${l}} ${cpu}"
  emit "proxmox_guest_memory_used_bytes{${l}} ${mem}"
  emit "proxmox_guest_memory_max_bytes{${l}} ${maxmem}"
  emit "proxmox_guest_netin_bytes_total{${l}} ${netin}"
  emit "proxmox_guest_netout_bytes_total{${l}} ${netout}"
  emit "proxmox_guest_disk_read_bytes_total{${l}} ${diskread}"
  emit "proxmox_guest_disk_write_bytes_total{${l}} ${diskwrite}"
}

NODE=$(hostname)

# Collect QEMU VM metrics
while IFS=$'\t' read -r vmid name; do
  collect_guest "$vmid" "$name" "qemu"
done < <(pvesh --noproxy get "/nodes/${NODE}/qemu" --output-format json 2>/dev/null \
  | jq -r '.[] | [.vmid, (.name // ("vm-" + (.vmid | tostring)))] | @tsv')

# Collect LXC container metrics
while IFS=$'\t' read -r vmid name; do
  collect_guest "$vmid" "$name" "lxc"
done < <(pvesh --noproxy get "/nodes/${NODE}/lxc" --output-format json 2>/dev/null \
  | jq -r '.[] | [.vmid, (.name // ("lxc-" + (.vmid | tostring)))] | @tsv')

# Atomic write — avoids node_exporter reading a partial file
mv "$TMPFILE" "$OUTFILE"
trap - EXIT
