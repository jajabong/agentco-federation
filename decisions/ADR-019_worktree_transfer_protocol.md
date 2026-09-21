# ADR-019: 邦联 Worktree 流转协议 (Worktree Transfer Protocol)

- **状态**: Accepted
- **签署人**: 集团总工程师 (Chief Engineer)
- **签署日期**: 2026-09-21
- **父 ADR**: ADR-017 邦联协同协议
- **适用范围**: 邦联跨节点任务单元的 git 操作规范

---

## 〇、 核心原则

**任务单元 = Git Worktree 单实例**

每个邦联任务对应一个独立 worktree 分支 (`wt/t_HASH_X`)。
跨节点流转通过 `git push/pull` 完成，**不打 tarball，不上传制品附件**。

---

## 一、 Worktree 生命周期

```
[Origin Node A]
   ↓ git worktree add -b wt/t_HASH_X worktrees/t_HASH_X
[Worktree 在 A 节点]
   ↓ worker 编码 + git commit
[Worktree 内容物: 完整代码 + 任务契约 + 验收标准]
   ↓ git push origin wt/t_HASH_X
[远端仓 (GitHub) 持有 branch wt/t_HASH_X]
   ↓
[Receiver Node B: git fetch + git worktree add]
[Worktree 在 B 节点]
   ↓ worker 接管 + 编码 + commit --amend
[Worktree 内容物: B 节点修订]
   ↓ git push origin wt/t_HASH_X
[远端仓更新 branch wt/t_HASH_X]
   ↓
[Origin Node A: git pull]
[A 节点 worktree 更新为 B 节点最终版]
   ↓ verifier 通过 → done
[Worktree merge 到 main + cleanup]
```

---

## 二、 完整操作规范

### 2.1 Origin Node: 派单 + 创建 Worktree

```bash
# 1. GM 决定将任务外溢到邦联
hermes kanban show t_HASH_X
# → output: capacity_required.engine_tier=tier1-local-nuclear

# 2. 检查本地饱和度
hermes_capacity_check
# → saturated = true, can_overflow

# 3. 创建 Worktree
cd ~/wrk/<node>/agentco
git worktree add -b wt/t_HASH_X worktrees/t_HASH_X
cd worktrees/t_HASH_X

# 4. 准备任务契约
mkdir -p .federation
cat > .federation/task.json <<EOF
{
  "task_id": "t_HASH_X",
  "title": "...",
  ...
}
EOF

# 5. 提交并推送
git add .federation/task.json
git commit -m "feat(t_HASH_X): initial federation task contract"
git push origin wt/t_HASH_X

# 6. 登记邦联队列 (公开 metadata)
cd ~/wrk/<node>/agentco-federation
cp <prepared-json> queue/pending/2026-09/t_HASH_X.json
git add queue/pending/2026-09/t_HASH_X.json
git commit -m "federation: enqueue t_HASH_X (tier1-local-nuclear)"
git push origin

# 7. 本地看板标记 (不丢任务)
hermes kanban comment t_HASH_X \
  --text "federation: out → agentco-federation/queue/pending/2026-09/t_HASH_X.json"
```

### 2.2 Receiver Node: 拉取 + 接管

```bash
# 1. GM 轮询邦联队列
cd ~/wrk/<node>/agentco-federation
git pull
# 检查 queue/pending/* 新任务

# 2. 评估任务能力匹配
cat queue/pending/2026-09/t_HASH_X.json | jq '.engine_tier, .capacity_required'
# 比对本地 capacity.json: engines_available

# 3. 适合 → 原子 claim
mkdir -p queue/claim-locks/2026-09
touch queue/claim-locks/2026-09/t_HASH_X.lock  # 抢占锁
git mv queue/pending/2026-09/t_HASH_X.json queue/running/2026-09/
git add -A
git commit -m "federation: claim t_HASH_X by <node>"
git push origin

# 4. 拉取 Worktree
cd ~/wrk/<node>/agentco
git fetch origin
git worktree add -b wt/t_HASH_X origin/wt/t_HASH_X worktrees/t_HASH_X
cd worktrees/t_HASH_X

# 5. 验证完整性
bash .federation/task.json  # 读 contract
git log --oneline origin/wt/t_HASH_X  # 看 history
# → 决定: 续做 / 重做 / 退回

# 6. 接入本地看板
hermes kanban create "t_HASH_X (邦联接管)" \
  --assignee dev \
  --workspace "worktree:/Users/henry/wrk/<node>/agentco/worktrees/t_HASH_X"
hermes kanban link parent t_HASH_X --child <new_card_id>  # 关联原任务
```

