# ADR-021: 单节点晶圆厂 Phase 0 验证清单 (SoloFab v1 适配版)

- **状态**: Accepted
- **签署人**: 集团总工程师 (Chief Engineer)
- **签署日期**: 2026-09-21
- **更新**: 2026-09-21 SoloFab v1 适配 (ADR-022)
- **父 ADR**: ADR-017 邦联协同协议 + ADR-022 SoloFab v1
- **适用范围**: 任何节点接入邦联前的最小验证 (单节点 SoloFab v1 模式)

---

## 〇、 Phase 0 目标 (SoloFab v1 视角)

**在单一节点上完整跑通"SoloFab 四层闭环"**, 证明该节点具备自治晶圆厂能力。

**SoloFab v1 适配**:
- ✅ 四层架构: Intent + Meta (GM) + Execution + Verification
- ✅ 单 worker 模式 (16GB 物理约束)
- ✅ Engine Tier 0 + Tier 3 (商业 API 主力)
- ❌ ~~Tier 1 核电~~ (Aimax 离线, 单节点无本地 LLM)
- ❌ ~~邦联队列感知~~ (Phase 0 跳过)
- ❌ ~~容量上报~~ (Phase 0 跳过)
- ❌ ~~饱和度外溢~~ (Phase 0 跳过, 本地满则排队)

**严格排除**:
- ❌ 任何跨节点派单
- ❌ GitHub 邦联队列操作 (Phase 1+ 范围)
- ❌ WG mesh 重新启用
- ❌ SSOT-5 三节点 commit 漂移检查 (单节点无此需求)
- ❌ 变异测试 (Mutation Testing) (Phase 2+ 范围)

---

## 一、 12 步验证清单 (每步 5-15 分钟)

| # | 步骤 | 命令/方法 | 验收 |
|---|---|---|---|
| 1 | **GM 进程健康** | `ps aux \| grep "hermes -p gm"` | PID 存在 |
| 2 | **Gateway 在线** | `hermes gateway status` | running + dispatch_in_gateway |
| 3 | **5 profile 检查** | `ls ~/.hermes/profiles/` | gm/dev/qa/pm/verifier 全在 |
| 4 | **机床 spawn 测试** | `hermes -p dev --cli -q "echo hi"` | 正常输出 |
| 5 | **本地看板列示** | `hermes kanban stats` | 状态分布合理 |
| 6 | **建最小测试卡** | `hermes kanban create "t_phase0_smoke ..."` | ready |
| 7 | **dispatcher claim** | `sleep 65` 后再查 | running |
| 8 | **worker 执行** | `hermes kanban log t_phase0_smoke` | 有心跳+命令 |
| 9 | **verifier 通过** | 等 done | 状态 done |
| 10 | **治理脚本** | `bash os/scripts/test_governance.sh` | 144/145 PASS |
| 11 | **GM 作战室节点矩阵** | 写 1 个本地查询脚本 `os/scripts/gm_local_node_matrix.sh` | 输出 CPU/RAM/Disk |
| 12 | **产出 Phase 0 报告** | 写到 `os/evals/single-node-smoke-2026-09-21.md` | 总工归档 |

---

## 二、 Phase 0 最小测试卡

**卡 t_phase0_smoke**:
```
title: Phase 0 单节点闭环冒烟测试
assignee: dev
workspace: dir:/Users/henry/agentco-master
est_steps: 4
est_walltime_min: 15
acceptance:
  1. bash os/scripts/test_governance.sh → 144/145 PASS
  2. touch /tmp/agentco_phase0_probe && git status → clean
  3. hermes kanban create 一张本地测试卡 → claim → worker hello world → done
  4. hermes kanban stats → done 计数 +1
```

---

## 三、 GM 节点矩阵脚本 (Step 11)

**新建**: `os/scripts/gm_local_node_matrix.sh`

**功能**:
- 输出当前节点的 CPU/Memory/Disk 状态
- 列出本地 Profile 数 + 活跃 Worker 数
- 检查 Gateway + GM 进程健康

**最小实现** (≤ 50 行 bash):
```bash
#!/usr/bin/env bash
# gm_local_node_matrix.sh - GM 本地作战室节点矩阵 (Phase 0)

set -uo pipefail

echo "=== 节点身份 ==="
hostname
uname -a
echo "节点 ID: $(whoami)@$(hostname)"

echo ""
echo "=== 物理状态 ==="
echo "CPU 核数: $(sysctl -n hw.ncpu)"
echo "CPU 负载 (1/5/15min): $(uptime | awk -F'load averages:' '{print $2}')"
echo "内存: $(vm_stat | awk '/free/ {free=$3} /active/ {active=$3} END {print "free=" free " active=" active}')"
echo "磁盘: $(df -h / | tail -1 | awk '{print $4 " free of " $2}')"

echo ""
echo "=== Hermes 运行时 ==="
echo "GM 进程: $(pgrep -f 'hermes -p gm' | head -1)"
echo "Gateway: $(hermes gateway status 2>&1 | head -3)"
echo "Profiles: $(ls ~/.hermes/profiles/ | tr '\n' ' ')"

echo ""
echo "=== Kanban 状态 ==="
hermes kanban stats

echo ""
echo "=== 邦联接入就绪度 ==="
[ -d ~/wrk/<node>/agentco ] && echo "✅ 本地仓库" || echo "❌ 本地仓库缺失"
[ -d ~/wrk/<node>/agentco-federation ] && echo "✅ 邦联仓" || echo "❌ 邦联仓缺失"
[ -f ~/.hermes/profiles/gm/SOUL.md ] && echo "✅ GM SOUL" || echo "❌ GM SOUL 缺失"
```

---

## 四、 Phase 0 完成判据

- ✅ 12 步验证清单全部通过
- ✅ 测试卡 t_phase0_smoke done
- ✅ 单节点闭环截图/日志保存到 `os/evals/single-node-smoke-2026-09-21.md`
- ✅ `test_governance.sh` 144/145 PASS

**Phase 0 通过 = 节点具备进入 Phase 1 (邦联 schema) 的资格**。

---

## 五、 关联文档

- ADR-017: 邦联协同协议 (跨节点场景)
- **ADR-022: SoloFab v1 单节点架构** (本节点适用)
- ADR-018: 邦联任务 JSON Schema
- ADR-019: Worktree 流转协议
- ADR-020: 隐私分级
- os/profiles/gm/SOUL.md: SoloFab 单节点降级模式 (铁律十六)
- os/profiles/verifier/SOUL.md: SoloFab 三轴门禁
- os/scripts/gm_local_node_matrix.sh: Phase 0 Step 11 节点矩阵脚本

---

**AgentCo 架构委员会 · 2026-09-21**