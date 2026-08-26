import test from "node:test";
import assert from "node:assert/strict";

import {
  buildMonsterConceptOpenAIRequest,
  buildMonsterPrompt,
  decodeImageBase64,
  handleMonsterAsset,
  isCurrentMonsterConcept,
  normalizeGeneratedTaskMonsters,
  requestMonsterConcept,
  requestMonsterImage,
  validateMonsterConcept,
  validateEnsureMonsterInput,
  validateQueueMessage,
} from "../src/monsters.ts";

const validConcept = {
  action_metaphor: "Repeatedly untangling algorithm mazes under time pressure.",
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
  image_description: "A squat lopsided maze imp stares blankly while tracing a glowing algorithm path through the groove in its oversized forehead.",
};

test("validates and normalizes an ensure-monster request", () => {
  assert.deepEqual(validateEnsureMonsterInput({
    canonical_tag: "  Coding.LeetCode ",
    display_name: " Algorithm Imp ",
    badge_kind: "Solver",
    level: 3,
  }), {
    ok: true,
    value: {
      canonicalTag: "coding.leetcode",
      displayName: "Algorithm Imp",
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
    display_name: "Alice's Monster",
    badge_kind: "Solver",
    level: 10,
  }).ok, false);
});

test("validates queue messages with a bounded level and style", () => {
  assert.deepEqual(validateQueueMessage({
    speciesId: "species-1",
    targetLevel: 9,
    styleVersion: "pixel-v1",
  }), { speciesId: "species-1", targetLevel: 9, styleVersion: "pixel-v1" });
  assert.throws(
    () => validateQueueMessage({ speciesId: "species-1", targetLevel: 0, styleVersion: "../bad" }),
    /Invalid queue message/,
  );
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
        monster_display_name: "Wrong Name",
        monster_match_kind: "new",
      },
      {
        title: "Read a book",
        monster_tag: "reading.book",
        monster_display_name: "Book Moth",
        monster_match_kind: "existing",
      },
    ],
  }, {});

  assert.equal(contract.monster_tag, null);
  assert.equal(contract.monster_display_name, null);
  assert.equal(contract.monster_match_kind, null);
  assert.deepEqual(
    contract.children.map((child) => [child.monster_tag, child.monster_display_name, child.monster_match_kind]),
    [
      ["coding.leetcode", "Wrong Name", "existing"],
      ["reading.book", "Book Moth", "new"],
    ],
  );
});

test("uses D1 as the authority for an existing species name", async () => {
  const database = {
    prepare: () => ({
      bind: () => ({
        all: async () => ({
          results: [{ canonical_tag: "reading.book", display_name: "Archive Moth" }],
        }),
      }),
    }),
  };
  const contract = await normalizeGeneratedTaskMonsters({
    kind: "single_task",
    monster_tag: "reading.book",
    monster_display_name: "Book Moth",
    monster_match_kind: "new",
    children: [],
  }, { MONSTER_DB: database });

  assert.equal(contract.monster_display_name, "Archive Moth");
  assert.equal(contract.monster_match_kind, "existing");
});

test("builds a private-data-free concept request tied to the category", () => {
  const request = buildMonsterConceptOpenAIRequest({
    canonical_tag: "coding.leetcode",
    display_name: "Algorithm Imp",
    badge_kind: "Solver",
  }, {
    OPENAI_MODEL: "test-model",
    MONSTER_CONCEPT_PROMPT_VERSION: "concept-test-v1",
  });

  assert.equal(request.model, "test-model");
  assert.equal(request.store, false);
  assert.match(request.input, /coding\.leetcode/);
  assert.match(request.instructions, /strong visual metaphor/i);
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
  assert.equal(validateMonsterConcept({ ...validConcept, task_features: [] }), false);

  const originalFetch = globalThis.fetch;
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init, body: JSON.parse(init.body) };
    return Response.json({ status: "completed", output_text: JSON.stringify(validConcept) });
  };
  t.after(() => { globalThis.fetch = originalFetch; });

  const result = await requestMonsterConcept({
    canonical_tag: "coding.leetcode",
    display_name: "Algorithm Imp",
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
    concept_prompt_version: "monster-concept-v2",
    visual_dna_json: JSON.stringify(validConcept),
  };
  assert.equal(isCurrentMonsterConcept(species, {
    MONSTER_CONCEPT_PROMPT_VERSION: "monster-concept-v2",
  }), true);
  assert.equal(isCurrentMonsterConcept(species, {
    MONSTER_CONCEPT_PROMPT_VERSION: "monster-concept-v3",
  }), false);
  assert.equal(isCurrentMonsterConcept({ ...species, visual_dna_json: "{}" }, {
    MONSTER_CONCEPT_PROMPT_VERSION: "monster-concept-v2",
  }), false);
});

