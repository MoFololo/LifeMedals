# 开发进度记录（PROGRESS.md）

> 本文件是"进度日志"。每次完成任务后，请在下方对应 checklist 打勾，并在文末"更新日志"追加一条记录。**不要删除或改写历史记录，只追加。**

---

## 当前状态

**阶段**：Step 4 - 证据提交与 AI 核验（已完成）
**已完成**：AI 预先规划 1–5 张证据照片及描述；macOS 按 1 / 2 / 3–5 张切换提交布局并支持 PhotosPicker、本地文件、拖放和剪贴板；同批照片合并展示；压缩后 SwiftData 外部存储、三态核验、补交与失败重试；Worker 核验端点共用全局限流和月度硬预算且不持久化图片
**下一步该做什么**：进入 Step 5，实现 Verified 后的 EXP 入账、等级计算和 Library；同时保留 Step 1 的断网增删改查和重启持久化手动验证

> 2026-07-30 架构已调整为本地优先。下方 2026-07-29 的 Supabase 条目保留为历史记录，不代表当前技术方向；迁移完成后不再依赖 Supabase Postgres、Auth、Storage 或 Edge Functions。
>
> **v1 范围强调：CloudKit 不进入当前开发阶段。v1 不配置 CloudKit、不实现跨设备同步或同步状态 UI，也不做 CloudKit、跨设备、同步冲突、离线恢复等相关测试。v1 只验收单台 Mac 上的 SwiftData 本地持久化。**
>
> **v1 登录与付费边界：v1 只做一个可跳过、没有实际权限作用的登录页面，不接 Sign in with Apple，不创建真实账户。会员、StoreKit 订阅、entitlement、个人 AI 配额和账户删除全部推迟到 v2。登录或跳过不能影响 v1 的本地与 AI 功能。**

---

## 给接手的人 / AI 的说明

1. 开始写代码前先读 `README.md`（尤其是"关键设计原则"部分），必要时也读 `docs/product-plan.md`。
2. 每完成一个子任务，把对应的 `[ ]` 改成 `[x]`。
3. 不要跳着做——先完成 SwiftData 本地迁移，再继续 AI 功能；不要提前接入或测试 CloudKit。
4. 每次会话结束前，在"更新日志"里追加一条：日期 + 做了什么 + 涉及哪些文件/commit。
5. 如果发现某个子任务需要拆得更细，可以直接在对应 Step 下面加新的 `[ ]` 行。

---

## Roadmap 详细进度

### Step 0：基础环境与架构调整
- [x] 创建 GitHub 仓库
- [x] 编写 README.md
- [x] 编写 docs/product-plan.md
- [x] 建 Xcode 项目（macOS App target）
- [x] 明确采用 SwiftData 本地优先架构，CloudKit 推迟到 v1 之后
- [x] 明确 v1 后端只做最小 OpenAI Responses API 代理；账户、订阅和按用户用量网关推迟到 v2
- [x] 申请/确认 OpenAI API Key
- [x] 选定代理平台后，将 Key 仅以 `OPENAI_API_KEY` 配置到代理服务端加密环境变量/Secret
- [x] 更新或移除旧 `.env.example` 中的 Supabase 配置

### Step 1：SwiftData 本地模型与持久化
- [x] 定义 `BadgeCategory` SwiftData 模型
- [x] 定义 `UserBadge` SwiftData 模型
- [x] 定义 `TaskContract` SwiftData 模型
- [x] 定义 `Evidence` SwiftData 模型（图片使用外部存储）
- [x] 定义 `XPLog` SwiftData 模型
- [x] 在 App 中配置 SwiftData model container
- [ ] 验证断网时的本地增删改查与重启持久化（需在 Xcode/模拟器中手动验证）
- [x] 移除 Supabase Auth 登录门槛，让应用直接进入本地主界面
- [x] 移除 Supabase 客户端依赖、Secrets 配置与废弃代码
- [x] 确认迁移完成后再移除 `supabase/` 旧方案目录

