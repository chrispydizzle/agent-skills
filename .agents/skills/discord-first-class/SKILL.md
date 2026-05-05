---
name: discord-first-class
description: Upgrade a squad from Discord-as-runtime-override to Discord-as-configured-primary-surface, including bot polling and outbox queuing
license: Proprietary. Re-license if you plan to publish it separately.
metadata:
  confidence: medium (validated once in prod)
  tags: discord, communication, configuration, monitoring
---

# Discord First-Class: Reusable Upgrade Skill

## When to use this skill

- Squad has Discord configured in `.env` but the monitor is treating it as a runtime override
- Monitor charter defaults to Teams; Discord requires explicit `Communication Mode Override` language
- `workflow.config.json` has no `communication` block
- `discord-discussion-state.json` or `discord-outbox.json` are missing or empty
- New squad is provisioning Discord as the primary communication surface from the start

## What this skill installs

This skill promotes Discord from an injected runtime override to a fully first-class, durable communication surface. Two layers:

### Layer 1 — Runner/Polling Engine (Required for Discord read access)

The runner must have `scripts/discord-watch.ps1` — the PowerShell module that:
- **Polls Discord REST API** — `GET /channels/{id}/messages?after={lastId}` with rate-limit awareness
- **Checkpoints results** to `.squad/state/discord-discussion-state.json` — tracks `pending` (new user messages awaiting agent reply) and `processed` (messages the squad has already handled)
- **Flushes the outbox** — reads `.squad/state/discord-outbox.json` and posts queued replies via webhook

If `scripts/discord-watch.ps1` is missing, see **Step 1** below to copy it from the squad framework repo.

**Key functions in discord-watch.ps1:**
- `Get-DiscordInstructions` — polls Discord API, updates state, renders instructions markdown
- `Flush-DiscordOutbox` / `Process-DiscordOutbox` — posts pending replies, marks sent
- `Read-DiscordDiscussionState` / `Save-DiscordDiscussionState` — state persistence
- `Get-DefaultDiscordDiscussionState` / `Get-DefaultDiscordOutboxState` — initial state schemas
- `Merge-DiscordMessagesIntoState` — reconciles new messages into the checkpoint

### Layer 2 — Config/Charter (Makes Discord the durable default)

Five files need updates (details in **Step 3–Step 7**):

1. **`workflow.config.json`** — adds `communication` block specifying Discord as primary
2. **`.squad/routing-ops.md`** — Channels section documents the Discord surface
3. **`.squad/team-ops.md`** — Channels section documents credential layout and runtime rules
4. **`.squad/charter-source/monitor.md`** — Discord is default; Teams is opt-in; references the Discord state schema
5. **`.github/agents/squad.agent.md`** — adds `discord_*` MCP detection, Communication Surface subsection, `COMMUNICATION_SURFACE` env var

## Prerequisites

All three credentials must be in `.env` (never commit `.env` or hardcode tokens in config files):

| Credential | Source | Purpose |
|-----------|--------|---------|
| `DISCORD_WEBHOOK_URL` | `.env` (never commit) | Write: loop summaries and agent replies via webhook |
| `DISCORD_BOT_TOKEN` | `.env` (never commit) | Read: polling channel messages (must be a Bot token, not user token) |
| `DISCORD_CHANNEL_ID` | `.env` (never commit) | Read: target channel snowflake ID for polling |

### How to get a bot token

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click "New Application" and give it a name
3. Go to the **Bot** section and click "Add Bot"
4. Copy the **TOKEN** (this is your `DISCORD_BOT_TOKEN`)
5. Under **Scopes**, select `bot`
6. Under **Permissions**, select `Read Messages/View Channels` and `Read Message History`
7. Use the generated invite URL to add the bot to your server
8. In the target Discord channel, ensure the bot role has `Read Message History` and `View Channels` permissions

### How to get webhook and channel ID

1. Right-click the target channel → **Edit Channel** → **Integrations** → **Webhooks** → **New Webhook**
2. Copy the full webhook URL — this is your `DISCORD_WEBHOOK_URL`
3. Enable Developer Mode in Discord (User Settings → Advanced → Developer Mode)
4. Right-click the target channel and select "Copy Channel ID" — this is your `DISCORD_CHANNEL_ID`

## Step-by-step instructions

### Step 1: Ensure `scripts/discord-watch.ps1` exists

**If already present** (squads using `chrispydizzle/old-cpu-squad` as the base framework will have this):
```powershell
if (Test-Path "scripts/discord-watch.ps1") {
    Write-Host "✅ scripts/discord-watch.ps1 already present"
}
```

**If not present**, copy it from the framework repo:
```powershell
# From your squad repo root
$source = "https://raw.githubusercontent.com/chrispydizzle/old-cpu-squad/main/scripts/discord-watch.ps1"
$dest = "scripts/discord-watch.ps1"
Invoke-WebRequest -Uri $source -OutFile $dest -UseBasicParsing
Write-Host "✅ Copied scripts/discord-watch.ps1 from framework"
```

