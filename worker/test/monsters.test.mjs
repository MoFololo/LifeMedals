import test from "node:test";
import assert from "node:assert/strict";

import {
  buildMonsterConceptOpenAIRequest,
  buildMonsterPrompt,
  buildSpeciesId,
  classifyMonsterImageReservationRejection,
  decodeImageBase64,
  handleMonsterAsset,
  isCurrentMonsterConcept,
  normalizeGeneratedTaskMonsters,
  requestMonsterConcept,
  requestMonsterImage,
  speciesDescriptionFromCanonicalTag,
  validateMonsterConcept,
  validateEnsureMonsterInput,
  validateQueueMessage,
} from "../src/monsters.ts";

const transparentPngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=";

const validConcept = {
  action_metaphor: "Repeatedly untangling algorithm mazes under time pressure.",
  signature_objects: ["maze", "bracket"],
  creature_archetype: "a squat worried maze imp",
  body_shape: "one lopsided bean-shaped body with two tiny legs",
  face: "blank uneven eyes and a small uncertain mouth",
  task_features: [
    "a crooked maze groove carved across its forehead",
    "two bent bracket-shaped horns that nearly touch",
  ],
  palette: ["dirty indigo", "stale cyan", "warm gray"],
  linework: "chunky one-to-three-pixel stepped outlines with no anti-aliasing",
  silhouette: "a compact bean with bracket horns and oversized forehead",
  evolution_motif: "the forehead maze gains one branch and the horns knot closer at each level",
  image_description: "A squat lopsided maze imp with bracket horns stares blankly while tracing a glowing algorithm path through the maze groove in its oversized forehead.",
};

test("validates and normalizes an ensure-monster request", () => {
  assert.deepEqual(validateEnsureMonsterInput({
    canonical_tag: "  Coding.LeetCode ",
    badge_kind: "Solver",
    level: 3,
  }), {
    ok: true,
    value: {
      canonicalTag: "coding.leetcode",
      badgeKind: "Solver",
      level: 3,
    },
  });
  assert.equal(validateEnsureMonsterInput({
    canonical_tag: "coding.leetcode",
    display_name: "Algorithm Imp",
    badge_kind: "Solver",
    level: 1,
    task_title: "private data",
  }).ok, false);
  assert.equal(validateEnsureMonsterInput({
    canonical_tag: "private_person_alice",
    badge_kind: "Solver",
    level: 10,
  }).ok, false);
});

test("validates queue messages with a bounded level and style", () => {
  assert.deepEqual(validateQueueMessage({
    speciesId: "species-solver-leetcode",
    targetLevel: 9,
    styleVersion: "pixel-v1",
  }), { speciesId: "species-solver-leetcode", targetLevel: 9, styleVersion: "pixel-v1" });
  assert.throws(
    () => validateQueueMessage({ speciesId: crypto.randomUUID(), targetLevel: 1, styleVersion: "pixel-v1" }),
    /Invalid queue message/,
  );
});

test("retries temporary image reservation failures but stops at the monthly ceiling", () => {
  assert.deepEqual(classifyMonsterImageReservationRejection({ reason: "rate_limited" }), {
    status: 429,
    code: "image_rate_limited",
    retryable: true,
  });
  assert.deepEqual(classifyMonsterImageReservationRejection({ reason: "protection_unavailable" }), {
    status: 503,
    code: "image_budget_unavailable",
    retryable: true,
  });
  assert.deepEqual(classifyMonsterImageReservationRejection({ reason: "budget_exhausted" }), {
    status: 503,
    code: "image_budget_exhausted",
    retryable: false,
  });
});

test("builds categorized species IDs from the simplest English description", () => {
  assert.equal(speciesDescriptionFromCanonicalTag("communication.send_email", "Career"), "email");
  assert.equal(buildSpeciesId("communication.send_email", "Career"), "species-career-email");
  assert.equal(buildSpeciesId("gaming.close_console", "Life"), "species-life-console");
  assert.equal(buildSpeciesId("career.job_search", "Career"), "species-career-jobsearch");
  assert.doesNotMatch(buildSpeciesId("gaming.console", "Life"), /^[a-f0-9-]{36}$/);
});

