# Module card

A module card is the learner's whole NotebookLM session for one module: numbered steps, run in order, with one paste block each, ending with the check-in template. Keep the card under about 350 words outside the paste blocks. Location hints stay loose, because NotebookLM's UI changes; if the learner says theirs differs, adapt.

## Shape

    **Module <n>: <capability title>** · about <minutes> min in NotebookLM (+ <minutes> lab)

    **1. <Step name>**: <where, one line> · <settings, if any>
    ```
    <exact text to paste>
    ```
    ...more steps...

    **Check-in**: when you're done, paste this back to me, filled in:
    ```
    Check-in: Module <n>
    Did: <steps done, anything skipped>
    Quiz: _/_ · Missed: <paste the questions you got wrong>
    Flashcards missed: <paste them>
    Lab: <done / partial / skipped> · <what broke or surprised you>
    Unclear: <anything that didn't click>
    ```

Leave the Lab line out of the check-in when the card has no Lab step. Never put the guess questions or their answers in any step.

## Steps to choose from

Pick 4–6 steps, in this order. Step numbers in the card run 1, 2, 3… whichever steps you pick.

### Add sources (Curate and Hybrid routes)

Where: Add source → Website, or YouTube. Paste one link at a time if the box takes only one.

```
<verified url 1>
<verified url 2>
<verified url 3>
```

Under the block, one short line per link: role and title, e.g. "Watch: Boundaries — Gary Bernhardt". Only include items meant as notebook sources (see `sources.md`). Labs, paywalled books and caption-less videos go in their own steps, never here. If the module reuses sources already in the notebook, name them instead of adding them again.

### Research (NotebookLM-led modules, and Hybrid gaps)

**NotebookLM-led.** First tell the learner which of their own files or pages to add (Add source → upload, Drive, or Website). Then run Deep Research from the source search box and import what it finds:

```
Research <topic> for someone who wants to <outcome>. Prefer
primary and expert sources: official docs, specifications or
standards, core-developer writing and conference talks, current
as of <version or year>. Cover: <the module titles>. Skip
beginner tutorials and <out of scope>.
```

**Hybrid gap.** Use Fast Research with a narrow query that names what the notebook already has, so research adds to it rather than duplicating it:

```
<gap scope> — official docs and expert deep dives only. I already
have <anchor titles>; find what they don't cover.
```

On Curate modules, skip this step unless the source pass named a gap; then use the Hybrid-gap query.

### See it (the main explanation)

Choose the format by the module's content:

| Content | Feature | Prompt pattern |
|---|---|---|
| A process, flow, pipeline or architecture | Video Overview → customize | "Explain only <scope> as a visual walkthrough. Show each step on screen, in order, and what changes between steps. The viewer knows <prerequisites>; skip them. Skip <out of scope>." |
| A comparison, hierarchy or set of tradeoffs | Infographic | "One infographic comparing <A>, <B>, <C> on <3–5 dimensions that matter for the outcome>. Include when to choose each and the most common mistake." |
| A whole-topic overview (module 1) | Audio Overview, Brief, or Video Overview | "Big picture of <topic> for someone who wants to <outcome>: the <3–5 main parts> and how they connect. Skip <out of scope>." |
| Many related terms | Mind Map, then click into <scope> | (no prompt; name the branches to open) |

When one anchor is a highly visual talk, you can tell the learner to watch it directly here instead of, or before, the generated overview. Give the minutes.

### Ask (optional, ~5 min)

Where: chat, with Learning Guide style if offered. Point it at the hardest part of the module:

```
Teach me <the trickiest part of the module> step by step, with
one concrete example from the sources. Ask me a check question
after each step before you continue.
```

### Quiz

Where: Studio → Quiz → customize · Difficulty: Medium for a first pass · Number: Standard.

```
Questions only on <module scope>. Mix "why" questions with
scenarios: <one example scenario type for this topic>. No
questions on <out of scope>.
```

Tell the learner to note the score and the questions they missed, and to tap "explain" on each miss.

### Flashcards

Where: Studio → Flashcards → customize · Difficulty: Medium · Number: Fewer.

```
Cards only on <module scope>: the mechanisms and the
distinctions between easily confused ideas (<pair A vs B>, <pair
C vs D>). No bare definitions.
```

Tell the learner to go through once, then rerun "Missed it" until it's clear.

### Lab (when the module has a hands-on exercise)

Where: their editor or terminal, outside NotebookLM. Give the verified exercise link, the exact commands to get started, one concrete goal, and a time box. Include any version gotcha from the source pass. The paste block holds the setup commands:

```
<clone / install / run commands>
```

Goal in one line, e.g. "Get the tire-pressure Alarm tested with a stub sensor, with no real Sensor() anywhere in the tests."

## Writing rules

- Each paste block is imperative and scoped: what to cover, what's already known, what to skip. "Summarize the sources" fails.
- Name real distinctions and scenario types from the topic, so NotebookLM's quiz and cards aim at what matters.
- Every URL in a card must be verified (`sources.md`).
- Give a realistic minute estimate for the whole card, with the lab separate.