Or manually copy `scripts/discord-watch.ps1` from the framework repository. The file is ~415 lines and includes all the state management, polling, and outbox logic.

**Verify the file:**
- Contains function `Get-DiscordInstructions`
- Contains function `Process-DiscordOutbox`
- Contains function `Read-DiscordDiscussionState` / `Save-DiscordDiscussionState`
- Line 13 in `run.ps1` loads it: `. (Join-Path $PSScriptRoot "scripts\discord-watch.ps1")`

### Step 2: Add `.env` credentials

Add these three lines to `.env` in your squad repo root (replace placeholder values with your actual credentials):

```
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN
DISCORD_BOT_TOKEN=Your_Bot_Token_Here
DISCORD_CHANNEL_ID=123456789
```

**Do NOT commit `.env`.** Ensure it's in `.gitignore`:

```powershell
if (-not (Select-String -Path ".gitignore" -Pattern "^\.env$" -Quiet)) {
    Add-Content ".gitignore" ".env"
    Write-Host "✅ Added .env to .gitignore"
}
```

### Step 3: Initialize state files

Create `.squad/state/discord-discussion-state.json` using the exact schema from the framework. Run:

```powershell
$statePath = ".squad/state/discord-discussion-state.json"
$outboxPath = ".squad/state/discord-outbox.json"

# Load the function from discord-watch.ps1
. (Join-Path $PSScriptRoot "scripts/discord-watch.ps1")

# Initialize both files
Initialize-DiscordStateFiles -DiscussionStatePath $statePath -OutboxPath $outboxPath -ChannelId $env:DISCORD_CHANNEL_ID

Write-Host "✅ Initialized discord-discussion-state.json and discord-outbox.json"
```

Or create them manually:

**`.squad/state/discord-discussion-state.json`:**
```json
{
  "schemaVersion": 2,
  "channelId": "YOUR_DISCORD_CHANNEL_ID",
  "lastMessageId": null,
  "lastScanAt": null,
  "lastProcessedAt": null,
  "pending": [],
  "processed": [],
  "note": "Discord channel instructions are read with DISCORD_BOT_TOKEN and DISCORD_CHANNEL_ID from local .env."
}
```

**`.squad/state/discord-outbox.json`:**
```json
{
  "schemaVersion": 1,
  "pending": [],
  "sent": [],
  "note": "Queue high-signal Discord replies here. The runner posts `pending` items after each loop round."
}
```

### Step 4: Update `workflow.config.json`

Add the `communication` block to `workflow.config.json`:

```json
{
  "name": "Your Squad Name",
  "communication": {
    "primary": "discord",
    "discord": {
      "credentialsFrom": ".env",
      "guards": {
        "post": "allow"
      }
    },
    "teams": {
      "enabled": false
    },
    "email": "block",
    "calendar": "block"
  }
}
```

**Key fields:**
- `primary: "discord"` — Discord is the default, not Teams
- `credentialsFrom: ".env"` — runner reads `DISCORD_WEBHOOK_URL`, `DISCORD_BOT_TOKEN`, `DISCORD_CHANNEL_ID` from local `.env`
- `guards.post: "allow"` — agent may post replies (no approval gate required)
- `teams.enabled: false` — Teams is disabled (set to `true` only if you actually use Teams alongside Discord)
- `email: "block"` — block email integration
- `calendar: "block"` — block calendar integration

### Step 5: Populate `routing-ops.md` and `team-ops.md`

Update the **Channels** section in both files. Use this template (replace with your actual channel info):

**In `.squad/routing-ops.md` — Channels section:**
```markdown
## Channels

- **Primary surface:** Discord (credentials via local .env — DISCORD_WEBHOOK_URL, DISCORD_BOT_TOKEN, DISCORD_CHANNEL_ID)
- Teams: disabled
- Email: blocked
- Calendar: blocked
```

**In `.squad/team-ops.md` — Channels section:**
```markdown
## Channels

- **Primary surface:** Discord (credentials via local .env — DISCORD_WEBHOOK_URL, DISCORD_BOT_TOKEN, DISCORD_CHANNEL_ID)
- Teams: disabled
- Email: blocked
- Calendar: blocked

## Runtime Settings

...

- Discord notifications are enabled through the local DISCORD_WEBHOOK_URL value in .env; do not store the webhook in tracked files.
- Discord instruction polling can be enabled with local DISCORD_BOT_TOKEN and DISCORD_CHANNEL_ID values in .env; do not store bot tokens in tracked files.
```

### Step 6: Update monitor charter (`.squad/charter-source/monitor.md` or equivalent)

Key changes:

