const OPENAI_IMAGE_GENERATIONS_URL = "https://api.openai.com/v1/images/generations";
const OPENAI_IMAGE_EDITS_URL = "https://api.openai.com/v1/images/edits";
const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";

const DEFAULT_IMAGE_MODEL = "gpt-image-2";
const DEFAULT_STYLE_VERSION = "grotesque-pixel-v1";
const DEFAULT_PROMPT_VERSION = "monster-image-v3";
const DEFAULT_CONCEPT_PROMPT_VERSION = "monster-concept-v2";
const DEFAULT_MONTHLY_IMAGE_BUDGET = 100;
const DEFAULT_IMAGES_PER_MINUTE = 2;

const MAX_ENSURE_REQUEST_BYTES = 4 * 1024;
const MAX_GENERATED_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_IMAGE_BASE64_LENGTH = 14_000_000;
const GENERATION_LEASE_MS = 5 * 60_000;
const CONCEPT_LEASE_MS = 2 * 60_000;
const ENQUEUE_STALE_MS = 5 * 60_000;

const CANONICAL_TAG_PATTERN = /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/;
const DISPLAY_NAME_PATTERN = /^[\p{L}\p{N}][\p{L}\p{N} _-]{0,59}$/u;
const BADGE_KINDS = new Set(["Solver", "Builder", "Career", "Athlete"]);
const VARIANT_STATUSES = new Set(["pending", "generating", "ready", "failed"]);

const MONSTER_CONCEPT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    action_metaphor: { type: "string", minLength: 1, maxLength: 240 },
    creature_archetype: { type: "string", minLength: 1, maxLength: 120 },
    body_shape: { type: "string", minLength: 1, maxLength: 180 },
    face: { type: "string", minLength: 1, maxLength: 180 },
    task_features: {
      type: "array",
      minItems: 2,
      maxItems: 3,
      items: { type: "string", minLength: 1, maxLength: 160 },
    },
    palette: {
      type: "array",
      minItems: 3,
      maxItems: 4,
      items: { type: "string", minLength: 1, maxLength: 40 },
    },
    linework: { type: "string", minLength: 1, maxLength: 160 },
    silhouette: { type: "string", minLength: 1, maxLength: 180 },
    evolution_motif: { type: "string", minLength: 1, maxLength: 240 },
    image_description: { type: "string", minLength: 1, maxLength: 700 },
  },
  required: [
    "action_metaphor",
    "creature_archetype",
    "body_shape",
    "face",
    "task_features",
    "palette",
    "linework",
    "silhouette",
    "evolution_motif",
    "image_description",
  ],
};

export const SEED_MONSTER_TAGS = new Set([
  "coding.leetcode",
  "coding.project",
  "coding.practice",
  "study.statistics",
  "study.learning",
  "fitness.workout",
  "communication.send_email",
  "communication.career",
  "chores.take_out_trash",
  "chores.household",
]);

const FALLBACK_DISPLAY_NAMES = {
  "coding.leetcode": "Algorithm Imp",
  "coding.project": "Forge Sprite",
  "coding.practice": "Puzzle Imp",
  "study.statistics": "Stat Wisp",
  "study.learning": "Study Wisp",
  "fitness.workout": "Training Brute",
  "communication.send_email": "Mail Bat",
  "communication.career": "Courier Wisp",
  "chores.take_out_trash": "Trash Slime",
  "chores.household": "Chore Slime",
};

class MonsterServiceError extends Error {
  constructor(status, code, message, retryable = false) {
    super(message);
    this.name = "MonsterServiceError";
    this.status = status;
    this.code = code;
    this.retryable = retryable;
  }
}

class MonsterLeaseBusyError extends Error {
  constructor() {
    super("Another consumer owns the active generation lease.");
    this.name = "MonsterLeaseBusyError";
  }
}

export async function handleEnsureMonsterVariant(request, env, requestId) {
  const missingBinding = missingMonsterBinding(env);
  if (missingBinding) {
    return monsterJsonError(
      503,
      "monster_service_not_configured",
      `The monster service binding ${missingBinding} is not configured.`,
      requestId,
    );
  }

  const contentType = request.headers.get("content-type") || "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return monsterJsonError(
      415,
      "unsupported_media_type",
      "Content-Type must be application/json.",
      requestId,
    );
  }

  let rawBody;
  try {
    rawBody = await readRequestTextBounded(request, MAX_ENSURE_REQUEST_BYTES);
  } catch (error) {
    if (error instanceof MonsterServiceError) {
      return monsterJsonError(error.status, error.code, error.message, requestId);
    }
    return monsterJsonError(400, "invalid_body", "Unable to read request body.", requestId);
  }

  let body;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return monsterJsonError(400, "invalid_json", "Request body must be valid JSON.", requestId);
  }

  const validation = validateEnsureMonsterInput(body);
  if (!validation.ok) {
    return monsterJsonError(400, "invalid_request", validation.error, requestId);
  }

  try {
    const species = await findOrCreateSpecies(env, validation.value);
    const targetVariant = await ensureVariantRows(
      env,
      species.id,
      validation.value.level,
    );

    if (targetVariant.status !== "ready") {
      await enqueueVariantIfNeeded(env, targetVariant, species.id, validation.value.level);
    }

    const refreshed = await findVariantById(env.MONSTER_DB, targetVariant.id);
    return monsterJsonResponse(
      { variant: variantSnapshot(refreshed || targetVariant, env) },
      refreshed?.status === "ready" ? 200 : 202,
      requestId,
    );
  } catch (error) {
    const serviceError = normalizeServiceError(error);
    console.error(JSON.stringify({
      event: "monster_ensure_failed",
      requestId,
      code: serviceError.code,
    }));
    return monsterJsonError(
      serviceError.status,
      serviceError.code,
      serviceError.message,
      requestId,
    );
  }
}

