# 🔥 FORGE

**Autonomous multi-agent development pipeline — Claude Code native**

Runs entirely inside Claude Code's Agent Teams. No OpenClaw dependency. No API billing per run.
All agents use the Claude Max subscription.

---

## What This Is

FORGE is a 5-agent team that autonomously:
- Researches the market and finds opportunities (Saul)
- Implements features from a shared task list (Jeff)
- Reviews all code before it merges (Tamara)
- Writes blog posts and social content (Steven)
- Creates ad images and social graphics (Massimo)

Every agent communicates via Slack. You (Alvaro) approve in TEST, then prod deploys.
The whole team gets smarter over time via a shared skill library.

---

## Quick Start

### Prerequisites
- Claude Code v2.1.32+ (`claude --version`)
- GitHub CLI authenticated (`gh auth status`)
- Slack Bot Token (see Setup below)

### Setup

1. **Clone this repo:**
   ```bash
   git clone https://github.com/asanint/forge
   cd forge
   ```

2. **Create `.env` (gitignored):**
   ```bash
   cp .env.example .env
   # Fill in SLACK_BOT_TOKEN and SLACK_TEAM_ID
   ```

3. **Set active project:**
   ```bash
   # Edit .claude/project.json with your target repo details
   ```

4. **Start Claude Code:**
   ```bash
   claude
   ```

5. **Spawn the team:**
   ```
   Assemble the FORGE team. Active project is SiteTrakr. Start with Saul 
   researching competitors, Jeff picking up the first backlog task, and 
   Tamara on standby for review.
   ```

---

## File Structure

```
forge/
├── CLAUDE.md                    # Rules loaded by ALL agents automatically
├── README.md                    # This file
├── .env.example                 # Environment variable template
├── .gitignore
└── .claude/
    ├── settings.json            # MCP servers, agent teams flag, permissions
    ├── project.json             # Active project config (swap to change targets)
    ├── agents/
    │   ├── jeff.md              # Builder
    │   ├── tamara.md            # Reviewer
    │   ├── saul.md              # Research
    │   ├── steven.md            # Content
    │   └── massimo.md           # Creative
    ├── skills/                  # Self-improving knowledge library
    │   ├── development/
    │   │   ├── feature-dev-workflow.md
    │   │   └── pr-checklist.md
    │   ├── research/
    │   │   └── competitor-analysis.md
    │   ├── content/
    │   │   └── blog-post-template.md
    │   ├── media/
    │   │   └── ad-creative-specs.md
    │   └── pipeline/
    │       └── incident-patterns.md  (auto-created by agents)
    ├── memory/
    │   ├── decisions.md         # Why key architectural choices were made
    │   └── incidents.md         # What went wrong and how it was fixed
    └── hooks/
        ├── TeammateIdle.sh      # Validates work before agent goes idle
        ├── TaskCompleted.sh     # Enforces completion criteria
        └── TaskCreated.sh       # Validates task format
```

---

## Pipelines

### Feature Development
```
Task created → Jeff implements → Tamara reviews (2 rounds min) 
→ Ray merges → auto-deploy TEST → Alvaro ✅ in Slack 
→ Ray deploys PROD → Steven announces → Massimo creates visuals
```

### Research → Tasks
```
Saul runs (Mon/Thu) → creates tasks from insights 
→ posts to #forge-research → Ray promotes high-priority to backlog
```

### Weekly Self-Improvement
```
Every Sunday 10PM → Ray spawns retrospective session 
→ reviews week's work → updates skills → posts summary to #forge-pipeline
```

---

## Slack Channels

| Channel | Purpose |
|---------|---------|
| `#forge-pipeline` | All task flow events |
| `#forge-reviews` | PR feedback and approvals |
| `#forge-research` | Saul's research reports |
| `#forge-alerts` | Needs Alvaro's attention |
| `#forge-skills` | New/updated skills |

---

## Switching Projects

Edit `.claude/project.json` and update the `name`, `repo`, `techStack`, `testUrl`, `prodUrl` fields.
All agents auto-adapt to the new project on next spawn.

---

## Slack Setup

1. Create app at https://api.slack.com/apps
2. Add bot scopes: `chat:write`, `channels:read`, `channels:history`, `reactions:read`
3. Install to workspace → copy Bot Token to `.env`
4. Find Team ID via https://api.slack.com/methods/auth.test → copy to `.env`
5. Create channels and invite the bot: `/invite @FORGE Bot`

---

## Cost

All agents run on Claude Sonnet via Claude Max subscription = **$0 extra**.
Only marginal cost: Massimo's image generation API (~$2-5/week).

---

*Built by Ray Castor for Alvaro Sanint — Jaibana Studios*
