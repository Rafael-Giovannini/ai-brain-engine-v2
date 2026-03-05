---
description: Validate spec-vs-code consistency and code quality. Checks doc alignment, entity coverage, API contracts, FR traceability, and code quality (architecture, security, smells).
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).
The first word of the input is typically the **workspace name** (e.g., `ghostfit`, `motor-financeiro`).
If no workspace is provided, ask the user which workspace to validate.

## Goal

Perform a comprehensive validation across 5 dimensions:
1. **Doc Consistency** — spec.md, plan.md, data-model.md, api-contracts.md aligned with each other
2. **BMAD Docs vs Specs** — PRD, architecture, sprint-plan, UX design aligned with spec/plan
3. **Spec vs Code** — code implements what the spec defines (entities, endpoints, FRs, tests)
4. **Code Quality** — architecture, security, clean code, code smells
5. **Ralph Config** — fix_plan.md, PROMPT.md, AGENT.md, .ralphrc consistent with project

This complements `/speckit.analyze` (which checks doc-vs-doc only) by adding **code validation**, **quality analysis**, and **full-stack doc/config consistency**.

## Operating Constraints

- **READ-ONLY**: Do **not** modify any source code files.
- **REPORT OUTPUT**: Write the validation report to `FEATURE_DIR/validation-report.md`.
- **GRACEFUL MISSING CODE**: If no source code exists yet, report all entities/endpoints as MISSING and skip code quality analysis — this is expected for early-stage projects.

## Execution Steps

### 1. Resolve Workspace & Feature

Parse the user input to extract:
- **WORKSPACE_NAME**: First argument (e.g., `ghostfit`)
- **FEATURE_NAME**: Optional `--feature` flag, or auto-detect

```
WORKSPACE_DIR = workspace/<WORKSPACE_NAME>
```

**Detect spec layout:**
- If `workspace/<name>/specs/spec.md` exists → **flat layout**, FEATURE_DIR = `workspace/<name>/specs`
- Else find numbered subdirectories in `workspace/<name>/specs/` → **nested layout**, pick the highest-numbered directory
- Set FEATURE_DIR accordingly

**Abort** if no spec.md is found in the resolved FEATURE_DIR.

### 2. Discover Source & Test Directories

Search for source code root (project-type agnostic):

| Candidate Path | Project Type |
|----------------|-------------|
| `WORKSPACE_DIR/android/app/src/main/java` | Android/Kotlin |
| `WORKSPACE_DIR/android/app/src/main/kotlin` | Android/Kotlin |
| `WORKSPACE_DIR/src` | .NET / Node / Generic |
| `WORKSPACE_DIR/lib` | Dart / Ruby |
| `WORKSPACE_DIR/app` | Rails / Next.js |

Use the first existing directory as SRC_DIR.

Search for test directories:

| Candidate Path | Project Type |
|----------------|-------------|
| `WORKSPACE_DIR/android/app/src/test` | Android unit tests |
| `WORKSPACE_DIR/android/app/src/androidTest` | Android instrumented |
| `WORKSPACE_DIR/tests` | .NET / Generic |
| `WORKSPACE_DIR/test` | Node / Generic |

Use all existing directories as TEST_DIRS.

If SRC_DIR is not found, note "No source code found" and proceed with doc-only validation + skip Passes B-F.

### 3. Load All Artifacts

**Spec artifacts** from FEATURE_DIR (note which are missing):

| Artifact | File | Required? |
|----------|------|-----------|
| Spec | `spec.md` | YES (abort if missing) |
| Plan | `plan.md` | Recommended |
| Data Model | `data-model.md` | Recommended |
| API Contracts | `contracts/api-contracts.md` OR `contracts/api-v1.md` OR `contracts/api*.md` | Recommended |
| Checklist | `checklists/requirements.md` | Optional |

**BMAD docs** from `WORKSPACE_DIR/docs/` (all optional, validate if present):

| Artifact | File Pattern | Purpose |
|----------|-------------|---------|
| Product Brief | `product-brief-*.md` | Vision, target audience, success metrics |
| PRD | `prd-*.md` | Functional/non-functional requirements |
| Architecture | `architecture-*.md` | System design, tech stack, patterns |
| Sprint Plan | `sprint-plan-*.md` | Story decomposition, priorities |
| UX Design | `ux-design-*.md` | Screens, flows, UI components |

