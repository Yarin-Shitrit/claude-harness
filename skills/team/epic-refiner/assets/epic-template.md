# Epic: <title>

> **Status:** Draft · **Author:** <name> · **Last updated:** <date>

## Summary
<2–3 sentences an executive can read and immediately understand: what this delivers and
why it matters. No jargon, no implementation detail.>

## Problem / Opportunity
<The user or business problem, grounded in discovery evidence. What is the cost of not
doing this?>

## Expected outcome & success metrics
<The change we expect in the world, and the measurable signal(s) that will tell us it
worked — metric, direction, and target. Avoid unmeasurable outcomes.>

## Users & personas
<Primary users and any affected stakeholders — end users, admins, operators. Who benefits,
who configures, who supports.>

## Scope
### In scope
- <…>
### Out of scope
- <explicit non-goals — these prevent scope creep>

## Functional requirements
<What the feature must let users do: key actions, workflows, inputs (mandatory / optional /
defaults), outputs (screens, reports, events), and required configuration.>

## User experience
<How users interact (UI / API / CLI), key usability and accessibility considerations, and
how errors are surfaced. Note design-team involvement if there's UI.>

## Acceptance criteria
<Testable, pass/fail statements. Each should be provable by a tester. Prefer Given/When/Then
or a clear checklist.>
- [ ] <criterion>

## Non-functional requirements
*Include only the subsections that apply; the readiness summary records anything marked N/A.*

- **Security & permissions:** <auth, encryption, data masking, role-based access>
- **Performance & capacity:** <throughput, data volumes, concurrency, growth; note any
  postponed load testing + its PBI>
- **Availability & reliability:** <required uptime, MTBF, failure tolerance>
- **Recoverability:** <state recovery, backups, recovery state>
- **Auditability & logging:** <what is logged/audited, where, retention>
- **Monitoring:** <health signals, destination, freshness, alert thresholds>
- **Network:** <firewall/networking changes; Dev/QA vs prod differences>
- **Risk:** <abnormal-behavior detection, risk-conditional behavior>

## Integrations & dependencies
<APIs, services, databases, libraries this relies on. Flag cross-team dependencies and
whether those teams are engaged.>

## Architecture notes
<Architectural input required? Key decisions or constraints. Link designs if any.>

## Delivery & rollout
<Can it ship independently? Installation/upgrade path. Rollout strategy (all-at-once /
gradual / flagged). Data migration plan and drills. Impact on existing workflows.>

## Risks
<What could go wrong, likelihood/impact, and mitigation or contingency.>

## Assumptions
<Stated assumptions this Epic rests on, each flagged as validated or still-to-verify (with
an owner where possible).>

## Globalization & future-proofing
*(Include if relevant.)*
<Regions, time zones, languages, currencies, data residency. Extension points for likely
future change.>

## Open questions / not-ready items
<Everything still unresolved. Be honest — this is the list that has to shrink before the
Epic is truly ready.>
- [ ] <question — owner>

## Suggested child stories / PBIs
*(Optional — a starting breakdown, including stories for postponed testing, migration
drills, and upgrade work.)*
- <story>

---

## Readiness summary
Mark each checklist topic. This is the honest readiness call — an Epic with several "Needs
work" rows is fine as a draft; it just isn't ready to enter delivery yet.

| Topic | Status | Notes |
| :-- | :-- | :-- |
| Purpose & clarity | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Functional requirements | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| User experience | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Integration & dependencies | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Independence | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Architecture | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Testability | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Performance & capacity | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Availability & reliability | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Recoverability | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Security & permissions | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Risk | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Network | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Auditability & logging | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Monitorability | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Installation & upgrade | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Rollout | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Data migration | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Globalization | ☐ Addressed / ☐ Needs work / ☐ N/A | |
| Future-proofing | ☐ Addressed / ☐ Needs work / ☐ N/A | |

**Overall readiness:** <Ready to groom / Needs another pass — and the one or two things
that would move it to Ready.>
