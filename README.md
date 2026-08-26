# 人生勋章（LifeMedals）

**项目状态**：🚧 iOS v2 客户端“任务怪物与怪物图鉴”闭环已实现并通过模拟器测试；Cloudflare 全球素材服务仍待后续服务端阶段接入

---

## 产品简介

用户说一句话（比如"明天晚上10点前做两道LeetCode Medium"），或上传邮件、syllabus、活动海报等图片，AI 从中生成一份可编辑的"任务契约"（标题、截止时间、验收标准、所属勋章）；用户确认后去执行，完成后提交证据（截图/照片），AI 核验通过后获得对应勋章的经验值，并存入可回顾的成就 Library。图片生成的任务会保留压缩后的来源图，方便之后在任务详情中回看上下文。

## 核心产品闭环

```
说一句话
   → AI生成任务契约（标题/截止时间/验收标准/所属勋章，可编辑）
   → 用户确认
   → 执行任务
   → 提交证据
   → AI核验
   → 发现/再次击败任务怪物
   → 勋章 + EXP 到账
   → 存入成就（勋章 Library + 怪物图鉴）
```

---

## 技术栈

| 层 | 选型 | 说明 |
|---|---|---|
| 客户端 | SwiftUI 多平台 App（macOS + iOS/iPadOS） | 单一 target 与 Swift 代码库，平台 API 由小型适配层隔离 |
| 本地数据 | SwiftData | 任务、证据、勋章、EXP 全部本地优先，核心功能离线可用 |
| 跨设备同步 | SwiftData + CloudKit | Mac 与 iPhone 使用同一 iCloud 私有容器；待付费团队完成真机跨设备验收 |
| 应用登录 | Sign in with Apple | 使用系统登录 UI，稳定标识保存在钥匙串；与 iCloud 同步身份分工明确 |
| v1 AI 代理 | Cloudflare Workers / Vercel Functions | 只跑通 OpenAI Responses API 请求转发，以全局限流和预算上限保护内测成本 |
| v2 订阅 | StoreKit 2 | v2 再实现购买、续费、恢复购买和 entitlement 校验 |
| v2 轻量后端 | AI 网关 + 小型持久化存储 | v2 再保存账户、订阅和 AI 用量；始终不存本地业务数据 |
| AI | OpenAI Responses API（`gpt-5.6-terra`，文本 + 图像输入） | 任务契约生成 + 证据核验，两个独立调用场景；使用 Structured Outputs 约束返回结构 |

> 不使用 Supabase Postgres、Auth 或 Storage。Apple 登录只建立应用会话，CloudKit 使用设备上的 iCloud 账户同步私有业务数据；两者技术上彼此独立。会员和订阅仍不属于当前范围。

---

## 项目结构

```
LifeMedals/
├── README.md                        # 本文件
├── docs/
│   ├── product-plan.md              # 完整产品与技术计划书
│   └── progress.md                  # 开发进度与任务清单
└── LifeMedals/                      # Xcode 项目（SwiftUI macOS+iOS 多平台 target）
    ├── LifeMedals.xcodeproj/
    └── LifeMedals/
        ├── LifeMedalsApp.swift
        ├── ContentView.swift
        ├── Models/                  # SwiftData 模型（BadgeCategory / UserBadge / TaskContract / Evidence / XPLog）
        └── Assets.xcassets/
```

> Supabase 客户端代码、Secrets 配置和旧方案目录已删除。当前 macOS target 已配置 Sign in with Apple 与 `iCloud.noorg.LifeMedals` CloudKit 容器。

---

## 数据模型（v1）

业务数据先写入当前设备的 SwiftData 数据库，并由 CloudKit 自动镜像到用户的 iCloud 私有数据库：

- `BadgeCategory`：默认或自定义勋章类别。
- `UserBadge`：每个类别独立累计的 EXP 和等级。
- `TaskContract`：标题、截止时间、锁定的验收标准、1–5 张证据照片计划、可选的任务来源图片、所属勋章、XP 奖励和状态。
- `TaskContract` 的可选怪物字段：canonical tag、保存时锁定的 1–9 级、variant ID、图片 URL 和 style version；怪物不再保存或展示名字，旧任务全部为 `nil` 时继续按原流程运行。
- `MonsterDiscovery`：用户私有的 tag + level + styleVersion 发现元数据、首次来源任务和击败次数；应用逻辑使用已处理任务 ID 防止重复核验回调重复计数。
- `Evidence`：本地证据图片、提交批次与顺序、提交时间、AI 三态核验结果和解释。
- `XPLog`：关联任务与勋章的 EXP 变动记录。