export async function handleGetMonsterVariant(
  encodedCanonicalTag,
  encodedLevel,
  env,
  requestId,
) {
  if (!env.MONSTER_DB) {
    return monsterJsonError(
      503,
      "monster_service_not_configured",
      "The monster database is not configured.",
      requestId,
    );
  }

  let canonicalTag;
  try {
    canonicalTag = normalizeCanonicalTag(decodeURIComponent(encodedCanonicalTag));
  } catch {
    canonicalTag = "";
  }
  const level = Number(encodedLevel);

  if (!isValidCanonicalTag(canonicalTag) || !Number.isInteger(level) || level < 1 || level > 9) {
    return monsterJsonError(
      400,
      "invalid_monster_variant",
      "The canonical tag or level is invalid.",
      requestId,
    );
  }

  const styleVersion = readNonEmptyString(env.MONSTER_STYLE_VERSION, DEFAULT_STYLE_VERSION);
  const variant = await env.MONSTER_DB.prepare(
    `SELECT
       v.id,
       v.level,
       v.status,
       v.image_object_key,
       v.style_version
     FROM monster_variants v
     JOIN monster_species s ON s.id = v.species_id
     WHERE s.canonical_tag = ? COLLATE NOCASE
       AND v.level = ?
       AND v.style_version = ?
     LIMIT 1`,
  ).bind(canonicalTag, level, styleVersion).first();

  if (!variant) {
    return monsterJsonError(404, "monster_variant_not_found", "Monster variant not found.", requestId);
  }

  return monsterJsonResponse(
    { variant: variantSnapshot(variant, env) },
    200,
    requestId,
    variant.status === "ready"
      ? { "Cache-Control": "public, max-age=60" }
      : { "Cache-Control": "no-store" },
  );
}

