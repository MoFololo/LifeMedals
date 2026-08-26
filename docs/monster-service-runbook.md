# 怪物素材服务上线清单

本文只描述让现有 iOS 怪物预览与图鉴真正获得图片所需的服务端工作。执行这些步骤会创建或修改 Cloudflare/OpenAI 资源；当前 iOS 实现没有代替你执行部署。

## 1. 准备账号与密钥

1. 在 OpenAI API 项目中确认组织已具备 GPT Image 使用资格，并启用账单与支出告警。
2. 创建仅供 `lifemedals-api` 使用的 OpenAI API key。
3. 在 `worker/` 中通过交互式命令保存 Secret，不要把值写入源码、`wrangler.jsonc`、shell 历史或 iOS：

   ```bash
   npx wrangler secret put OPENAI_API_KEY --env staging
   ```

GPT Image 2 官方资料：

- <https://developers.openai.com/api/docs/models/gpt-image-2>
- <https://developers.openai.com/api/docs/guides/image-generation>

## 2. 创建 Cloudflare 资源

先登录正确的 Cloudflare 账号并确认 `npx wrangler whoami`。建议先建立 staging，再建立 production。以下名称可按环境加后缀：

```bash
cd worker
npx wrangler d1 create lifemedals-monsters --location enam --binding MONSTER_DB --update-config
npx wrangler r2 bucket create lifemedals-monster-assets --location enam --binding MONSTER_ASSETS --update-config
npx wrangler queues create lifemedals-monster-generation
npx wrangler queues create lifemedals-monster-generation-dlq
```

在 `wrangler.jsonc` 中加入：

- D1 binding：`MONSTER_DB`
- R2 binding：`MONSTER_ASSETS`
- Queue producer：`MONSTER_GENERATION_QUEUE`
- 同一个 Worker 的 Queue consumer，并配置 `max_retries` 与 dead-letter queue
- `nodejs_compat`
- Worker observability 与采样率
- 非 Secret 版本值：`MONSTER_STYLE_VERSION=grotesque-pixel-v2`、`MONSTER_PROMPT_VERSION=monster-image-v4`、`MONSTER_CONCEPT_PROMPT_VERSION=monster-concept-v3`、`MONSTER_IMAGE_MODEL=gpt-image-2`

Cloudflare 要求 Worker 通过 Wrangler bindings 访问 D1、R2 与 Queue，而不是在 Worker 内调用 Cloudflare 管理 REST API：

- <https://developers.cloudflare.com/d1/worker-api/>
- <https://developers.cloudflare.com/r2/api/workers/workers-api-reference/>
- <https://developers.cloudflare.com/queues/configuration/configure-queues/>

## 3. 建立 D1 schema 与种子分类

创建 migration：

```bash
npx wrangler d1 migrations create lifemedals-monsters create_monster_catalog
```

Migration 至少建立：

- `monster_species`
- `monster_aliases`
- `monster_variants`

`monster_variants` 必须对 `species_id + level + style_version` 建立唯一约束，状态支持 `pending / generating / ready / failed`。图片只在 D1 保存 object key、content type、byte size、hash、model/prompt/style 版本与错误摘要，不能保存 Base64。

先本地应用和测试，再应用远程 migration：

```bash
npx wrangler d1 migrations apply lifemedals-monsters --local
npx wrangler d1 migrations apply lifemedals-monsters --remote
```

插入种子 taxonomy 与 aliases，至少覆盖：

- `coding.leetcode`
- `study.statistics`
- `fitness.workout`
- `sports.basketball`
- `sports.baseball`
- `sports.tennis`
- `sports.swimming`
- `communication.send_email`
- `chores.take_out_trash`

alias 只保存小写英文与数字，不为每种输入语言分别维护翻译。任务生成模型负责把中文或其他语言的活动归类并翻译为英文 taxonomy。物种 ID 必须使用 `species-[medaltype]-[description]`，description 采用最简单的单词；必须使用两个单词时直接连接在最后一个 `-` 后面。

## 4. 实现客户端所需 API

保留现有 `/health`、`/generate-task`、`/verify-evidence`，新增：

### `POST /monster-variants/ensure`

只接受：

- `canonical_tag`
- `badge_kind`
- `level`（1...9）

必须重新规范化 tag、限制长度和字符、限制 body 大小，并忽略/拒绝怪物名、Prompt、图片、用户 ID、任务内容和证据。使用 D1 唯一约束与 `INSERT OR IGNORE` 幂等创建；已 ready 立即返回，pending/generating 返回当前状态，新 variant 只入队一次。