test("builds a stable evolution prompt without user task content", () => {
  const prompt = buildMonsterPrompt({
    canonical_tag: "coding.leetcode",
    display_name: "Algorithm Imp",
    badge_kind: "Solver",
    visual_dna_json: JSON.stringify(validConcept),
  }, 3, "grotesque-pixel-v1", { MONSTER_PROMPT_VERSION: "monster-image-v3" });

  assert.match(prompt, /coding\.leetcode/);
  assert.match(prompt, /evolution level 3 of 9/i);
  assert.match(prompt, /Preserve the exact same face, body plan, palette/i);
  assert.match(prompt, /logical 48 by 48 pixel canvas/i);
  assert.match(prompt, /nearest-neighbor upscale/i);
  assert.match(prompt, /visible square-pixel grid/i);
  assert.match(prompt, /no anti-aliasing/i);
  assert.match(prompt, /extremely simple/i);
  assert.match(prompt, /No sprite sheet/i);
  assert.match(prompt, /glossy 3D/i);
  assert.match(prompt, /Prompt version: monster-image-v3/);
  assert.match(prompt, /maze groove carved across its forehead/i);
  assert.doesNotMatch(prompt, /Binding of Isaac/i);
  assert.doesNotMatch(prompt, /task title|email address|user name/i);
});

test("requests a base WebP image with bounded low-cost settings", async (t) => {
  const originalFetch = globalThis.fetch;
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init, body: JSON.parse(init.body) };
    return Response.json({ data: [{ b64_json: Buffer.from("webp-bytes").toString("base64") }] });
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
  assert.equal(captured.body.output_format, "webp");
  assert.equal(captured.body.output_compression, 80);
  assert.equal(captured.body.quality, "low");
  assert.equal("input_fidelity" in captured.body, false);
  assert.equal(Buffer.from(bytes).toString(), "webp-bytes");
});

test("edits the preceding image without placing the API key in form data", async (t) => {
  const originalFetch = globalThis.fetch;
  let captured;
  globalThis.fetch = async (url, init) => {
    captured = { url, init };
    return Response.json({ data: [{ b64_json: Buffer.from("evolved-webp").toString("base64") }] });
  };
  t.after(() => { globalThis.fetch = originalFetch; });

  const previousObject = {
    blob: async () => new Blob([new Uint8Array([1, 2, 3])], { type: "image/webp" }),
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
  assert.equal(captured.init.body.get("input_fidelity"), null);
  assert.equal(captured.init.body.get("OPENAI_API_KEY"), null);
  assert.equal(captured.init.body.get("image[]").name, "level-1.webp");
});

test("rejects malformed data and serves only immutable monster keys", async () => {
  assert.throws(() => decodeImageBase64("not base64"), /invalid image data/i);

  const invalid = await handleMonsterAsset("/monster-assets/private.txt", {
    MONSTER_ASSETS: { get: async () => assert.fail("invalid keys must not reach R2") },
  }, "request-1");
  assert.equal(invalid.status, 404);

  const hash = "a".repeat(64);
  const validKey = `monsters/grotesque-pixel-v1/coding.leetcode/level-1-${hash}.webp`;
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
  assert.equal(response.headers.get("Content-Type"), "image/webp");
  assert.equal(response.headers.get("Cache-Control"), "public, max-age=31536000, immutable");
});