export async function handleMonsterAsset(pathname, env, requestId) {
  if (!env.MONSTER_ASSETS) {
    return new Response("Not found", { status: 404 });
  }

  let objectKey;
  try {
    objectKey = decodeURIComponent(pathname.slice("/monster-assets/".length));
  } catch {
    return new Response("Not found", { status: 404 });
  }

  if (!isValidMonsterObjectKey(objectKey)) {
    return new Response("Not found", { status: 404 });
  }

  const object = await env.MONSTER_ASSETS.get(objectKey);
  if (!object) {
    return new Response("Not found", { status: 404 });
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("Content-Type", "image/webp");
  headers.set("Cache-Control", "public, max-age=31536000, immutable");
  headers.set("ETag", object.httpEtag);
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-Request-ID", requestId);

  return new Response(object.body, { status: 200, headers });
}

export async function handleMonsterQueue(batch, env) {
  for (const message of batch.messages) {
    try {
      await processMonsterGeneration(message.body, env);
      message.ack();
    } catch (error) {
      if (error instanceof MonsterLeaseBusyError) {
        message.retry({ delaySeconds: 30 });
        continue;
      }

      const serviceError = normalizeServiceError(error);
      console.error(JSON.stringify({
        event: "monster_generation_failed",
        messageId: message.id,
        attempt: message.attempts,
        code: serviceError.code,
        retryable: serviceError.retryable,
      }));

      if (serviceError.retryable) {
        message.retry({ delaySeconds: Math.min(300, 30 * Math.max(1, message.attempts)) });
      } else {
        message.ack();
      }
    }
  }
}

export async function processMonsterGeneration(rawMessage, env) {
  const message = validateQueueMessage(rawMessage);
  const missingBinding = missingMonsterBinding(env);
  if (missingBinding) {
    throw new MonsterServiceError(
      503,
      "monster_service_not_configured",
      `The monster service binding ${missingBinding} is not configured.`,
      true,
    );
  }
  if (!env.OPENAI_API_KEY) {
    throw new MonsterServiceError(
      503,
      "openai_not_configured",
      "OpenAI is not configured.",
      false,
    );
  }

  const storedSpecies = await env.MONSTER_DB.prepare(
    `SELECT
       id,
       canonical_tag,
       display_name,
       badge_kind,
       visual_dna_json,
       style_version,
       concept_status,
       concept_description,
       concept_model,
       concept_prompt_version,
       concept_lease_expires_at
     FROM monster_species
     WHERE id = ?
     LIMIT 1`,
  ).bind(message.speciesId).first();
  if (!storedSpecies) {
    throw new MonsterServiceError(404, "monster_species_not_found", "Monster species not found.");
  }
  const species = await ensureMonsterConcept(storedSpecies, env);

  const result = await env.MONSTER_DB.prepare(
    `SELECT
       id,
       species_id,
       level,
       status,
       image_object_key,
       style_version,
       lease_expires_at
     FROM monster_variants
     WHERE species_id = ?
       AND style_version = ?
       AND level <= ?
     ORDER BY level ASC`,
  ).bind(species.id, message.styleVersion, message.targetLevel).all();

  const variants = result.results || [];
  const current = variants.find((variant) => variant.status !== "ready");
  if (!current) return;

  const now = new Date();
  const nowISO = now.toISOString();
  const leaseExpiresAt = new Date(now.getTime() + GENERATION_LEASE_MS).toISOString();
  const claim = await env.MONSTER_DB.prepare(
    `UPDATE monster_variants
     SET
       status = 'generating',
       generation_attempts = generation_attempts + 1,
       queue_enqueued_at = NULL,
       lease_expires_at = ?,
       failure_code = NULL,
       updated_at = ?
     WHERE id = ?
       AND (
         status IN ('pending', 'failed')
         OR (
           status = 'generating'
           AND (lease_expires_at IS NULL OR lease_expires_at < ?)
         )
       )`,
  ).bind(leaseExpiresAt, nowISO, current.id, nowISO).run();

  if (readD1Changes(claim) === 0) {
    throw new MonsterLeaseBusyError();
  }

  try {
    let previousObject = null;
    if (current.level > 1) {
      const previous = variants.find((variant) => variant.level === current.level - 1);
      if (!previous || previous.status !== "ready" || !previous.image_object_key) {
        await resetVariantPending(env.MONSTER_DB, current.id, "previous_level_not_ready");
        throw new MonsterLeaseBusyError();
      }
      previousObject = await env.MONSTER_ASSETS.get(previous.image_object_key);
      if (!previousObject || previousObject.size > MAX_GENERATED_IMAGE_BYTES) {
        await resetVariantPending(env.MONSTER_DB, current.id, "previous_image_unavailable");
        throw new MonsterServiceError(
          503,
          "previous_image_unavailable",
          "The previous monster level image is unavailable.",
          true,
        );
      }
    }

    const budget = await reserveMonsterImageBudget(env);
    if (!budget.allowed) {
      await failVariant(
        env.MONSTER_DB,
        current.id,
        budget.reason === "budget_exhausted"
          ? "image_budget_exhausted"
          : "image_budget_unavailable",
      );
      throw new MonsterServiceError(
        503,
        budget.reason === "budget_exhausted"
          ? "image_budget_exhausted"
          : "image_budget_unavailable",
        "Monster image generation is unavailable under the current budget.",
        false,
      );
    }

    const prompt = buildMonsterPrompt(species, current.level, message.styleVersion, env);
    const imageBytes = await requestMonsterImage({
      prompt,
      previousObject,
      level: current.level,
      env,
    });
    const contentHash = await sha256Hex(imageBytes);
    const objectKey = [
      "monsters",
      message.styleVersion,
      species.canonical_tag,
      `level-${current.level}-${contentHash}.webp`,
    ].join("/");

    await env.MONSTER_ASSETS.put(objectKey, imageBytes, {
      httpMetadata: {
        contentType: "image/webp",
        cacheControl: "public, max-age=31536000, immutable",
      },
      customMetadata: {
        canonicalTag: species.canonical_tag,
        level: String(current.level),
        model: readNonEmptyString(env.MONSTER_IMAGE_MODEL, DEFAULT_IMAGE_MODEL),
        promptVersion: readNonEmptyString(env.MONSTER_PROMPT_VERSION, DEFAULT_PROMPT_VERSION),
        styleVersion: message.styleVersion,
        contentHash,
      },
    });

    await env.MONSTER_DB.prepare(
      `UPDATE monster_variants
       SET
         status = 'ready',
         image_object_key = ?,
         image_content_type = 'image/webp',
         image_byte_size = ?,
         image_content_hash = ?,
         model = ?,
         lease_expires_at = NULL,
         failure_code = NULL,
         updated_at = ?
       WHERE id = ?`,
    ).bind(
      objectKey,
      imageBytes.byteLength,
      contentHash,
      readNonEmptyString(env.MONSTER_IMAGE_MODEL, DEFAULT_IMAGE_MODEL),
      new Date().toISOString(),
      current.id,
    ).run();

    if (current.level < message.targetLevel) {
      await env.MONSTER_GENERATION_QUEUE.send(message, { delaySeconds: 1 });
    }

    console.log(JSON.stringify({
      event: "monster_generation_ready",
      speciesId: species.id,
      canonicalTag: species.canonical_tag,
      level: current.level,
      styleVersion: message.styleVersion,
      imageBytes: imageBytes.byteLength,
    }));
  } catch (error) {
    if (error instanceof MonsterLeaseBusyError) throw error;
    const serviceError = normalizeServiceError(error);
    if (!new Set(["image_budget_exhausted", "image_budget_unavailable"]).has(serviceError.code)) {
      await failVariant(env.MONSTER_DB, current.id, serviceError.code);
    }
    throw serviceError;
  }
}

export function validateEnsureMonsterInput(body) {
  if (!isPlainObject(body)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }
  const allowedKeys = new Set(["canonical_tag", "display_name", "badge_kind", "level"]);
  if (Object.keys(body).some((key) => !allowedKeys.has(key))) {
    return { ok: false, error: "Request body contains unsupported fields." };
  }

  const canonicalTag = normalizeCanonicalTag(body.canonical_tag);
  if (!isValidCanonicalTag(canonicalTag)) {
    return { ok: false, error: "canonical_tag is invalid." };
  }

  const displayName = typeof body.display_name === "string" ? body.display_name.trim() : "";
  if (!DISPLAY_NAME_PATTERN.test(displayName)) {
    return { ok: false, error: "display_name contains unsupported characters or length." };
  }
  if (!BADGE_KINDS.has(body.badge_kind)) {
    return { ok: false, error: "badge_kind is invalid." };
  }
  if (!Number.isInteger(body.level) || body.level < 1 || body.level > 9) {
    return { ok: false, error: "level must be an integer between 1 and 9." };
  }

  return {
    ok: true,
    value: {
      canonicalTag,
      displayName,
      badgeKind: body.badge_kind,
      level: body.level,
    },
  };
}

export function validateQueueMessage(body) {
  if (
    !isPlainObject(body) ||
    typeof body.speciesId !== "string" ||
    body.speciesId.length === 0 ||
    body.speciesId.length > 100 ||
    !Number.isInteger(body.targetLevel) ||
    body.targetLevel < 1 ||
    body.targetLevel > 9 ||
    typeof body.styleVersion !== "string" ||
    !/^[a-z0-9][a-z0-9._-]{0,39}$/.test(body.styleVersion)
  ) {
    throw new MonsterServiceError(400, "invalid_queue_message", "Invalid queue message.");
  }
  return {
    speciesId: body.speciesId,
    targetLevel: body.targetLevel,
    styleVersion: body.styleVersion,
  };
}

export async function normalizeGeneratedTaskMonsters(contract, env) {
  if (!isPlainObject(contract)) return contract;
  const normalized = { ...contract };
  const descriptors = [];

  if (normalized.kind === "task_group") {
    normalized.monster_tag = null;
    normalized.monster_display_name = null;
    normalized.monster_match_kind = null;
    normalized.children = Array.isArray(normalized.children)
      ? normalized.children.map((child) => {
          const next = normalizeGeneratedMonsterDescriptor(child);
          descriptors.push(next);
          return next;
        })
      : normalized.children;
  } else {
    Object.assign(normalized, normalizeGeneratedMonsterDescriptor(normalized));
    descriptors.push(normalized);
  }

  const validTags = [...new Set(
    descriptors
      .map((descriptor) => descriptor.monster_tag)
      .filter((tag) => isValidCanonicalTag(tag)),
  )];
  const storedSpecies = await findSpeciesByCanonicalTags(env?.MONSTER_DB, validTags);

  for (const descriptor of descriptors) {
    const species = storedSpecies.get(descriptor.monster_tag);
    if (species) {
      descriptor.monster_display_name = species.display_name;
      descriptor.monster_match_kind = "existing";
    } else if (isValidCanonicalTag(descriptor.monster_tag)) {
      descriptor.monster_match_kind = SEED_MONSTER_TAGS.has(descriptor.monster_tag)
        ? "existing"
        : "new";
    }
  }

  return normalized;
}

export function buildMonsterConceptOpenAIRequest(species, env = {}) {
  const model = readNonEmptyString(env.OPENAI_MODEL, "gpt-5.6-terra");
  const conceptPromptVersion = readNonEmptyString(
    env.MONSTER_CONCEPT_PROMPT_VERSION,
    DEFAULT_CONCEPT_PROMPT_VERSION,
  );

  return {
    model,
    store: false,
    reasoning: { effort: "low" },
    max_output_tokens: 1_500,
    instructions: [
      "Design one original recurring monster species as a strong visual metaphor for a general task category.",
      "The canonical category tag is the semantic source of truth. Do not produce a generic badge-themed creature; make it unmistakably related to that action rather than merely matching its badge color.",
      "Invent two or three concrete anatomy, prop, or behavior features that communicate the category without using written words, UI screenshots, brand logos, trademarks, or copyrighted characters.",
      "Art direction: an original low-resolution grotesque pixel mascot that is odd, deadpan, awkward, slightly unsettling, and endearingly stupid.",
      "Design for a logical 48 by 48 pixel sprite: one compact silhouette, an oversized expressive face, a tiny simple body, and no more than two category-specific visual features.",
      "Every form must be expressible as chunky square pixel clusters. Favor lopsided anatomy, blank or worried eyes, a tiny mouth, one- to three-pixel-thick stepped outlines, flat fills, and three or four dirty muted colors.",
      "No smooth curves, no anti-aliasing, no gradients, no soft brushwork, no paper texture, and no painterly shading. Also avoid polished concept art, glossy 3D, anime beauty, elaborate armor, realistic anatomy, high-resolution pixel rendering, gore, horror violence, and direct imitation of any existing game or franchise.",
      "Keep the species family-friendly. Strange bodily proportions are welcome, but no exposed organs, blood, mutilation, or sexual content.",
      "Create an evolution motif that can grow gradually through nine levels while preserving the same face, body plan, palette, and category-specific features.",
      "Do not include any user, task title, company, filename, place, account, or other private or one-off detail.",
      `Concept prompt version: ${conceptPromptVersion}.`,
    ].join("\n"),
    input: [
      `CANONICAL_CATEGORY_TAG\n${species.canonical_tag}`,
      `SPECIES_NAME\n${species.display_name}`,
      `BADGE_FAMILY\n${species.badge_kind}`,
    ].join("\n\n"),
    text: {
      verbosity: "low",
      format: {
        type: "json_schema",
        name: "monster_species_concept",
        strict: true,
        schema: MONSTER_CONCEPT_SCHEMA,
      },
    },
  };
}

export function validateMonsterConcept(value) {
  if (!isPlainObject(value)) return false;
  const stringLimits = {
    action_metaphor: 240,
    creature_archetype: 120,
    body_shape: 180,
    face: 180,
    linework: 160,
    silhouette: 180,
    evolution_motif: 240,
    image_description: 700,
  };
  if (Object.keys(value).length !== 10) return false;
  for (const [key, maxLength] of Object.entries(stringLimits)) {
    if (!isBoundedNonEmptyString(value[key], maxLength)) return false;
  }
  if (!isBoundedStringArray(value.task_features, 2, 3, 160)) return false;
  if (!isBoundedStringArray(value.palette, 3, 4, 40)) return false;
  return true;
}

export function isCurrentMonsterConcept(species, env = {}) {
  const currentPromptVersion = readNonEmptyString(
    env.MONSTER_CONCEPT_PROMPT_VERSION,
    DEFAULT_CONCEPT_PROMPT_VERSION,
  );
  if (
    species?.concept_status !== "ready" ||
    species?.concept_prompt_version !== currentPromptVersion
  ) {
    return false;
  }
  try {
    return validateMonsterConcept(JSON.parse(species.visual_dna_json));
  } catch {
    return false;
  }
}

export async function requestMonsterConcept(species, env) {
  const response = await fetch(OPENAI_RESPONSES_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(buildMonsterConceptOpenAIRequest(species, env)),
    signal: AbortSignal.timeout(60_000),
  });

  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new MonsterServiceError(
      502,
      "invalid_monster_concept_response",
      "OpenAI returned an unreadable monster concept response.",
      true,
    );
  }

  if (!response.ok) {
    const code = response.status === 401
      ? "openai_authentication_failed"
      : response.status === 429
        ? "openai_concept_rate_limited"
        : "openai_concept_request_failed";
    throw new MonsterServiceError(
      response.status === 429 ? 503 : 502,
      code,
      "The OpenAI monster concept request failed.",
      response.status !== 401,
    );
  }
  if (payload?.status !== "completed") {
    throw new MonsterServiceError(
      502,
      "incomplete_monster_concept_response",
      "OpenAI did not complete the monster concept.",
      true,
    );
  }

  const outputText = findOpenAIOutputText(payload);
  let concept;
  try {
    concept = JSON.parse(outputText);
  } catch {
    concept = null;
  }
  if (!validateMonsterConcept(concept)) {
    throw new MonsterServiceError(
      502,
      "invalid_monster_concept",
      "OpenAI returned an invalid monster concept.",
      true,
    );
  }
  return concept;
}