所有模型使用稳定 UUID。证据图片先保存到本地，并使用适合大字段的外部存储方式；SwiftData/CloudKit 负责同步，AI 代理不会持久化图片或上述模型数据。模型已移除 CloudKit 不支持的唯一约束，并将关系调整为可选。

### iOS v2：任务怪物与怪物图鉴

- 任务生成响应可为单任务和每个 child task 返回 `monster_tag` 和 `monster_match_kind`。taxonomy 永远使用英文；即使用户输入中文，也会先归类并翻译成可复用的英文 tag。明确命名的运动会保留为独立物种，例如 `sports.basketball`、`sports.baseball`、`sports.tennis` 和 `sports.swimming`；`fitness.workout` 只表示健身房、力量训练或一般锻炼。Worker 与 iOS 兼容回退层都会阻止具体运动被压扁成健身怪物。
- 用户在确认页最终选择勋章后，客户端读取该勋章当时的 `BadgeRank.rawValue` 并把 `monsterLevel` 锁入任务。该任务随后获得 EXP 并升级也不会改变本次遭遇等级。任务组父容器没有怪物，每个可独立核验的 child task 单独分配。
- 任务确认页会立即用 tag + 当前勋章等级查询全球素材：ready 时预览对应怪物，缺失、生成中或服务不可用时显示本地未知轮廓，并在后台调用 ensure。保存后的未完成任务继续隐藏素材；核验为 Verified 时会再次刷新，先原子保存任务、发现记录和 EXP，再播放怪物揭晓，之后才播放原有勋章/EXP 动画。Reduce Motion 使用淡入淡出。
- 顶级“勋章”导航已演进为“成就”，内部保留“勋章”并新增“怪物图鉴”。图鉴仅查询用户自己的 `MonsterDiscovery`，按物种展示 1–9 级路线，未发现等级保持锁定。
- 客户端只向 `POST /monster-variants/ensure` 发送规范化 tag、badge kind 和 level，并通过 `GET /monster-variants/{tag}/{level}` 刷新状态；不接受怪物名、自定义生图 Prompt，也不包含 OpenAI Key、Cloudflare Token 或 R2 管理凭证。图片使用公开 HTTPS URL，并在浏览后写入 iOS Caches 目录供离线回看。
- `monster_aliases` 只接受小写英文 alias。新物种 ID 固定为 `species-[medaltype]-[description]`；description 优先使用一个最简单的单词，确需两个单词时直接连接，不增加额外连字符，例如 `species-career-email` 和 `species-career-jobsearch`。
- 怪物概念必须先选出 1–2 个与 canonical tag 强关联的具体物品或材料，再把每一个锚点强制融入身体、主轮廓或穿戴/手持装备；背景暗示不算包含。完整规则见 [`docs/monster-image-spec.md`](docs/monster-image-spec.md)。
- ensure、轮询或图片下载失败不阻止本地保存、提醒、证据核验、EXP 或发现记录；图片未 ready 时先把未知怪物收入图鉴，图鉴会继续轮询并在 ready 后替换为真实图片。

全球素材服务继续按“D1 只存通用物种/variant 元数据、R2 只存系统生成图片、Queue 异步幂等生成”的边界实现；不得把用户身份、任务、证据、XP 或个人发现写入这些全局资源。GPT Image 2 调用和 Prompt 模板只存在于 Worker，`OPENAI_API_KEY` 继续只使用 Worker Secret。具体上线顺序见 [`docs/monster-service-runbook.md`](docs/monster-service-runbook.md)。

以下服务端控制数据是 **v2 规划**，不在 v1 创建：

- `UserAccount`：Sign in with Apple 对应的 LifeMedals 用户标识。
- `SubscriptionEntitlement`：StoreKit 原始交易 ID、产品、状态和有效期。
- `UsageLedger`：当前计费周期内的 AI 生成/核验用量。

即使进入 v2，服务端账户也不能读取用户的任务、勋章、XP 或 Library；证据图片仅在核验请求期间短暂转发给 OpenAI Responses API，不做持久化。

---

## v1 功能范围

### ✅ 包含
- SwiftData 本地持久化，离线创建、编辑和浏览任务
- 系统 Sign in with Apple 登录、钥匙串会话保存与撤销状态检查；允许离线进入
- iCloud 私有数据库自动同步、账户状态和同步事件状态 UI
- 自然语言输入 → AI 生成任务契约 → 用户可编辑（标题/截止时间/验收标准/所属勋章）→ 确认
- 邮件、课程资料或活动海报图片 → AI 提取明确下一步 → 保留来源图供任务详情回看
- 支持五类勋章：解题、创造、职业、运动和生活；家务、游戏、个人爱好、寄快递、烹饪等默认归入生活，运动始终归入运动
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
- iOS 上架素材与 TestFlight/App Review（基础客户端已开始迁移）
- 服务端账户删除与 Sign in with Apple token 撤销（当前没有 LifeMedals 账户后端）
- StoreKit 2 会员订阅、购买、续费、退款和恢复购买
- entitlement 校验、免费/会员 AI 配额、用量计费和会员权限控制

