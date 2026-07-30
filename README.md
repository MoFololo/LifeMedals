# 人生勋章（LifeMedals）

**项目状态**：🚧 v1 开发中（已完成 SwiftData 本地存储迁移，Supabase 相关代码与目录已移除；CloudKit 暂不进入 v1）

---

## 产品简介

用户说一句话（比如"明天晚上10点前做两道LeetCode Medium"），AI 生成一份可编辑的"任务契约"（标题、截止时间、验收标准、所属勋章），用户确认后去执行；完成后提交证据（截图/照片），AI 核验通过后获得对应勋章的经验值，并存入可回顾的成就 Library。

## 核心产品闭环

```
说一句话
   → AI生成任务契约（标题/截止时间/验收标准/所属勋章，可编辑）
   → 用户确认
   → 执行任务
   → 提交证据
   → AI核验
   → 勋章 + EXP 到账
   → 存入 Library
```

---

## 技术栈

| 层 | 选型 | 说明 |
|---|---|---|
| 客户端 | SwiftUI（macOS App，target 未来复用到 iOS） | 单一 Swift 代码库，Mac/iOS 共享业务逻辑 |
| 本地数据 | SwiftData | 任务、证据、勋章、EXP 全部本地优先，核心功能离线可用 |
| 跨设备同步（v1 之后） | CloudKit | 长期方案；v1 不接入、不测试 |
| v1 登录页 | SwiftUI 占位页面 | 可跳过，不关联真实账户、权限或会员权益 |
| v1 AI 代理 | Cloudflare Workers / Vercel Functions | 只跑通 Claude 请求转发，以全局限流和预算上限保护内测成本 |
| v2 账户与订阅 | Sign in with Apple + StoreKit 2 | v2 再实现真实登录、购买、续费、恢复购买和 entitlement 校验 |
| v2 轻量后端 | AI 网关 + 小型持久化存储 | v2 再保存账户、订阅和 AI 用量；始终不存本地业务数据 |
| AI | Claude API（文本 + 多模态） | 任务契约生成 + 证据核验，两个独立调用场景 |

> 不使用 Supabase Postgres、Auth 或 Storage。**v1 不接入真实账户、会员或订阅系统；登录页只是可跳过的 UI 占位，不影响任何功能。** v1 只跑通 SwiftData、契约生成、证据核验、勋章和 Library 的最基本闭环，同时不配置或测试 CloudKit。

---

## 项目结构

```
LifeMedals/
├── README.md                        # 本文件
├── docs/
│   ├── product-plan.md              # 完整产品与技术计划书
│   └── progress.md                  # 开发进度与任务清单
└── LifeMedals/                      # Xcode 项目（SwiftUI，macOS target）
    ├── LifeMedals.xcodeproj/
    └── LifeMedals/
        ├── LifeMedalsApp.swift
        ├── ContentView.swift
        ├── Models/                  # SwiftData 模型（BadgeCategory / UserBadge / TaskContract / Evidence / XPLog）
        └── Assets.xcassets/
```

> Supabase 客户端代码、Secrets 配置和旧登录页已移除，`supabase/` 旧方案目录已删除。v1 会重新制作一个不承载真实账户能力的登录占位页；Sign in with Apple、StoreKit 和 CloudKit 均推迟到 v2。

---

## 数据模型（v1）

v1 业务数据只保存在当前设备的 SwiftData 本地数据库中：

- `BadgeCategory`：默认或自定义勋章类别。
- `UserBadge`：每个类别独立累计的 EXP 和等级。
- `TaskContract`：标题、截止时间、锁定的验收标准、所属勋章、XP 奖励和状态。
- `Evidence`：本地证据图片、提交时间、AI 三态核验结果和解释。
- `XPLog`：关联任务与勋章的 EXP 变动记录。

所有模型使用稳定 UUID。证据图片先保存到本地，并使用适合大字段的外部存储方式；后端不会持久化图片或上述模型数据。模型设计尽量为未来 CloudKit 同步保留兼容性，但这不是 v1 的开发或验收内容。

以下服务端控制数据是 **v2 规划**，不在 v1 创建：

- `UserAccount`：Sign in with Apple 对应的 LifeMedals 用户标识。
- `SubscriptionEntitlement`：StoreKit 原始交易 ID、产品、状态和有效期。
- `UsageLedger`：当前计费周期内的 AI 生成/核验用量。

即使进入 v2，服务端账户也不能读取用户的任务、勋章、XP 或 Library；证据图片仅在核验请求期间短暂转发给 Claude，不做持久化。

---

## v1 功能范围

