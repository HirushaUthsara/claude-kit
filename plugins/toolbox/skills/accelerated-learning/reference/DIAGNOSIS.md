# Diagnosis by pretest

Read this before the first probe.

## Contents

- Why pretest instead of quiz
- The two anchor probes
- Probe patterns that work
- Probe patterns that fail
- Domain-specific openers
- Baseline template
- Reading the evidence

## Why pretest instead of quiz

A pretest does three jobs a diagnostic quiz does not:

1. **It routes.** You learn which modules to skip.
2. **It teaches.** Attempting a problem before instruction improves later learning of that material, and this holds even when the attempt is wrong — the failure creates the gap the explanation then fills. A quiz that only measures throws this away.
3. **It calibrates the learner.** People are poor judges of their own understanding. A failed attempt is more convincing than being told they have a gap.

Because probes teach, do not skip them for someone who seems knowledgeable. Aim them higher instead.

## The two anchor probes

**Probe 1 — ceiling.** Aim at something near the top of the topic. If they clear it, you delete whole modules and the journey shortens dramatically. If they miss it, you have learned where the ceiling actually is, and they have primed the material.

**Probe 2 — load-bearing prerequisite.** Aim at the one idea that everything downstream depends on. If this is shaky, everything after it will be, and no amount of careful teaching later will compensate.

Probes 3 and 4 are optional. Add them only when the topic is broad enough that two probes leave the route genuinely ambiguous.

## Probe patterns that work

- **Predict the outcome.** "Two threads increment the same counter 1000 times each. What's the final value, and why?"
- **Choose and justify.** "Blob storage or a managed disk for this workload — which, and what makes you sure?"
- **Spot the flaw.** Show a plausible-but-wrong design, config, or derivation. Ask what breaks.
- **Tiny case.** "A user in subnet A can't reach a service in subnet B. Name the first two things you'd check."
- **Draw the boundary.** "Where does X stop being the right tool?"
- **Explain the why.** "Why does this exist at all — what was broken before it?"

Each of these produces reasoning you can read. Right or wrong is less informative than *how* they got there.

## Probe patterns that fail

- Self-rating on a scale. It measures confidence, not knowledge, and the two correlate weakly.
- "Have you used X before?" Usage is not understanding.
- Definition recall. Recognising a term says nothing about whether they can apply it.
- Anything answerable by pattern-matching the question's own wording.
- Batching several probes into one response. It reads as an exam and it collapses the evidence.

## Domain-specific openers

| Domain | Ceiling probe aims at | Prerequisite probe aims at |
|---|---|---|
| Cloud / infra | A design tradeoff under a real constraint | Addressing, identity, or isolation model |
| Programming | Predicting runtime behaviour of a short snippet | The execution model (memory, scheduling, evaluation order) |
| ML / stats | When the method fails or is inappropriate | What the objective is actually optimising |
| Finance / tax | Applying a rule to a case with an exception in it | Which entity or jurisdiction the rule attaches to |
| Law / policy | Reasoning from principle to a novel fact pattern | The source of authority and its limits |
| Language learning | Producing a sentence under a constraint they haven't drilled | The sound-to-script mapping, or core word order |
| Craft or performance | Diagnosing what went wrong in a finished attempt | The physical or perceptual primitive underneath |
| Decision-making | Naming the tradeoff a proposal is hiding | What would count as evidence against it |

## Baseline template

Deliver this as prose, not a table. Keep it under 120 words.

- **Solid** — what they demonstrated, named specifically. Cite the probe.
- **Shaky** — what they got partly right, and the exact edge that wobbled.
- **Gap** — what is missing and blocks the outcome.
- **Skipping** — modules being cut, each tied to the evidence that justifies cutting it.
- **Pace** — the tier chosen, with the reason in half a sentence.

Then: "Correct anything I've got wrong here." Stop.

## Reading the evidence

- A correct answer with wrong reasoning is a gap, not a pass. Record it as shaky.
- A wrong answer with sound reasoning is usually a missing fact, not a missing model. Cheap to fix.
- Fluent vocabulary with no mechanism underneath is the most common trap with experienced professionals. Probe the mechanism before believing the vocabulary.
- Hedging ("I think maybe...") on something they get right means shaky, not solid. Believe the hedge.
- If they decline to attempt, do not push twice. Assume the lower tier and let the first teaching turn re-test.
