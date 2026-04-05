# Architecture Decisions

> Why we made key choices. Updated by agents when architectural decisions are made.
> Format: ## [Date] — [Decision] | [Reason]

## 2026-04-05 — FORGE v2 native Claude Code architecture
Using Claude Code Agent Teams instead of OpenClaw cron-spawned agents.
**Reason:** True parallel execution, direct agent-to-agent messaging, shared task list, and zero marginal cost (runs in Claude Max subscription). OpenClaw v1 was sequential and cost $80-180/month in API calls.

## 2026-04-05 — All agents on Claude Sonnet
Every teammate runs on claude-sonnet-4-6 via the Max subscription.
**Reason:** Subscription covers all usage. No model diversity needed for this pipeline — Sonnet handles code, research, content, and creative direction well. Massimo's images require separate image generation API.

## 2026-04-05 — Slack as mission control (not WhatsApp)
Pipeline events flow to Slack channels, not WhatsApp DMs.
**Reason:** Async approval workflow. Alvaro reacts ✅ in #forge-alerts instead of being pinged on WhatsApp for every PR. Keeps dev work out of personal chat.

## 2026-04-05 — Mandatory 2-round review minimum
Tamara must request changes on Round 1. No first-pass approvals.
**Reason:** A reviewer that always approves is not reviewing. Forcing at least one round of back-and-forth catches the edge cases that look fine on first read.

## 2026-04-05 — .claude/skills/ as shared knowledge base
All agents read and write to the same skill library.
**Reason:** Inspired by Hermes Agent's self-improving loop. Skills compound over time — what Tamara catches in PR #5 prevents the same bug in PR #50.