### `GET /monster-variants/{canonicalTag}/{level}`

返回统一 envelope：

```json
{
  "variant": {
    "variant_id": "...",
    "status": "ready",
    "image_url": "https://assets.example.com/monsters/...webp",
    "style_version": "grotesque-pixel-v2"
  }
}
```

pending、generating、failed 时 `image_url` 为 `null`。不存在可返回 404；不要返回 D1/R2/OpenAI 凭证。对 GET 设置短缓存，对 ready 元数据设置合理缓存，并对 ensure/GET 使用现有全局 Usage Gate 或独立怪物限流。

## 5. 实现 Queue consumer 与 GPT Image 生成链

Consumer 对每条消息重新读取 D1；ready 立即确认，generating 使用租约/更新时间避免并发重复，failed 只允许受控重试。

生成规则：

1. Level 1 根据服务端 visual DNA 与固定模板调用 Image API generation。visual DNA 必须遵守 [`monster-image-spec.md`](monster-image-spec.md)：先选 1–2 个强关联 `signature_objects`，再把每一个锚点融入怪物身体、主轮廓或装备。
2. Level N 必须等待 1...N-1 ready，并优先使用 Level N-1 的 R2 图片调用 image edit，保持同一物种连续进化。
3. GPT Image 参数由服务端固定为 `model=gpt-image-2`、方形尺寸、`quality=low`、WebP 与适当压缩；客户端不能覆盖。
4. Prompt 固定 family-friendly、无血腥、无具体受版权保护角色模仿，并包含稳定 visual DNA、level progression、style/prompt version。
5. 解码 OpenAI 返回的图片后计算内容 hash，写入不可变 R2 key：`monsters/{styleVersion}/{canonicalTag}/level-{level}-{hash}.webp`。
6. R2 成功后再把 D1 variant 原子更新为 ready；失败写入安全错误摘要并抛出，让 Queue 重试。不要记录 API key、完整图片 Base64 或用户任务。

为图片生成设置独立的每分钟与每月预算。现有任务生成/核验请求预算不能自动覆盖 Queue consumer 的 OpenAI 调用。

## 6. 配置公开图片域名

为 R2 配置只读自定义域名/CDN，例如 `assets.lifemedals.app`。公开响应至少设置：

- 正确的 `Content-Type: image/webp`
- 内容 hash 对应的 `ETag`
- `Cache-Control: public, max-age=31536000, immutable`
- 禁止列目录、上传和删除

iOS 只接受 HTTPS 图片且限制为 10 MB，因此生成端应在写入前验证格式和大小。

## 7. 验证与部署顺序

1. 为 normalization、D1 幂等、并发 ensure、Queue 重试、等级依赖、R2 写入失败和 OpenAI 错误补测试。
2. 运行 `npm test`、`npx wrangler types`、TypeScript 检查和 `npx wrangler deploy --dry-run`。
3. 部署 staging，配置 staging Secret，应用 staging migration。
4. 并发调用同一个 tag + level，确认只产生一条 variant 和一次有效生成。
5. 测试 Level 3 首次请求能够按 1→2→3 顺序生成。
6. 确认 iOS 确认页先显示未知怪物，ready 后自动显示图片；完成时 ready 图片进入图鉴，未 ready 时先保存未知发现并稍后替换。
7. 查看 Queue dead-letter、Worker 结构化日志、OpenAI 用量和 R2 对象，再发布 production。
8. 最后把生产 Worker 根地址配置为 `LifeMedalsAPIBaseURL`。Debug 构建默认使用 `lifemedals-api-staging`，Release 构建默认使用 `lifemedals-api`；需要临时切换时可用 `LIFEMEDALS_API_BASE_URL` 覆盖。

## 8. 上线验收标准

- 两个用户请求同一 tag + level 时复用同一张图片。
- abandoned draft 最多只产生通用素材，不产生任何用户记录；D1/R2 不出现任务文字、证据或身份。
- Worker/OpenAI 暂时失败时，iOS 仍可保存、核验、记 EXP 和写入未知发现。
- 图片生成完成后，重新进入或停留在怪物图鉴会把未知占位替换为真实图片。
- iOS 包、日志和网络请求中不存在 OpenAI key、Cloudflare token 或 R2 管理凭证。