async function ensureMonsterConcept(species, env) {
  if (isCurrentMonsterConcept(species, env)) return species;

  const now = new Date();
  const nowISO = now.toISOString();
  const leaseExpiresAt = new Date(now.getTime() + CONCEPT_LEASE_MS).toISOString();
  const previousConceptPromptVersion = species.concept_prompt_version ?? null;
  const claim = await env.MONSTER_DB.prepare(
    `UPDATE monster_species
     SET
       concept_status = 'generating',
       concept_generation_attempts = concept_generation_attempts + 1,
       concept_lease_expires_at = ?,
       concept_failure_code = NULL,
       updated_at = ?
     WHERE id = ?
       AND (
         concept_status IN ('pending', 'failed')
         OR (
           concept_status = 'generating'
           AND (concept_lease_expires_at IS NULL OR concept_lease_expires_at < ?)
         )
         OR (
           concept_status = 'ready'
           AND concept_prompt_version IS ?
         )
       )`,
  ).bind(
    leaseExpiresAt,
    nowISO,
    species.id,
    nowISO,
    previousConceptPromptVersion,
  ).run();
  if (readD1Changes(claim) === 0) throw new MonsterLeaseBusyError();

  try {
    const budget = await reserveMonsterConceptBudget(env);
    if (!budget.allowed) {
      const budgetCode = budget.reason === "rate_limited"
        ? "concept_rate_limited"
        : budget.reason === "budget_exhausted"
          ? "concept_budget_exhausted"
          : "concept_budget_unavailable";
      throw new MonsterServiceError(
        budget.reason === "rate_limited" ? 429 : 503,
        budgetCode,
        "Monster concept generation is unavailable under the current budget.",
        budget.reason !== "budget_exhausted",
      );
    }

    const concept = await requestMonsterConcept(species, env);
    const model = readNonEmptyString(env.OPENAI_MODEL, "gpt-5.6-terra");
    const promptVersion = readNonEmptyString(
      env.MONSTER_CONCEPT_PROMPT_VERSION,
      DEFAULT_CONCEPT_PROMPT_VERSION,
    );
    const generatedAt = new Date().toISOString();
    await env.MONSTER_DB.prepare(
      `UPDATE monster_species
       SET
         visual_dna_json = ?,
         concept_status = 'ready',
         concept_description = ?,
         concept_model = ?,
         concept_prompt_version = ?,
         concept_lease_expires_at = NULL,
         concept_failure_code = NULL,
         concept_generated_at = ?,
         updated_at = ?
       WHERE id = ?`,
    ).bind(
      JSON.stringify(concept),
      concept.image_description,
      model,
      promptVersion,
      generatedAt,
      generatedAt,
      species.id,
    ).run();

    console.log(JSON.stringify({
      event: "monster_concept_ready",
      speciesId: species.id,
      canonicalTag: species.canonical_tag,
      model,
      promptVersion,
    }));
    return {
      ...species,
      visual_dna_json: JSON.stringify(concept),
      concept_status: "ready",
      concept_description: concept.image_description,
      concept_model: model,
      concept_prompt_version: promptVersion,
      concept_lease_expires_at: null,
    };
  } catch (error) {
    const serviceError = normalizeServiceError(error);
    await env.MONSTER_DB.prepare(
      `UPDATE monster_species
       SET
         concept_status = 'failed',
         concept_lease_expires_at = NULL,
         concept_failure_code = ?,
         updated_at = ?
       WHERE id = ?`,
    ).bind(sanitizeFailureCode(serviceError.code), new Date().toISOString(), species.id).run();
    throw serviceError;
  }
}

