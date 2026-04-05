# FORGE — Agent Harness

> This file is loaded automatically by ALL agents (Ray, Jeff, Tamara, Saul, Steven, Massimo).
> Last updated: 2026-04-05

## What Is FORGE

FORGE is a fully autonomous multi-agent development pipeline running natively in Claude Code.
It is **completely independent of OpenClaw** — no cron jobs, no OpenClaw sessions, no API key billing per run.

Every agent runs inside the Claude Max subscription. Zero marginal cost.

## Active Project

The active project is set in `.claude/project.json`. All agents read this file to know what they're building.

```
cat .claude/project.json
```

Fields: `name`, `description`, `repo`, `techStack`, `testUrl`, `prodUrl`, `slackChannel`

## Pipeline Rules — Non-Negotiable

1. **No direct pushes to main** — always branch → PR
2. **All PRs require Tamara review** — minimum 2 rounds (Round 1 is always request-changes)
3. **Merge → auto-deploy to TEST** — never deploy to prod directly
4. **Alvaro approves TEST** before prod deploy (reacts ✅ in #forge-alerts on Slack)
5. **No task = no work** — every action must be tied to a task in the shared task list
6. **Only Ray merges PRs** — Tamara approves, Ray merges

## Agent Roster

| Agent | Role | Talks To |
|-------|------|----------|
| **Ray** | Team Lead — coordinates, merges, deploys, reports | Everyone |
| **Saul** | Research — competitive analysis, SEO, user pain points | Ray, Steven |
| **Jeff** | Builder — implements features from task list | Tamara (directly) |
| **Tamara** | Reviewer — QA gate on all PRs | Jeff (directly), Ray |
| **Steven** | Content — blog, social, announcements | Saul, Ray |
| **Massimo** | Creative — ad images, social graphics | Steven, Ray |

## Self-Improvement Protocol

After completing any task requiring 5+ non-trivial tool calls:

1. Ask: "Did I learn something non-obvious?"
2. If yes → create or patch a skill in `.claude/skills/`
3. If you hit a failure or dead end → document in `.claude/memory/incidents.md`
4. If an architectural decision was made → document in `.claude/memory/decisions.md`

Skills are shared across ALL teammates. Every improvement compounds.

## Skills Index (auto-loaded)

@.claude/skills/development/feature-dev-workflow.md
@.claude/skills/development/pr-checklist.md
@.claude/skills/pipeline/incident-patterns.md
@.claude/memory/decisions.md
@.claude/memory/incidents.md

## Communication Channels (Slack)

| Channel | Purpose |
|---------|---------|
| `#forge-pipeline` | Task flow events: started, merged, deployed |
| `#forge-reviews` | PR review feedback and approvals |
| `#forge-research` | Saul's research reports |
| `#forge-alerts` | Blockers needing Alvaro's attention |
| `#forge-skills` | New/updated skill announcements |

## Environments

- **Test:** defined in active project config — auto-deployed after merge
- **Production:** deployed ONLY after Alvaro's ✅ reaction in #forge-alerts

## Hooks

Quality gates run automatically outside the agent loop:
- `TeammateIdle` → validates agent completed real work before going idle
- `TaskCompleted` → enforces completion criteria (PR exists, output written, etc.)
- `TaskCreated` → validates task format (must have type prefix)