1. **Replace the Communication Surface intro** with:
   ```markdown
   ## Communication Surface

   Discord is the default primary external communication surface. No override or injection is required to use Discord — it is active whenever `workflow.config.json` does not explicitly disable it.

   - Treat Discord as the primary surface unless `workflow.config.json -> communication.teams.enabled: true` is set.
   - Do not report missing Teams channels, Teams MCP, mail, or calendar as blockers unless Teams is explicitly enabled in the workflow config. They are intentionally unused in Discord-default squads.
   - Use injected `## Discord Instructions` as operator messages for the current loop when present.
   - Teams integration is opt-in only. See **Teams Integration (opt-in)** section below.
   ```

2. **Add or update the Discord Discussion State Management section** (around line 67 in the current template):
   ```markdown
   ## Discord Discussion State Management

   Maintain `.squad/state/discord-discussion-state.json` as your durable checkpoint for Discord monitoring. The file schema:

   ```json
   {
     "schemaVersion": 2,
     "channelId": "<discord channel snowflake id>",
     "lastMessageId": "<snowflake of last message seen>",
     "lastScanAt": "<ISO timestamp>",
     "lastProcessedAt": "<ISO timestamp>",
     "pending": [],
     "processed": []
   }
   ```

   - **`pending`** — new Discord messages awaiting a visible agent reply
   - **`processed`** — Discord messages the agent has already handled (includes reply outbox ID and summary)
   - **`lastMessageId`** — prevents re-fetching old messages; polling starts after this ID
   - **`lastScanAt`** / **`lastProcessedAt`** — audit timestamps for reconciliation
   ```

3. **Gate any Teams-specific language** behind a conditional:
   ```markdown
   ## Teams Integration (opt-in)

   Teams is only available when `workflow.config.json -> communication.teams.enabled: true`. Do not implement Teams-dependent logic unless Teams is explicitly enabled.
   ```

### Step 7: Update `squad.agent.md` (if your squad controls it)

Three updates to `.github/agents/squad.agent.md`:

1. **Add Discord to MCP Detection table** (around line 515):
   ```markdown
   - `discord_*` or `discord-mcp-*` → Discord (messages, channels, webhooks)
   ```

2. **Add Communication Surface subsection** (around line 539):
   ```markdown
   ### Communication Surface

   The active communication surface is configured in `workflow.config.json -> communication.primary`. Read this field on session start and route accordingly — do not assume Teams.

   - **On session start:** Read `workflow.config.json -> communication.primary` (value: `discord` or `teams`).
   - **Route monitor spawns** with the correct surface context from config, not from injected overrides or hardcoded defaults.
   - **If `communication.primary` is missing:** Default to `discord` — Discord is the more common modern surface.

   Pass the resolved surface to spawned agents as `COMMUNICATION_SURFACE` (see spawn templates below).
   ```

3. **Add `COMMUNICATION_SURFACE` to spawn templates**. Find the Lightweight and Standard templates and add this line after `GITHUB_REPO`:
   ```markdown
   - `COMMUNICATION_SURFACE`: resolved from `workflow.config.json -> communication.primary`
   ```

   Example:
   ```markdown
   - `TEAM_NAME`: "Your Squad Name"
   - `GITHUB_REPO`: "owner/repo"
   - `COMMUNICATION_SURFACE`: "discord"
   ```

⚠️ **Coordinator restart required after this change.** The coordinator will pick up the new `COMMUNICATION_SURFACE` env var on next invocation.

## Validation checklist

After following all steps, validate:

- [ ] `scripts/discord-watch.ps1` exists and contains `Get-DiscordInstructions` function
- [ ] `.env` exists with all 3 Discord credentials; `.env` is in `.gitignore`
- [ ] `workflow.config.json` has `communication.primary: "discord"`
- [ ] `.squad/state/discord-discussion-state.json` exists with schemaVersion 2
- [ ] `.squad/state/discord-outbox.json` exists with schemaVersion 1
- [ ] Monitor charter no longer defaults to Teams (includes "Discord is the default" language)
- [ ] `routing-ops.md` and `team-ops.md` both have Channels sections documenting Discord
- [ ] `.github/agents/squad.agent.md` includes `Communication Surface` subsection and `COMMUNICATION_SURFACE` in spawn templates (if applicable)

### Run the startup check

```powershell
./run.ps1 -Validate
```

Expected output:
```
  🚀 Your Squad Name — X charter(s), Discord notifications
  🔔 Discord webhook configured
  👂 Discord instruction polling configured
  ✅ Validation passed!
