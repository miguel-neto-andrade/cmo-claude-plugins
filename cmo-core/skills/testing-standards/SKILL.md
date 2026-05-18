---
name: testing-standards
description: Universal testing principles for any language / framework — tier structure (unit / integration / functional / performance), two-level Jira traceability (Task for unit + integration, Requirement for functional), test independence and parallel execution, anti-flake rules, scenario coverage. Use when writing, reviewing, or scaffolding tests in any project, in any language. Stack-specific patterns (test runner, fixture style, mocking library, framework helpers) live in dedicated skills (e.g., `dotnet-testing`, future `python-testing`, `frontend-testing`, `firmware-testing`).
---

# Testing Standards

Universal testing principles that apply regardless of language or framework. Stack-specific patterns (test runner, assertion library, mocking library, framework helpers) live in dedicated skills and reference back here for the rules below.

## Tiered testing

Every project distinguishes four tiers. Each tier lives in its own test project / directory / module, named per the stack's convention. Mixing tiers in one runner costs CI flexibility and the ability to gate slow tests behind a different cadence.

| Tier | Scope |
|---|---|
| Unit | Pure logic. No I/O, no host, no real external dependencies (DB, broker, file system, network). Services, handlers, validators, value objects, helpers. |
| Integration | The real wiring of the application against real external dependencies (DB, broker, object store, mail server, …) exercised through its real entry point (HTTP request, message consumer, scheduled job). Covers auth, validation, routing, persistence, message handling, migrations. |
| Functional / e2e | Top-level user-journey verification, typically browser-based. Only for projects with an end-user-facing surface (web UI, native app). Login flows, checkout, dashboard render. |
| Performance | Hot-path benchmarking against a stable baseline. Add only when a hot path is identified — never as table-stakes for a new project. |

### Coverage rule — endpoint scenarios

Every API endpoint's full scenario set — happy path, validation failures, authorisation failures (each non-allowed role / policy), not-found, conflict, unauthenticated, domain-specific errors — must be **covered somewhere**. The default tier split:

- **Unit tier carries the bulk.** Every branch of the request handler, every branch of each authorisation handler / policy class, every validator rule. These are pure(-ish) functions over their inputs; exhaustive cases run in milliseconds.
- **Integration tier is a thin wiring layer per endpoint** — one happy-path test plus at least one denied test per policy on the endpoint. Its job is to prove what unit tests cannot see: the right `[Authorize(Policy = …)]` is on the right action, the policy is registered with the correct handler lifetime, middleware ordering and EF translation work end-to-end, and the controller maps the handler's result to the correct status code / response shape.

Re-asserting handler branch coverage at the integration tier is duplication, not safety. Use the slow tier only for what the slow tier can uniquely prove.

**Integration assertions stay at the controller boundary.** Status code, response body shape, headers, and observable side effects on the real dependency (DB rows, queued messages). Integration tests do not reach inside to assert handler internals — that is the unit tier's job.

**Regulated-context exception.** If the project is under an audit trail that requires per-endpoint per-role HTTP-level evidence (typical for medical-device software and similar), promote the full matrix to the integration tier and accept the CI cost — the durable artifact "we hit `/foo` as role Y and got 403" is what an auditor accepts; "we tested the policy handler in isolation" is weaker. Document the elevation in the project's `CLAUDE.md` / testing README so it's an explicit choice, not a habit.

### Coverage rule — functional / e2e tier

Each critical user journey has at least one e2e smoke test. Full detailed coverage belongs in the integration tier — functional tests are the slowest and most brittle tier; one happy-path test per journey, not exhaustive coverage.

---

## Test independence and parallel execution

- **Tests are independent and run in parallel.** No test depends on another test's state, ordering, or side effects. Each test owns its data — seed what it needs, clean up nothing (the fixture or per-test scope does that).
- **Do not disable the test runner's parallelism** (xUnit collection parallelism, pytest-xdist, Vitest threads, Go `t.Parallel()`, …) without a concrete reason **and** a comment explaining it.
- **If two tests interact, one of them is buggy.** Fix the test that leaks state — never serialise the suite to mask a leak.
- **No arbitrary delays.** Never `Thread.Sleep` / `await asyncio.sleep` / `setTimeout` / `vTaskDelay` / `time.sleep` to "wait for something to happen". If a test is flaky on timing, the production code has a race. Fix the race, not the test.

---

## Traceability — two levels, tier-dependent

Required for regulated projects (medical-device software, customer-facing backends, anything under an IEC 62304 or similar regulatory audit trail). Optional for internal tools, dev tooling, and throwaway experiments — but if the project's README / `CLAUDE.md` is silent and the project ships to a regulated context, **assume traceability is required**.

When required, every test method carries a trait / marker / annotation linking it to a Jira issue. **The key depends on the tier**:

| Tier | Trait key | Jira issue type | Meaning |
|---|---|---|---|
| Unit | `Task` | Task | The work item that introduced this behaviour |
| Integration | `Task` | Task | Same — the contract a Task implements |
| Functional / e2e | `Requirement` | Requirement | The user-facing capability the journey verifies |

Both keys point at the same Jira project; the issue *type* (Task vs Requirement) tells the audit trail what level of contract the test is verifying.

- Tests that don't map to a single Jira issue (route-sanity probes, log-assertion teardowns, infra smoke tests) use a sentinel ID (e.g. `SW-INFRA`) under the `Task` key. **Never omit the key at the required tier.**
- **Don't fake IDs** in non-regulated projects to "look compliant" — skip the trait entirely.
- The trait must be queryable from CI so a Jira automation can pull the test list for a given Task or Requirement at release time.

