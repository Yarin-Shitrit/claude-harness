# Spec Document Skill — Usage Guide

A skill for generating technical specification documents that follow our team's standard format.

## Setup

Install through the marketplace (Claude Code, Codex) or manually copy the skill folder (Antigravity). Full instructions live in the [repo README](../../../../README.md). Once installed, restart your agent session.

## How to use it

Open the agent in the directory where you want the spec saved (typically your project root or a `docs/` folder), then ask for a spec in plain language. The skill triggers on explicit phrasings — these all work:

- "Write a spec for [feature]"
- "Draft a specification document for this story"
- "Turn this into a spec doc"
- "Create a design doc for [thing]"

Casual mentions of "spec" in passing won't trigger it; you have to ask for one.

## What the agent will do

1. **Inventory the context.** It reads the conversation, any files you've attached or referenced, and the relevant code in your working directory.
2. **Ask clarifying questions** for genuine gaps — usually around business context ("why now?"), non-functional requirements, or alternative implementations you considered.
3. **Write the spec** as `spec-<feature-name>.md` in your working directory (or `docs/` / `specs/` if you have one).
4. **Flag thin sections** in its final message so you know what to double-check.

## How to get the best output

- **Give it material.** Open the agent in the right directory, paste the ticket or upstream decision, attach relevant files. The more it knows upfront, the fewer questions it asks.
- **Answer its questions concretely.** If it asks "why now?", a specific answer ("customer X escalated last week") produces a much better Intro than a vague one.
- **Treat the first draft as a draft.** The agent will mark sections where it made assumptions. Review those first.

## The output structure

Every spec follows this format:

- **Intro** — The problem (plain language) + Why we got this assignment (context)
- **Requirements** — Functional (testable behaviors) + Non-functional (perf/scale/security/etc.)
- **Proposed Implementation** — Broken down by area (DB schema, API design, etc.). Each area presents Option A / Option B / ... with trade-offs, and ends with an explicit recommendation.
- **Summary** — Chosen approach, key decisions, out-of-scope items.

## Common questions

**Can I ask for changes after the first draft?**
Yes — just tell the agent what to change ("flesh out the API options", "the recommendation in section 2 should be Option B because ..."). It will edit the file in place.

**How many options will the agent present per area?**
Up to 4, and only the ones genuinely worth considering. If only 2 approaches are strong, it'll present 2. If only 1 is viable, it'll present 1 and explain why alternatives were ruled out. It won't pad with weak options to fill space.

**What if I only want part of a spec?**
Ask for it directly: "draft just the Proposed Implementation section for [feature]". The skill is built around the full doc but the agent will accommodate partial requests.

**What if I can't pick a recommendation yet?**
The skill is strict: every area gets a recommendation. If information is missing, the agent will name what's missing and still pick the option it would bet on today. Don't ship a spec without recommendations.
