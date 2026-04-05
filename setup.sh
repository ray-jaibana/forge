#!/bin/bash
# setup.sh — FORGE Mac mini setup wizard
# Run this once to get FORGE fully operational on the Mac mini

set -euo pipefail

FORGE_ROOT="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail() { echo -e "${RED}❌ $*${NC}"; }
step() { echo -e "\n${YELLOW}── $* ──${NC}"; }

echo ""
echo "🔥 FORGE Mac mini Setup"
echo "========================"

# ── Step 1: Claude Code ───────────────────────────────────────────────────────
step "1. Claude Code CLI"
if command -v claude &>/dev/null; then
  VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  MAJOR=$(echo "$VERSION" | cut -d. -f1)
  MINOR=$(echo "$VERSION" | cut -d. -f2)
  if [ "$MAJOR" -ge 2 ] && [ "$MINOR" -ge 1 ]; then
    ok "Claude Code v$VERSION — ready"
  else
    warn "Claude Code v$VERSION found but v2.1.32+ required"
    warn "Run: npm install -g @anthropic-ai/claude-code"
  fi
else
  fail "Claude Code not found"
  echo "Install with: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

# ── Step 2: GitHub CLI ────────────────────────────────────────────────────────
step "2. GitHub CLI"
if gh auth status &>/dev/null; then
  USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
  ok "GitHub CLI authenticated as: $USER"
else
  fail "GitHub CLI not authenticated"
  echo "Run: gh auth login"
  exit 1
fi

# ── Step 3: .env file ─────────────────────────────────────────────────────────
step "3. Environment (.env)"
ENV_FILE="$FORGE_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Creating .env from .env.example..."
  cp "$FORGE_ROOT/.env.example" "$ENV_FILE"
fi

# Check for existing Slack user token (from OpenClaw heartbeat)
EXISTING_USER_TOKEN="${SLACK_USER_TOKEN}"
TEAM_ID="T02DX337GBY"

# Verify the token still works
TOKEN_CHECK=$(curl -s "https://slack.com/api/auth.test" \
  -H "Authorization: Bearer $EXISTING_USER_TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('ok','false'))")

if [ "$TOKEN_CHECK" = "True" ]; then
  ok "Slack user token verified (Jaibana Studios workspace)"
  
  # Check if we need a bot token for posting
  # User tokens can post messages too — check if we have chat:write scope
  SCOPE_CHECK=$(curl -s "https://slack.com/api/auth.test" \
    -H "Authorization: Bearer $EXISTING_USER_TOKEN" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('ok'))
")
  
  # Write to .env (use user token as SLACK_BOT_TOKEN — works for posting)
  grep -q "SLACK_BOT_TOKEN" "$ENV_FILE" || echo "" >> "$ENV_FILE"
  
  # Update or add the tokens
  python3 -c "
import re
with open('$ENV_FILE', 'r') as f:
    content = f.read()

# Replace placeholders
content = re.sub(r'SLACK_BOT_TOKEN=.*', 'SLACK_BOT_TOKEN=$EXISTING_USER_TOKEN', content)
content = re.sub(r'SLACK_TEAM_ID=.*', 'SLACK_TEAM_ID=$TEAM_ID', content)

# Add if not present
if 'SLACK_BOT_TOKEN' not in content:
    content += '\nSLACK_BOT_TOKEN=$EXISTING_USER_TOKEN\n'
if 'SLACK_TEAM_ID' not in content:
    content += 'SLACK_TEAM_ID=$TEAM_ID\n'

with open('$ENV_FILE', 'w') as f:
    f.write(content)
print('written')
"
  ok "Slack tokens written to .env"
else
  warn "Slack user token check failed — you may need to create a new Slack bot token"
  echo "  1. Go to https://api.slack.com/apps"
  echo "  2. Create app 'FORGE Bot' in Jaibana Studios workspace"
  echo "  3. Add bot scopes: chat:write, channels:read, channels:history, reactions:read"
  echo "  4. Install and copy Bot Token → add to .env as SLACK_BOT_TOKEN"
fi

# ── Step 4: Slack channels ────────────────────────────────────────────────────
step "4. Slack channels"
CHANNELS=("forge-pipeline" "forge-reviews" "forge-research" "forge-alerts" "forge-skills")
MISSING=()

for CH in "${CHANNELS[@]}"; do
  EXISTS=$(curl -s "https://slack.com/api/conversations.list?limit=200" \
    -H "Authorization: Bearer $EXISTING_USER_TOKEN" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); names=[c['name'] for c in d.get('channels',[])]; print('yes' if '$CH' in names else 'no')" 2>/dev/null || echo "unknown")
  
  if [ "$EXISTS" = "yes" ]; then
    ok "#$CH exists"
  else
    MISSING+=("#$CH")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  warn "Missing Slack channels: ${MISSING[*]}"
  echo "  Create these in Slack, then re-run setup.sh"
fi

# ── Step 5: MCP servers ───────────────────────────────────────────────────────
step "5. MCP servers (Slack + GitHub)"
if command -v npx &>/dev/null; then
  ok "npx available — MCP servers will auto-install on first use"
else
  warn "npx not found — install Node.js"
fi

# ── Step 6: Claude Code auth ──────────────────────────────────────────────────
step "6. Claude Code subscription auth"
# Claude Code authenticates via claude.ai OAuth — check if logged in
if claude config list &>/dev/null 2>&1; then
  ok "Claude Code authenticated"
else
  warn "Claude Code may need authentication"
  echo "  Run: claude  (follow the OAuth login prompt)"
fi

# ── Step 7: macOS LaunchAgent (auto-start daemon) ────────────────────────────
step "7. Auto-start daemon on login"
PLIST="$HOME/Library/LaunchAgents/com.jaibana.forge-daemon.plist"

if [ ! -f "$PLIST" ]; then
  cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jaibana.forge-daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$FORGE_ROOT/daemon/forge-daemon.sh</string>
        <string>_run</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$FORGE_ROOT</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/Users/raybot/.local/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$FORGE_ROOT/daemon/logs/launchagent.log</string>
    <key>StandardErrorPath</key>
    <string>$FORGE_ROOT/daemon/logs/launchagent-err.log</string>
</dict>
</plist>
PLIST_EOF
  ok "LaunchAgent created: $PLIST"
else
  ok "LaunchAgent already exists"
fi

echo ""
echo "────────────────────────────────────────"
echo "✅ FORGE Mac mini setup complete!"
echo ""
echo "Next steps:"
echo "  1. Start the daemon:       ./forge start"
echo "  2. Test heartbeat:         ./forge heartbeat"
echo "  3. Test a cron job:        ./forge cron run morning-brief"
echo "  4. Open agent session:     ./forge session"
echo ""
echo "To enable auto-start on login:"
echo "  launchctl load ~/Library/LaunchAgents/com.jaibana.forge-daemon.plist"
echo ""
