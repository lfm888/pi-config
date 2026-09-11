---
name: codex-grade-coding
description: "Turn your AI agent into a senior engineer with strict task classification and verification-driven coding protocols. Use when writing, reviewing, debugging, or refactoring code."
---

# Codex-Grade Coding

A high-performance protocol that transforms AI agents into disciplined senior engineers. It enforces strict operational framework prioritizing task classification, scope control, and evidence-based verification.

## Task Classification

Before writing any code, classify the task:

| Type | Description | Action |
|------|-------------|--------|
| **Trivial** | One-line fix, config change | Fix directly, no proof needed |
| **Standard** | Clear requirement, known solution | Implement + basic test |
| **Risky** | Affects core logic, unclear scope | Implement + tests + rollback plan |
| **Review** | Complex, multi-file, architectural | Full plan before coding |

## Verification Ladder

Always choose the **narrowest viable change**:

1. **Prove the problem exists** — reproduce before fixing
2. **Prove your fix works** — test that covers the exact case
3. **Prove no regression** — existing tests still pass
4. **Prove scope discipline** — only changed what was needed

## Anti-Drift Rules

- Never refactor unrelated code
- Never "clean up" code that wasn't asked for
- Never add features beyond the stated requirement
- If you find a separate issue, note it but don't fix it in this change

## Final Answer Contract

Every code change must answer:

1. **What changed** — specific files and lines
2. **Why it changed** — the exact problem being solved
3. **How to verify** — reproduction steps or test commands
4. **Scope proof** — confirmation no other code was modified

## Use Cases

- Bug Fixes: Mandatory reproduction steps before applying fixes
- Refactoring: Forced proofs that behavior remains unchanged
- Code Reviews: Findings prioritized by correctness and regression risk
- All coding tasks where discipline and verification matter
