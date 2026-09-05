import test from "node:test";
import assert from "node:assert/strict";

import worker, {
  GlobalUsageGate,
  buildTaskGenerationOpenAIRequest,
  buildEvidenceVerificationOpenAIRequest,
  isTaskContract,
  validateGenerateTaskInput,
  validateEvidenceVerificationInput,
} from "../src/index.ts";

class MemoryStorage {
  constructor() {
    this.values = new Map();
  }

  transaction(callback) {
    return callback({
      get: async (key) => this.values.get(key),
      put: async (key, value) => this.values.set(key, value),
    });
  }
}

async function reserve(gate, requestsPerMinute, monthlyRequestBudget) {
  const response = await gate.fetch(
    new Request("https://usage-gate.internal/reserve", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ requestsPerMinute, monthlyRequestBudget }),
    }),
  );
  return response.json();
}

async function reserveMonsterImage(gate, monthlyMonsterImageBudget, monsterImagesPerMinute = 10) {
  const response = await gate.fetch(
    new Request("https://usage-gate.internal/reserve-monster-image", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ monthlyMonsterImageBudget, monsterImagesPerMinute }),
    }),
  );
  return response.json();
}

test("enforces the global fixed-window rate limit", async () => {
  const gate = new GlobalUsageGate({ storage: new MemoryStorage() });

  assert.equal((await reserve(gate, 2, 10)).allowed, true);
  assert.equal((await reserve(gate, 2, 10)).allowed, true);

  const rejected = await reserve(gate, 2, 10);
  assert.equal(rejected.allowed, false);
  assert.equal(rejected.reason, "rate_limited");
  assert.ok(rejected.retryAfterSeconds >= 1);
});

test("enforces the monthly hard request budget", async () => {
  const gate = new GlobalUsageGate({ storage: new MemoryStorage() });

  assert.equal((await reserve(gate, 10, 2)).allowed, true);
  assert.equal((await reserve(gate, 10, 2)).allowed, true);

  const rejected = await reserve(gate, 10, 2);
  assert.equal(rejected.allowed, false);
  assert.equal(rejected.reason, "budget_exhausted");
  assert.match(rejected.resetAt, /^\d{4}-\d{2}-01T00:00:00\.000Z$/);
});

test("enforces an independent monthly monster image budget", async () => {
  const gate = new GlobalUsageGate({ storage: new MemoryStorage() });

  assert.equal((await reserveMonsterImage(gate, 2)).allowed, true);
  assert.equal((await reserveMonsterImage(gate, 2)).allowed, true);

  const rejected = await reserveMonsterImage(gate, 2);
  assert.equal(rejected.allowed, false);
  assert.equal(rejected.reason, "budget_exhausted");
  assert.match(rejected.resetAt, /^\d{4}-\d{2}-01T00:00:00\.000Z$/);
});

test("enforces an independent monster image rate limit", async () => {
  const gate = new GlobalUsageGate({ storage: new MemoryStorage() });

  assert.equal((await reserveMonsterImage(gate, 20, 2)).allowed, true);
  assert.equal((await reserveMonsterImage(gate, 20, 2)).allowed, true);
  const rejected = await reserveMonsterImage(gate, 20, 2);
  assert.equal(rejected.allowed, false);
  assert.equal(rejected.reason, "rate_limited");
  assert.ok(rejected.retryAfterSeconds >= 1);
});

const validEvidenceBody = {
  task_title: "完成两道 LeetCode",
  evidence_requirement: "提交显示两道题均为 Accepted 的截图。",
  images: [
    {
      mime_type: "image/jpeg",
      base64_data: Buffer.from("compressed-jpeg").toString("base64"),
    },
  ],
};

const validImageTaskBody = {
  text: "帮我提取最重要的下一步",
  timezone: "America/New_York",
  locale: "zh-CN",
  source_image: {
    mime_type: "image/jpeg",
    base64_data: Buffer.from("compressed-source-jpeg").toString("base64"),
  },
};

