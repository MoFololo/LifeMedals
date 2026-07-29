# 开发进度记录（PROGRESS.md）

> 本文件是"进度日志"。每次完成任务后，请在下方对应 checklist 打勾，并在文末"更新日志"追加一条记录。**不要删除或改写历史记录，只追加。**

---

## 当前状态

**阶段**：Step 0 - 环境搭建（尚未开始具体搭建）
**已完成**：仅创建 GitHub 仓库 + 编写 README.md / docs/product-plan.md
**下一步该做什么**：见下方 "Step 0" 里第一个未勾选的子任务

---

## 给接手的人 / AI 的说明

1. 开始写代码前先读 `README.md`（尤其是"关键设计原则"部分），必要时也读 `docs/product-plan.md`。
2. 每完成一个子任务，把对应的 `[ ]` 改成 `[x]`。
3. 不要跳着做——按 Step 顺序推进，不要提前实现后面 Step 的功能。
4. 每次会话结束前，在"更新日志"里追加一条：日期 + 做了什么 + 涉及哪些文件/commit。
5. 如果发现某个子任务需要拆得更细，可以直接在对应 Step 下面加新的 `[ ]` 行。

---

## Roadmap 详细进度

### Step 0：环境搭建 👈 当前阶段
- [x] 创建 GitHub 仓库
- [x] 编写 README.md
- [x] 编写 docs/product-plan.md
- [ ] 建 Xcode 项目（macOS App target）
- [ ] 建 Supabase 项目，拿到 Project URL / anon key
- [ ] 申请 Anthropic API Key
- [ ] 配置 `.env.example`（列出需要哪些环境变量，但不填真实值）
- [ ] 把 Anthropic API Key 配置到 Supabase Edge Function 环境变量（确认没有写进客户端代码或提交到 git）

### Step 1：数据模型 + 登录
- [ ] 在 Supabase 建 `badge_categories` 表
- [ ] 在 Supabase 建 `user_badges` 表
- [ ] 在 Supabase 建 `tasks` 表
- [ ] 在 Supabase 建 `evidence` 表
- [ ] 在 Supabase 建 `xp_logs` 表
- [ ] 把上述表结构存成 `supabase/migrations/` 里的 SQL 文件
- [ ] 客户端接入 Supabase Auth
- [ ] 做登录 / 注册页面（SwiftUI）

### Step 2：自然语言生成任务契约
- [ ] 写 `supabase/functions/generate-task` Edge Function
- [ ] 设计 prompt，要求 Claude 严格返回 JSON（title / deadline / evidence_requirement / suggested_badge / suggested_xp）
- [ ] 客户端：输入框 + 调用该 function
- [ ] 客户端：渲染可编辑表单（标题/截止时间/验收标准/所属勋章都可改）
- [ ] 客户端：确认按钮，确认后写入 `tasks` 表

### Step 3：任务列表与本地提醒
- [ ] SwiftUI 主界面：待办任务列表
- [ ] 任务详情页（查看契约内容）
- [ ] 截止时间本地通知（系统 Notification）

### Step 4：证据提交与 AI 核验
- [ ] 客户端：PhotosPicker 选图 / 拍照
- [ ] 图片上传到 Supabase Storage
- [ ] 写 `supabase/functions/verify-evidence` Edge Function
- [ ] 设计 prompt：传入图片 + 锁定的 `evidence_requirement`，返回三态结果 + 解释
- [ ] 客户端：展示 Verified / Need More Proof / Not Verified
- [ ] 客户端：`Need More Proof` 时支持补交证据

### Step 5：勋章与成就系统
- [ ] EXP 累加逻辑（写入 `xp_logs`，更新 `user_badges`）
- [ ] 等级计算逻辑
- [ ] Library 页面：按勋章分类回顾历史任务和证据截图
- [ ] 首页周小结（本周完成率、连续天数、勋章进度条）

### Step 6：自用内测（至少 1-2 周）
- [ ] 自己每天用起来记录任务
- [ ] 记录："契约生成准不准" 的问题案例
- [ ] 记录："证据要求是否太麻烦" 的问题案例
- [ ] 记录："完成后反馈是否有动力感" 的主观感受

### Step 7：小范围内测（5-10 人）
- [ ] 找到 5-10 名测试用户
- [ ] 收集"AI生成验收标准是否合理"的反馈
- [ ] 收集"AI误判率"的反馈
- [ ] 汇总问题清单，决定哪些进 v1.1

### Step 8：打磨与上架准备
- [ ] UI 细节打磨
- [ ] 补充空状态 / 错误态页面
- [ ] Mac App Store 上架素材（截图、描述等，如决定上架）

### Step 9：迁移到 iOS
- [ ] 加 iOS target
- [ ] 适配触屏交互（拍照直接上传等）
- [ ] 适配小屏布局

---

## 更新日志

<!-- 每条记录格式：YYYY-MM-DD | 做了什么 | 涉及文件/commit -->

- 2026-07-29 | 创建 GitHub 仓库，编写 README.md 和 docs/product-plan.md，创建本 PROGRESS.md | README.md, docs/product-plan.md, PROGRESS.md