Each stack's testing skill spells out exactly how the trait is expressed in that language's test runner and what filter syntax CI uses to slice by tier:

- **xUnit / .NET** — `[Trait(Traits.Task, "SW-1234")]` / `[Trait(Traits.Requirement, "SW-5678")]`; `dotnet test --filter "task=SW-1234"`.
- **pytest / Python** — `@pytest.mark.task("SW-1234")` / `@pytest.mark.requirement("SW-5678")`; `pytest -m "task and SW-1234"`.
- **Vitest / TypeScript** — `it("...").tag("task:SW-1234")` (or equivalent test-context API); `vitest --testNamePattern` or grep tag.
- **GoogleTest / C++** — test name suffix or a custom listener that emits the trait into the JUnit report; CI filter via gtest_filter.

The stack skill is the source of truth for the *syntax*; the rule above is the source of truth for *which key goes on which tier*.

---

## Test class and method naming

- **One subject per test class / module.** Named after the unit under test plus the stack's conventional suffix (`*Tests.cs` in C#, `test_*.py` in Python, `*.spec.ts` in TypeScript, `*Test.cpp` in C++).
- **One behaviour per test method / function.** Name follows the stack's idiom but always encodes **action + condition + observable outcome**:
  - C#/Java: `Method_Condition_Result` — e.g. `Approve_PendingInvoice_SetsStatusApproved`
  - Python: `test_method_condition_result` — e.g. `test_approve_pending_invoice_sets_status_approved`
  - TypeScript (BDD): `it("returns X when Y given Z")` — e.g. `it("returns 200 with the invoice when the customer exists")`
- **One assertion concept per test.** Multiple assertion calls are fine if they verify the same logical outcome.

---

## Test data

- Use a **builder helper** or a **faker library** (Bogus / Faker / `factory_boy` / `@faker-js/faker`) for non-trivial test data.
- Never scatter hand-rolled object literals across test files — the test reads as fixture noise, and changing the underlying type breaks dozens of unrelated tests.
- Each test seeds exactly what it needs. No "shared global fixture" that every test reads from — that's a parallel-execution and isolation hazard.
- Sensitive data (real PII, real credentials, real keys) never appears in test fixtures, even fake-looking ones. Use obviously-synthetic values: `"customer@example.test"`, `"+15555550100"`, `00000000-0000-0000-0000-000000000001`.

---

## Mirror the source layout

Test files mirror the production folder structure. `src/.../foo/bar/InvoiceService.cs` → `tests/.../foo/bar/InvoiceServiceTests.cs`. Same rule in Python: `app/foo/bar/invoice_service.py` → `tests/foo/bar/test_invoice_service.py`. Navigation is one click; refactors that move source code force matching test renames.

---

## Coverage is not the goal

Hitting 80% line coverage with weak assertions is not testing. Coverage is a lagging indicator; **scenario coverage** is the goal:

- Every behaviour change ships with a test that fails without the change and passes with it.
- Every API endpoint has every scenario covered *somewhere* — most at the unit tier, with a thin wiring smoke at the integration tier (see the rule above).
- Every critical user journey has at least one functional / e2e smoke test (where the project has a UI).

Reach for line-coverage tools (Coverlet, `pytest --cov`, `c8`, `gcovr`) for **blind-spot detection**, not as a CI gate. A red coverage diff is an invitation to look at what's missing — it is not, by itself, a reason to block a PR.

---

## Quick reference

| Aspect | Rule |
|---|---|
| Tiers | Unit / Integration / Functional / Performance — separate projects or modules per stack convention |
| Unit tier | Pure logic, no I/O, no host, no real external dependencies |
| Integration tier | Real wiring + real dependencies (Testcontainers in .NET, equivalent elsewhere) via the real entry point |
| Endpoint coverage | Every endpoint × every scenario covered *somewhere*. Default: unit tier carries branch coverage (request handler + authorisation handler + validator); integration tier is a per-endpoint wiring smoke (one happy + at least one denied per policy) asserting at the controller boundary. Promote the full matrix to integration only when an audit trail demands HTTP-level evidence. |
| Functional / e2e tier | Browser-based smoke per critical journey; only for projects with a UI; not full coverage |
| Performance tier | Add only when a hot path is identified |
| Parallelism | Tests must run safely in parallel; do not disable the runner's parallelism without a documented reason |
| Independence | Each test owns its data; no order dependencies; no shared mutable state |
| Anti-flake | No `Thread.Sleep` / `time.sleep` / `setTimeout` to "wait for things to happen" — fix the race in production code |
| Traceability — required regulated projects | Unit + integration → trait key `Task` linking to a Jira **Task**; functional → trait key `Requirement` linking to a Jira **Requirement**. Both keys, same Jira project, different issue types. Sentinel `SW-INFRA` under `Task` for infra/probe tests. |
| Traceability — internal-only projects | Skip both traits; don't fake IDs |
| Test class naming | Stack-conventional suffix on the subject's name (`*Tests` in C#, `test_*` in Python, `*.spec.ts` in TS) |
| Test method naming | `action + condition + outcome` — stack-conventional format |
| Test data | Builder / faker — never scattered hand-rolled literals; obviously-synthetic values; one test seeds one test |
| Mirroring | tests/... mirrors src/... exactly |
| Coverage | Scenario coverage is the goal; line coverage is a blind-spot indicator, not a CI gate |