**Ralph config** from `WORKSPACE_DIR/.ralph/` and `WORKSPACE_DIR/.ralphrc` (all optional):

| Artifact | File | Purpose |
|----------|------|---------|
| Ralph Config | `.ralphrc` | Project name, type, root, allowed tools |
| Ralph Prompt | `.ralph/PROMPT.md` | Dev instructions, tech stack, specs paths |
| Ralph Agent | `.ralph/AGENT.md` | Build/test/run commands |
| Fix Plan | `.ralph/fix_plan.md` | Task tracker with stories/phases |

### 4. Build Semantic Inventories

Create internal representations from the loaded artifacts:

**From spec.md:**
- Extract all **FR-XXX** identifiers with their descriptions
- Extract all **User Stories** with their acceptance scenarios (Given/When/Then)
- Extract **Edge Cases** list
- Extract **Key Entities** mentioned

**From data-model.md:**
- Extract all **entity names** with their fields (name, type, constraints)
- Extract all **enum definitions** with their values
- Extract **storage layer mapping** (which entities go to DB, memory, encrypted files)

**From api-contracts.md:**
- Extract all **endpoints** (method, path, request/response fields, timeouts)
- Extract **error handling** patterns and user-facing messages
- Extract **category mappings** or other lookup tables

**From plan.md:**
- Extract **project structure** (planned files and directories)
- Extract **tech stack** decisions
- Extract **implementation phases**

### 5. Validation Passes

#### Pass A: Doc Consistency

Compare artifacts against each other:

| Check | Sources | Default Severity |
|-------|---------|-----------------|
| Entities in data-model match entities referenced in spec | data-model vs spec | HIGH |
| Endpoints in contracts match architecture in plan | api-contracts vs plan | HIGH |
| FR identifiers referenced consistently across all docs | spec vs plan vs data-model | MEDIUM |
| Enum values consistent between data-model and contracts | data-model vs api-contracts | HIGH |
| Error messages in contracts match edge cases in spec | api-contracts vs spec | MEDIUM |
| Tech stack in plan matches dependencies in quickstart | plan vs quickstart | LOW |

#### Pass B: Entity Validation (Spec vs Code)

For each entity in data-model.md:
1. Use Glob/Grep to search for a class/data class/record matching the entity name in SRC_DIR
2. If found, read the file and check each field from the spec exists
3. For enum types, verify enum values match
4. For storage annotations, verify they match the storage layer mapping

Report per entity: **COMPLETE** (all fields match) / **PARTIAL** (class exists, some fields missing) / **MISSING** (no class found)

**Language-specific search patterns:**
- Kotlin/Java: `class <Name>`, `data class <Name>`, `@Entity`
- C#/.NET: `class <Name>`, `record <Name>`, `public <Type> <Field>`
- TypeScript: `interface <Name>`, `class <Name>`, `type <Name>`

#### Pass C: API Contract Validation (Spec vs Code)

For each endpoint in api-contracts.md:
1. Search for route handler matching the HTTP method + path
2. Verify request/response models have correct fields
3. Check timeout configurations if specified

**Language-specific search patterns:**
- Kotlin (Retrofit): `@POST("path")`, `@GET("path")`, `@PUT`, `@DELETE`
- C# (ASP.NET): `[HttpPost("path")]`, `[HttpGet]`, `[Route("path")]`
- TypeScript (Express/Next): `router.post("path")`, `app.get("path")`

Report per endpoint: **IMPLEMENTED** / **MISSING** / **PATH_MISMATCH**

#### Pass D: FR Traceability

For each FR-XXX in spec.md:
1. Grep SRC_DIR for `FR-XXX` in comments or docstrings
2. Grep TEST_DIRS for `FR-XXX` in test names or comments
3. If no direct reference, attempt semantic matching: extract key nouns from FR description and search for matching class/function names

Report per FR: **TRACED** (found in code AND tests) / **PARTIAL** (code OR tests, not both) / **UNTRACED** (neither)

#### Pass E: Acceptance Scenario vs Test Coverage