test("normalizes descriptors and removes the group-root monster", async () => {
  const contract = await normalizeGeneratedTaskMonsters({
    kind: "task_group",
    monster_tag: "private.person",
    monster_display_name: "Private Person",
    monster_match_kind: "new",
    children: [
      {
        title: "Solve a problem",
        monster_tag: "Coding.LeetCode",
        monster_match_kind: "new",
      },
      {
        title: "Read a book",
        monster_tag: "reading.book",
        monster_match_kind: "existing",
      },
    ],
  }, {});

  assert.equal(contract.monster_tag, null);
  assert.equal("monster_display_name" in contract, false);
  assert.equal(contract.monster_match_kind, null);
  assert.deepEqual(
    contract.children.map((child) => [child.monster_tag, child.monster_match_kind]),
    [
      ["coding.leetcode", "existing"],
      ["reading.book", "new"],
    ],
  );
});

test("keeps named sports as distinct reusable species", async () => {
  const cases = [
    ["打一场篮球", "fitness.workout", "sports.basketball"],
    ["Swim ten laps", "fitness.workout", "sports.swimming"],
    ["Play tennis", "sports.activity", "sports.tennis"],
    ["Do a gym workout", "fitness.workout", "fitness.workout"],
  ];

  for (const [title, generatedTag, expectedTag] of cases) {
    const contract = await normalizeGeneratedTaskMonsters({
      kind: "single_task",
      title,
      monster_tag: generatedTag,
      monster_match_kind: "existing",
      children: [],
    }, {});
    assert.equal(contract.monster_tag, expectedTag);
    assert.equal(contract.monster_match_kind, "existing");
  }
});

test("classifies gaming tasks as Life unless they are game-development projects", async () => {
  const ordinaryGameTask = await normalizeGeneratedTaskMonsters({
    kind: "single_task",
    suggested_badge: "Solver",
    monster_tag: "gaming.console",
    monster_match_kind: "new",
    children: [],
  }, {});
  assert.equal(ordinaryGameTask.suggested_badge, "Life");

  const gameDevelopmentTask = await normalizeGeneratedTaskMonsters({
    kind: "single_task",
    suggested_badge: "Solver",
    monster_tag: "gaming.development",
    monster_match_kind: "new",
    children: [],
  }, {});
  assert.equal(gameDevelopmentTask.suggested_badge, "Builder");

  const incorrectlySuggestedBuilder = await normalizeGeneratedTaskMonsters({
    kind: "single_task",
    suggested_badge: "Builder",
    monster_tag: "gaming.console",
    monster_match_kind: "new",
    children: [],
  }, {});
  assert.equal(incorrectlySuggestedBuilder.suggested_badge, "Life");
});

test("uses D1 as the authority for an existing species taxonomy", async () => {
  const database = {
    prepare: () => ({
      bind: () => ({
        all: async () => ({
          results: [{ canonical_tag: "reading.book" }],
        }),
      }),
    }),
  };
  const contract = await normalizeGeneratedTaskMonsters({
    kind: "single_task",
    monster_tag: "reading.book",
    monster_match_kind: "new",
    children: [],
  }, { MONSTER_DB: database });

  assert.equal("monster_display_name" in contract, false);
  assert.equal(contract.monster_match_kind, "existing");
});

test("resolves an AI-generated English tag through an English alias", async () => {
  const database = {
    prepare: (sql) => ({
      bind: () => ({
        all: async () => ({
          results: sql.includes("FROM monster_aliases")
            ? [{ alias: "email", canonical_tag: "communication.send_email" }]
            : [],
        }),
      }),
    }),
  };
  const contract = await normalizeGeneratedTaskMonsters({
    kind: "single_task",
    monster_tag: "communication.email",
    monster_match_kind: "new",
    children: [],
  }, { MONSTER_DB: database });

  assert.equal(contract.monster_tag, "communication.send_email");
  assert.equal(contract.monster_match_kind, "existing");
});

