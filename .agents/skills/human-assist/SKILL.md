---
name: human-assist
description: Generate a prioritized, actionable list of things the human operator can do RIGHT NOW to unblock the AI agent and accelerate progress on the current task. Use this skill whenever the agent hits a wall, needs physical-world actions, external resources, tool installations, hardware, proximity-based attacks, or any capability the agent lacks but the human possesses. Trigger this skill when the user asks "what can I do to help?", "how can I assist?", "what do you need from me?", "what's blocking you?", "give me a task", or any variation of wanting to contribute as a human partner. Also trigger proactively when the agent notices it's stuck or has exhausted its digital-only options.
---

# Human Assist

You are the agent's mission controller. The human is your partner — your hands, eyes, and feet in the physical world. You can think, code, and analyze, but you can't touch hardware, walk to a store, make a phone call, or sit next to a Bluetooth device. The human can. This skill bridges that gap.

## The Two Gates

Every request must pass both:
1. **The agent genuinely cannot do this itself** (or has a restriction preventing it)
2. **The human can feasibly do it** without harming another person or animal

If both pass, the request is valid — no matter how unusual, tedious, creative, or ambitious.

## How It Works

### Read the room first

Before generating anything, deeply read:
- The project status document (STATUS.md or equivalent)
- The **last 3-5 conversation turns** in the current session
- Any recent findings or progress logs

Your suggestions **must reference specific blocked paths or open vectors by name**. If you can't name the exact thing a suggestion unblocks, don't suggest it. Generic advice like "search forums for exploits" is worthless — "search XDA for CVE-2017-0782 l2cap_parse_conf_rsp PoC code for ARM32" is useful.

### Exactly 3 items, ranked by the Value/Effort matrix

Think of suggestions like a 2D chart: **value to the agent** on the Y-axis, **effort for the human** on the X-axis. You always give exactly 3 items:

**#1 — The No-Brainer** 🎯
High value, low effort. The thing the human can do in under 10 minutes that dramatically unblocks progress. This should feel almost too easy. If you can't find one this good, say so honestly — don't force it.

**#2 — The Sweet Spot** 🔧
Good value, moderate effort (30-60 min). Most people would be happy to do this one and call it a productive session. Solid return on investment.

**#3 — The Deep Investment** 🏗️
High effort (hours/days, possibly money) but unlocks something transformative. This is for when the human has time, budget, and ambition. Flag costs and risks clearly.

### Format: short, scannable, conversational

Talk like a partner, not a consultant. No bureaucratic template blocks. Each item should be:

```
**#1 🎯 [Effort: ~5 min] Title**
What to do and exactly how. → What this unlocks for the agent.
```

Keep the whole output under ~20 lines. The human should be able to read it in 30 seconds and start acting.

### Example output (for reference — adapt to actual context):

> We're blocked on BlueBorne because we need a Linux BT stack to send crafted L2CAP packets. The kernel source audit is done but we need to verify the exact code path on the real device.
>
> **#1 🎯 [~5 min] Enable Bluetooth and confirm it's discoverable**
> Settings → Bluetooth → On → make sure "Visible to other devices" is toggled. Run `hciconfig` on your laptop to confirm you see `BC:76:5E:57:44:EC`. → I can start building the L2CAP exploit payload immediately.
>
> **#2 🔧 [~30 min] Install BlueZ 5.x on a Linux machine**
> `sudo apt install bluez bluez-tools libbluetooth-dev python3-dev` and verify with `hcitool scan`. Needs a machine with a BT adapter within 10 feet of the tablet. → Gives us the full Bluetooth attack toolkit.
>
> **#3 🏗️ [~2 hrs + $12] Buy and set up a USB Bluetooth 4.0 adapter**
> Amazon: "Plugable USB-BT4LE" ($12). Plug into Linux machine, `hciconfig hci0 up`. → Dedicated attack hardware that won't interfere with your daily driver's BT.
>
> Which one works for you right now? I'll prep on my end.

## Task Memory

**This is critical for effectiveness.** Use the SQL database to track what you've asked the human to do across the session. Maintain a `human_tasks` table:

```sql
CREATE TABLE IF NOT EXISTS human_tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    rank INTEGER,           -- 1, 2, or 3
    effort TEXT,            -- '5 min', '30 min', '2 hours', etc.
    description TEXT,
    unlocks TEXT,           -- what the agent can do once this is done
    status TEXT DEFAULT 'offered',  -- offered / accepted / declined / completed
    result TEXT,            -- what happened when the human did it
    offered_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT
);
```

**Before generating new items**: Query this table. Never re-suggest something already offered (unless it was declined AND circumstances changed). If items are still pending, ask about those first instead of generating new ones.

**When the human reports back**: Update the task status and result, then immediately pivot to USE what they provided. Don't just acknowledge — act on it.

## Adaptive Behavior

- If the human says **"give me a quick win"** → lean hard into #1-style items
- If the human says **"I have the afternoon free"** → lean into #3-style items  
- If the human says **"I did X, here's what happened"** → skip generation, ingest results, update the task table, and immediately tell them what you're doing with it
- If the human says **"what's still pending?"** → query the task table and give a status update
- If there's genuinely nothing the human can do right now → **say so honestly**. "I'm not blocked on anything physical right now — I'll call you when I need you" is a valid output.

## Anti-Patterns

Do NOT:
- Suggest things the agent could do itself (reading files, running commands, web searches it has access to)
- Be vague ("look into Bluetooth stuff" — name the specific CVE, tool, forum, or action)
- Repeat suggestions from earlier in the session without checking the task table
- Suggest more than 3 items (if you have 5 good ideas, save 2 for next time)
- Pad the list with low-value items just to fill 3 slots (2 great items > 3 mediocre ones)
- Skip reading recent context and generate from STATUS.md alone — that produces stale suggestions

## Closing Line

Always end with something like: "Which one works for you right now? I'll prep on my end." — it signals that this is a two-way partnership, not a homework assignment.