For each acceptance scenario (Given/When/Then) in spec.md:
1. Extract the key action and expected outcome
2. Search TEST_DIRS for test methods with matching keywords
3. Consider test names like `should_X_when_Y`, `test_X`, `@Test fun X`

Report per scenario: **COVERED** / **UNCOVERED**

#### Pass F: Code Quality Analysis

For each source file found in SRC_DIR, analyze:

**F1. Architecture & Clean Code:**
- Layer separation: domain/model classes must NOT import infrastructure/framework (e.g., Retrofit, Room, HttpClient, DbContext)
- Single Responsibility: flag files > 300 lines or classes > 10 public methods
- Naming: class/function names should be descriptive and match domain terminology from spec
- Business logic placement: controllers/activities/composables should delegate to use cases/domain, not contain logic

**F2. Security (OWASP Top 10):**
- No hardcoded secrets: search for API key strings, passwords, tokens inline in code (not via BuildConfig/env/config)
- Encryption: sensitive data (photos, tokens) must use proper encryption (Tink, DPAPI, etc.)
- Input validation: API/user inputs should be validated at boundaries
- No SQL injection: queries must use parameterized patterns (Room @Query, EF Core LINQ)

**F3. Code Smells:**
- Duplicated code blocks (same logic in multiple places)
- Functions with > 5 parameters
- Deeply nested callbacks (> 3 levels)
- Magic numbers/strings (should be constants)
- TODO/FIXME/HACK comments without associated issue reference

**F4. Test Quality:**
- Business logic (use cases, domain) should have corresponding test files
- Test names should be descriptive (`should_X_when_Y` pattern)
- Tests should test behavior, not implementation details

**F5. Performance (when applicable):**
- Network calls on main thread (Android: no `runBlocking` on Main, .NET: no `.Result` on sync)
- Async/coroutine usage for I/O operations
- Obvious memory leaks (unremoved listeners, strong Activity references)

Report per file with findings: category, severity, description, recommendation.

#### Pass G: BMAD Docs vs Specs

If BMAD docs exist in `WORKSPACE_DIR/docs/`, cross-validate:

| Check | Sources | Default Severity |
|-------|---------|-----------------|
| User Stories in spec match stories in sprint-plan | spec.md vs sprint-plan | HIGH |
| Tech stack in architecture matches plan.md tech stack | architecture vs plan | HIGH |
| Screens/flows in UX design match UI screens in plan project structure | ux-design vs plan | MEDIUM |
| NFRs in PRD match non-functional requirements in spec | prd vs spec | HIGH |
| FRs in PRD match FRs in spec (count, descriptions) | prd vs spec | HIGH |
| Target audience/personas in product-brief match PRD | product-brief vs prd | LOW |
| Architecture patterns match code structure (if code exists) | architecture vs SRC_DIR | MEDIUM |
| Priority ordering consistent between sprint-plan and spec stories | sprint-plan vs spec | MEDIUM |

Report per finding: severity, location (both files), description, recommendation.

#### Pass H: Ralph Config Validation

If Ralph config exists in `WORKSPACE_DIR/.ralph/` and `WORKSPACE_DIR/.ralphrc`, validate:

**H1. .ralphrc consistency:**
- `PROJECT_NAME` matches the workspace/product name from docs
- `PROJECT_TYPE` matches actual tech stack (e.g., `android-kotlin` for Kotlin projects, `dotnet-angular` for .NET)
- `PROJECT_ROOT` points to actual workspace directory (`workspace/<name>`)
- `ALLOWED_TOOLS` include tools relevant for the project type (e.g., `Bash(./gradlew *)` for Android, `Bash(dotnet *)` for .NET)
- `ALLOWED_TOOLS` do NOT include dangerous commands (`Bash(rm *)`, `Bash(git clean *)`, `Bash(git reset *)`)

**H2. PROMPT.md consistency:**
- Project name matches .ralphrc and docs
- Tech stack description matches architecture doc and plan.md
- Branch name matches actual current branch
- Spec/docs file paths listed are valid (files actually exist)
- Architecture description matches architecture doc
- Testing guidelines match actual test framework (JUnit vs xUnit, etc.)

**H3. AGENT.md consistency:**
- Build commands match actual project type (gradlew vs dotnet vs npm)
- Test commands reference correct test frameworks and directories
- Prerequisites match tech stack (JDK version, SDK version, etc.)
- File paths in project structure match actual workspace structure