export function buildMonsterPrompt(species, level, styleVersion, env = {}) {
  let visualDNA = {};
  try {
    visualDNA = JSON.parse(species.visual_dna_json);
  } catch {
    visualDNA = deriveVisualDNA(species.canonical_tag, species.badge_kind);
  }

  const progression = level === 1
    ? "This is the base form: use the fewest possible pixel clusters and only the two strongest category-specific features."
    : `This is evolution level ${level} of 9. Preserve the exact same face, body plan, palette, pixel scale, and category metaphor from the reference image. Add only one tiny pixel-readable mutation from the evolution motif; do not increase rendering detail.`;

  return [
    "Create one original family-friendly collectible grotesque pixel monster sprite for the LifeMedals iOS app.",
    `Canonical species tag: ${species.canonical_tag}.`,
    `Species name: ${species.display_name}.`,
    `Badge family: ${species.badge_kind}.`,
    `AI-authored stable species concept: ${JSON.stringify(visualDNA)}.`,
    progression,
    "The category connection must be immediately visible through one or two simple anatomy or prop features; do not produce a generic fantasy monster or a complex scene.",
    "PIXEL CONSTRUCTION IS MANDATORY: design on a logical 48 by 48 pixel canvas, then nearest-neighbor upscale it. Every edge must snap to a visible square-pixel grid with chunky staircase contours.",
    "Use crisp hard-edged pixel clusters, one- to three-pixel-thick dark outlines, no anti-aliasing, no subpixel detail, no smooth vector curves, no blur, no gradients, and no paper or paint texture.",
    "Make it extremely simple: one squat lopsided blob-like silhouette, oversized blank or worried eyes, a tiny mouth, tiny limbs if needed, and at most two category-specific details. It should be easy to redraw as a tiny game sprite.",
    "Use only three or four dirty muted colors plus a dark outline, flat fills, and at most one blocky shadow tone. Place it on a plain warm off-white solid background.",
    "Keep exactly one centered front-facing or slight three-quarter full-body sprite with generous empty space. No sprite sheet, alternate pose, animation frame, decorative scene, border, or ground shadow.",
    "No polished concept art, smooth illustration, glossy 3D, anime styling, realistic anatomy, intricate armor, high-resolution pixel detail, or painterly rendering.",
    "No text, letters, numbers, logo, watermark, trademark, recognizable interface, gore, exposed organs, or imitation of any copyrighted character or franchise.",
    `Style version: ${styleVersion}.`,
    `Prompt version: ${readNonEmptyString(env.MONSTER_PROMPT_VERSION, DEFAULT_PROMPT_VERSION)}.`,
  ].join("\n");
}

