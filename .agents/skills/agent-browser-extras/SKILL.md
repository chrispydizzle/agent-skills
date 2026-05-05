---
name: agent-browser-extras
description: >
  Additional browser automation guidance for agent-browser. Use alongside
  agent-browser for persistent profile troubleshooting, authentication boundary
  checks, media uploads, social publishing, crop/aspect controls, carousel
  posting, and live verification of uploaded or shared visual assets.
---

# Agent Browser Extras

Internal overlay skill extending `agent-browser` for profile and media-publish
edge cases.

## Persistent profile authentication boundary

Repeated profile warnings are ambiguous. After closing and reopening with the
requested profile, trust the visible page state over the warning text:

- If the page shows a logged-out state or login form, stop before credential
  handling and report the auth boundary.
- If the page is authenticated, continue but capture the state that proves it.
- Do not treat repeated warning text alone as proof that the requested profile
  was not used.

## Media crop and aspect controls

For social posts, carousels, thumbnails, and other media uploads:

1. Identify crop/aspect controls during the upload or create step.
2. Explicitly select the intended option when the platform offers one, such as
   `4:5` for portrait carousel assets.
3. Capture evidence before sharing that the composer preview uses the intended
   crop.
4. After sharing, verify the live post or final preview when possible because
   composer previews can differ from published rendering.

## Live-dimension verification

When a platform has known crop-default issues, pre-share evidence is necessary
but not always sufficient. Prefer a live-post screenshot, downloaded asset
dimensions, or another final-state check before declaring the visual state
correct.

## Anti-patterns

- Dismissing a logged-out page because a persistent-profile warning also
  appeared.
- Relying on default media crop controls when the desired aspect is available.
- Treating a composer preview as final evidence when the platform may crop
  differently after posting.
