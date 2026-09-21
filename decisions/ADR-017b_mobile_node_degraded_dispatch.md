# ADR-017: 移动节点调度降级策略（Mobile Node Degraded Dispatch）

- **状态**: Accepted (正式生效)
- **签署人**: 董事长 (Henry) & 集团总工程师 (Chief Architect) & 集团总经办 (Group Chief GM)
- **签署日期**: 2026-09-21
- **适用范围**: AgentCo 4 节点联邦（VPS / HM / Mac mini / Aimax）的 dispatcher 派单层
- **依赖**: ADR-010（3+1 拓扑）、ADR-014（双擎分工）、ADR-016（Aimax Docker 125B）

---

## 〇、 决策背景

2026-09-21 实测确认 4 节点拓扑新增 **HM (Henry Macbook, 10.0.0.2, utun14)** 行，原 ADR-010 节点表缺该行，且 dispatcher 派单策略未考虑 HM 的移动节点特性：

| 物理特征 | 固定节点 (VPS/Mac mini/Aimax) | 移动节点 (HM) |
|---|---|---|
| 网络 | 专线 / 7x24H 宽带 | Wi-Fi / 4G / 合盖休眠 / 出差断网 |
| 延迟 | 38-78 ms（稳定，jitter < 5ms） | 76-155 ms（jitter ±35ms） |
| 可用性 | 99.9% 在线 | 难以保证 8 小时连续在线 |
| 握手频率 | 持续 25s keepalive | 43s 前可达，但断网恢复后需重连 |
| SSH 可达性 | ✅ 常开 | ❌ 不开（一令席位合规边界） |
| 调度策略 | 接收所有角色卡 | **降级路径**（详见后文） |

**核心矛盾**：dispatcher 当前 `kanban.db` 派单逻辑无"目标节点可达性"预过滤，可能向失联 HM 派卡后 worker spawn 失败，重试超时后才回退（浪费 1-3 分钟）。

---

## 一、 决策

### 1. HM 失联时的 dev 卡降级路径

```
原派单：dev 卡 → assignee=dev (绑定 HM)
降级后：dev 卡 → assignee=dev (fallback=macmini)
```

**触发条件**（满足任一即触发降级）：
1. `ping -c1 -W2 10.0.0.2` 连续 3 次失败（窗口 5 分钟）
2. VPS 端 `wg show wg0 | grep 4r10Fni…` latest handshake > 5 分钟前
3. macmini dispatcher 日志出现"spawn dev failed: connection refused to 10.0.0.2"

**降级动作**：dispatcher 在派 dev 卡前，先查 `mesh_status.json` 中 HM 的 liveness = `stale | offline`，若 stale > 5min 则强制改派 macmini 本地 worker 执行。**不修改卡片的 assignee 字段**（保留审计），仅在 `metadata.dispatched_node` 字段记录实际执行节点。

### 2. Aimax 失联时的推理降级路径

```
原推理：client → aimax 10.0.0.4:8080 (qwen3.8-flash)
降级后：client → vps anchor 10.0.0.1:8088 (anchor router → cloud fallback)
```

**触发条件**：
1. `curl --max-time 3 http://10.0.0.4:8080/health` 返回非 200
2. aimax container `qwen38-flash-next-qwen-drluoto-mtp-1` status != `Up`（vps 通过 `ssh aimax "docker ps"` 检测）
3. WG tunnel 10.0.0.4 ping > 200ms 或 0% 丢包

**降级动作**：client side（macmini 或 HM）检测到 aimax 不可达后，自动切换到 vps anchor 路由，由 anchor 的 worker pool 选择 cloud worker（如 `claude-sonnet-5` / `gpt-6-astra`）作为本地模型的替代品。**不修改卡片的 model 字段**，仅记录降级原因到 `metadata.fallback_reason`。

### 3. VPS 失联时的兜底（极端情况）

VPS 是双引擎之一的路由网关 + 真理源，若 VPS 失联（公网光纤故障）：

- **macmini 仍在线** → 本地 `kanban.db` 继续派单，本地 worker 继续工作；所有 PR 暂存本地，待 VPS 恢复后批量推送。
- **HM 仍在线但 VPS 断** → HM 通过 Wi-Fi 公网可独立访问 GitHub（GitHub 是 +1 真理庭），可绕过 VPS 直接 `gh pr create`。
- **Aimax 仍在线但 VPS 断** → Aimax 也可独立 `gh pr create`，但失去与 macmini 的派单通道，进入"单机自治"模式。

详见 ADR-010 § 三"全节点对称孤岛自治与重连汇流协议"。

---

## 二、 心跳检测机制

### 1. macmini 侧的 liveness 心跳（每 5 分钟）

由 dispatcher watchdog 或独立 cron 触发：

