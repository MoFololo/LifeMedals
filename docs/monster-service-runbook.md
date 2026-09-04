# Monster Service Deployment and Operations Runbook

This runbook covers the Cloudflare/OpenAI service that supplies generic monster artwork to the existing client. It does not store or process personal discovery state.

## Current environment status

| Environment | API Worker | OpenAI and usage gate | D1/R2/Queue monster bindings | Status |
| --- | --- | --- | --- | --- |
| Staging | `lifemedals-api-staging` | Configured | Configured | Deployed; health returned 200 on 2026-09-03 |
| Production | `lifemedals-api` | Configured by the base Worker setup | Not present in committed top-level config | Monster promotion pending |

The staging configuration currently names:

- D1: `lifemedals-monsters-staging`
- R2: `lifemedals-monster-assets-staging`
- Queue: `lifemedals-monster-generation-staging`
- Dead-letter queue: `lifemedals-monster-generation-dlq-staging`
- Style: `grotesque-pixel-v2`
- Image prompt: `monster-image-v4`
- Concept prompt: `monster-concept-v3`
- Image model: `gpt-image-2`

Resource identifiers already committed in `wrangler.jsonc` are configuration, not secrets. Never commit the OpenAI key or Cloudflare API credentials.

## 1. Prerequisites and secrets

Use the correct Cloudflare account and an OpenAI project with GPT Image access, billing, and spending alerts.

```bash
cd worker
npx wrangler whoami
npx wrangler secret put OPENAI_API_KEY --env staging
```

Enter the secret only at Wrangler's interactive prompt. Do not place it in source, `wrangler.jsonc`, command arguments, shell history, iOS configuration, or logs.

Before production promotion, set the production secret separately:

```bash
npx wrangler secret put OPENAI_API_KEY
```

## 2. Service boundaries

The service accepts generic catalog identifiers only:

- canonical English tag;
- medal family;
- level 1 through 9;
- server-controlled style and prompt versions.

It must reject or ignore user identity, task text, evidence, custom prompts, supplied images, monster names, and arbitrary storage keys. D1/R2/Queue must never contain personal tasks, EXP, evidence, or discoveries.

Worker bindings access D1, R2, Durable Objects, and Queues directly. Runtime code must not use Cloudflare management API tokens.

## 3. Schema and taxonomy

The committed migration chain is:

1. `0001_create_monster_catalog.sql`
2. `0002_add_monster_concepts.sql`
3. `0003_normalize_monster_taxonomy.sql`
4. `0004_add_distinct_sport_species.sql`

It creates and evolves `monster_species`, `monster_aliases`, `monster_concepts`, and `monster_variants`. Variants are unique by species, level, and style version and use `pending`, `generating`, `ready`, or `failed` states. D1 stores only object keys, content type, byte size, content hash, model/prompt/style versions, leases, and safe error summaries—not image Base64.

Aliases are lowercase English. Non-English user input is translated and normalized by task generation. Named sports stay separate, and species IDs follow `species-[medaltype]-[description]`.

Apply migrations locally before remote deployment:

```bash
cd worker
npx wrangler d1 migrations apply lifemedals-monsters-staging --local --env staging
npx wrangler d1 migrations apply lifemedals-monsters-staging --remote --env staging
```

For production, create the production D1 resource, add its binding to the top-level configuration, and use its exact database name in the equivalent remote command. Never guess or reuse the staging database ID.

## 4. API contract

Existing endpoints:

- `GET /health`
- `POST /generate-task`
- `POST /verify-evidence`

Monster endpoints:

### `POST /monster-variants/ensure`

Accepted request fields:

```json
{
  "canonical_tag": "sports.tennis",
  "badge_kind": "athlete",
  "level": 3
}
```

The handler normalizes and validates the tag, badge, level, and body size. D1 uniqueness plus idempotent inserts ensure concurrent requests reuse one variant. A ready variant returns immediately; a new or retryable variant is queued without exposing generation internals.

### `GET /monster-variants/{canonicalTag}/{level}`

The response uses a stable envelope:

```json
{
  "variant": {
    "variant_id": "...",
    "status": "ready",
    "image_url": "https://.../monster-assets/monsters/...webp",
    "style_version": "grotesque-pixel-v2"
  }
}
```