test("builds a private-data-free concept request tied to the category", () => {
  const request = buildMonsterConceptOpenAIRequest({
    canonical_tag: "coding.leetcode",
    badge_kind: "Solver",
  }, {
    OPENAI_MODEL: "test-model",
    MONSTER_CONCEPT_PROMPT_VERSION: "concept-test-v1",
  });

  assert.equal(request.model, "test-model");
  assert.equal(request.store, false);
  assert.match(request.input, /coding\.leetcode/);
  assert.match(request.input, /SPECIES_ID\nspecies-solver-leetcode/);
  assert.doesNotMatch(request.input, /SPECIES_NAME/);
  assert.match(request.instructions, /strong visual metaphor/i);
  assert.match(request.instructions, /signature_objects/);
  assert.match(request.instructions, /basketball and\/or hoop/i);
  assert.match(request.instructions, /Every returned signature object must be visibly built into/i);
  assert.match(request.instructions, /logical 48 by 48 pixel sprite/i);
  assert.match(request.instructions, /chunky square pixel clusters/i);
  assert.match(request.instructions, /no anti-aliasing/i);
  assert.match(request.instructions, /not produce a generic/i);
  assert.match(request.instructions, /Concept prompt version: concept-test-v1/);
  assert.doesNotMatch(request.instructions, /Binding of Isaac/i);
  assert.equal(request.text.format.type, "json_schema");
  assert.equal(request.text.format.strict, true);
});

test("validates and requests a structured monster concept", async (t) => {
  assert.equal(validateMonsterConcept(validConcept), true);
  assert.equal(validateMonsterConcept({ ...validConcept, signature_objects: [] }), false);
  assert.equal(validateMonsterConcept({ ...validConcept, task_features: [] }), false);
  assert.equal(validateMonsterConcept({
    ...validConcept,
    image_description: "A generic monster without its bracket anchor.",
  }), false);

  const originalFetch = globalThis.fetch;
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init, body: JSON.parse(init.body) };
    return Response.json({ status: "completed", output_text: JSON.stringify(validConcept) });
  };
  t.after(() => { globalThis.fetch = originalFetch; });

  const result = await requestMonsterConcept({
    canonical_tag: "coding.leetcode",
    badge_kind: "Solver",
  }, { OPENAI_API_KEY: "test-only", OPENAI_MODEL: "test-model" });

  assert.deepEqual(result, validConcept);
  assert.equal(captured.url, "https://api.openai.com/v1/responses");
  assert.equal(captured.init.headers.Authorization, "Bearer test-only");
  assert.equal(captured.body.store, false);
  assert.equal(captured.body.text.format.name, "monster_species_concept");
});

test("invalidates stored concepts when the concept prompt version changes", () => {
  const species = {
    concept_status: "ready",
    concept_prompt_version: "monster-concept-v3",
    visual_dna_json: JSON.stringify(validConcept),
  };
  assert.equal(isCurrentMonsterConcept(species, {
    MONSTER_CONCEPT_PROMPT_VERSION: "monster-concept-v3",
  }), true);
  assert.equal(isCurrentMonsterConcept(species, {
    MONSTER_CONCEPT_PROMPT_VERSION: "monster-concept-v4",
  }), false);
  assert.equal(isCurrentMonsterConcept({ ...species, visual_dna_json: "{}" }, {
    MONSTER_CONCEPT_PROMPT_VERSION: "monster-concept-v3",
  }), false);
});

test("builds a stable evolution prompt without user task content", () => {
  const prompt = buildMonsterPrompt({
    canonical_tag: "coding.leetcode",
    badge_kind: "Solver",
    visual_dna_json: JSON.stringify(validConcept),
  }, 3, "grotesque-pixel-v3-transparent", { MONSTER_PROMPT_VERSION: "monster-image-v5" });

  assert.match(prompt, /coding\.leetcode/);
  assert.doesNotMatch(prompt, /Species name:/i);
  assert.match(prompt, /evolution level 3 of 9/i);
  assert.match(prompt, /Preserve the exact same face, body plan, palette/i);
  assert.match(prompt, /logical 48 by 48 pixel canvas/i);
  assert.match(prompt, /nearest-neighbor upscale/i);
  assert.match(prompt, /visible square-pixel grid/i);
  assert.match(prompt, /no anti-aliasing/i);
  assert.match(prompt, /extremely simple/i);
  assert.match(prompt, /No sprite sheet/i);
  assert.match(prompt, /glossy 3D/i);
  assert.match(prompt, /Prompt version: monster-image-v5/);
  assert.match(prompt, /entire area outside the monster must have zero alpha/i);
  assert.match(prompt, /no pale matte or fringe/i);
  assert.match(prompt, /MANDATORY SIGNATURE OBJECTS OR MATERIALS/i);
  assert.match(prompt, /"maze","bracket"/);
  assert.match(prompt, /missing any listed anchor is invalid/i);
  assert.match(prompt, /maze groove carved across its forehead/i);
  assert.doesNotMatch(prompt, /Binding of Isaac/i);
  assert.doesNotMatch(prompt, /task title|email address|user name/i);
});

