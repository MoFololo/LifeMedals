# 人生勋章（LifeMedals）

**项目状态**：🚧 v1 开发中（Step 1 数据模型已完成，Step 2 进行中）

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
| 后端 | Supabase（Postgres + Auth + Storage + Edge Functions） | v1 优先用托管方案，跑通产品逻辑；不自建服务器 |
| AI | OpenAI API（文本 + 多模态） | 任务契约生成 + 证据核验，两个独立调用场景 |

> 后端未来可能迁移到自建 FastAPI/Node + PostgreSQL + 队列，但**这是 v2 以后的事，v1 不做**。

---

## 项目结构

```
LifeMedals/
├── README.md                        # 本文件
├── docs/
│   ├── product-plan.md              # 完整产品与技术计划书
│   └── progress.md                  # 开发进度与任务清单
├── LifeMedals/                      # Xcode 项目（SwiftUI，macOS target）
│   ├── LifeMedals.xcodeproj/
│   └── LifeMedals/
│       ├── LifeMedalsApp.swift
│       ├── ContentView.swift
│       └── Assets.xcassets/
└── supabase/
    └── migrations/
        └── 20260729000000_init_schema.sql   # 数据库表结构 SQL
```

> `supabase/functions/`（Edge Functions）将在 Step 2 开始后创建。

---

## 数据模型（v1）

表结构已落库（见 `supabase/migrations/20260729000000_init_schema.sql`）。

```sql
-- 用户由 Supabase Auth 自带的 auth.users 提供，这里只列业务表

-- 全局固定，仅 service_role 可写，登录用户只读
badge_categories (
  id         uuid primary key,
  name       text,        -- 如 "Problem Solver"
  icon       text,
  created_at timestamptz
)
-- 默认种类：Problem Solver 🧩 / Builder 🔨 / Career 💼 / Athlete 🏃 / Scholar 📚

user_badges (
  id                 uuid primary key,
  user_id            uuid references auth.users,
  badge_category_id  uuid references badge_categories,
  current_xp         int default 0,
  level              int default 1,
  updated_at         timestamptz
)

tasks (
  id                    uuid primary key,
  user_id               uuid references auth.users,
  title                 text,
  deadline              timestamptz,
  evidence_requirement  text,   -- AI生成、用户确认后锁定，核验阶段不可修改
  badge_category_id     uuid references badge_categories,
  xp_reward             int,
  status                text,   -- pending | completed | expired
  created_at            timestamptz
)

-- 仅存 AI 核验通过的证据；核验失败时只向用户展示原因，不入库
evidence (
  id           uuid primary key,
  task_id      uuid references tasks,
  image_url    text,
  submitted_at timestamptz
)

xp_logs (
  id                 uuid primary key,
  user_id            uuid references auth.users,
  badge_category_id  uuid references badge_categories,
  task_id            uuid references tasks,
  xp_change          int,
  created_at         timestamptz
)
```

---

## v1 功能范围

### ✅ 包含
- 登录 / 注册（Supabase Auth）
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

---

## 关键设计原则（写代码时必须遵守）

1. **验收标准锁定**：任务一旦被用户确认，`evidence_requirement` 不可再被 AI 在核验阶段修改或重新解释。核验只能基于确认时锁定的标准。
2. **三态核验结果**：AI 核验结果永远是 `Verified / Need More Proof / Not Verified` 三选一，不做强制二选一，`Need More Proof` 时允许用户补交证据。
3. **证据要轻量**：设计每类任务默认的证据要求时，优先选用户本来就会产生的东西（如 LeetCode 的 Accepted 截图），不要为了"证明"而制造额外负担。
4. **每个勋章类别独立计算 EXP/等级**，不要把所有类别合并成一个总等级。

---

## 当前开发阶段（Roadmap）

> 详细进度见 [`docs/progress.md`](./docs/progress.md)，这里只列各阶段概览。

- [x] **Step 0：环境搭建**（已完成）
- [x] **Step 1：数据模型 + Supabase Auth 接入**（DB 表已建，登录 UI 进行中）
- [ ] **Step 2：自然语言生成任务契约** 👈 **当前进行中**
  - 写 `supabase/functions/generate-task`，调用 OpenAI API，严格返回 JSON
  - 客户端渲染可编辑表单 + 确认按钮
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

# 3. 配置 Supabase URL / anon key（在 Xcode Scheme 或 .xcconfig 中设置，不要提交进 git）

# 4. 本地运行 Edge Functions（需要 Supabase CLI）
supabase functions serve
```

> Edge Functions 源码将在 Step 2 完成后添加至 `supabase/functions/`。

---

## 参考文档

- 完整产品与技术计划书：[`docs/product-plan.md`](./docs/product-plan.md)