`image_url` is `null` while pending, generating, or failed. The response never contains D1, R2, Cloudflare, or OpenAI credentials.

### `GET /monster-assets/{objectKey}`

Only valid immutable monster object paths are accepted. The handler reads R2 and returns the stored content type, ETag, and cache metadata. It does not list buckets or permit upload/delete operations.

## 5. Generation pipeline

1. The consumer reloads variant state from D1 and claims a time-bounded generation lease.
2. Level 1 derives stable visual DNA and one or two required signature objects using the server concept prompt.
3. Level N waits until Level N-1 is ready and then uses that immutable R2 image as the edit input.
4. The server fixes the model, square size, low quality, WebP output, compression, safety rules, and prompt versions. Clients cannot override them.
5. The result is decoded, validated, hashed, and written to `monsters/{styleVersion}/{canonicalTag}/level-{level}-{hash}.webp`.
6. Only after R2 succeeds does D1 atomically mark the variant ready.
7. Safe failures update D1 and throw when Queue retry is appropriate. Logs exclude secrets, full Base64 images, and private task content.

Every concept and image must comply with [Monster image specification](monster-image-spec.md).

## 6. Usage protection and recovery

Task generation and evidence verification use the shared Durable Object limits configured by:

- `GLOBAL_REQUESTS_PER_MINUTE`
- `MONTHLY_REQUEST_BUDGET`

Monster images use an independent reservation path and:

- `MONSTER_IMAGES_PER_MINUTE`
- `MONTHLY_MONSTER_IMAGE_BUDGET`

The current staging defaults are two image reservations per minute and 100 per UTC month. These counters limit request volume, not dollar spend; retain OpenAI project spending alerts.

Temporary budget exhaustion must not permanently poison a variant. The current code records a retryable state and allows a later ensure/consumer pass after the budget window resets. Permanent input or safety failures remain controlled failures.

## 7. Verification before deployment

```bash
cd worker
npm test
npm run check
npx wrangler deploy --dry-run --env staging
```

Also verify the complete migration chain against a fresh local D1 database. The tests should cover normalization, alias lookup, idempotent/concurrent ensure, generation leases, level dependencies, R2 failure, OpenAI failure, asset-key validation, budget enforcement, and recovery after temporary budget exhaustion.

## 8. Staging deployment and smoke test

Apply remote migrations before deploying code that requires them:

```bash
cd worker
npx wrangler d1 migrations apply lifemedals-monsters-staging --remote --env staging
npx wrangler deploy --env staging
```

Then verify:

1. `/health` reports `openaiConfigured`, `usageProtectionConfigured`, and `monsterServiceConfigured` as true.
2. Concurrent ensures for the same tag/level produce one reusable variant.
3. A first request for Level 3 eventually builds Level 1, then 2, then 3.
4. R2 responses are valid WebP assets with immutable caching metadata.
5. The iOS confirmation page transitions from the unknown silhouette to ready art.
6. Verification can save an unknown discovery and the Atlas later replaces it with ready art.
7. Queue retries and dead-letter behavior are visible in Cloudflare, without sensitive log data.
8. OpenAI usage and the independent image budget increase as expected.

## 9. Production promotion

Production promotion is still pending. Use separate production resources rather than renaming or reusing staging:

1. Create production D1, R2, generation Queue, and dead-letter Queue resources.
2. Add their exact bindings to the top-level `wrangler.jsonc` configuration.
3. Configure production style/model/budget variables and the encrypted OpenAI secret.
4. Apply all migrations to the production D1 database.
5. Run the same smoke tests against production with a small budget.
6. Confirm Release uses the production Worker base URL.
7. Monitor errors, dead letters, OpenAI spend, R2 object growth, and D1 variant state during rollout.

Do not promote solely because `/health` is green. Validate actual ensure, sequential generation, asset delivery, and client refresh behavior.

## 10. Acceptance criteria

- Multiple users requesting one tag/level reuse one global image.
- Abandoned drafts can create only generic catalog assets and no personal records.
- Worker/OpenAI failures do not block local saves, verification, notifications, EXP, or discovery persistence.
- A pending discovery automatically gains artwork after the variant becomes ready.
- The iOS bundle, requests, and logs contain no OpenAI key, Cloudflare token, or R2 management credential.
- Existing R2 images are immutable; art revisions use a new style version and object key.