test("health identifies the deployed Worker release", async () => {
  const response = await worker.fetch(
    new Request("https://example.test/health"),
    { OPENAI_API_KEY: "test-only", GLOBAL_USAGE_GATE: {} },
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.release, "2026-09-04-transparent-monster-png-1");
  assert.equal(body.monsterServiceConfigured, false);
  assert.equal(response.headers.get("X-LifeMedals-Release"), body.release);
});

test("validates image task input and requires text or an image", () => {
  assert.equal(validateGenerateTaskInput(validImageTaskBody), null);
  assert.equal(validateGenerateTaskInput({ ...validImageTaskBody, text: "" }), null);
  assert.match(
    validateGenerateTaskInput({ text: "", timezone: "UTC", locale: "en-US" }),
    /Either non-empty text or source_image/,
  );
  assert.match(
    validateGenerateTaskInput({
      ...validImageTaskBody,
      source_image: { ...validImageTaskBody.source_image, mime_type: "image/png" },
    }),
    /image\/jpeg/,
  );
});

test("builds a stateless vision request for task generation", () => {
  const request = buildTaskGenerationOpenAIRequest(validImageTaskBody, "test-model");

  assert.equal(request.model, "test-model");
  assert.equal(request.store, false);
  assert.equal(request.input[0].content[0].type, "input_text");
  assert.match(request.input[0].content[0].text, /帮我提取最重要的下一步/);
  assert.equal(request.input[0].content[1].type, "input_image");
  assert.match(request.input[0].content[1].image_url, /^data:image\/jpeg;base64,/);
  assert.match(request.instructions, /extract every independent executable action/);
  assert.match(request.instructions, /heading such as Next Steps.*not a child task/);
  assert.match(request.instructions, /Preserve explicit dates exactly/);
  assert.match(request.instructions, /same calendar date one month later/);
  assert.equal("deadline_preset" in request.text.format.schema.properties, false);
  assert.match(request.instructions, /own objective, lightweight evidence requirement/);
  assert.match(request.instructions, /names, email addresses, phone numbers/);
  assert.match(request.instructions, /never cause redaction, omission, refusal/);
  assert.match(request.instructions, /monster_tag/);
  assert.match(request.instructions, /Use monster_match_kind=existing/i);
  assert.match(request.instructions, /Life includes chores, cooking, errands, sending packages, games/i);
  assert.match(request.instructions, /Exercise and sports always use Athlete/i);
  assert.match(request.instructions, /sports\.basketball/);
  assert.match(request.instructions, /Never collapse a named sport into fitness\.workout/i);
  assert.match(request.instructions, /same specificity rule across every badge/i);
  assert.match(request.instructions, /chores\.take_out_trash rather than chores\.household/i);
  assert.match(request.instructions, /taxonomy is always English/i);
  assert.match(request.instructions, /gaming\.console, not controls\.toggle/i);
  assert.doesNotMatch(request.instructions, /monster_display_name/);
  assert.deepEqual(
    request.text.format.schema.properties.suggested_badge.enum,
    ["Solver", "Builder", "Career", "Athlete", "Life"],
  );
  assert.equal("monster_display_name" in request.text.format.schema.properties, false);
  assert.equal(
    "monster_display_name" in request.text.format.schema.properties.children.items.properties,
    false,
  );
  assert.equal("evidence_image_count" in request.text.format.schema.properties, false);
  assert.equal("evidence_image_descriptions" in request.text.format.schema.properties, false);
  assert.equal(
    "evidence_image_count" in request.text.format.schema.properties.children.items.properties,
    false,
  );
  assert.doesNotMatch(request.instructions, /privacy-conscious/);
});

test("allows visible personal information during evidence verification", () => {
  const request = buildEvidenceVerificationOpenAIRequest(validEvidenceBody, "test-model");

  assert.match(request.instructions, /names, email addresses, phone numbers/);
  assert.match(request.instructions, /must never lower the verdict/);
  assert.match(request.instructions, /Temporary testing exception/);
  assert.match(request.instructions, /hide, blur, redact, crop out, omit/);
  assert.match(request.instructions, /printed name is visible text, not biometric identification/i);
});

