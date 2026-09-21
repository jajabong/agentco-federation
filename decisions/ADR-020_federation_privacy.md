# ADR-020: 邦联隐私分级与加密协议 (Privacy Classification)

- **状态**: Accepted
- **签署人**: 集团总工程师 (Chief Engineer)
- **签署日期**: 2026-09-21
- **父 ADR**: ADR-017 邦联协同协议
- **适用范围**: 邦联跨节点任务流转的隐私保护

---

## 〇、 决策背景

邦联默认 `public` 仓库 (`jajabong/agentco-federation`)，元数据对邦联全员透明。
但 AgentCo 部分任务涉及**敏感商业逻辑**:
- 商业模型 (Open Anchor 70/30 套利策略)
- 客户数据 / 内部算法
- 财务决策细节
- 内部架构演进

这些任务**不能明文上邦联队列**。本 ADR 定义三级隐私保护。

---

## 一、 三级隐私分级

| Level | 字段 | body 可见 | body 加密 | 收件节点限定 |
|---|---|---|---|---|
| **L1: public-federation** | 默认 | ✅ 全明文 | ❌ | ❌ 任意节点 |
| **L2: public-no-detail** | 显式 | ❌ 仅元数据 | ✅ AES-256-GCM | ❌ 任意节点 |
| **L3: private-encrypted** | 显式 | ❌ 仅 metadata | ✅ AES-256-GCM | ✅ 指定单一节点 |

### 1.1 L1: public-federation

**用途**: 通用邦联任务，可公开分享的任务 (重构、研究、文档)。

**实施**: 直接 `git push` JSON + 任务契约，所有邦联节点可见。

**风险**: 邦联外人员也能看到 (GitHub 公开仓)。非邦联成员可 fork 学习，但**不能 claim** (无 GPG 身份)。

### 1.2 L2: public-no-detail

**用途**: 任务标题/容量可见，但 body (业务逻辑) 加密。

**实施**:
- `title`: 通用化 (如 "[ENCRYPTED] Optimizer v2.0")
- `capacity_required`: 明文 (其他节点评估能力用)
- `contract`: 简化版 (只含验收命令)
- `body` (业务逻辑): AES-256-GCM 加密

**接收**: 任意邦联节点都有密钥，可解密 (邦联全员信任)。

### 1.3 L3: private-encrypted

**用途**: 高度敏感任务，仅指定节点可解密。

**实施**:
- `title`: 完全脱敏
- `encrypted_payload.recipient_node_id`: 明确指定 (如 "mac-mini")
- 加密密钥仅该节点持有 (用其 GPG 公钥加密的对称密钥)
- 其他邦联节点**可看到任务存在但无法解密**

---

## 二、 加密协议

### 2.1 加密流程 (Origin Node)

```python
# pseudocode
import json
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey

# 1. 生成 ephemeral 对称密钥
symmetric_key = os.urandom(32)  # AES-256
nonce = os.urandom(12)

# 2. 用对称密钥加密 body
aesgcm = AESGCM(symmetric_key)
plaintext = json.dumps(task_body).encode()
ciphertext = aesgcm.encrypt(nonce, plaintext, None)

# 3. 用收件节点公钥加密对称密钥
recipient_pubkey = load_pubkey(recipient_node_fpr)
encrypted_key = recipient_pubkey.encrypt(symmetric_key)

# 4. 写入 JSON
encrypted_payload = {
    "cipher": "AES-256-GCM",
    "encrypted_body": base64(ciphertext),
    "encrypted_key": base64(encrypted_key),  # 或用 GPG 包装
    "nonce": base64(nonce),
    "recipient_pubkey_fpr": recipient_node_fpr
}
```

### 2.2 解密流程 (Receiver Node)

```python
# pseudocode
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# 1. 用本地私钥解密对称密钥
private_key = load_private_key(local_node_fpr)
symmetric_key = private_key.decrypt(
    base64_decode(encrypted_payload["encrypted_key"])
)

# 2. 用对称密钥解密 body
aesgcm = AESGCM(symmetric_key)
plaintext = aesgcm.decrypt(
    base64_decode(encrypted_payload["nonce"]),
    base64_decode(encrypted_payload["encrypted_body"]),
    None
)

task_body = json.loads(plaintext)
```

---

## 三、 邦联密钥分发

### 3.1 GPG 公钥登记 (`members.md` + `bindings/<node>/pubkey.pem`)

```bash
# Origin Node: 生成 GPG 密钥对 (一次性)
gpg --full-generate-key --algorithm RSA --length 4096
gpg --armor --export <fpr> > bindings/henry-mac/pubkey.pem
git add bindings/henry-mac/
git commit -m "federation: register henry-mac GPG pubkey"
git push origin
```

