# Visuals

Read this before building any visual.

## Contents

- Typed triggers
- The evidence behind the rules
- Medium routing
- Cost ladder
- Art direction
- Quality gate
- Scoping rules
- Surface fallbacks

## Typed triggers

The trigger is the concept type, not the turn's word budget. If the step is spatial, time-ordered, state-based, quantitative, a flow or topology, or a real-world object the learner has not seen — build a visual. The information is non-verbal and prose is a lossy encoding of it.

If the step is a definition, a rule, a procedure they will type, or a misconception correction — use prose. A visual there is decoration.

Do not describe a visual you could have built. Do not recommend that the learner picture something.

## The evidence behind the rules

The art direction further down is not taste, which is why it is worth protecting when a turn feels crowded. Each rule maps to a measured effect.

- **Build the visual at all.** Words with graphics beat words alone by the largest single margin in the multimedia literature. That is why a required visual degrades to a cheaper visual and never to prose.
- **Cut everything not being taught.** Excluding extraneous material improved learning in every one of the 23 experimental tests Mayer and Fiorella reviewed — the best-supported principle here, and the one behind the scoping rules below.
- **Attach labels to what they label.** Words placed near their corresponding graphics beat separated ones in all 22 tests reviewed. A distant legend is a defect, not a style choice.
- **Cue the one relationship being taught.** Signalling helps, but by a visibly smaller margin than the two above. Do not let highlighting crowd out deletion.
- **Break a dense visual into learner-paced parts.** Segmenting helps; a stepped control usually beats one crowded figure.

Effect magnitudes vary by study and population, and at least one classroom replication found smaller effects than Mayer's across the board, with two reversing. Treat the ordering as reliable and the numbers as approximate.

## Medium routing

| Learning task | Medium |
|---|---|
| Change an input, see the consequence | Interactive HTML artifact |
| Step through state, trace a path, watch a mechanism run | Interactive artifact with a step control |
| Numeric relationship, distribution, trend, payoff, uncertainty | Chart |
| Topology, architecture, hierarchy, dependency, state machine | Precise static diagram (SVG or Mermaid) |
| Bounded metaphor for an abstract idea | Generated illustration |
| Real object, place, interface, physical arrangement | Retrieved imagery |
| Exact comparison across fixed attributes | Table |
| Execution behaviour is the concept | Code plus its actual output |

Never use generated imagery for exact diagrams, data, code behaviour, or anything that must be numerically or technically precise.

## Cost ladder

When the ideal medium is unavailable or too expensive for the turn, step *down the ladder*, not out of it:

interactive artifact → animated or stepped SVG → static SVG or Mermaid diagram → chart → retrieved image → annotated table

Prose is not on this ladder. A required visual never degrades to prose.

## Art direction

Design for an adult professional. Clear, modern, credible — not childish, not corporate-template, not theatrically futuristic.

**Diagrams and charts.** Direct labels next to what they label, never a distant legend the reader has to match up. Strong hierarchy. Deliberate whitespace. Highlight the one relationship being taught and mute everything else. Avoid default plotting-library appearance, rainbow palettes, and heavy gridlines.

**Interactive explainers.** One dominant visual stage, not a dashboard of cards. Direct manipulation. Every control produces an immediately visible, educationally meaningful change. Meaningful transitions, clear active and inactive states, theme-aware colour, readable labels. Avoid raw form controls floating above an unstyled SVG.

**Generated illustrations.** One focal point, deliberate composition, coherent lighting, generous negative space. No dense labels, no text-heavy panels, no icon collages, no stock-photo or generic-infographic look.

**Retrieved imagery.** Clear composition, sufficient resolution, direct relevance. Never decorative filler.

Keep visual language consistent across a module — the same colour, direction, and shape should keep the same meaning from step to step.

## Quality gate

Scale the gate to the cost of the medium.

**Static SVG, Mermaid, chart, table** — no preview round. Check three things and ship:

1. Is the focal idea findable in three seconds?
2. Does it show only the current step, with nothing unlearned leaking in?
3. Are the labels attached to what they describe?

**Interactive artifacts and generated images** — render or inspect before showing, then also check:

4. Does every control do something educationally meaningful?
5. Does it open in a useful default state with a clear observation task?
6. Would it look credible in a paid learning product?

For a generated image that misses the brief, regenerate once with a corrected prompt. Do not iterate further; drop to the next rung of the ladder instead.

## Scoping rules

Scope every teaching visual to the current step. Hide, crop, dim, or postpone everything else. A technically correct full-system diagram is instructionally wrong when it exposes four unlearned ideas at once.

When reusing one artifact across several steps, progressively reveal only the layer or control the current step needs.

Pair every visual with one short observation task so the learner knows what to look at or manipulate.

## Surface fallbacks

Detect what the environment actually supports. Never promise, describe, or wait on a capability that is not present, and never announce the limitation as a failure — just take the next rung down.

- **No inline artifacts** — write a self-contained HTML file the learner opens locally, or drop to a static diagram plus a tiny runnable example.
- **No image generation** — use retrieved imagery, or a polished diagram. Never claim an illustration was produced when it was not.
- **No structured input controls** — render the same 2–4 options as a lettered list with a free-text alternative.
- **Text-only surface** — precise ASCII or Mermaid diagrams plus code output. Even here, do not fall back to plain prose for a spatial concept.

When the image-generation capability requires the image to end the response, put the observation task immediately before generating, and let the image close the turn.
