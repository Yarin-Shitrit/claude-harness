# Probing Question Banks

Supplemental follow-ups that go beyond the raw checklist. The checklist tells you *which*
topics to cover; these help you go deeper when an answer is thin, vague, or suspiciously
confident. Don't read them as a script — pick the two or three that actually open up the
weak spot in front of you.

## Cross-cutting probes (apply everywhere)

These four failure modes are why most Epics that "look ready" aren't. Keep them in your
peripheral vision through the whole conversation.

- **Success metrics.** "How will we know this worked?" If the answer is a feeling ("users
  will be happier") and not a measurable signal, push: what number moves, in which
  direction, measured how, by when? An Epic without a success metric can't be evaluated
  after it ships.
- **Assumptions.** Whenever a claim is stated as fact, ask what it rests on. "This assumes
  X — is X verified, or is it a bet?" Convert load-bearing bets into explicit assumptions
  to validate, ideally with an owner.
- **Dependencies.** "What has to be true, or done by someone else, for this to work?" Probe
  for other teams, upstream services, data availability, third parties, and sequencing.
  Hidden dependencies are the classic reason an Epic that looked independent stalls mid-sprint.
- **Acceptance criteria.** For each capability, ask "how would a tester prove this is done?"
  If a criterion can't be turned into a pass/fail check, it's a wish, not a criterion.

## A. Purpose & value

- Whose problem is this, really — and how do we know they have it? What evidence from
  discovery backs it?
- If we *didn't* build this, what happens? What's the cost of inaction?
- How does this ladder up to a product or business objective / OKR this quarter?
- Which persona benefits most, and are there personas who are affected but not served
  (e.g. admins configuring it, ops supporting it)?
- What is explicitly *out* of scope, and why? A crisp non-goal prevents scope creep later.

## B. Functional scope & UX

- Walk the primary workflow end to end — where does a user start, and what's the last thing
  they do? Where are the branch points and error paths?
- What are the mandatory inputs vs. optional ones vs. sensible defaults? What validation
  applies?
- What does the feature produce — screens, reports, files, events, notifications? Who
  consumes each output?
- How does a user recover from a mistake? What does a good error message say here?
- Are there accessibility, responsiveness, or localization expectations for the UX?
- Has design been involved if there's UI? If not, when will they be?

## C. Integration & structure

- What does this call, and what calls this? Map the APIs, services, databases, and events
  in both directions.
- Which of those dependencies are owned by another team — and have they been pulled into
  discovery/grooming yet, or are we planning around a stranger's roadmap?
- Is architectural input needed? If the shape of the solution isn't obvious, was an
  architect in the room during discovery?
- Can this be delivered independently to production, or is it entangled with other work
  that must ship first?

## D. Quality attributes (NFRs)

- **Performance & capacity:** peak throughput expected? Data volumes at rest and in flight?
  Concurrency? Year-on-year growth? If load/stress testing is being postponed, is a PBI
  written so it isn't forgotten?
- **Availability & reliability:** required uptime (avoid 100%)? Acceptable MTBF? Is failure
  tolerable, and what's the blast radius when it happens?
- **Recoverability:** does it need to restore prior state on restart, or start clean? Backup
  cadence? What's the recovery state?
- **Security & permissions:** authentication, encryption, data masking? Role-based access —
  who can and can't use this? Any sensitive/regulated data in play?
- **Risk:** any need to detect abnormal behavior, or behave differently under risk
  conditions (fraud, abuse, safety)?
- **Testability:** how do we test it? Special test data or a test-only API needed? Which
  environments (Dev/QA/Prod) are suitable, and does anything have to be verified in prod?
- **Network:** firewall rules or other networking changes? Does the network differ between
  Dev/QA and production (and therefore need prod-specific testing)?

## E. Operability

- **Auditability:** does anything here need an audit trail? What events, what data, stored
  where, retained how long?
- **Logging:** what should be logged, at what level, to which destination? What would an
  on-call engineer need at 3am to debug this?
- **Monitorability:** what signals prove it's healthy in production? Where do metrics land,
  how fresh, and what threshold should alert someone?

## F. Delivery & lifecycle

- **Installation / upgrade:** any special install steps? If this is an upgrade, what's the
  migration path, and are there PBIs for the upgrade work itself?
- **Rollout:** all-at-once or gradual (flag, canary, ring)? What existing workflows could
  this disrupt, and how do we de-risk that?
- **Data migration:** is data being migrated? What data, and is a migration drill planned
  and tested *before* production? (This is a frequent source of go-live incidents — treat a
  migration as its own mini-project with its own stories.)

## G. Reach & future

- **Globalization:** must it work across regions, time zones, languages, currencies? Any
  data-residency constraints?
- **Future-proofing:** where is this most likely to change next, and does the design leave
  room — hooks, extension points, config — for that without a rewrite?