### 2.3 Receiver Node: 完成 + 回流

```bash
# 1. Worker 完成编码 + verifier 通过
cd ~/wrk/<node>/agentco/worktrees/t_HASH_X
git add .
git commit --amend --signoff --no-edit  # 合并到原 commit
git push origin wt/t_HASH_X

# 2. 邦联队列标记完成
cd ~/wrk/<node>/agentco-federation
echo '{
  "task_id": "t_HASH_X",
  "done_at": "2026-09-22T10:00:00Z",
  "node": "<node>",
  "sha": "<final-commit-sha>",
  "branch": "wt/t_HASH_X",
  "duration_min": 95
}' > queue/done/2026-09/t_HASH_X.meta.json
git rm queue/running/2026-09/t_HASH_X.json
git add queue/done/2026-09/t_HASH_X.meta.json
git commit -m "federation: complete t_HASH_X by <node>"
git push origin

# 3. 本地看板 done
hermes kanban complete <new_card_id> \
  --result "邦联接管完成, see queue/done/2026-09/t_HASH_X.meta.json"

# 4. 清理 Worktree
cd ~/wrk/<node>/agentco
git worktree remove worktrees/t_HASH_X
git branch -D wt/t_HASH_X  # 本地分支清理
git worktree prune
```

### 2.4 Origin Node: 同步结果

```bash
# 1. 拉取更新
cd ~/wrk/<node>/agentco
git fetch origin
git pull  # 自动合并 wt/t_HASH_X 分支最新内容

# 2. 邦联队列回执
cd ~/wrk/<node>/agentco-federation
git pull
# queue/done/2026-09/t_HASH_X.meta.json 已存在

# 3. 合并到 main
cd ~/wrk/<node>/agentco
git checkout main
git merge --no-ff wt/t_HASH_X -m "merge: t_HASH_X from <receiver_node>"
git push origin main  # 触发 GitHub Actions CI

# 4. 清理本地 Worktree
git branch -D wt/t_HASH_X
git worktree prune

# 5. 本地看板标记
hermes kanban complete t_HASH_X \
  --result "邦联跨节点交付完成, see queue/done/2026-09/t_HASH_X.meta.json"
```

---

## 三、 命名规范

| 对象 | 命名 | 示例 |
|---|---|---|
| Branch | `wt/t_HASH_X` | `wt/t_a1b2c3d4` |
| Worktree 目录 | `worktrees/t_HASH_X` | `worktrees/t_a1b2c3d4` |
| 邦联任务文件 | `queue/<status>/<YYYY-MM>/t_HASH_X.json` | `queue/pending/2026-09/t_a1b2c3d4.json` |
| 邦联完成回执 | `queue/done/<YYYY-MM>/t_HASH_X.meta.json` | `queue/done/2026-09/t_a1b2c3d4.meta.json` |
| 抢占锁 | `queue/claim-locks/<YYYY-MM>/t_HASH_X.lock` | `queue/claim-locks/2026-09/t_a1b2c3d4.lock` |

---

## 四、 抢占锁 (Claim Lock)

**问题**: 多个节点同时拉取同一任务 → 重复执行。

**解法**: `git mv` 不是原子操作，**文件锁是必须的**。

```bash
# Receiver Node: 抢占
mkdir -p queue/claim-locks/2026-09
git pull
if [ ! -f queue/claim-locks/2026-09/t_HASH_X.lock ]; then
  echo "<node>:$(date +%s)" > queue/claim-locks/2026-09/t_HASH_X.lock
  git add queue/claim-locks/2026-09/t_HASH_X.lock
  git commit -m "federation: claim-lock t_HASH_X by <node>"
  git push origin
  # → 如果 push 成功 (无冲突), 抢占成功
  # → 如果 push 失败 (其他节点抢先), 回滚并跳过
fi
```

**Owner 字段格式**: `<node_id>:<unix_timestamp>`，便于审计。

**Lease 过期**: 24h 后其他节点可重新抢占 (lease expire)。

