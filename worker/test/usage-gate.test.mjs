import test from "node:test";
import assert from "node:assert/strict";

import worker, {
  GlobalUsageGate,
  buildEvidenceVerificationOpenAIRequest,
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

const validEvidenceBody = {
  evidence_requirement: "提交显示两道题均为 Accepted 的截图。",
  images: [
    {
      mime_type: "image/jpeg",
      base64_data: Buffer.from("compressed-jpeg").toString("base64"),
    },
  ],
};

test("validates compressed evidence without accepting extra fields", () => {
  assert.equal(validateEvidenceVerificationInput(validEvidenceBody), null);
  assert.match(
    validateEvidenceVerificationInput({ ...validEvidenceBody, task_title: "ignored" }),
    /unsupported fields/,
  );
  assert.match(
    validateEvidenceVerificationInput({
      ...validEvidenceBody,
      images: [{ mime_type: "image/png", base64_data: "YWJjZA==" }],
    }),
    /image\/jpeg/,
  );
});

test("builds a stateless vision request around the locked requirement", () => {
  const request = buildEvidenceVerificationOpenAIRequest(validEvidenceBody, "test-model");

  assert.equal(request.model, "test-model");
  assert.equal(request.store, false);
  assert.equal(request.input[0].content[0].type, "input_text");
  assert.match(request.input[0].content[0].text, /提交显示两道题均为 Accepted 的截图。/);
  assert.equal(request.input[0].content[1].type, "input_image");
  assert.match(request.input[0].content[1].image_url, /^data:image\/jpeg;base64,/);
  assert.deepEqual(
    request.text.format.schema.properties.verdict.enum,
    ["verified", "need_more_proof", "not_verified"],
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