### ✅ 包含
- SwiftData 本地持久化，离线创建、编辑和浏览任务
- 一个可跳过的登录页面，仅用于预留未来入口；v1 不接真实账户，登录与否不改变功能
- 自然语言输入 → AI 生成任务契约 → 用户可编辑（标题/截止时间/验收标准/所属勋章）→ 确认
- 支持四类任务：LeetCode/课程学习、项目开发、投递求职申请、健身/运动
- 提交截图证据 → AI 核验 → 返回 Verified / Need More Proof / Not Verified
- 勋章体系：默认几个类别，EXP 累加，等级显示
- Library：按勋章分类回顾历史任务和证据
- 截止前本地通知提醒

### ❌ v1 明确不做（留到 v2+）
- 订机票等涉及个人隐私信息的任务类型
- 任何形式的防作弊机制（GPS、实时拍摄水印等）
- 社交功能：好友、排行榜、监督
- 金钱惩罚机制
- 通用 AI 聊天助手
- iOS 客户端（先把 Mac 做完）
- CloudKit 接入、iCloud 状态 UI、跨设备同步及其相关测试
- Sign in with Apple 真实账户体系、会话和账户删除
- StoreKit 2 会员订阅、购买、续费、退款和恢复购买
- entitlement 校验、免费/会员 AI 配额、用量计费和会员权限控制

---

## 关键设计原则（写代码时必须遵守）

1. **验收标准锁定**：任务一旦被用户确认，`evidence_requirement` 不可再被 AI 在核验阶段修改或重新解释。核验只能基于确认时锁定的标准。
2. **三态核验结果**：AI 核验结果永远是 `Verified / Need More Proof / Not Verified` 三选一，不做强制二选一，`Need More Proof` 时允许用户补交证据。
3. **证据要轻量**：设计每类任务默认的证据要求时，优先选用户本来就会产生的东西（如 LeetCode 的 Accepted 截图），不要为了"证明"而制造额外负担。
4. **每个勋章类别独立计算 EXP/等级**，不要把所有类别合并成一个总等级。
5. **v1 纯本地优先**：本地增删改查、Library、EXP 和通知不依赖网络；AI 请求可稍后重试且不能导致本地数据丢失。CloudKit 不属于 v1。
6. **v1 登录页没有业务权限**：登录页必须允许跳过，不连接 Sign in with Apple，不区分免费/会员，也不能阻塞本地或 AI 主链路；它只是为 v2 预留产品入口。
7. **v1 只验证闭环**：AI 代理不做账户、订阅或个人额度系统，仅用全局限流、内测范围、Anthropic 用量告警和预算上限控制成本，不作为可公开扩张的商业架构。
8. **v2 再做商业化**：Sign in with Apple、StoreKit、entitlement、周期 AI 配额和账户删除全部在 v2 实现；届时后端仍只保存账户/计费控制数据，不保存任务或证据。

---

## 当前开发阶段（Roadmap）

> 详细进度见 [`docs/progress.md`](./docs/progress.md)，这里只列各阶段概览。

- [x] **Step 0：Xcode 项目与基础环境**
- [ ] **Step 1：SwiftData 本地模型与持久化** 👈 **当前进行中**
  - ✅ 移除 Supabase Auth 登录门槛和客户端依赖
  - ✅ 建立 SwiftData 核心模型与本地持久化（model container 已接入）
  - 待办：在 Xcode/模拟器中手动验证单设备离线读写与重启后的持久化
- [ ] **Step 2：登录占位页 + AI 代理 + 任务契约生成**
  - 制作可跳过的登录页面，不接真实账户，不影响任何功能
  - 部署最小 `generate-task` 代理，通过全局限流和预算上限保护内测
  - 客户端渲染可编辑表单，确认后写入 SwiftData
- [ ] Step 3：任务列表与本地提醒
- [ ] Step 4：证据提交与 AI 核验
- [ ] Step 5：勋章与成就系统
- [ ] Step 6：自用内测（至少 1-2 周）
- [ ] Step 7：小范围内测（5-10 人）
- [ ] Step 8：打磨与上架准备
- [ ] Step 9：迁移到 iOS

---

## 本地运行

```bash
# 1. 克隆仓库
git clone https://github.com/yourusername/LifeMedals.git

# 2. 在 Xcode 打开项目
open LifeMedals/LifeMedals.xcodeproj

# 3. 直接运行；v1 不需要配置 iCloud / CloudKit
```

> Claude API Key 只配置在 Cloudflare Worker / Vercel Function 的服务端环境变量中，禁止写入客户端或提交到 Git。v1 使用全局限流、有限内测和预算上限控制调用；按账户验证订阅与额度的能力推迟到 v2。

---

## 参考文档

- 完整产品与技术计划书：[`docs/product-plan.md`](./docs/product-plan.md)
- Apple：[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Apple：[在 App 内提供账户删除](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
