# Sprint 2 Keystone MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the narrow Sprint 2 talent-aware behavior pass: Martyrdom-aware Zealot healing/stealth rules, talent-aware Psyker Venting Shriek peril preservation, and Veteran Focus Target verification with only a narrow ping contingency if needed.

**Architecture:** Keep the first pass at the owning seams. Use tiny local talent helpers in `heuristics_zealot.lua`, `healing_deferral.lua`, `heuristics_psyker.lua`, and only `ping_system.lua` if Veteran validation exposes a real issue. Do not introduce a generic keystone framework or widen Sprint 2 into the post-1.0 backlog.

**Tech Stack:** Lua 5.5, busted, DMF hook modules, Makefile, git

---

### Task 1: Lock Sprint 2 Scope In Docs

**Files:**
- Add: `docs/superpowers/specs/2026-04-18-sprint-2-keystone-mvp-design.md`
- Add: `docs/superpowers/plans/2026-04-18-sprint-2-keystone-mvp.md`

- [ ] **Step 1: Write the approved Sprint 2 design down exactly**

Capture the actual scope boundary so implementation does not drift back toward the stale broad `#38` issue body.

Must state explicitly:
- roadmap-narrow Sprint 2 wins over the broad issue text
- `#38` is the MVP / proof-of-concept for follow-up keystone work
- no Scrier's Gaze tuning
- no pocketable healing path
- no profile-ID logic

- [ ] **Step 2: Record the execution posture**

Document that the first pass stays in the owning modules with local helpers, and that Veteran is verification-first rather than pre-committed rewrite work.

---

### Task 2: Add Red Tests For Zealot + Psyker Talent-Aware Behavior

**Files:**
- Modify: `tests/heuristics_spec.lua`
- Test: `tests/heuristics_spec.lua`

- [ ] **Step 1: Add Martyrdom stealth cases**

Add cases that prove:
- low health alone no longer triggers `zealot_invisibility` when `zealot_martyrdom` is present
- overwhelm / low-toughness pressure still activates stealth under Martyrdom
- non-Martyrdom low-health emergency behavior is preserved

- [ ] **Step 2: Add Psyker shout talent cases**

Add cases that prove:
- `psyker_damage_based_on_warp_charge` and/or `psyker_warp_glass_cannon` raises the effective shout vent threshold
- `psyker_shout_vent_warp_charge` allows an even later, more decisive vent threshold
- surround / priority / low-toughness branches still fire the shout independent of the threshold shift

- [ ] **Step 3: Run the targeted heuristics spec**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/heuristics_spec.lua
```

Expected:
- new cases fail against the current generic logic

---

### Task 3: Add Red Tests For Martyrdom Healing Deferral

**Files:**
- Modify: `tests/healing_deferral_spec.lua`
- Test: `tests/healing_deferral_spec.lua`

- [ ] **Step 1: Add Martyrdom station and deployable cases**

Add cases that prove:
- Martyrdom bots defer health stations even when the generic human-vs-bot threshold would normally allow the bot to heal
- Martyrdom bots also defer med-crates on the live deployable seam
- non-Martyrdom behavior still obeys the existing setting thresholds

- [ ] **Step 2: Run the targeted healing deferral spec**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/healing_deferral_spec.lua
```

Expected:
- the new Martyrdom cases fail against the current generic logic

---

### Task 4: Implement Zealot + Psyker Talent-Aware Rules

**Files:**
- Modify: `scripts/mods/BetterBots/heuristics_zealot.lua`
- Modify: `scripts/mods/BetterBots/healing_deferral.lua`
- Modify: `scripts/mods/BetterBots/heuristics_psyker.lua`

- [ ] **Step 1: Add minimal local talent helpers**

In each owning module, add tiny helpers for presence checks rather than a new shared module.

Rules:
- helpers stay private to the file
- absent talent tables must fall back to current generic behavior

- [ ] **Step 2: Implement Martyrdom behavior**

Update `heuristics_zealot.lua` so:
- non-Martyrdom behavior is unchanged
- Martyrdom blocks the low-health-only Shroudfield emergency path
- overwhelm / low-toughness / ally-aid branches remain live

Update `healing_deferral.lua` so:
- Martyrdom bots always defer health stations and med-crates on the live seams
- debug messages make the Martyrdom reason visible

- [ ] **Step 3: Implement Psyker shout behavior**

Update `heuristics_psyker.lua` so:
- peril-value talents raise the shout vent threshold
- improved vent-on-shout talent raises it further or otherwise biases the shout toward serving as the vent valve
- other shout triggers remain intact

- [ ] **Step 4: Re-run the touched specs**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/heuristics_spec.lua
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/healing_deferral_spec.lua
```

Expected:
- all new cases pass

---

### Task 5: Validate Veteran Focus Target Seam

**Files:**
- Modify: `tests/ping_system_spec.lua`
- Maybe modify: `scripts/mods/BetterBots/ping_system.lua`

- [ ] **Step 1: Add a seam test for Veteran-owned tagging**

Write a test that reflects the actual Sprint 2 question:
- does the current ping path let a Focus Target Veteran claim a qualifying tag on a fresh elite/special target?

- [ ] **Step 2: Decide based on the failing shape**

If the test proves the current path is already sufficient:
- keep production code unchanged
- document that Sprint 2 Veteran slice was verification-only

If the test shows a real seam failure:
- patch only `ping_system.lua`
- keep the fix narrow and Focus Target-specific
- do not widen into `target_selection.lua`

- [ ] **Step 3: Run the targeted ping spec**

Run:

```bash
lua /usr/lib/luarocks/rocks-5.5/busted/2.3.0-1/bin/busted tests/ping_system_spec.lua
```

Expected:
- either green validation with no production change, or one narrow fix that makes the new case pass

---

### Task 6: Sync Docs And Verify

**Files:**
- Modify any impacted docs if behavior descriptions materially changed:
  - `docs/dev/architecture.md`
  - `README.md`
  - `docs/dev/roadmap.md`
  - `docs/dev/status.md`
  - `docs/dev/validation-tracker.md`

- [ ] **Step 1: Update docs for the shipped Sprint 2 behavior**

At minimum, sync any design/roadmap language that becomes stale once the implementation lands.

- [ ] **Step 2: Run the local verification set**

Run:

```bash
make check-ci
```

If `make check-ci` is too slow while iterating, run the targeted specs first and finish with the full gate before claiming completion.

- [ ] **Step 3: Record any residual risk**

If Veteran remains verification-only or Psyker thresholds still need in-game tuning, state that explicitly as a runtime validation risk rather than quietly widening the code.
