# ADR-018: 邦联任务 JSON Schema (Federation Task Schema)

- **状态**: Accepted
- **签署人**: 集团总工程师 (Chief Engineer)
- **签署日期**: 2026-09-21
- **父 ADR**: ADR-017 邦联协同协议
- **适用范围**: `agentco-federation/queue/*/*.json`

---

## 〇、 设计目标

为邦联跨节点任务流转提供**强画像**的元数据契约：
- 接收节点 GM 能**精准匹配**能力
- 避免错配重试浪费
- 节点能力图谱透明化

**核心原则**: `capacity_required.engine_tier` **必填** (强画像 = 强邦联路由)

---

## 一、 任务 JSON Schema (Draft v1)

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "title": "AgentCo Confederation Task",
  "type": "object",
  "required": ["task_id", "title", "privacy", "origin_node", "engine_tier", "contract", "created_at"],
  "properties": {
    "task_id": {
      "type": "string",
      "pattern": "^t_[a-f0-9]{8}$",
      "description": "任务 ID，与本地 kanban.db 一致"
    },
    "title": {
      "type": "string",
      "maxLength": 200
    },
    "privacy": {
      "type": "string",
      "enum": ["public-federation", "public-no-detail", "private-encrypted"],
      "default": "public-federation",
      "description": "public-federation: 邦联可见全 body; public-no-detail: 仅元数据, body 加密; private-encrypted: body 加密 + 收件节点限定"
    },
    "origin_node": {
      "type": "string",
      "pattern": "^[a-z0-9-]+$",
      "description": "派单节点 ID (members.md 注册)"
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    },
    "urgency": {
      "type": "string",
      "enum": ["p0", "p1", "p2", "p3"],
      "default": "p2"
    },
    "engine_tier": {
      "type": "string",
      "enum": ["tier1-local-nuclear", "tier2-speculative", "tier3-commercial-jet", "tier0-readonly"],
      "description": "★ 必填: 所需引擎类型"
    },
    "capacity_required": {
      "type": "object",
      "properties": {
        "estimated_tokens": { "type": "integer", "description": "预估总 Token 消耗" },
        "estimated_walltime_min": { "type": "integer", "description": "预估墙钟时间(分钟)" },
        "memory_gb": { "type": "number", "description": "预估内存需求 (GB)" },
        "cpu_cores": { "type": "integer", "description": "所需 CPU 核数" }
      }
    },
    "contract": {
      "type": "object",
      "required": ["acceptance"],
      "properties": {
        "est_steps": { "type": "integer", "maximum": 10 },
        "acceptance": {
          "type": "array",
          "items": { "type": "string" },
          "description": "可执行验收命令列表"
        },
        "forbidden_paths": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "encrypted_payload": {
      "type": "object",
      "description": "仅 privacy != public-federation 时存在",
      "properties": {
        "recipient_node_id": { "type": "string", "description": "限定接收节点" },
        "cipher": { "type": "string", "enum": ["AES-256-GCM"], "default": "AES-256-GCM" },
        "encrypted_body": { "type": "string", "description": "base64 密文" },
        "nonce": { "type": "string" },
        "recipient_pubkey_fpr": { "type": "string", "description": "收件节点 GPG 公钥指纹" }
      }
    },
    "metadata": {
      "type": "object",
      "properties": {
        "skill_hint": { "type": "string" },
        "verifier_required": { "type": "boolean", "default": true },
        "deadline": { "type": "string", "format": "date-time" },
        "tags": { "type": "array", "items": { "type": "string" } },
        "skill_tokens_used": { "type": "integer" }
      }
    }
  }
}
```

---

## 二、 engine_tier 必填论证

### 必填理由 (总工建议 C1)

| 维度 | 必填 | 选填 |
|---|---|---|
| **邦联路由效率** | ✅ 接收节点 GM 精准匹配 | ❌ 默认 fallback 错配 |
| **任务画像完整性** | ✅ 强画像 = 强自治 | ❌ 弱画像 = 噪声队列 |
| **邦联流量控制** | ✅ 引擎能力对得上的节点才接 | ❌ 错配重试浪费 |
| **GM 工作量** | +30 秒思考 (4 选 1) | 0 |

### 三选一成本极低

派单时本来就要判断:
- 这是批量粗活吗？→ `tier1-local-nuclear`
- 这是投机性草稿吗？→ `tier2-speculative`
- 这是攻坚件吗？→ `tier3-commercial-jet`
- 这是纯检索？→ `tier0-readonly`

这一步本来就存在，**engine_tier 只是把这个判断显式化 + 结构化**。

---

## 三、 引擎类型定义 (engine_tier Enum)

| tier | 含义 | 典型场景 | 推荐节点 |
|---|---|---|---|
| **tier0-readonly** | 纯只读/检索 | 文件查找、API 查询、文档阅读 | 任意 |
| **tier1-local-nuclear** | 0 成本本地大模型 | 海量代码扫描、单测生成、批量重构 | Aimax 128G |
| **tier2-speculative** | 投机加速 | Draft + Verify 双模型、MTP 加速 | 本地 + 商业混合 |
| **tier3-commercial-jet** | 商业 API 攻坚 | 复杂架构、跨节点协议、顶层设计 | 任意 + 商业 API |

---

## 四、 节点能力登记 (capacity.json)

**对应 Schema**: 每个节点在 `agentco-federation/capacity/<node_id>.json` 登记能力：

```json
{
  "node_id": "henry-mac",
  "last_heartbeat": "2026-09-21T18:30:00Z",
  "physical": {
    "memory_total_gb": 16,
    "memory_used_gb": 6.2,
    "cpu_cores": 8,
    "cpu_load_5min": 1.8,
    "disk_free_gb": 200
  },
  "engines_available": [
    "tier0-readonly",
    "tier3-commercial-jet"
  ],
  "wip": 4,
  "wip_threshold": 6,
  "saturated": false,
  "federation_role": "origin_node_preferred"
}
```

**origin GM 派单时**: 根据 `engines_available` 预过滤目标节点，避免错配。

---

## 五、 最小可工作示例

### 邦联任务示例 (public-federation)

```json
{
  "task_id": "t_a1b2c3d4",
  "title": "Refactor: extract kanban_db to standalone module",
  "privacy": "public-federation",
  "origin_node": "henry-mac",
  "created_at": "2026-09-21T18:30:00Z",
  "urgency": "p2",
  "engine_tier": "tier1-local-nuclear",
  "capacity_required": {
    "estimated_tokens": 50000,
    "estimated_walltime_min": 90,
    "memory_gb": 2.0,
    "cpu_cores": 4
  },
  "contract": {
    "est_steps": 5,
    "acceptance": [
      "bash os/scripts/test_governance.sh",
      "python3 -m pytest tests/test_kanban_db_read.py"
    ],
    "forbidden_paths": [".git/", "node_modules/"]
  },
  "metadata": {
    "skill_hint": "python-refactor",
    "verifier_required": true,
    "deadline": "2026-09-23T18:30:00Z",
    "tags": ["refactor", "module-boundary"]
  }
}
```

### 敏感任务示例 (private-encrypted)

```json
{
  "task_id": "t_e5f6g7h8",
  "title": "[ENCRYPTED]",
  "privacy": "private-encrypted",
  "origin_node": "henry-mac",
  "created_at": "2026-09-21T18:30:00Z",
  "urgency": "p1",
  "engine_tier": "tier3-commercial-jet",
  "encrypted_payload": {
    "recipient_node_id": "mac-mini",
    "cipher": "AES-256-GCM",
    "encrypted_body": "base64-ciphertext-here...",
    "nonce": "random-nonce-12bytes",
    "recipient_pubkey_fpr": "ABCD1234..."
  },
  "contract": {
    "acceptance": ["<decrypt-then-show>"]
  },
  "metadata": {
    "verifier_required": true
  }
}
```

---

## 六、 版本与演进

- **当前**: v1 (Phase 1)
- **预留**: v2 将加入 `priority_score` 字段 (邦联调度算法用)
- **向后兼容**: 6 个月内接受 v1 节点接入

---

## 七、 关联文档

- ADR-017: 邦联协同协议 (父任务)
- ADR-019: Worktree 流转协议
- ADR-020: 隐私分级 (private-encrypted 详细)
- ADR-021: Phase 0 单节点 12 步清单

---

**AgentCo 架构委员会 · 2026-09-21**