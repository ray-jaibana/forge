---
name: pr-checklist
description: What Tamara checks on every PR review. Updated when new bug classes are caught.
version: 1.0.0
updated: 2026-04-05
updated_by: ray
---

## When to Use
Before every PR review. Load this, go through it line by line.

## Security (Block if Any Found)
- [ ] No hardcoded secrets, tokens, or API keys
- [ ] User input is sanitized before use in queries or HTML
- [ ] Auth checks present on all protected endpoints
- [ ] No sensitive data logged to console
- [ ] SQL queries use parameterized inputs (no string concatenation)

## Error Handling (Block if Missing on Critical Ops)
- [ ] All async operations have try/catch
- [ ] Database writes have error handling — what happens if the write fails?
- [ ] External API calls handle network errors and non-2xx responses
- [ ] Destructive operations (delete, overwrite) have explicit confirmation
- [ ] Errors surface useful messages to the user, not raw stack traces

## Tests
- [ ] New functionality has at least one test
- [ ] Edge cases are tested (empty arrays, null values, network errors)
- [ ] Existing tests still pass

## Performance
- [ ] No N+1 queries (check loops that call the database)
- [ ] No blocking operations on the main thread
- [ ] No unbounded data fetches (pagination or limits on queries)

## Code Quality
- [ ] TypeScript types are correct — no `any` without justification
- [ ] Naming is clear — variables and functions say what they do
- [ ] No dead code or commented-out blocks
- [ ] Follows existing patterns in the codebase

## Scope
- [ ] PR does exactly what the task describes — no more, no less
- [ ] No unrelated changes bundled in

## UI (if applicable)
- [ ] Works on mobile viewport
- [ ] Loading states handled
- [ ] Error states handled (not just the happy path)

---

## Known Bug Patterns (Updated as caught)

*This section grows over time. Each entry = a real bug caught in a real PR.*

| Date | PR | Pattern | Rule Added |
|------|-----|---------|------------|
| (first entry will appear here after first real review) | | | |
