#!/usr/bin/env bash
# gm_federation_pull.sh - GM 邦联队列拉取
# 用法: gm_federation_pull.sh [--since TAG]
# 作用: 拉取 jajabong/agentco-federation queue/pending/ → 本地 kanban.db (作为外部卡)
# 出处: ADR-017 §4 邦联 dispatcher 协议
set -euo pipefail

FED_REPO="${FEDERATION_REPO:-jajabong/agentco-federation}"
LOCAL_DB="${KANBAN_DB:-$HOME/agentco-master/os/kanban.db}"
WORKDIR="${FEDERATION_WORKDIR:-/tmp/agentco-federation-work}"

cd "$WORKDIR"
git fetch origin main --quiet
git reset --hard origin/main --quiet

# 拉取 queue/pending/*.json
for f in queue/pending/*.json; do
  [ -e "$f" ] || continue
  task_id=$(jq -r '.task_id' "$f")
  origin=$(jq -r '.origin_node' "$f")
  echo "[federation-pull] Ingesting $task_id from $origin"
  # 委派: GM 决策是否接单 (capacity match + privacy 检查)
  # 这里只做最小演示, 真实逻辑由 hermes kanban CLI 承担
  if hermes kanban show "$task_id" >/dev/null 2>&1; then
    echo "[federation-pull] $task_id already exists locally, skip"
    continue
  fi
  # 移到 queue/running (本地接单)
  mv "$f" queue/running/
  echo "[federation-pull] $task_id moved to queue/running (GM claim)"
done

git add -A
git commit -m "federation: pull round $(date -u +%FT%TZ)" --quiet || true
git push origin main --quiet
