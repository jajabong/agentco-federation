#!/usr/bin/env bash
# gm_federation_push.sh - GM 邦联队列推送
# 用法: gm_federation_push.sh <task_id>
# 作用: 本地 kanban 卡 → 邦联 queue/pending/ (广播给其他节点)
# 出处: ADR-017 §4 邦联 dispatcher 协议
set -euo pipefail

FED_REPO="${FEDERATION_REPO:-jajabong/agentco-federation}"
WORKDIR="${FEDERATION_WORKDIR:-/tmp/agentco-federation-work}"
task_id="${1:?usage: gm_federation_push.sh <task_id>}"

cd "$WORKDIR"
git fetch origin main --quiet
git reset --hard origin/main --quiet

# 从本地 kanban.db 读卡 body → 生成 federation task JSON
# (最小演示: 假设卡已存在 federation-task JSON 缓存, 真实实现需 hermes kanban show)
payload_file="queue/pending/${task_id}.json"
if [ ! -e "$payload_file" ]; then
  echo "[federation-push] $task_id payload not staged, abort"
  exit 1
fi

# 校验 schema
python3 -c "
import json, jsonschema
schema = json.load(open('schemas/task.schema.json'))
data = json.load(open('$payload_file'))
jsonschema.validate(data, schema)
print('[federation-push] schema OK')
"

git add -A
git commit -m "federation: push $task_id by $(whoami) at $(date -u +%FT%TZ)" --quiet
git push origin main --quiet
echo "[federation-push] $task_id broadcasted to federation"
