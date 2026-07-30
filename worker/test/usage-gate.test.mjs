import test from "node:test";
import assert from "node:assert/strict";

import { GlobalUsageGate } from "../src/index.ts";

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
