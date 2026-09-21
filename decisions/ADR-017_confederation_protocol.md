# ADR-017: AgentCo 邦联协同协议（Confederation Protocol）

- **状态**: Accepted (正式生效，替代原 3+1 联邦法典)
- **签署人**: 董事长 (Henry) & 集团总工程师 (Chief Engineer)
- **签署日期**: 2026-09-21
- **理论基础**: 取代 ADR-010/ADR-012 的"联邦"模型，转向**邦联 (Confederation)** 自治协同
- **适用范围**: AgentCo 全网物理节点 + GitHub 公共协调层

---

## 〇、 决策背景：从"联邦"到"邦联"的范式跃迁

在 2026-09-21 关键头脑风暴中，董事长指出过去"3+1 联邦"模型的根本缺陷：

1. **脑裂脆弱性**：依赖 WireGuard mesh 内网，节点失联 = 联邦瘫痪
2. **母子管控假设**：Mac mini 必须为集团中枢，但实际可以是独立晶圆厂之一
3. **资源错配**：联邦架构假设"总部不动手只派单"，但每个节点都有完整加工能力
4. **扩展瓶颈**：新节点需要物理网线/内网协议/SSH 密钥手工配置

**新范式核心洞察**：

> **邦联 = 多个自治晶圆厂 + GitHub 公共协调层**
>
> 每个节点是**独立、完整、自洽**的晶圆厂；邦联不强制同步，只在节点主动寻求/接受外部协作时介入。

---

## 一、 邦联架构 (Confederation Architecture)

### 1.1 单节点晶圆厂 (Single-Node Foundry)

**最小完整配置**（每个节点都具备）：

```
┌─────────────────────────────────────────────────────────┐
│ 单一节点晶圆厂 (Henry Mac 当前实例)                       │
├─────────────────────────────────────────────────────────┤
│ ✓ 1 个本地看板 (kanban.db)                                │
│ ✓ 1 个本地 Gateway + GM daemon                            │
│ ✓ 4-5 个 Profile (gm/dev/qa/pm + verifier)                 │
│ ✓ 1-N 个 Workers (机床调用)                                │
│ ✓ N 个 Lathe (Hermes/OpenCode/Codex CLI)                  │
│ ✓ M 个 Engine (商业 API / 本地模型)                       │
│ ✓ 1 个本地 Verifier (三轴门禁)                             │
│ ✓ 本地治理工具链 (test_governance.sh, ssot_gate.sh)      │
│ ✓ 本地 Git 仓库 (agentco 或私人仓)                       │
└─────────────────────────────────────────────────────────┘
```

**单节点自治闭环**：

```
[本地 GM]
    ↓ 派单
[Worker] → [Lathe] → [Engine] → [代码/工件]
    ↓
[Verifier 三轴门禁]
    ↓ pass
[Git commit + done]
```

### 1.2 邦联协调层 (Confederation Coordination Layer)