test("requests a base transparent PNG with bounded low-cost settings", async (t) => {
  const originalFetch = globalThis.fetch;
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init, body: JSON.parse(init.body) };
    return Response.json({ data: [{ b64_json: transparentPngBase64 }] });
  };
  t.after(() => { globalThis.fetch = originalFetch; });

  const bytes = await requestMonsterImage({
    prompt: "safe prompt",
    previousObject: null,
    level: 1,
    env: { OPENAI_API_KEY: "test-only", MONSTER_IMAGE_MODEL: "gpt-image-2" },
  });

  assert.equal(captured.url, "https://api.openai.com/v1/images/generations");
  assert.equal(captured.init.headers.Authorization, "Bearer test-only");
  assert.equal(captured.body.model, "gpt-image-2");
  assert.equal(captured.body.output_format, "png");
  assert.equal(captured.body.background, "transparent");
  assert.equal("output_compression" in captured.body, false);
  assert.equal(captured.body.quality, "low");
  assert.equal("input_fidelity" in captured.body, false);
  assert.deepEqual(Array.from(bytes.slice(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10]);
});

test("edits the preceding image without placing the API key in form data", async (t) => {
  const originalFetch = globalThis.fetch;
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init };
    return Response.json({ data: [{ b64_json: transparentPngBase64 }] });
  };
  t.after(() => { globalThis.fetch = originalFetch; });

  const previousObject = {
    blob: async () => new Blob([new Uint8Array([1, 2, 3])], { type: "image/png" }),
  };
  await requestMonsterImage({
    prompt: "evolve safely",
    previousObject,
    level: 2,
    env: { OPENAI_API_KEY: "test-only", MONSTER_IMAGE_MODEL: "gpt-image-2" },
  });

  assert.equal(captured.url, "https://api.openai.com/v1/images/edits");
  assert.equal(captured.init.headers.Authorization, "Bearer test-only");
  assert.equal(captured.init.body.get("model"), "gpt-image-2");
  assert.equal(captured.init.body.get("quality"), "low");
  assert.equal(captured.init.body.get("output_format"), "png");
  assert.equal(captured.init.body.get("background"), "transparent");
  assert.equal(captured.init.body.get("output_compression"), null);
  assert.equal(captured.init.body.get("input_fidelity"), null);
  assert.equal(captured.init.body.get("OPENAI_API_KEY"), null);
  assert.equal(captured.init.body.get("image[]").name, "level-1.png");
});

test("rejects malformed data and serves only immutable monster keys", async () => {
  assert.throws(() => decodeImageBase64("not base64"), /invalid image data/i);
  const opaquePng = Buffer.from(transparentPngBase64, "base64");
  opaquePng[25] = 2;
  assert.throws(
    () => decodeImageBase64(opaquePng.toString("base64")),
    /PNG with an alpha channel/i,
  );

  const invalid = await handleMonsterAsset("/monster-assets/private.txt", {
    MONSTER_ASSETS: { get: async () => assert.fail("invalid keys must not reach R2") },
  }, "request-1");
  assert.equal(invalid.status, 404);

  const hash = "a".repeat(64);
  const validKey = `monsters/grotesque-pixel-v3-transparent/coding.leetcode/level-1-${hash}.png`;
  const response = await handleMonsterAsset(`/monster-assets/${validKey}`, {
    MONSTER_ASSETS: {
      get: async (key) => {
        assert.equal(key, validKey);
        return {
          body: new Blob([new Uint8Array([1, 2, 3])]).stream(),
          httpEtag: '"etag"',
          writeHttpMetadata: () => {},
        };
      },
    },
  }, "request-2");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Content-Type"), "image/png");
  assert.equal(response.headers.get("Cache-Control"), "public, max-age=31536000, immutable");
});