```

### Perform an end-to-end test

1. Start the runner:
   ```powershell
   ./run.ps1
   ```

2. Send a message in the Discord channel (e.g., "Hello squad!")

3. Wait one polling cycle (default 5 minutes, or as configured in `workflow.config.json`)

4. Check `.squad/state/discord-discussion-state.json`:
   ```
   "lastScanAt": "2026-05-05T00:30:00.1234567-04:00"
   "pending": [{ "id": "...", "author": "...", "content": "Hello squad!" }]
   ```

5. Check runner logs for:
   ```
   👂 Discord instruction polling configured
   ```

6. After the agent responds, check `.squad/state/discord-outbox.json`:
   ```
   "pending": [{ "id": "...", "createdAt": "...", "content": "✅ Agent reply..." }]
   ```

7. Wait another cycle; the reply should post to Discord and outbox should move the item to `sent`

## What NOT to do

- ❌ **Never commit `.env`** or hardcode any Discord token in config files, charters, or code
- ❌ **Don't set `communication.teams.enabled: true`** unless you actually use Teams
- ❌ **Don't delete the Teams gated section** from monitor.md — just gate it behind `communication.teams.enabled: true`
- ❌ **Don't reuse the same webhook URL** across squads — Discord webhooks are single-use per squad
- ❌ **Don't bypass the outbox** — always queue Discord replies through `.squad/state/discord-outbox.json` with `id`, `createdAt`, `messageId`, `author`, and `content`

## Troubleshooting

### "Discord webhook configured" but no messages appear

- **Check `DISCORD_WEBHOOK_URL` in `.env`** — must be full URL starting with `https://discord.com/api/webhooks/`
- **Check bot permissions** — bot role must have "Send Messages" and "Embed Links" in target channel
- **Check outbox** — message may be in `pending` but not `sent`; check `lastError` field

### "Discord instruction polling configured" but no messages are read

- **Check `DISCORD_BOT_TOKEN` and `DISCORD_CHANNEL_ID` in `.env`** — both must be present
- **Check bot is in the server** — bot must be a member of the Discord server
- **Check bot permissions on channel** — must have "Read Message History" and "View Channels"
- **Check for API errors** — if `discord-discussion-state.json` has `lastError` field, it logs failed API calls

### Messages appear in `pending` but agent doesn't see them

- **Check `run.ps1` output** — should show `## Discord Instructions` section in the prompt
- **Check prompt is being injected** — monitor charter must include Discord in the agent spawn prompt
- **Check `Get-DiscordInstructions` function** — verify it's returning non-empty markdown

### Outbox items stuck in `pending`

- **Check `DISCORD_WEBHOOK_URL` validity** — webhook may have been revoked or URL is malformed
- **Check `lastError` field in outbox item** — logs the HTTP error
- **Manual retry** — edit outbox item to set `attempts: 0` and `sentAt: null`; runner will retry on next cycle

## Decision pin template

When your squad adopts this skill, record the decision in `.squad/decisions/inbox/`:

```markdown
### YYYY-MM-DDTHH:MM:SS±HH:MM: Skill applied — discord-first-class

**By:** [Your Name]

**What:** Applied .squad/skills/discord-first-class/SKILL.md — upgraded Discord from runtime override to configured primary surface.

**Why:** Discord is now the default communication surface; no override injection needed. Enables durable checkpoint polling (discord-discussion-state.json), outbox queuing (discord-outbox.json), and consistent charter behavior across agent runs.

**Changes:**
- Added `scripts/discord-watch.ps1` [or: already present from framework]
- Updated `workflow.config.json` with `communication` block
- Populated `.squad/state/discord-discussion-state.json` and `.squad/state/discord-outbox.json`
- Updated routing-ops.md, team-ops.md, monitor.md
- Updated squad.agent.md with Communication Surface section

**Status:** ✅ Validated with end-to-end test; startup check passed.
```

---

## Reference: Full file locations

After applying this skill, your squad repo should have this structure:

```
.
├── .env (never committed — holds DISCORD_WEBHOOK_URL, DISCORD_BOT_TOKEN, DISCORD_CHANNEL_ID)
├── .gitignore (includes .env)
├── workflow.config.json (communication block)
├── run.ps1 (loads scripts/discord-watch.ps1 on line 13)
├── loop.md
├── .squad/
│   ├── routing-ops.md (Channels section)
│   ├── team-ops.md (Channels section)
│   ├── charter-source/
│   │   └── monitor.md (Communication Surface + Discord State Management sections)
│   ├── state/
│   │   ├── discord-discussion-state.json
│   │   └── discord-outbox.json
│   ├── skills/
│   │   └── discord-first-class/
│   │       └── SKILL.md (this file)
│   └── decisions/
│       └── inbox/
│           └── [your-decision-drop].md
├── scripts/
│   └── discord-watch.ps1 (function library)
└── .github/
    └── agents/
        └── squad.agent.md (Communication Surface subsection, COMMUNICATION_SURFACE env var)
```

---

**Validated:** May 2026 — Judgement Day squad  
**Framework repo:** chrispydizzle/old-cpu-squad  
**Confidence:** medium (single production validation)