```
┌─────────────────────────────────────────────────────────┐
│ GitHub 邦联仓 (jajabong/agentco-federation)              │
├─────────────────────────────────────────────────────────┤
│ 可见性: public   (邦联全员可见元数据)                    │
│ 用途: 邦联协调 / 跨节点任务流转                            │
│                                                          │
│ ┌─────────────────────┐  ┌────────────────────────────┐ │
│ │ 公开看板 (JSON+Issues)│  │   节点注册 (members.md)    │ │
│ │ queue/pending/       │  │   capacity/<node>.json     │ │
│ │ queue/running/       │  │   bindings/<node>/pubkey    │ │
│ │ queue/done/          │  │                             │ │
│ └─────────────────────┘  └────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
         ↑↓ git pull/push          ↑↓ git pull/push
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Node A: Henry Mac│  │ Node B: Mac mini│  │ Node C: Aimax   │
│ 本地看板(自主)  │  │ 本地看板(自主)  │  │ 本地看板(自主)  │
│ GM 满载 → push  │  │ GM 空闲 → pull  │  │ GM 空闲 → pull  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### 1.3 核心区别: 联邦 vs 邦联

| 维度 | 联邦 (ADR-010/012) | 邦联 (ADR-017) |
|---|---|---|
| **协调器** | WireGuard mesh 内网 | GitHub 公共仓 |
| **节点关系** | 母子公司集中管控 | 独立晶圆厂自治 |
| **通信协议** | VPN 内网隧道 | git push/pull (HTTPS) |
| **资产可见性** | 私有托管 (Gitee bare) | GitHub 公开 + 受邀注册 |
| **故障域** | 全网脑裂风险 | 节点独立存活 |
| **接入门槛** | 物理网线 + 密钥 | git clone + members.md |
| **资源调度** | 总部统一派单 | 本地饱和才外溢 |
| **节点死亡** | 联邦瘫痪 | 其他节点照常工作 |

---

## 二、 邦联协议 (Confederation Protocol)

### 2.1 本地饱和度 (Local Saturation Trigger) — Phase 0/1 静态阈值

**触发外溢条件**（必须同时满足）：
1. 本地 WIP ≥ **6** (满载高效区)
2. 本地 CPU > **80%** (5min 平均负载)
3. 至少有 1 个本地 ready/backlog 任务

**饱和度判定**:
```bash
# Node GM 每 30s 检查本地饱和度
hermes_capacity_check() {
  local wip=$(hermes kanban stats | grep "running\|ready" | wc -l)
  local cpu=$(ps -A -o %cpu | awk '{sum+=$1} END {print sum}')
  if [ "$wip" -ge 6 ] && [ "$cpu" -gt 80 ]; then
    return 0  # saturated → trigger overflow
  fi
  return 1
}
```

### 2.2 任务外溢协议 (Task Overflow Protocol)

**当本地饱和且有任务排队**:

1. GM 选择**非紧急 (p2/p3)** 任务
2. 生成邦联任务 JSON (schema 见 ADR-018)
3. `git push` 到 `agentco-federation/queue/pending/`
4. 留下本地副本 (本地看板标记 `federation: out`)
5. 接收节点的 GM 看到推送后 pull + 评估 + claim

**任务内吸协议 (Task Inflow Protocol)**:

**当本地空闲且邦联队列有任务**:

1. GM `git pull` `agentco-federation/queue/pending/`
2. 评估任务 `capacity_required.engine_tier` 与本地能力
3. 适合 → 原子 claim (git mv 到 running/) + 拉到本地看板
4. 不适合 → 跳过，下次轮询再看
5. 完工 → git mv 到 done/ + git push

### 2.3 Worktree 流转协议 (Worktree Transfer Protocol)

**任务单元 = Git Worktree 单实例**:

```
【Origin Node A: 派单】
git worktree add -b wt/t_HASH_X worktrees/t_HASH_X
# worker 编码
git add . && git commit -m "feat(t_HASH_X):<summary>"
git push origin wt/t_HASH_X

【邦联队列登记】
vim queue/pending/2026-09/t_HASH_X.json  # 按 ADR-018 schema
git push origin HEAD

【Receiver Node B: 接管】
git fetch origin
git worktree add -b wt/t_HASH_X origin/wt/t_HASH_X worktrees/t_HASH_X
cd worktrees/t_HASH_X
bash $CONTRACT/acceptance.sh
git commit --amend --signoff
git push origin wt/t_HASH_X