**H4. fix_plan.md consistency:**
- All stories/phases in fix_plan match stories in spec.md
- Story order/priority matches spec priorities
- No completed tasks marked `[x]` that reference non-existent code
- No tasks referencing files/entities not in the spec or data-model
- Phase count matches number of stories in spec

Report per finding: severity, file, description, recommendation.

### 6. Severity Assignment

| Level | Criteria |
|-------|----------|
| **CRITICAL** | P1 entity missing from code; endpoint in contract without implementation; hardcoded secret; SQL injection; constitution MUST violation |
| **HIGH** | Entity with missing key fields; enum mismatch; business logic outside domain layer; significant code duplication |
| **MEDIUM** | FR without tests; acceptance scenario uncovered; moderate code smells; magic numbers |
| **LOW** | Naming inconsistencies; minor TODOs; extra code fields not in spec |

### 7. Produce Validation Report

Write the report to `FEATURE_DIR/validation-report.md` with this structure:

```markdown
# Validation Report: <workspace> / <feature>

**Generated**: <YYYY-MM-DD HH:MM>
**Workspace**: <workspace-name>
**Feature**: <feature-name>

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Spec Doc Consistency Issues | N |
| BMAD Docs vs Spec Issues | N |
| Ralph Config Issues | N |
| Entities: Defined / Implemented | N / M |
| API Endpoints: Defined / Implemented | N / M |
| FRs Traced to Code | N / M (X%) |
| Acceptance Scenarios with Tests | N / M (X%) |
| Code Quality Issues | N |
| Critical Issues | N |
| High Issues | N |
| Medium Issues | N |

---

## 1. Spec Doc Consistency (Pass A)

| ID | Severity | Location | Finding | Recommendation |
|----|----------|----------|---------|----------------|

## 2. Entity Coverage Matrix (Pass B)

| Entity | Code File | Status | Missing Fields | Extra Fields |
|--------|-----------|--------|----------------|--------------|

## 3. API Contract Coverage (Pass C)

| Endpoint | Code File | Status | Notes |
|----------|-----------|--------|-------|

## 4. FR Traceability (Pass D)

| FR | Description | In Code? | In Tests? | Status |
|----|-------------|----------|-----------|--------|

## 5. Acceptance Scenario Coverage (Pass E)

| Story | Scenario | Key Assertion | Test Found? | Test File |
|-------|----------|---------------|-------------|-----------|

## 6. Code Quality (Pass F)

| File | Category | Severity | Finding | Recommendation |
|------|----------|----------|---------|----------------|

## 7. BMAD Docs vs Specs (Pass G)

| ID | Severity | Docs File | Spec File | Finding | Recommendation |
|----|----------|-----------|-----------|---------|----------------|

## 8. Ralph Config (Pass H)

| ID | Severity | File | Finding | Recommendation |
|----|----------|------|---------|----------------|

---

## Next Actions

### Critical (must fix before continuing)
- [items]

### High (fix soon)
- [items]

### Medium (address during implementation)
- [items]
```

### 8. Summary & Next Steps

After writing the report:
- Print the Executive Summary table to the user
- Print the count of findings by severity
- If CRITICAL issues exist: recommend fixing before continuing implementation
- If only MEDIUM/LOW: user may proceed
- Suggest: "Run `/validate <workspace>` again after fixing issues to verify"

## Language

- **ALL output MUST be in Brazilian Portuguese (PT-BR)**: report text, findings, recommendations, summaries, and conversation with the user.
- Technical terms (file names, code identifiers, severity levels like CRITICAL/HIGH/MEDIUM/LOW) may remain in English.

## Operating Principles

- **NEVER modify source code files** (report-only)
- **NEVER hallucinate implementations** (if a file doesn't exist, report MISSING)
- **Be specific**: cite file paths, line numbers, exact field names
- **Be actionable**: every finding must have a concrete recommendation
- **Handle early-stage gracefully**: if no code exists, focus on doc consistency and note that code validation will be meaningful after implementation begins
- **Limit findings to 80 rows** across all passes; aggregate overflow in summary
- **Deterministic**: rerunning without changes should produce consistent results