---

## 关键设计原则（写代码时必须遵守）

1. **验收标准锁定**：任务一旦被用户确认，`evidence_requirement` 不可再被 AI 在核验阶段修改或重新解释。核验只能基于确认时锁定的标准。
2. **三态核验结果**：AI 核验结果永远是 `Verified / Need More Proof / Not Verified` 三选一，不做强制二选一，`Need More Proof` 时允许用户补交证据。
3. **证据要轻量**：设计每类任务默认的证据要求时，优先选用户本来就会产生的东西（如 LeetCode 的 Accepted 截图），不要为了"证明"而制造额外负担。
4. **每个勋章类别独立计算 EXP/等级**，不要把所有类别合并成一个总等级。
5. **本地优先同步**：本地增删改查、Library、EXP 和通知不依赖网络；CloudKit 与 AI 请求失败都不能导致本地数据丢失。
6. **身份职责分离**：Sign in with Apple 负责应用会话，设备 iCloud 账户负责 CloudKit，同步不可用时允许离线使用；登录不代表会员权益。
7. **v1 只验证闭环**：AI 代理不做账户、订阅或个人额度系统，仅用全局限流、内测范围、OpenAI 项目用量/支出告警和代理端硬预算上限控制成本，不作为可公开扩张的商业架构。
8. **v2 再做商业化**：服务端账户体系、StoreKit、entitlement、周期 AI 配额和账户删除全部在 v2 实现；届时后端仍只保存账户/计费控制数据，不保存任务或证据。

---

## 当前开发阶段（Roadmap）

> 详细进度见 [`docs/progress.md`](./docs/progress.md)，这里只列各阶段概览。

- [x] **Step 0：Xcode 项目与基础环境**
- [ ] **Step 1：SwiftData 本地模型与持久化**
  - ✅ 移除 Supabase Auth 登录门槛和客户端依赖
  - ✅ 建立 SwiftData 核心模型与本地持久化（model container 已接入）
  - 待办：在 Xcode/模拟器中手动验证单设备离线读写与重启后的持久化
- [ ] **Step 2：Apple 登录 + AI 代理 + 任务契约生成**
  - ✅ 接入 Sign in with Apple、钥匙串会话与可跳过的离线入口
  - ✅ `generate-task` 代理已加入全局限流和每月硬调用上限，待部署并在 OpenAI 控制台设置支出告警
  - ✅ 客户端已支持自然语言输入、失败重试、可编辑契约和确认后写入 SwiftData
- [x] **Step 3：任务列表与本地提醒**
- [x] **Step 4：证据提交与 AI 核验** 👈 **当前已完成**
- [x] Step 5：勋章与成就系统
- [ ] Step 6：自用内测（至少 1-2 周）
- [ ] Step 7：小范围内测（5-10 人）
- [ ] Step 8：打磨与上架准备
- [ ] Step 9：迁移到 iOS（多平台 target、首轮 API/布局适配和双平台编译已完成；待真机与跨设备验收）
- [ ] **Step 10：macOS CloudKit 基础接入**（兼容 schema、登录和状态 UI 已完成；开发者后台激活受付费团队资格阻塞）

---

## 本地运行

```bash
# 1. 克隆仓库
git clone https://github.com/yourusername/LifeMedals.git

# 2. 在 Xcode 打开项目
open LifeMedals/LifeMedals.xcodeproj

# 3. Scheme 选择 LifeMedals，再选择 My Mac 或任一 iPhone Simulator 运行
#    Debug 默认进入本地开发模式，不需要付费开发者团队
```

Debug 默认定义 `LIFEMEDALS_LOCAL_DEVELOPMENT`：使用本机 SwiftData、不给构建附加云端 entitlements，并在界面中关闭 Apple 登录与 CloudKit，因此免费 Personal Team 可以直接编译运行。Release 保留完整云端配置，容器标识固定为 `iCloud.noorg.LifeMedals`；要运行或分发云端版本，仍需加入 Apple Developer Program，在 Xcode 中选择付费团队并创建描述文件。云端开发环境验证后，还需在 CloudKit Console 将 schema 发布到 Production。

### OpenAI API Key：只配置到代理服务端

使用专门供 LifeMedals 使用的 OpenAI Project Key，环境变量名固定为 `OPENAI_API_KEY`。Key 不能写入 Swift、`Info.plist`、Xcode Scheme、客户端请求、Markdown、日志或任何会提交到 Git 的文件；LifeMedals 客户端只能调用自己的代理端点。

