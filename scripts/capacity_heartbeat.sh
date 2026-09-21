#!/usr/bin/env bash
# capacity_heartbeat.sh - 节点容量心跳 (30s 一轮)
# 用法: 由 launchd/cron 周期触发
# 作用: 采集本节点 CPU/RAM/Disk/WIP → 更新 capacity/<node_id>.json → push 到邦联
# 出处: ADR-017 §5 + ADR-018 §4
set -euo pipefail

NODE_ID="${NODE_ID:-$(scutil --get ComputerName | tr '[:upper:]' '[:lower:]' | tr -d ' ')}"
WORKDIR="${FEDERATION_WORKDIR:-/tmp/agentco-federation-work}"
CAP_FILE="$WORKDIR/capacity/${NODE_ID}.json"

cd "$WORKDIR"

# 物理指标采集 (macOS specific; Linux 需替换)
mem_total_gb=$(sysctl -n hw.memsize | awk '{printf "%.1f", $1/1024/1024/1024}')
mem_used_gb=$(vm_stat | awk '/^Pages active/ {active=$3} /^Pages wired/ {wired=$4} /^Pages inactive/ {inact=$5} /^Pages free/ {free=$6} END {printf "%.1f", ((active+wired+inact)*4096)/1024/1024/1024}')
cpu_cores=$(sysctl -n hw.ncpu)
cpu_load=$(sysctl -n vm.loadavg | awk '{print $2}')
disk_free_gb=$(df -g / | awk 'NR==2 {print $4}')

# WIP 从 kanban 拉
wip=$(hermes kanban stats 2>/dev/null | awk '/running/ {print $2}' || echo 0)
wip_threshold=6
saturated=$( [ "$wip" -ge "$wip_threshold" ] && echo true || echo false )

# engines_available: henry-mac 当前 Tier 0 + Tier 3
engines='["tier0-readonly","tier3-commercial-jet"]'

cat > "$CAP_FILE" <<EOF
{
  "node_id": "$NODE_ID",
  "last_heartbeat": "$(date -u +%FT%TZ)",
  "physical": {
    "memory_total_gb": $mem_total_gb,
    "memory_used_gb": $mem_used_gb,
    "cpu_cores": $cpu_cores,
    "cpu_load_5min": $cpu_load,
    "disk_free_gb": $disk_free_gb
  },
  "engines_available": $engines,
  "wip": $wip,
  "wip_threshold": $wip_threshold,
  "saturated": $saturated,
  "federation_role": "origin_node_preferred"
}
EOF

# 校验 schema
python3 -c "
import json, jsonschema
schema = json.load(open('schemas/capacity.schema.json'))
data = json.load(open('$CAP_FILE'))
jsonschema.validate(data, schema)
"

git add "capacity/${NODE_ID}.json"
git commit -m "capacity: heartbeat ${NODE_ID} wip=${wip} sat=${saturated}" --quiet || true
git push origin main --quiet || true
