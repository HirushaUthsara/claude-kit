# Topic presets

Set `kind` on the topic in Study HQ. Each preset changes five things: what Claude looks for in the source pass, what any research query asks for, how to explain, how to drill, and what the test looks like. The **Sources** lists below are what to look for when curating (`sources.md`), and what to steer a NotebookLM research query toward when Claude can't reach the material.

## docs: technical docs and tools

Typical outcome: operate, debug or design with X.

**Sources**
- Official docs for the exact version in use, with the version in the source title.
- Release notes.
- One design doc or deep dive for the *why*.
- One troubleshooting guide or postmortem.

**Absorb**
- Video Overview for request paths, data flows and architecture.
- Infographic for comparing options.
- Read sections for commands and config.

**Prove**
- The use-it case is a realistic failure: "pods on node B can't reach X, what do you check first and why".
- Suggest a hands-on lab in a sandbox or Claude Code when the module allows it.

**Drill:** Flashcards on mechanisms and distinctions.

**Watch:** docs lag reality. If NotebookLM's answer conflicts with what the learner sees in their running system, trust the system, mention the doc gap, and suggest a newer source.

## exam: certification and exam prep

Typical outcome: pass `<exam>` by `<date>`. Store the date in the topic's `deadline`.

**Sources**
- The official exam guide or blueprint with domain weights. This is always source #1.
- The official materials it names.
- Practice questions, if the learner has them.

**Modules**
- One module per blueprint domain.
- Order by weight × weakness.
- The "not covering" list is everything off-blueprint.

**Absorb:** Audio Deep Dive for domain overviews; Infographic for "which service when" comparisons.

**Drill**
- Quiz at Hard, scenario style. Exams test judgement.
- Flashcards only for limits and numbers the exam actually asks.

**Final week:** one mixed quiz across every domain, then a flashcard drill limited to whatever is still shaky.

## papers: research papers

Typical outcome: explain and evaluate the contribution, or implement the method.

**Sources**
- The paper.
- 1–2 papers it builds on.
- Optionally, one paper that cites or critiques it.

**Modules:** problem and claim → method → evidence → assumptions and limitations.

**Absorb**
- Audio Overview, Critique or Debate format, for the claim.
- Video Overview or Infographic for the method's pipeline.

**Prove**
- A five-sentence summary in their own words.
- Plus one limitation the learner finds themselves, not one the paper admits.
- Verify every statement about what the paper claims. Misattribution happens most here.

**Drill:** Quiz on *why* questions. Make flashcards for numbers only if the learner will cite or implement them.

## custom: internal or learner-provided material

Typical outcome: work effectively in their team's system, master a course they're taking, or learn from their own notes.

**Route:** NotebookLM-led. The learner's material is the primary source, and Claude can't see it until they paste or describe it.

**Sources**
- The learner's own files: internal docs, runbooks, design docs, course slides, a syllabus. Name exactly which kinds to add.
- Public background Claude curates: docs for the open-source tools the internal system is built on, for example.

**Absorb:** Audio Overview for the lay of the land; Video Overview for internal architectures and flows.

**Prove**
- Use-it cases come from their real system: "a deploy to staging hangs at step X; where do you look first?"
- Ask them to paste relevant snippets when grading needs their specifics. Never guess at internal details.

**Drill:** Flashcards on their system's names, owners and boundaries, but only the ones they'll actually need.