export async function requestMonsterImage({ prompt, previousObject, level, env }) {
  const model = readNonEmptyString(env.MONSTER_IMAGE_MODEL, DEFAULT_IMAGE_MODEL);
  let response;

  if (!previousObject) {
    response = await fetch(OPENAI_IMAGE_GENERATIONS_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        prompt,
        size: "1024x1024",
        quality: "low",
        output_format: "webp",
        output_compression: 80,
        background: "opaque",
        n: 1,
      }),
      signal: AbortSignal.timeout(180_000),
    });
  } else {
    const form = new FormData();
    form.set("model", model);
    form.set("prompt", prompt);
    form.set("size", "1024x1024");
    form.set("quality", "low");
    form.set("output_format", "webp");
    form.set("output_compression", "80");
    form.set("background", "opaque");
    form.append("image[]", await previousObject.blob(), `level-${level - 1}.webp`);

    response = await fetch(OPENAI_IMAGE_EDITS_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}` },
      body: form,
      signal: AbortSignal.timeout(180_000),
    });
  }

  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new MonsterServiceError(
      502,
      "invalid_openai_image_response",
      "OpenAI returned an unreadable image response.",
      true,
    );
  }

  if (!response.ok) {
    const code = response.status === 401
      ? "openai_authentication_failed"
      : response.status === 429
        ? "openai_image_rate_limited"
        : "openai_image_request_failed";
    throw new MonsterServiceError(
      response.status === 429 ? 503 : 502,
      code,
      "The OpenAI image request failed.",
      response.status !== 401,
    );
  }

  const imageBase64 = payload?.data?.[0]?.b64_json;
  return decodeImageBase64(imageBase64);
}

export function decodeImageBase64(value) {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > MAX_IMAGE_BASE64_LENGTH ||
    value.length % 4 !== 0 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(value)
  ) {
    throw new MonsterServiceError(
      502,
      "invalid_openai_image_data",
      "OpenAI returned invalid image data.",
      true,
    );
  }

  let binary;
  try {
    binary = atob(value);
  } catch {
    throw new MonsterServiceError(
      502,
      "invalid_openai_image_data",
      "OpenAI returned invalid image data.",
      true,
    );
  }

  if (binary.length === 0 || binary.length > MAX_GENERATED_IMAGE_BYTES) {
    throw new MonsterServiceError(
      502,
      "openai_image_size_invalid",
      "The generated image size is invalid.",
      true,
    );
  }

  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function findOrCreateSpecies(env, input) {
  let species = await findSpeciesByCanonicalTag(env.MONSTER_DB, input.canonicalTag);
  if (species) return species;

  const now = new Date().toISOString();
  const speciesId = crypto.randomUUID();
  await env.MONSTER_DB.prepare(
    `INSERT OR IGNORE INTO monster_species (
       id,
       canonical_tag,
       display_name,
       badge_kind,
       visual_dna_json,
       style_version,
       created_at,
       updated_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    speciesId,
    input.canonicalTag,
    input.displayName,
    input.badgeKind,
    JSON.stringify(deriveVisualDNA(input.canonicalTag, input.badgeKind)),
    readNonEmptyString(env.MONSTER_STYLE_VERSION, DEFAULT_STYLE_VERSION),
    now,
    now,
  ).run();

  species = await findSpeciesByCanonicalTag(env.MONSTER_DB, input.canonicalTag);
  if (!species) {
    throw new MonsterServiceError(
      503,
      "monster_species_write_failed",
      "Unable to create the monster species.",
      true,
    );
  }
  return species;
}

async function findSpeciesByCanonicalTag(database, canonicalTag) {
  return database.prepare(
    `SELECT id, canonical_tag, display_name, badge_kind, visual_dna_json, style_version
     FROM monster_species
     WHERE canonical_tag = ? COLLATE NOCASE
     LIMIT 1`,
  ).bind(canonicalTag).first();
}

async function findSpeciesByCanonicalTags(database, canonicalTags) {
  const species = new Map();
  if (!database || canonicalTags.length === 0) return species;

  const placeholders = canonicalTags.map(() => "?").join(", ");
  try {
    const result = await database.prepare(
      `SELECT canonical_tag, display_name
       FROM monster_species
       WHERE canonical_tag IN (${placeholders})`,
    ).bind(...canonicalTags).all();
    for (const row of result.results || []) {
      species.set(row.canonical_tag, row);
    }
  } catch {
    // Task generation remains available if the optional catalog lookup fails.
  }
  return species;
}