【Receiver 登记回执】
git mv queue/pending/2026-09/t_HASH_X.json queue/done/2026-09/
echo '{"done_at":"...","node":"B","sha":"..."}' >> done/.../t_HASH_X.meta.json
git push origin HEAD
```

### 2.4 故障自愈 (Faut Tolerance)

| 场景 | 邦联自愈策略 |
|---|---|
| **GitHub 不可达** | 各节点本地继续自治，邦联队列堆积，恢复后批量同步 |
| **节点 A 推单后失联** | 任务在 pending/ 滞留，其他节点仍可 pull |
| **节点 B claim 后失联** | 24h lease expire，任务回滚到 pending/ |
| **origin_node 与 receiver 冲突** | git push 冲突 → 接收节点 force-with-lease 解决 |
| **敏感任务泄露** | encrypted_payload 保护，明文不可读 |

---

## 三、 受邀注册 (Trusted Membership)

### 3.1 `members.md` 注册机制

**准入规则**:
1. 节点 Owner 提 PR 到 `agentco-federation/members.md`
2. 附 GPG 公钥指纹 + 物理节点描述
3. 至少 1 位现有节点 Owner Approve
4. ADR 合规自检通过 (本 ADR + ADR-018/019/020)
5. 完成 Phase 0 单节点验证 + Phase 1 邦联 dry-run

**当前节点 (2026-09-21 起)**:

| Node ID | Owner | GPG FP | 物理机 | 角色 | 状态 |
|---|---|---|---|---|---|
| henry-mac | jajabong | TBD | M4 Mac mini 16GB | 驾驶舱+总工驻地 | ✅ active |
| mac-mini  | dongsheng | TBD | M2 Mac mini 16GB | 集团 GM+直精车间 | 🟡 pending |
| aimax     | TBD | TBD | Strix Halo 128GB | 重工子公司 | ⚪ not invited |

---

## 四、 落地路线图 (4 阶段)

### Phase 0: 单节点自治 (Phase 0 - 立即启动)

- 目标: Henry Mac 一个节点完整跑通五位一体闭环
- 范围: 本地派单 → Worker → Lathe → Verifier → done
- 排除: 跨节点 / 邦联队列 / WG mesh / 商业 API
- 验收: 12 步清单 (见 ADR-021)

### Phase 1: 邦联 schema (Phase 1 - Schema Ready)

- 目标: agentco-federation 仓 + JSON Schema + members.md
- 范围: ADR-018 task schema + ADR-019 worktree lifecycle + ADR-020 privacy
- 准入: Phase 0 完成
- 验收: Schema 接受 PR 流程跑通

### Phase 2: GM 双看板 (Phase 2 - GM Federation-Aware)

- 目标: gm_federation_pull.sh + gm_federation_push.sh + capacity_heartbeat.sh
- 范围: GM 同时查询本地 kanban + 邦联 queue
- 准入: Phase 1 完成
- 验收: 同一节点自己 push/pull 自己成功

### Phase 3: 多节点接入 (Phase 3 - Multi-Node Live)

- 目标: Mac mini / Aimax 接入邦联 + members.md 登记
- 范围: 2 节点互派单成功
- 准入: Phase 2 完成
- 验收: 跨节点任务从派单到 done 全流程跑通

---

## 五、 历史背景 (Historical Context)

**原 3+1 联邦法典 (ADR-010, ADR-012)** 于 2026-09-19/20 由董事长签署生效，
奠定了 AgentCo 工业制造体系的理论基础：
- 空间法人拓扑（母子控股）
- 五位一体因果解耦流水线
- 全节点对称孤岛自治
- 现代制造业离散装配理论

但因实际运行中暴露**脑裂脆弱性** (WG mesh 断 = 全网瘫痪) 与**资源错配**
（Mac mini 实际不是真正的中枢），2026-09-21 战略复盘正式修订为**邦联架构**。

**保留与继承**:
- ✅ 五位一体流水线（GM/Worker/Lathe/Engine/Verifier）
- ✅ 全节点对称孤岛自治原则
- ✅ 利特尔法则 + Test-Time Compute + 超级晶圆厂隐喻
- ✅ Profile 矩阵与治理法典

**修订与替代**:
- ❌ Mac mini 唯一中枢 → 每个节点都是独立晶圆厂
- ❌ 母子公司管控 → 邦联国自治协同
- ❌ WireGuard 唯一协调器 → GitHub 公共协调层
- ❌ 全网仅 Mac mini 有主派单权 → 本地饱和才外溢

**参考 ADR-010 / ADR-012 / ADR-016 (已被本文档部分替代)**。

---

## 六、 关联文档

- ADR-018: 邦联任务 JSON Schema (元数据契约)
- ADR-019: Worktree 流转协议 (任务单元契约)
- ADR-020: 隐私分级 (private-encrypted 模式)
- ADR-021: Phase 0 单节点 12 步验证清单
- ADR-010: (已替代) 3+1 联邦协同法典
- ADR-012: (已替代) 工业联邦五位一体流水线
- ADR-016: (部分重叠) Aimax Docker 125B MoE

---

**AgentCo 架构委员会 · 2026-09-21**