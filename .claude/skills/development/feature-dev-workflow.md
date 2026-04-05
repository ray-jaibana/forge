---
name: feature-dev-workflow
description: Jeff's standard workflow for implementing a feature from task to merged PR
version: 1.0.0
updated: 2026-04-05
updated_by: ray
---

## When to Use
Before starting any development task.

## Procedure

### 1. Understand the Task (Before Any Code)
- Read the full task description
- Identify: what user problem does this solve?
- Identify: what files will this touch?
- If unclear on scope or approach: message Ray BEFORE starting

### 2. Set Up the Branch
```bash
git checkout main && git pull
git checkout -b feature/[short-kebab-name]
# Example: feature/add-budget-alerts
```

### 3. Implement
- Follow existing code patterns — consistency beats cleverness
- Handle error cases (don't assume happy path)
- Add TypeScript types — no `any` unless unavoidable
- Don't bundle unrelated changes

### 4. Test
```bash
npm run test          # existing tests must still pass
npm run typecheck     # no TypeScript errors
npm run lint          # no lint errors
```
- Write new tests for new functionality
- Test the unhappy paths, not just the happy path

### 5. Commit
```bash
git add -p            # stage changes intentionally, not blindly
git commit -m "feat: [what this does]

- [key detail 1]
- [key detail 2]
Task: [task-id]"
git push origin feature/[branch-name]
```

### 6. Create PR
- Title: `feat: [what this does]`
- Description includes:
  - What changed and why
  - How to test it manually
  - Screenshots if UI changed
  - Any known limitations

### 7. Message Tamara
"PR #X ready for review — [one-line description]"

### 8. Address Review Feedback
- Read all of Tamara's feedback before making any changes
- Address everything — don't cherry-pick
- Push fixes to the same branch (don't create new PRs)
- Message Tamara when fixes are pushed

## Pitfalls
- Don't push to main directly — the hook will catch it but it's wasteful
- Don't close and reopen PRs for the same feature
- Don't let PRs sit — respond to Tamara's feedback within the same session

## Verification
PR created, all checks green, Tamara messaged.