在确定代理平台后，任选其一完成配置：

- **Cloudflare Workers**：本仓库的 Worker 位于 `worker/`。从 GitHub 导入时将 Project name 设为 `lifemedals-api`、Build command 留空、Deploy command 保持 `npx wrangler deploy`，并在 Advanced settings 中将 Root directory 设为 `worker`。首次部署后进入目标 Worker → **Settings → Variables and Secrets**，新增加密 Secret `OPENAI_API_KEY`，值填已申请的 Key，然后重新部署。也可在 `worker/` 目录运行 `npx wrangler secret put OPENAI_API_KEY`，按交互提示粘贴 Key；不要把 Key 直接写在命令参数中。
- **Vercel Functions**：进入目标 Project → **Settings → Environment Variables**，新增敏感变量 `OPENAI_API_KEY`，按需勾选 Production / Preview / Development，然后重新部署。

代理代码只从运行环境读取 Key：Cloudflare Workers 使用 `env.OPENAI_API_KEY`，Vercel Functions 使用 `process.env.OPENAI_API_KEY`。不要返回或打印变量值。

当前 Worker 使用 SQLite Durable Object，在调用 OpenAI **之前**原子预留一次额度；`POST /generate-task` 和 `POST /verify-evidence` 共用同一个全局计数器。默认全局每分钟最多 20 次、每个 UTC 自然月最多 500 次。达到频率限制返回 429，达到月度硬上限返回 402，保护组件异常时返回 503 且不会继续调用 OpenAI。可在 `worker/wrangler.jsonc` 中调整 `GLOBAL_REQUESTS_PER_MINUTE` 和 `MONTHLY_REQUEST_BUDGET`，再运行 `npm test` 与 `npm run check` 验证。这个月度上限按请求次数计算，不是对 OpenAI 账单金额的实时估算，因此仍需在 OpenAI 项目控制台单独设置用量/支出告警。

Cloudflare 部署完成后访问 `GET /health`；只有 API Key 和全局保护都配置成功时才返回 200。客户端的长期默认地址由 `LifeMedalsAPIConfiguration.defaultBaseURL` 保存：Debug 构建默认连接 staging Worker，Release 构建默认连接 production Worker，因此从 iPhone 主屏幕重新启动 App 时仍然有效。更换 Worker 时修改对应构建的值：

```text
static let defaultBaseURL = "https://你的-worker.workers.dev/"
```

若只想在一次 Xcode 调试会话中临时覆盖地址，可以在 **Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables** 中设置 `LIFEMEDALS_API_BASE_URL`。

Mac/iOS 客户端会自动调用该地址下的 `POST /generate-task` 与 `POST /verify-evidence`。`generate-task` 接受文字，也接受一张压缩 JPEG 与可选补充说明；图片只在当前请求中转发给 OpenAI，并固定使用 `store: false`。输入草稿使用本机 `AppStorage` 保存；断网或请求失败不会清空，恢复联网后可直接重试。生成结果可以编辑标题、截止时间、验收标准和所属勋章，确认后连同可选来源图片写入 SwiftData。

生成任务契约时，AI 会同时给出 1–5 张证据照片数量及内容描述：1–2 张分别描述每个槽位，3–5 张使用一条整组描述。提交页据此显示单张大正方形、双张独立方框或 3–5 张横向草稿栏。iOS 支持相机、PhotosPicker 与文件选择；macOS 额外支持拖放和 `⌘V`。照片可在提交前预览删除；必须填满任务要求的照片数并明确点击提交，才会保存并调用 AI 核验。同一次提交的照片共享批次 ID，在历史区合并为一行。客户端先把原图转换为最长边不超过 1800 px、单张不超过约 1 MB 的 JPEG 副本，再写入 `Evidence.imageData` 的 SwiftData 外部存储；原始照片不复制进应用。核验失败时，整批本地记录保持 `Pending Verification`，可从任务详情重试。

`verify-evidence` 只在当前请求的内存中读取 Base64 图片，图片不会写入 Durable Object、KV、R2、日志或其他 Worker 持久化服务；响应也带 `Cache-Control: no-store`。转发给 OpenAI Responses API 时固定使用 `store: false`，不创建 Responses 应用状态。需要注意：OpenAI 默认的滥用监控日志属于平台数据政策范围，除非项目获批并启用 Zero Data Retention，不能把 `store: false` 表述为整个上游链路的零保留。

---

## 参考文档

- 完整产品与技术计划书：[`docs/product-plan.md`](./docs/product-plan.md)
- iOS 迁移与真机验收计划：[`docs/ios-migration-plan.md`](./docs/ios-migration-plan.md)
- Apple：[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Apple：[在 App 内提供账户删除](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