async function ensureVariantRows(env, speciesId, targetLevel) {
  const now = new Date().toISOString();
  const styleVersion = readNonEmptyString(env.MONSTER_STYLE_VERSION, DEFAULT_STYLE_VERSION);
  const promptVersion = readNonEmptyString(env.MONSTER_PROMPT_VERSION, DEFAULT_PROMPT_VERSION);
  const statements = [];
  for (let level = 1; level <= targetLevel; level += 1) {
    statements.push(
      env.MONSTER_DB.prepare(
        `INSERT OR IGNORE INTO monster_variants (
           id,
           species_id,
           level,
           status,
           prompt_version,
           style_version,
           created_at,
           updated_at
         ) VALUES (?, ?, ?, 'pending', ?, ?, ?, ?)`,
      ).bind(
        crypto.randomUUID(),
        speciesId,
        level,
        promptVersion,
        styleVersion,
        now,
        now,
      ),
    );
  }
  await env.MONSTER_DB.batch(statements);

  const target = await env.MONSTER_DB.prepare(
    `SELECT id, species_id, level, status, image_object_key, style_version, queue_enqueued_at
     FROM monster_variants
     WHERE species_id = ? AND level = ? AND style_version = ?
     LIMIT 1`,
  ).bind(speciesId, targetLevel, styleVersion).first();
  if (!target) {
    throw new MonsterServiceError(
      503,
      "monster_variant_write_failed",
      "Unable to create the monster variant.",
      true,
    );
  }
  return target;
}

async function enqueueVariantIfNeeded(env, targetVariant, speciesId, targetLevel) {
  const now = new Date();
  const nowISO = now.toISOString();
  const staleBefore = new Date(now.getTime() - ENQUEUE_STALE_MS).toISOString();
  const claim = await env.MONSTER_DB.prepare(
    `UPDATE monster_variants
     SET
       status = CASE WHEN status = 'failed' THEN 'pending' ELSE status END,
       queue_enqueued_at = ?,
       failure_code = NULL,
       updated_at = ?
     WHERE id = ?
       AND status <> 'ready'
       AND (
         status = 'failed'
         OR queue_enqueued_at IS NULL
         OR queue_enqueued_at < ?
       )`,
  ).bind(nowISO, nowISO, targetVariant.id, staleBefore).run();

  if (readD1Changes(claim) === 0) return;

  try {
    await env.MONSTER_GENERATION_QUEUE.send({
      speciesId,
      targetLevel,
      styleVersion: targetVariant.style_version,
    });
  } catch {
    await env.MONSTER_DB.prepare(
      `UPDATE monster_variants
       SET status = 'failed', queue_enqueued_at = NULL, failure_code = 'queue_unavailable', updated_at = ?
       WHERE id = ?`,
    ).bind(new Date().toISOString(), targetVariant.id).run();
    throw new MonsterServiceError(
      503,
      "monster_queue_unavailable",
      "Monster generation could not be queued.",
      true,
    );
  }
}

async function findVariantById(database, id) {
  return database.prepare(
    `SELECT id, species_id, level, status, image_object_key, style_version, queue_enqueued_at
     FROM monster_variants
     WHERE id = ?
     LIMIT 1`,
  ).bind(id).first();
}

async function reserveMonsterImageBudget(env) {
  if (!env.GLOBAL_USAGE_GATE) {
    return { allowed: false, reason: "protection_unavailable" };
  }
  const monthlyMonsterImageBudget = readPositiveInteger(
    env.MONTHLY_MONSTER_IMAGE_BUDGET,
    DEFAULT_MONTHLY_IMAGE_BUDGET,
  );
  const monsterImagesPerMinute = readPositiveInteger(
    env.MONSTER_IMAGES_PER_MINUTE,
    DEFAULT_IMAGES_PER_MINUTE,
  );

  try {
    const id = env.GLOBAL_USAGE_GATE.idFromName("lifemedals-v1-global");
    const gate = env.GLOBAL_USAGE_GATE.get(id);
    const response = await gate.fetch("https://usage-gate.internal/reserve-monster-image", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ monthlyMonsterImageBudget, monsterImagesPerMinute }),
    });
    if (!response.ok) return { allowed: false, reason: "protection_unavailable" };
    return await response.json();
  } catch {
    return { allowed: false, reason: "protection_unavailable" };
  }
}

async function reserveMonsterConceptBudget(env) {
  if (!env.GLOBAL_USAGE_GATE) {
    return { allowed: false, reason: "protection_unavailable" };
  }
  const requestsPerMinute = readPositiveInteger(env.GLOBAL_REQUESTS_PER_MINUTE, 20);
  const monthlyRequestBudget = readPositiveInteger(env.MONTHLY_REQUEST_BUDGET, 500);

  try {
    const id = env.GLOBAL_USAGE_GATE.idFromName("lifemedals-v1-global");
    const gate = env.GLOBAL_USAGE_GATE.get(id);
    const response = await gate.fetch("https://usage-gate.internal/reserve", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ requestsPerMinute, monthlyRequestBudget }),
    });
    if (!response.ok) return { allowed: false, reason: "protection_unavailable" };
    return await response.json();
  } catch {
    return { allowed: false, reason: "protection_unavailable" };
  }
}

async function failVariant(database, variantId, failureCode) {
  await database.prepare(
    `UPDATE monster_variants
     SET status = 'failed', queue_enqueued_at = NULL, lease_expires_at = NULL, failure_code = ?, updated_at = ?
     WHERE id = ?`,
  ).bind(sanitizeFailureCode(failureCode), new Date().toISOString(), variantId).run();
}