test("treats drafts, scheduled emails, and sent emails as task-related effort", () => {
  const generationRequest = buildTaskGenerationOpenAIRequest(
    {
      text: "Write and send my professor an email tomorrow morning.",
      timezone: "America/New_York",
      locale: "en-US",
    },
    "test-model",
  );
  const verificationRequest = buildEvidenceVerificationOpenAIRequest(
    {
      ...validEvidenceBody,
      evidence_requirement: "Show that the email to the professor was sent.",
      task_title: "Send my RA resume to the professor",
    },
    "test-model",
  );

  assert.match(generationRequest.instructions, /confirmed scheduled-send state/i);
  assert.match(generationRequest.instructions, /Never invent or require a formal application page/i);
  assert.match(verificationRequest.instructions, /visible email conversation, draft, sent message, scheduled message/i);
  assert.match(verificationRequest.instructions, /task-related effort and must be verified/i);
  assert.match(verificationRequest.instructions, /writing, drafting, scheduling, or sending/i);
  assert.match(verificationRequest.instructions, /Do not require proof of recipient, content, delivery, timing, or sent status/i);
  assert.doesNotMatch(verificationRequest.instructions, /unsent draft.*not enough/i);
});

test("generate-task forwards the source image without storing response state", async (t) => {
  const originalFetch = globalThis.fetch;
  let capturedRequest;
  globalThis.fetch = async (url, init) => {
    capturedRequest = { url, body: JSON.parse(init.body) };
    return Response.json({
      status: "completed",
      output_text: JSON.stringify({
        kind: "single_task",
        title: "报名校园摄影社",
        description: "根据海报要求完成校园摄影社报名。",
        deadline: "2026-08-24T23:59:00-04:00",
        deadline_preset: "tomorrow",
        evidence_requirement: "提交报名成功页面截图。",
        suggested_badge: "Career",
        estimated_hours: 0.25,
        monster_tag: "communication.career",
        monster_match_kind: "existing",
        children: [],
      }),
    });
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const env = {
    OPENAI_API_KEY: "test-only",
    OPENAI_MODEL: "test-model",
    GLOBAL_USAGE_GATE: {
      idFromName: () => "global-id",
      get: () => ({ fetch: async () => Response.json({ allowed: true }) }),
    },
  };
  const response = await worker.fetch(
    new Request("https://example.test/generate-task", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validImageTaskBody),
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal(capturedRequest.url, "https://api.openai.com/v1/responses");
  assert.equal(capturedRequest.body.store, false);
  assert.equal(capturedRequest.body.input[0].content[1].type, "input_image");
  assert.equal((await response.json()).title, "报名校园摄影社");
});

test("validates compressed evidence without accepting extra fields", () => {
  assert.equal(validateEvidenceVerificationInput(validEvidenceBody), null);
  assert.match(
    validateEvidenceVerificationInput({ ...validEvidenceBody, ignored: "extra" }),
    /unsupported fields/,
  );
  assert.match(
    validateEvidenceVerificationInput({ ...validEvidenceBody, task_title: "" }),
    /task_title/,
  );
  assert.match(
    validateEvidenceVerificationInput({
      ...validEvidenceBody,
      images: [{ mime_type: "image/png", base64_data: "YWJjZA==" }],
    }),
    /image\/jpeg/,
  );
});

test("builds a supportive vision request using title-or-criterion verification", () => {
  const request = buildEvidenceVerificationOpenAIRequest(validEvidenceBody, "test-model");

  assert.equal(request.model, "test-model");
  assert.equal(request.store, false);
  assert.equal(request.input[0].content[0].type, "input_text");
  assert.match(request.input[0].content[0].text, /TASK_TITLE\n完成两道 LeetCode/);
  assert.match(request.input[0].content[0].text, /ACCEPTANCE_CRITERION\n提交显示两道题均为 Accepted 的截图。/);
  assert.doesNotMatch(request.input[0].content[0].text, /EXPECTED_IMAGE_COUNT/);
  assert.match(request.instructions, /PRIMARY DECISION RULE/i);
  assert.match(request.instructions, /matching either one is enough/i);
  assert.match(request.instructions, /any work, effort, activity, artifact, attempt, partial progress/i);
  assert.match(request.instructions, /Assume the user finished any unseen remainder/i);
  assert.match(request.instructions, /only Today and Tomorrow is verified/i);
  assert.match(request.instructions, /criterion asks to show an ordinary date beyond/i);
  assert.match(request.instructions, /machine-learning notes/i);
  assert.match(request.instructions, /RA or job application performed by email/i);
  assert.match(request.instructions, /Never demand a formal application page/i);
  assert.match(request.instructions, /Any 1 to 5 submitted images/i);
  assert.match(request.instructions, /so blurry, dark, blank, blocked, or unreadable/i);
  assert.match(request.instructions, /every submitted image is clearly unrelated/i);
  assert.doesNotMatch(request.instructions, /materially contradict completion/i);
  assert.doesNotMatch(request.instructions, /clearly show the task remains incomplete/i);
  assert.doesNotMatch(request.instructions, /unsent draft with no other completion signal is not enough/i);
  assert.equal(request.input[0].content[1].type, "input_image");
  assert.match(request.input[0].content[1].image_url, /^data:image\/jpeg;base64,/);
  assert.deepEqual(
    request.text.format.schema.properties.verdict.enum,
    ["verified", "need_more_proof", "not_verified"],
  );
});

test("validates task contracts without requiring a photo plan", () => {
  const baseContract = {
    kind: "single_task",
    title: "完成两道 LeetCode",
    description: "完成两道指定难度的题目。",
    deadline: "2026-08-01T22:00:00+08:00",
    deadline_preset: "this_weekend",
    evidence_requirement: "提交两道题均为 Accepted 的截图。",
    suggested_badge: "Solver",
    estimated_hours: 0.5,
    monster_tag: "coding.leetcode",
    monster_match_kind: "existing",
    children: [],
  };

  assert.equal(isTaskContract(baseContract), true);
  assert.equal(
    isTaskContract({
      ...baseContract,
      evidence_image_count: 5,
      evidence_image_descriptions: ["旧客户端留下的兼容字段。"],
    }),
    true,
  );
  assert.equal(
    isTaskContract({ ...baseContract, evidence_image_descriptions: [] }),
    true,
  );
  assert.equal(
    isTaskContract((({ deadline_preset: _, ...contract }) => contract)(baseContract)),
    true,
  );
  assert.equal(
    isTaskContract({ ...baseContract, estimated_hours: 0.1 }),
    false,
  );
  assert.equal(
    isTaskContract({ ...baseContract, estimated_hours: 8.25 }),
    false,
  );
  assert.equal(
    isTaskContract({ ...baseContract, estimated_hours: 1.1 }),
    false,
  );
  assert.equal(
    isTaskContract({ ...baseContract, title: "这是一个超过十二个字的中文任务标题" }),
    false,
  );
  assert.equal(
    isTaskContract({ ...baseContract, title: "This task title contains more than eight English words total" }),
    false,
  );
});

test("validates task groups and requires child-specific acceptance criteria", () => {
  const child = (title) => ({
    title,
    description: `Details for ${title}.`,
    evidence_requirement: `Show completion of ${title}.`,
    estimated_hours: 0.25,
    monster_tag: "study.learning",
    monster_match_kind: "existing",
  });
  const group = {
    kind: "task_group",
    title: "Complete all Next Steps",
    description: "Finish the listed follow-up actions.",
    deadline: "2026-08-25T23:59:00-04:00",
    deadline_preset: "tomorrow",
    evidence_requirement: "",
    suggested_badge: "Solver",
    estimated_hours: 0.5,
    monster_tag: null,
    monster_match_kind: null,
    children: [child("Complete the survey"), child("Join Piazza")],
  };

  assert.equal(isTaskContract(group), true);
  assert.equal(isTaskContract({ ...group, children: [] }), false);
  // The client deliberately degrades a one-child group to a normal task.
  assert.equal(isTaskContract({ ...group, children: [child("Only action")] }), true);
  assert.equal(
    isTaskContract({
      ...group,
      children: [child("Complete the survey"), { ...child("Join Piazza"), evidence_requirement: "" }],
    }),
    false,
  );
  assert.equal(
    isTaskContract({ ...group, evidence_requirement: "Parent should not require proof" }),
    false,
  );
});

test("accepts any 1–5 evidence photos regardless of a legacy planned count", () => {
  assert.equal(
    validateEvidenceVerificationInput({
      ...validEvidenceBody,
      evidence_image_count: 2,
      evidence_image_descriptions: ["第一张", "第二张"],
    }),
    null,
  );
  assert.match(
    validateEvidenceVerificationInput({
      ...validEvidenceBody,
      images: [],
    }),
    /between 1 and 5/,
  );
});

test("verify-evidence fails closed when the global usage gate rejects it", async () => {
  const env = {
    OPENAI_API_KEY: "test-only",
    GLOBAL_USAGE_GATE: {
      idFromName: () => "global-id",
      get: () => ({
        fetch: async () => Response.json({
          allowed: false,
          reason: "rate_limited",
          retryAfterSeconds: 17,
        }),
      }),
    },
  };
  const response = await worker.fetch(
    new Request("https://example.test/verify-evidence", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validEvidenceBody),
    }),
    env,
  );

  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "17");
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});