### Step 2：登录占位页 + AI 代理 + 任务契约生成
- [x] 制作登录页面和跳过入口（只做 UI 占位，不接真实认证）
- [x] 确认登录或跳过后的功能完全相同，登录状态不参与任何权限判断
- [x] 选择 Cloudflare Workers，创建不保存业务数据的最小代理工程
- [x] 实现带输入与请求大小校验的 `generate-task` 端点
- [x] 设计 prompt 和 JSON Schema，使用 OpenAI Structured Outputs 返回 title / deadline / evidence_requirement / evidence_image_count / evidence_image_descriptions / suggested_badge / suggested_xp
- [x] 代理：用 SQLite Durable Object 加入原子全局限流（默认 20 次/分钟）
- [x] 代理：加入调用 OpenAI 前强制执行的月度硬请求上限（默认 500 次/月）
- [x] OpenAI 项目控制台：配置用量/支出告警（必须由项目所有者手动完成）
- [x] 客户端：输入框 + 调用代理
- [x] 客户端：渲染可编辑表单（标题/截止时间/验收标准/所属勋章都可改）
- [x] 客户端：确认按钮，确认后写入 SwiftData
- [x] 网络失败时保留输入并支持稍后重试

### Step 3：任务列表与本地提醒
- [x] SwiftUI 主界面：待办任务列表
- [x] 任务详情页（查看契约内容）
- [x] 截止时间本地通知（系统 Notification）

### Step 4：证据提交与 AI 核验
- [x] 客户端：macOS 支持 PhotosPicker、本地文件、拖放和 `⌘V` 粘贴；按 AI 规划的 1–5 张照片切换单槽、双槽和横向草稿栏，填满后再提交
- [x] 压缩并把证据副本保存到本地 SwiftData 外部存储
- [x] 写带全局限流和预算保护的 `verify-evidence` 端点
- [x] 确认证据图片只在请求期间处理，服务端不持久化
- [x] 设计 prompt：传入同批图片 + 锁定的 `evidence_requirement` + 照片数量与描述，返回三态结果 + 解释
- [x] 客户端：展示 Verified / Need More Proof / Not Verified
- [x] 客户端：`Need More Proof` 时支持补交证据
- [x] 把核验结果写回 SwiftData；失败时保留待核验记录以便重试

### Step 5：勋章与成就系统
- [ ] EXP 累加逻辑（写入 `XPLog`，更新 `UserBadge`）
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
- [ ] 验证登录页可跳过，且不会阻塞任何 v1 功能
- [ ] Mac App Store 上架素材（截图、描述等，如决定上架）

### Step 9：迁移到 iOS
- [ ] 加 iOS target
- [ ] 适配触屏交互（拍照直接上传等）
- [ ] 适配小屏布局

### v1 之后：CloudKit 同步（不属于当前 roadmap）

- [ ] 配置 iCloud / CloudKit capability 和 container
- [ ] 实现并展示同步状态与错误状态
- [ ] 验证 CloudKit 恢复联网后的自动同步
- [ ] 验证 Mac 与 iPhone 之间的跨设备同步
- [ ] 测试同步冲突、离线恢复和证据图片同步

> 上述任务在 v1 完成前不得开始，也不计入 v1 的开发进度或验收标准。

### v2：真实账户、会员与订阅（不属于当前 roadmap）

- [ ] 接入 Sign in with Apple capability、真实登录和安全会话
- [ ] 建立 `UserAccount` / `SubscriptionEntitlement` / `UsageLedger` 服务端模型
- [ ] 在 App Store Connect 配置 StoreKit 2 自动续期订阅产品
- [ ] 实现购买、恢复购买、交易更新监听和服务端 entitlement 验证
- [ ] 使用 `appAccountToken` 关联 LifeMedals 账户与 StoreKit 交易
- [ ] 定义免费版/会员版周期 AI 配额并实现按用户计量与限流
- [ ] 实现 App 内账户删除、服务端数据清理和 Sign in with Apple token 撤销
- [ ] 测试购买、续费、过期、退款、恢复购买、额度重置和超额拒绝
- [ ] 完成会员权益说明、订阅管理入口、隐私政策及数据删除说明

> v2 商业化任务不得提前进入 v1；v1 只需要把产品最基本闭环跑通。

