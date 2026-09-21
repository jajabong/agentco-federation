# AgentCo Confederation Members Registry

> 来源：ADR-017 §3 (members.md 协议)
> 更新：每次新节点加入/退场时 PR 修订

## 已注册节点

### henry-mac
- **Role**: origin_node_preferred (主派单节点)
- **Public Key**: bindings/henry-mac/pubkey.pem
- **Capacity**: capacity/henry-mac.json (heartbeat 30s)
- **Status**: 🟢 Active (2026-09-21 注册)
- **Engine Tiers**: tier0-readonly, tier3-commercial-jet
- **Owner**: jajabong (Henry)

### mac-mini
- **Role**: satellite_node (待接入)
- **Status**: 🟡 Invited (2026-09-21)
- **Engine Tiers**: tier0-readonly, tier3-commercial-jet (待确认)
- **Invitation PR**: (Phase 1 Step 12)

### aimax
- **Role**: satellite_node (待接入)
- **Status**: 🟡 Invited (2026-09-21)
- **Engine Tiers**: tier0-readonly, tier1-local-nuclear, tier3-commercial-jet (Aimax 125B)
- **Invitation PR**: (Phase 1 Step 12)

## 接入流程

1. 节点 owner fork `jajabong/agentco-federation`
2. 添加 `bindings/<node_id>/pubkey.pem` + `capacity/<node_id>.json`
3. 追加本文件 members 列表
4. 提 PR 到 `main`
5. henry-mac GM 审核 + merge
6. merge 后 60s 内新节点进入邦联队列感知