test("verify-evidence forwards images statelessly and returns the three-state result", async (t) => {
  const originalFetch = globalThis.fetch;
  let capturedRequest;
  globalThis.fetch = async (url, init) => {
    capturedRequest = { url, init, body: JSON.parse(init.body) };
    return Response.json({
      status: "completed",
      output_text: JSON.stringify({
        verdict: "need_more_proof",
        explanation: "截图相关，但还需显示第二道题的 Accepted 状态。",
      }),
    });
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const env = {
    OPENAI_API_KEY: "test-only",
    OPENAI_MODEL: "test-model",
    GLOBAL_USAGE_GATE: {
      idFromName: () => "global-id",
      get: () => ({
        fetch: async () => Response.json({ allowed: true }),
      }),
    },
  };
  const response = await worker.fetch(
    new Request("https://example.test/verify-evidence", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validEvidenceBody),
    }),
    env,
  );

  assert.equal(response.status, 200);
  assert.equal(capturedRequest.url, "https://api.openai.com/v1/responses");
  assert.equal(capturedRequest.body.store, false);
  assert.equal(capturedRequest.body.model, "test-model");
  assert.equal(capturedRequest.body.input[0].content[1].type, "input_image");
  assert.deepEqual(await response.json(), {
    verdict: "need_more_proof",
    explanation: "截图相关，但还需显示第二道题的 Accepted 状态。",
  });
});

test("verify-evidence exposes the upstream refusal reason for testing", async (t) => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json({
    status: "completed",
    output: [
      {
        type: "message",
        content: [
          {
            type: "refusal",
            refusal: "Example refusal involving visible contact information.",
          },
        ],
      },
    ],
  });
  t.after(() => {
    globalThis.fetch = originalFetch;
  });

  const response = await worker.fetch(
    new Request("https://example.test/verify-evidence", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validEvidenceBody),
    }),
    {
      OPENAI_API_KEY: "test-only",
      GLOBAL_USAGE_GATE: {
        idFromName: () => "global-id",
        get: () => ({ fetch: async () => Response.json({ allowed: true }) }),
      },
    },
  );
  const body = await response.json();

  assert.equal(response.status, 422);
  assert.equal(body.error.code, "request_refused");
  assert.match(body.error.message, /Example refusal involving visible contact information/);
});