---

## 更新日志

<!-- 每条记录格式：YYYY-MM-DD | 做了什么 | 涉及文件/commit -->

- 2026-07-31 | 升级多图证据计划：任务生成新增 1–5 张照片数量与描述（1–2 张逐张描述，3–5 张整组描述）；提交页新增单张大方框、双张独立方框和 3–5 张横向布局，每个槽位支持图库/本地文件并保留拖放粘贴；照片填满后按批次落库与核验，历史区将同批照片合并到一行，并兼容识别上一版毫秒级连续提交的多图记录。Worker 核验上限升至 5 张并校验照片计划；Worker 8 项测试、macOS Debug 编译通过 | TaskContract.swift, Evidence.swift, ContentView.swift, TaskGenerationService.swift, EvidenceSubmissionView.swift, EvidenceImageProcessor.swift, EvidenceVerificationService.swift, worker/src/index.ts, worker/test/usage-gate.test.mjs, README.md, docs/product-plan.md, docs/progress.md

- 2026-07-31 | 完成 Step 4 证据闭环：任务详情新增 Liquid Glass 证据区，支持 PhotosPicker 选图和 Mac 相机拍照；图片最长边压缩至 1800 px、单张约 1 MB 后写入 SwiftData `@Attribute(.externalStorage)`，失败时保留 Pending Verification 记录重试；新增 `verify-evidence`，与契约生成共用 Durable Object 全局限流/月度硬预算，在内存中转发最近最多 4 张证据并以 `store: false` 调用 Responses API，按锁定验收标准返回 Verified / Need More Proof / Not Verified 与解释；Need More Proof 支持补交。补充输入边界、Prompt/Schema、限流失败关闭和 no-store 测试；Worker 6 项测试、Wrangler dry-run、macOS Debug 编译通过 | LifeMedals/LifeMedals/ContentView.swift, EvidenceSubmissionView.swift, EvidenceCameraView.swift, EvidenceImageProcessor.swift, EvidenceVerificationService.swift, LifeMedals.xcodeproj/project.pbxproj, worker/src/index.ts, worker/test/usage-gate.test.mjs, README.md, docs/progress.md

- 2026-07-30 | 完成任务契约生成客户端：新增液态玻璃主界面、自然语言输入、代理调用、可编辑契约表单、确认后 SwiftData 写入；输入使用 AppStorage 本机保存，断网/超时后保留并支持重试。Worker 新增 SQLite Durable Object 全局限流与月度硬请求上限，保护异常时失败关闭；补充自动测试、部署配置与使用说明。Xcode Debug 编译、Worker 单元测试和 Wrangler dry-run 均通过；待部署 Worker、配置客户端 URL，并由项目所有者在 OpenAI 控制台设置支出告警 | LifeMedals/LifeMedals/ContentView.swift, TaskGenerationService.swift, LifeMedals.xcodeproj/project.pbxproj, worker/src/index.ts, worker/wrangler.jsonc, worker/test/usage-gate.test.mjs, worker/package.json, README.md, docs/progress.md

- 2026-07-30 | 创建 Cloudflare Worker 最小 OpenAI 代理：新增 Wrangler 工程配置、`GET /health` 与 `POST /generate-task`；服务端读取 `OPENAI_API_KEY`，调用 Responses API `gpt-5.6-terra` 并用 Structured Outputs 返回任务契约；加入请求大小/字段校验、超时与安全错误处理、`store: false`；Wrangler dry-run 与模拟请求测试通过，尚未部署或配置 Secret | worker/package.json, worker/package-lock.json, worker/wrangler.jsonc, worker/src/index.ts, README.md, docs/progress.md

- 2026-07-30 | 将当前 AI 方案从 Anthropic/Claude 迁移为 OpenAI Responses API：默认模型设为 `gpt-5.6-terra`，结构化结果改用 Structured Outputs，服务端密钥统一为 `OPENAI_API_KEY`；已确认 OpenAI API Key 申请完成，待选定代理平台后配置加密环境变量 | README.md, docs/product-plan.md, docs/progress.md, .env.example