### 3.2 密钥验证 (接入流程)

1. 新节点提 PR 添加 `bindings/<node>/pubkey.pem`
2. PR Reviewers 至少 2 人: 验证指纹 + 验证 Origin 签名
3. Approve 后 Merge 到 main
4. 该节点的公钥正式注册

### 3.3 密钥轮换

**频率**: 每 6 个月或密钥疑似泄露时。

**流程**:
1. 节点生成新密钥对
2. 旧密钥签名新公钥 (链式信任)
3. 提 PR 更新 `bindings/<node>/pubkey.pem`
4. Reviewers 验证链式签名后合并

---

## 四、 邦联任务分级模板

### L1 (public-federation) - 公开示例

```json
{
  "task_id": "t_a1b2c3d4",
  "title": "Refactor: extract kanban_db to standalone module",
  "privacy": "public-federation",
  "origin_node": "henry-mac",
  "engine_tier": "tier1-local-nuclear",
  "contract": {
    "acceptance": ["bash os/scripts/test_governance.sh"]
  }
  // ... body 全明文
}
```

### L2 (public-no-detail) - 元数据公开示例

```json
{
  "task_id": "t_e5f6g7h8",
  "title": "[ENCRYPTED] 商业策略优化器 v2.0",
  "privacy": "public-no-detail",
  "origin_node": "henry-mac",
  "engine_tier": "tier3-commercial-jet",
  "capacity_required": { "estimated_tokens": 100000, "estimated_walltime_min": 180 },
  "contract": {
    "acceptance": ["<decrypt-then-show>"]
  },
  "encrypted_payload": {
    "cipher": "AES-256-GCM",
    "encrypted_body": "base64-ciphertext...",
    "encrypted_key": "base64-wrapped-with-federation-pubkey...",
    "nonce": "base64-12bytes-nonce",
    "recipient_scope": "any-federation-member"
  }
}
```

### L3 (private-encrypted) - 单一节点示例

```json
{
  "task_id": "t_i9j0k1l2",
  "title": "[CONFIDENTIAL]",
  "privacy": "private-encrypted",
  "origin_node": "henry-mac",
  "engine_tier": "tier3-commercial-jet",
  "capacity_required": { "estimated_tokens": 50000, "estimated_walltime_min": 60 },
  "encrypted_payload": {
    "cipher": "AES-256-GCM",
    "encrypted_body": "base64-ciphertext...",
    "encrypted_key": "base64-wrapped-with-mac-mini-pubkey...",
    "nonce": "base64-12bytes-nonce",
    "recipient_node_id": "mac-mini",
    "recipient_pubkey_fpr": "ABCD1234EFGH5678..."
  }
}
```

---

## 五、 邦联合规边界

### 5.1 邦联成员可看不可做

- ✅ 看到 `queue/pending/*.json` 元数据
- ✅ 评估任务能力匹配度
- ❌ 解密 L3 任务 (除非你是指定 recipient_node_id)
- ❌ 修改 Origin 节点的任务契约

### 5.2 Origin 节点不泄漏本地敏感

- ❌ 邦联任务中**绝对禁止**:
  - 真实客户数据
  - 商业 Key (API tokens, passwords)
  - 财务数字
  - 内部 IP/域名 (除 `members.md` 已登记的)
- ✅ 邦联任务可以包含:
  - 任务标题 (脱敏)
  - 容量需求
  - 验收命令 (通用)
  - Worktree 内容 (脱敏后的代码)

### 5.3 违规处理

**铁律**: 任何邦联成员发现泄漏事故，必须：
1. **立即** 撤下泄漏文件 (git revert + force push)
2. **立即** 通知所有邦联成员 (members.md 中列出的 GPG 加密广播)
3. **24h 内** 提交 DEBT 记录到 `agentco/DEBT.md`
4. **72h 内** 仲裁委员会评估 + 决策 (是否吊销该节点成员资格)

---

## 六、 Phase 实施

### Phase 1 (当前)
- ✅ 隐私分级定义 (本 ADR)
- ⏸ 加密协议实现 (Phase 2)

### Phase 2
- 🔜 AES-256-GCM 加密工具实现
- 🔜 GPG 公钥分发机制
- 🔜 加密 payload schema 验证

### Phase 3
- 🔜 多节点密钥信任链建立
- 🔜 密钥轮换 SOP

---

## 七、 关联文档

- ADR-017: 邦联协同协议
- ADR-018: 邦联任务 JSON Schema (`encrypted_payload` 字段)
- ADR-019: Worktree 流转协议
- ADR-021: Phase 0 单节点 12 步清单

---

**AgentCo 架构委员会 · 2026-09-21**