async function resetVariantPending(database, variantId, failureCode) {
  await database.prepare(
    `UPDATE monster_variants
     SET status = 'pending', queue_enqueued_at = NULL, lease_expires_at = NULL, failure_code = ?, updated_at = ?
     WHERE id = ?`,
  ).bind(sanitizeFailureCode(failureCode), new Date().toISOString(), variantId).run();
}

function normalizeGeneratedMonsterDescriptor(value) {
  const descriptor = isPlainObject(value) ? { ...value } : {};
  const canonicalTag = normalizeCanonicalTag(descriptor.monster_tag);
  descriptor.monster_tag = canonicalTag;

  const displayName = typeof descriptor.monster_display_name === "string"
    ? descriptor.monster_display_name.trim()
    : "";
  descriptor.monster_display_name = DISPLAY_NAME_PATTERN.test(displayName)
    ? displayName
    : FALLBACK_DISPLAY_NAMES[canonicalTag] || prettifyCanonicalTag(canonicalTag);
  descriptor.monster_match_kind = descriptor.monster_match_kind === "existing"
    ? "existing"
    : "new";
  return descriptor;
}

function deriveVisualDNA(canonicalTag, badgeKind) {
  const finalName = canonicalTag.split(".").pop()?.replaceAll("_", " ") || "quest";
  const badgeDNA = {
    Solver: {
      body: "compact clever imp or wisp",
      colors: ["indigo", "cyan"],
      feature: "glowing puzzle rune",
      temperament: "curious",
    },
    Builder: {
      body: "compact crafting sprite or slime",
      colors: ["orange", "steel"],
      feature: "small maker tool",
      temperament: "inventive",
    },
    Career: {
      body: "small polished courier creature",
      colors: ["navy", "gold"],
      feature: "professional messenger charm",
      temperament: "reliable",
    },
    Athlete: {
      body: "friendly compact training beast",
      colors: ["red", "charcoal"],
      feature: "athletic wristbands",
      temperament: "energetic",
    },
  };
  return { subject: finalName, ...(badgeDNA[badgeKind] || badgeDNA.Solver) };
}

function variantSnapshot(variant, env) {
  const ready = variant.status === "ready" && typeof variant.image_object_key === "string";
  return {
    variant_id: variant.id,
    status: VARIANT_STATUSES.has(variant.status) ? variant.status : "pending",
    image_url: ready ? publicMonsterAssetURL(env, variant.image_object_key) : null,
    style_version: variant.style_version || DEFAULT_STYLE_VERSION,
  };
}

function publicMonsterAssetURL(env, objectKey) {
  const configuredBase = readNonEmptyString(env.MONSTER_ASSET_BASE_URL, "").replace(/\/+$/, "");
  if (!configuredBase) return null;
  return `${configuredBase}/${objectKey.split("/").map(encodeURIComponent).join("/")}`;
}

function isValidMonsterObjectKey(value) {
  return /^monsters\/[a-z0-9][a-z0-9._-]{0,39}\/[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\/level-[1-9]-[a-f0-9]{64}\.webp$/.test(value);
}

function normalizeCanonicalTag(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function isValidCanonicalTag(value) {
  return typeof value === "string" && value.length <= 80 && CANONICAL_TAG_PATTERN.test(value);
}

function prettifyCanonicalTag(tag) {
  const finalComponent = tag.split(".").pop() || "Quest Creature";
  return finalComponent
    .replaceAll("_", " ")
    .split(" ")
    .filter(Boolean)
    .map((word) => word.slice(0, 1).toUpperCase() + word.slice(1))
    .join(" ")
    .slice(0, 60) || "Quest Creature";
}

async function readRequestTextBounded(request, limit) {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > limit) {
    throw new MonsterServiceError(
      413,
      "request_too_large",
      `Request body must not exceed ${limit} bytes.`,
    );
  }
  if (!request.body) return "";

  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      throw new MonsterServiceError(
        413,
        "request_too_large",
        `Request body must not exceed ${limit} bytes.`,
      );
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

async function sha256Hex(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...digest].map((value) => value.toString(16).padStart(2, "0")).join("");
}

function readD1Changes(result) {
  const changes = Number(result?.meta?.changes);
  return Number.isFinite(changes) ? changes : 0;
}

function readPositiveInteger(value, fallback) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function readNonEmptyString(value, fallback) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : fallback;
}

function isBoundedNonEmptyString(value, maxLength) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= maxLength;
}

function isBoundedStringArray(value, minItems, maxItems, maxStringLength) {
  return Array.isArray(value) &&
    value.length >= minItems &&
    value.length <= maxItems &&
    value.every((item) => isBoundedNonEmptyString(item, maxStringLength));
}

function findOpenAIOutputText(response) {
  if (typeof response?.output_text === "string") return response.output_text;
  if (!Array.isArray(response?.output)) return "";
  for (const item of response.output) {
    if (!Array.isArray(item?.content)) continue;
    for (const content of item.content) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        return content.text;
      }
    }
  }
  return "";
}

function sanitizeFailureCode(value) {
  const safe = String(value || "monster_generation_failed")
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "_")
    .slice(0, 80);
  return safe || "monster_generation_failed";
}

function normalizeServiceError(error) {
  if (error instanceof MonsterServiceError) return error;
  return new MonsterServiceError(
    503,
    "monster_service_unavailable",
    "The monster service is temporarily unavailable.",
    true,
  );
}

function missingMonsterBinding(env) {
  if (!env.MONSTER_DB) return "MONSTER_DB";
  if (!env.MONSTER_ASSETS) return "MONSTER_ASSETS";
  if (!env.MONSTER_GENERATION_QUEUE) return "MONSTER_GENERATION_QUEUE";
  return null;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function monsterJsonError(status, code, message, requestId) {
  return monsterJsonResponse({ error: { code, message } }, status, requestId);
}

function monsterJsonResponse(body, status, requestId, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-ID": requestId,
      ...extraHeaders,
    },
  });
}