---

## 五、 故障恢复

### 场景 A: Receiver claim 后失联

```
T+0h:  Receiver claim t_HASH_X, 写入 queue/running/
T+1h:  Receiver 失联 (断网/崩溃)
T+24h: lease expire, 其他节点可抢占
T+24h: 另一个 Node C 看到 running/ 没有心跳, 重写为 pending/
T+24h: Node C 重新接管 t_HASH_X
```

### 场景 B: Worktree 推送冲突

```
Origin push wt/t_HASH_X (commit A)
Receiver push wt/t_HASH_X (commit B)  # 同时推送冲突
```

**解决**:
```bash
# Receiver 先 fetch
git fetch origin
git rebase origin/wt/t_HASH_X
# 或: git push --force-with-lease (仅当本地有真实修改)
```

**铁律**: `wt/t_HASH_X` 分支由**最后提交者**拥有，git log 决定最终内容。

### 场景 C: Worktree 体积过大

**限制**: 单 worktree 不超过 50MB (含依赖但不含 node_modules)。

**解决**:
- `.gitignore` 在创建 worktree 前必须配齐
- 大文件走 git LFS (Phase 2+)
- 二进制制品 (jar, whl, image) 不进 worktree

---

## 六、 最小配置示例

### Origin Node: Henry Mac 派单 (tier1)

```bash
cd ~/wrk/henry-mac/agentco
git worktree add -b wt/t_a1b2c3d4 worktrees/t_a1b2c3d4
cd worktrees/t_a1b2c3d4

# 准备契约
mkdir -p .federation
cat > .federation/task.json <<EOF
{
  "task_id": "t_a1b2c3d4",
  "title": "Refactor: extract kanban_db module",
  "privacy": "public-federation",
  "origin_node": "henry-mac",
  "created_at": "2026-09-21T19:00:00Z",
  "urgency": "p2",
  "engine_tier": "tier1-local-nuclear",
  "capacity_required": { "estimated_tokens": 50000, "estimated_walltime_min": 90, "memory_gb": 2.0 },
  "contract": { "acceptance": ["bash os/scripts/test_governance.sh"] }
}
EOF

git add .federation/task.json
git commit -m "feat(t_a1b2c3d4): federation task contract"
git push origin wt/t_a1b2c3d4

# 邦联队列登记
cd ~/wrk/henry-mac/agentco-federation
cp worktrees/t_a1b2c3d4/.federation/task.json queue/pending/2026-09/t_a1b2c3d4.json
git add queue/pending/2026-09/t_a1b2c3d4.json
git commit -m "federation: enqueue t_a1b2c3d4 (tier1-local-nuclear)"
git push origin
```

### Receiver Node: Mac mini 接管

```bash
# 1. 拉取邦联队列
cd ~/wrk/mac-mini/agentco-federation
git pull
cat queue/pending/2026-09/t_a1b2c3d4.json | jq '.engine_tier'

# 2. 能力匹配 (本地 capacity.json 有 tier1-local-nuclear)
cat capacity/mac-mini.json | jq '.engines_available'
# → ["tier0-readonly", "tier3-commercial-jet"]
# → 不匹配，跳过

# (假设 mac-mini 后来装了 tier1)
# → 匹配 → 抢占
touch queue/claim-locks/2026-09/t_a1b2c3d4.lock
git mv queue/pending/2026-09/t_a1b2c3d4.json queue/running/2026-09/
git add -A && git commit -m "federation: claim t_a1b2c3d4 by mac-mini"
git push origin

# 3. 拉取 Worktree
cd ~/wrk/mac-mini/agentco
git fetch origin
git worktree add -b wt/t_a1b2c3d4 origin/wt/t_a1b2c3d4 worktrees/t_a1b2c3d4

# 4. 接入本地看板
hermes kanban create "t_a1b2c3d4 邦联接管" --assignee dev --workspace "worktree:/Users/henry/wrk/mac-mini/agentco/worktrees/t_a1b2c3d4"
```

---

## 七、 关联文档

- ADR-017: 邦联协同协议 (父任务)
- ADR-018: 邦联任务 JSON Schema
- ADR-020: 隐私分级 (加密 payload)
- ADR-021: Phase 0 单节点 12 步清单

---

**AgentCo 架构委员会 · 2026-09-21**