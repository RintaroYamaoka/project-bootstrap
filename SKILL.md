---
name: project-bootstrap
description: Operating rules for AI-driven project setup, architecture, implementation, testing, and debugging. Use this at the start of a project to guide design discussions and implementation work.
---

# Project Bootstrap Skill

Use this skill when starting or evolving a project with AI-driven development.
This skill defines how to design, implement, validate, and debug the project without losing structural integrity.

## Intent
This repository should be developed through small, explicit, testable changes.
The goal is not to generate code quickly.
The goal is to produce code that is structurally correct, easy to reason about, and safe to extend.

## Core Principles
- Prefer **KISS** over premature flexibility.
- Use **Clean Architecture**.
- Respect **SOLID**, but do not over-abstract.
- Prefer **root-cause fixes** over symptom-hiding patches.
- Prefer **fail fast** over silent fallback.
- Treat **tests as executable contracts**.
- Keep AI work **small, explicit, and verifiable**.

## Development Flow
Always work in this order.

### 1. Clarify the project
Define:
- what to build
- what not to build
- success conditions
- constraints
- external dependencies

Do not start implementation while these are unclear.

### 2. Clarify requirements
Define:
- user requirement
- system requirement
- inputs
- outputs
- failure conditions
- boundaries with external systems

### 3. Design before implementation
Define:
- main use cases
- responsibilities
- interfaces / DTOs / contracts
- dependency direction
- directory placement
- initial test targets

If this cannot be described clearly, do not implement yet.

### 4. Define test viewpoints
Before implementation, list at least:
- normal cases
- error cases
- boundary cases
- state transitions

If test viewpoints cannot be described, the responsibility or contract is still unclear.

### 5. Implement in small units
- 1 change = 1 responsibility
- do not ask AI for large multi-responsibility implementation
- keep contracts stable unless explicitly changing them
- validate after each small change

### 6. Validate
After each change, confirm:
- import / build / run passes
- relevant tests pass
- contract is preserved
- no speculative code or unnecessary fallback was added

### 7. Fix properly
For bugs:
1. identify the symptom
2. locate the responsible layer
3. clarify reproduction condition
4. add or define a regression test
5. apply a root-cause fix
6. rerun tests

## Architecture Rules
- Separate business logic from IO.
- Keep dependency direction **outside -> inside** only.
- Inner layers must not know outer implementation details.
- Depend on abstractions, not concrete infrastructure.
- Use constructor injection / DI where appropriate.

### Layer Responsibilities
- `domain`: entities, value objects, domain rules, domain services
- `application`: use cases, DTOs, ports, application services
- `interface`: controllers, presenters, cli/batch entry points, request/response mapping
- `infrastructure`: DB, API, files, logs, config, framework-specific code
- `composition`: dependency wiring / composition root

### Forbidden
- Do not put framework or DB details in `domain`.
- Do not make `application` depend directly on infrastructure concrete classes.
- Do not mix transformation, decision, persistence, and presentation in one class.
- Do not add architecture "just in case".

## Directory Structure Policy
Use **layer-first + feature/bounded-context substructure**.

### Recommended Structure
```text
project-root/
  skills/
    project-bootstrap/
      SKILL.md

  docs/
  src/
    domain/
      <context>/
    application/
      <context>/
    interface/
      http/
      cli/
      batch/
    infrastructure/
      persistence/
      external/
      filesystem/
      logging/
      config/
    composition/
  tests/
    unit/
    integration/
    e2e/
  scripts/
  tools/
  data/
  tmp/
```

### Directory Rules
- Top level should be organized by **layer**.
- Inside each layer, organize by **bounded context / feature** if needed.
- File placement is determined by **responsibility**, not convenience.
- If unsure, decide the layer first, then the folder.
- Do not use a mixed "everything for one feature in one folder" structure unless there is a strong reason.

## Test Policy
### Principles
- Tests are part of the specification.
- "It runs" is not enough.
- A bug fix is not complete without a regression test when practical.
- In AI-driven development, tests are the main defense against plausible-but-wrong code.

### Priority
1. unit tests
2. integration tests
3. e2e tests

### Test-first targets
Prefer testing these first:
- validation
- transformation
- branching logic
- state judgment
- external IO boundaries
- code AI tends to break repeatedly

### Minimum viewpoints
For each non-trivial change, consider:
- normal case
- error case
- boundary case
- state transition

### Forbidden
- large implementation with no validation strategy
- fixing bugs only by manual debugging
- brittle tests tied too closely to implementation details
- treating "passed once" as sufficient evidence

## AI Working Rules
AI is allowed to:
- propose small implementations
- suggest design refinements
- list test viewpoints
- draft test code
- summarize or inspect existing structure

AI must not:
- invent APIs, classes, files, or behavior without confirming they exist
- perform unrelated refactors
- add speculative options, branches, or future-proofing
- hide problems with fallback logic
- treat untested code as complete
- change architecture style without instruction

### Required input when asking AI to implement
Always specify:
- purpose
- target responsibility
- input/output contract
- allowed dependencies
- forbidden dependencies
- constraints
- test viewpoints
- completion criteria

## Implementation Rules
- One function or method should do one thing.
- Keep nesting shallow.
- Avoid unnecessary patterns.
- Prefer readability over cleverness.
- Do not rely on comments to explain unclear code; rewrite the code instead.
- Keep public contracts explicit.

## Type Rules
- Use type annotations on all functions.
- Do not use bare `dict`, `list`, `tuple`, or `set`; specify element types.
- Use `Any` only to explicitly signal dynamic data, not to escape type checking.
- Create type aliases only when reused meaningfully.

## Fail-fast Rules
- Do not add fallback just to "keep it working".
- Do not swallow unexpected errors.
- Raise problems early when assumptions are violated.
- Catch side-effect failures only when the main process should continue safely.
- Do not replace proper validation with runtime patching.

## Root-cause Rules
- Fix causes, not symptoms.
- Before adding sort, filter, fallback, or retry, verify whether the source or responsibility is wrong.
- Do not pile conditions onto unclear structure.
- If a temporary workaround is unavoidable, label it clearly as temporary.

## Pre-implementation Checklist
Before implementing, confirm:
- purpose is clear
- scope is clear
- responsibility is singular
- layer is clear
- input/output is explicit
- failure conditions are explicit
- directory placement is clear
- dependency direction is clear
- test viewpoints are listed
- completion criteria are clear

If any of these are unclear, stop and design first.

## Post-implementation Checklist
After implementing, confirm:
- import / build / run passes
- type signatures match responsibility
- no unnecessary branch, fallback, or speculative code was added
- request scope was respected
- relevant tests exist
- relevant tests pass
- regression test was added for bug fixes when practical
- architecture and dependency direction remain intact

## Definition of Done
A change is done only when:
- purpose is clear
- responsibility is clear
- contract is clear
- layer placement is correct
- dependency direction is preserved
- relevant validation or test exists
- relevant tests pass
- no obvious symptom-hiding patch was introduced
- no speculative AI-generated change was left in place

## Decision Heuristics
When unsure, decide in this order:
1. Is this really necessary?
2. Is the responsibility singular?
3. Which layer owns it?
4. Can it be simpler?
5. Can it be tested?
6. Can AI do it in a smaller unit?

### Final defaults
- When in doubt, choose **KISS**.
- When unclear, go back to **design**.
- When fragile, define **tests first**.
- When patch-like, search for the **root cause**.
- When AI wants to do too much, **split the responsibility further**.