```bash
# /Users/dongshenglu/agentco/os/scripts/node_liveness.sh (建议)
HM_ALIVE=$(ping -c1 -W2 10.0.0.2 | grep -c "1 received")  # 1=alive, 0=dead
AIMAX_ALIVE=$(curl -sS --max-time 3 http://10.0.0.4:8080/health | grep -c '"status":"ok"')
VPS_ALIVE=$(curl -sS --max-time 3 http://10.0.0.1:8088/v1/models | grep -c '"object":"list"')
echo "$(date -Iseconds) HM=$HM_ALIVE AIMAX=$AIMAX_ALIVE VPS=$VPS_ALIVE" \
  >> /Users/dongshenglu/.hermes/logs/node_liveness.log
```

输出写入 `mesh_status.json`，dispatcher 派单前查询。

### 2. VPS 侧的握手心跳（25 秒 keepalive，已存在）

VPS `wg0.conf` 已配置 `persistent keepalive = every 25 seconds`，HM / Mac mini / Aimax 端均配对回应。VPS 端每 25s 检查 peer handshake timestamp。

### 3. Aimax 侧的 docker 健康（30 秒，container 内置）

`qwen38-flash-next-qwen-drluoto-mtp-1` 容器自带 `--ctx-checkpoints 8` 健康检查机制；外部由 macmini watchdog 每 60s `curl /health` 复核。

---

## 三、 降级策略实施细则

### 1. dispatcher 派单前的可达性过滤（建议落地步骤）

```
IF card.assignee == "dev" AND mesh_status["hm"]["liveness"] == "offline" > 5min:
    log.warning(f"[ADR-017] dev 卡 {card.id} 降级派发：HM offline, fallback=macmini")
    set metadata.dispatched_node = "macmini"
    spawn worker on macmini local

ELIF card.model in ["qwen3.8-flash-next-mtp", "aimax-*"] AND mesh_status["aimax"]["liveness"] == "offline":
    log.warning(f"[ADR-017] aimax 模型卡降级：fallback=vps anchor")
    set metadata.fallback_reason = "aimax offline at {ts}"
    route to anchor.router("anchor-auto")
```

### 2. 节点恢复后的回切

当 HM 重新握手（VPS 端 25s 内看到新 handshake），`mesh_status.json` 更新为 `liveness = online`，dispatcher **下一张** dev 卡重新派发到 HM（不在途卡强制迁移，避免 worker 状态混乱）。

### 3. 日志与告警

- 每次降级触发，dispatcher 写 `kanban.db.events` 一条 `degraded_dispatch` 记录。
- macmini cron 每小时聚合降级次数，若 > 5 次/小时，发 telegram 告警到董事长。

---

## 四、 边界（明确不做的事）

1. **不影响 aimax/vps/macmini 之间的固定调度**：三者均为 7x24H 在线节点，dispatcher 仍按原优先级派发，不引入额外心跳判断。
2. **不修改 `kanban.db` 表结构**：仅在 `metadata` 字段增加 `dispatched_node` / `fallback_reason` 两个非必填字段。
3. **不修改 WireGuard / ssh config**：本 ADR 仅是派单策略，不动网络层。
4. **不强制迁移在途卡**：降级只影响新派发的卡；在途 worker 不打断，避免数据污染。
5. **HM SSH 不开通**：HM 作为一令席位保持 0 常驻负载（ADR-010 边界），SSH 不可达 = 合规而非故障。

---

## 五、 与既有 ADR 的关系

- **ADR-010 § 三 (孤岛自治)**：本 ADR 是该章节的**移动节点特化版**——把"断网孤岛"的检测从被动（worker spawn 失败）改为主动（5min 心跳预过滤）。
- **ADR-014 (双擎分工)**：本 ADR 在 HM 失联时**优先保 Aimax**，因为 Aimax 125B 是内网 0 成本算力，cloud worker 是兜底。
- **ADR-016 (Aimax Docker 125B)**：本 ADR 是 ADR-016 的**可用性兜底**——aimax 容器若挂，推理自动 fallback 到 vps anchor 的 cloud worker pool。

---

## 六、 验收标准

1. `os/scripts/node_liveness.sh` 存在并能输出 `HM/AIMAX/VPS` 三态。
2. `mesh_status.json` 5 分钟内至少更新一次。
3. dispatcher 派单日志能体现"降级派发"事件（card_id + 原因 + 时间）。
4. HM 失联 5 分钟后第一张 dev 卡自动 fallback 到 macmini（实测或 dry-run 验证）。
5. Aimax 失联 5 分钟后第一次推理调用自动 fallback 到 vps anchor。

---

## 七、 后续可演进项（非本次范围）

- 节点预测性健康：基于过去 24h 抖动数据，提前 5min 预警 HM 即将失联。
- 多 HM 冗余：若董事长未来增加第二台移动设备，dispatcher 支持 `hm-primary` / `hm-secondary` 角色漂移。
- aimax 多实例：当前 aimax 跑一个 qwen3.8-flash 容器，未来若 125B MoE 上线，dispatcher 支持 round-robin 多实例。

---

**本法典自发布之日起即刻生效，dispatcher 与 node_liveness 维护者须无条件严格遵照执行！**