- 2026-07-30 | 恢复登录页（重新实现为 v1 可跳过占位 UI，不接真实认证/账户，登录与跳过效果完全相同）；`LifeMedalsApp` 用本地 `@State` 控制展示 LoginView 或 ContentView，不做持久化、不影响 SwiftData/AI 功能；`xcodebuild` 编译通过 | LifeMedals/LifeMedals/LifeMedals/LoginView.swift, LifeMedalsApp.swift, docs/progress.md

- 2026-07-29 | 创建 GitHub 仓库，编写 README.md 和 docs/product-plan.md，创建本 PROGRESS.md | README.md, docs/product-plan.md, PROGRESS.md
- 2026-07-29 | 配置 .env.example，列出 SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY / OPENAI_API_KEY 等环境变量（含本地开发注释） | .env.example, docs/progress.md
- 2026-07-29 | 做登录 / 注册页面（SwiftUI，Liquid Glass 风格），接入 Supabase Auth（signIn/signUp/signOut/authStateChanges），新增 Secrets.swift（gitignored）管理本地密钥，App 根据登录状态在 LoginView / ContentView 间切换，本地 xcodebuild 编译通过 | LifeMedals/LifeMedals/LifeMedals/LoginView.swift, AuthViewModel.swift, SupabaseManager.swift, Secrets.swift, Secrets.example.txt, LifeMedalsApp.swift, ContentView.swift, .gitignore, docs/progress.md
- 2026-07-30 | 调整技术架构为 SwiftData 本地优先 + CloudKit 自动同步；取消应用登录和 Supabase 数据层；后端缩减为无状态 Claude API 代理，并重排开发路线 | README.md, docs/product-plan.md, docs/progress.md
- 2026-07-30 | 收紧 v1 范围：v1 只做 SwiftData 单设备本地持久化；CloudKit 接入、跨设备同步及全部相关测试推迟到 v1 之后 | README.md, docs/product-plan.md, docs/progress.md
- 2026-07-30 | 完成 Supabase → SwiftData 迁移：新增 `BadgeCategory`/`UserBadge`/`TaskContract`/`Evidence`/`XPLog` SwiftData 模型并接入 App 的 model container；移除 Supabase Auth 登录门槛、SupabaseManager、Secrets.swift/Secrets.example.txt、SPM 的 supabase-swift 包依赖（project.pbxproj、Package.resolved）以及旧 `supabase/migrations` 目录；`.env.example` 改为仅列出无状态 AI 代理所需的 `ANTHROPIC_API_KEY`；`xcodebuild` 编译通过 | LifeMedals/LifeMedals/LifeMedals/Models/BadgeCategory.swift, UserBadge.swift, TaskContract.swift, Evidence.swift, XPLog.swift, LifeMedalsApp.swift, ContentView.swift, LifeMedals/LifeMedals.xcodeproj/project.pbxproj, .env.example, .gitignore, docs/progress.md
- 2026-07-30 | 补充账户与商业化架构：本地功能游客可用，AI/会员功能使用 Sign in with Apple；StoreKit 2 管理订阅；后端改为最小化账户、entitlement、AI 用量与限流网关，仍不保存任务和证据；CloudKit 继续推迟到 v1 之后 | README.md, docs/product-plan.md, docs/progress.md
- 2026-07-30 | 再次收紧 v1：登录页仅作可跳过的 UI 占位且没有实际权限作用；Sign in with Apple、会员、StoreKit 订阅、entitlement 和个人 AI 配额全部推迟到 v2；v1 只跑通本地数据、AI 契约与证据核验闭环 | README.md, docs/product-plan.md, docs/progress.md

- 2026-07-31 | 完成 Step 3：任务页按截止时间展示 SwiftData 待办契约，支持逾期状态与 Liquid Glass 契约详情；新增 UserNotifications 本地截止提醒，保存未来任务时请求权限并按稳定任务 UUID 调度，应用启动后恢复/清理提醒，前台也显示系统横幅，权限拒绝或调度失败不影响任务保存；macOS Debug 构建通过 | LifeMedals/LifeMedals/ContentView.swift, LifeMedals/LifeMedals/TaskNotificationService.swift, docs/progress.md
