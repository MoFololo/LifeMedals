# 人生勋章（LifeMedals）

**项目状态**：🚧 v1 开发中（MVP 阶段，尚未有可运行版本）

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
   → AI核验（Verified / Need More Proof / Not Verified）
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

## 建议的项目结构

```
repo/
├── README.md                  # 本文件
├── docs/
│   └── product-plan.md        # 完整产品与技术计划书
├── ProofApp/                  # Xcode 项目（SwiftUI，macOS target）
│   ├── ProofApp.xcodeproj
│   ├── Sources/
│   │   ├── Models/            # Task, Evidence, Badge 等数据模型
│   │   ├── Views/             # 任务列表、契约确认表单、Library等
│   │   ├── Networking/        # 调用 Supabase / Edge Functions 的封装
│   │   └── App.swift
├── supabase/
│   ├── functions/
│   │   ├── generate-task/     # 一句话 → 任务契约 JSON
│   │   └── verify-evidence/   # 图片+验收标准 → 核验结果 JSON
│   └── migrations/            # 数据库表结构 SQL
└── .env.example
```

---

## 数据模型（v1）

```sql
-- 用户由 Supabase Auth 自带的 auth.users 提供，这里只列业务表

badge_categories (
  id            uuid primary key,
  user_id       uuid references auth.users,   -- 允许用户自定义类别
  name          text,        -- 如 "Problem Solver"
  icon          text
)

user_badges (
  id                 uuid primary key,
  user_id            uuid references auth.users,
  badge_category_id  uuid references badge_categories,
  current_xp         int default 0,
  level              int default 1
)

tasks (
  id                    uuid primary key,
  user_id               uuid references auth.users,
  title                 text,
  deadline              timestamptz,
  evidence_requirement  text,        -- AI生成、用户确认后锁定，之后不可被AI临时更改
  badge_category_id     uuid references badge_categories,
  xp_reward             int,
  status                text,        -- pending | verified | need_more_proof | not_verified | expired
  created_at            timestamptz default now()
)

evidence (
  id            uuid primary key,
  task_id       uuid references tasks,
  image_url     text,
  ai_verdict    text,        -- Verified | Need More Proof | Not Verified
  ai_explanation text,
  submitted_at  timestamptz default now()
)

xp_logs (
  id                 uuid primary key,
  user_id            uuid references auth.users,
  badge_category_id  uuid references badge_categories,
  task_id            uuid references tasks,
  xp_change          int,
  created_at         timestamptz default now()
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

> 每完成一步，请在这里勾选并更新"当前进行中"标记，方便下一个协作者（人或AI）接手。

- [ ] **Step 0：环境搭建** 👈 **当前进行中**
  - 建 Xcode 项目（macOS target）
  - 建 Supabase 项目，拿到 URL / anon key
  - 申请 Anthropic API Key，配置到 Supabase Edge Function 的环境变量（不要放进客户端代码）
- [ ] Step 1：数据模型 + 登录
  - 在 Supabase 建好上面列出的表和 migration
  - 客户端接入 Supabase Auth，做登录/注册页
- [ ] Step 2：自然语言生成任务契约
  - 写 `supabase/functions/generate-task`，调用 Claude API，严格要求返回 JSON
  - 客户端渲染可编辑表单 + 确认按钮
- [ ] Step 3：任务列表与本地提醒
  - SwiftUI 主界面 + 截止时间本地通知
- [ ] Step 4：证据提交与 AI 核验
  - 图片上传到 Supabase Storage
  - 写 `supabase/functions/verify-evidence`
  - 客户端展示三态核验结果
- [ ] Step 5：勋章与成就系统
  - EXP/等级计算逻辑
  - Library 页面 + 每周小结
- [ ] Step 6：自用内测（至少 1-2 周）
- [ ] Step 7：小范围内测（5-10 人）
- [ ] Step 8：打磨与上架准备
- [ ] Step 9：迁移到 iOS

---

## 本地运行（占位，代码搭建后补全）

```bash
# TODO: Step 0 完成后补充
# 1. 克隆仓库
# 2. cp .env.example .env，填入 Supabase URL / anon key
# 3. 用 Xcode 打开 ProofApp.xcodeproj 运行
# 4. supabase functions serve 本地跑 Edge Functions（需要 Supabase CLI）
```

---

## 参考文档

- 完整产品与技术计划书：[`docs/product-plan.md`](./docs/product-plan.md)