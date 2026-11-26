# Sources

The source pass happens once per topic, at planning, and is topped up per module when a card needs it. It decides the route and produces 3–5 verified anchors per module. A good pass is the main way this system beats a generic NotebookLM notebook, so give it real effort: a full topic usually takes 8–20 searches.

## 1. Choose the route

Answer these in order. The first "yes" usually decides it.

1. **Is the material internal or private?** Company docs, the learner's codebase, a private wiki, a paid course they're enrolled in. Claude can't see it, so the route is **NotebookLM-led**: the card tells the learner exactly which of their files or pages to add. Claude can still curate public background, such as the docs of the open-source framework their internal system is built on.
2. **Is it customized?** The learner's own notes, a syllabus, a teacher's slides, an exam's official blueprint. Those files are the primary sources: **NotebookLM-led**, plus 1–2 public anchors if they genuinely help.
3. **Is it new or fast-moving?** Search anyway; recent material is exactly where a search beats memory. If the results include official docs, release notes or the authors' own writing, curate them. If they're thin or mostly aggregator and summary sites, go **Hybrid** or **NotebookLM-led**, and say why in one line.
4. **Does the module mostly need synthesis across many sources?** For example, an audio debate across ten papers, or comparing the learner's twenty uploaded PDFs. NotebookLM's research and source features fit better: **Hybrid**, with the research query doing the heavy lifting.
5. Otherwise, for an established public topic: **Curate**.

A topic can mix routes. Record the topic's main route in HQ, and note per module when it differs.

## 2. Research

- Search each module separately; a combined query returns shallow results for all of them.
- Search each named tool, library or talk on its own as well, especially anything version-specific.
- Fetch the page when a snippet doesn't confirm that it's the right page, author or version.
- When the learner supplied a list, check each item by title and author. AI-generated plans often contain plausible but invented video titles and IDs.

For each module, aim for:

| Role | What it is | How the learner uses it |
|---|---|---|
| **Docs** | Official reference for the exact version in use | Notebook source |
| **Read** | Why-it-works explanation by a primary author or recognized expert: book chapter, essay, design doc | Notebook source if public; otherwise read directly |
| **Watch** | Conference talk or maintainer video | Notebook source (public, with captions), and watch directly when it's highly visual |
| **Lab** | Hands-on exercise: official tutorial, kata, exercise repo | Do directly; never a notebook source |
| **Listen** (optional, one per topic) | Podcast episode with a primary author | Watch or listen directly, or add as a source |

Not every module needs every role. Three strong items beat five padded ones.

## 3. Quality ladder

Prefer higher rungs. Go lower only when nothing higher covers the module.

1. Official docs, specifications and standards, pinned to the version the learner uses.
2. Primary authors and maintainers: the creator's book (especially free online editions), talks, design docs, release notes.
3. Recognized experts at major venues (PyCon, NDC, GOTO, Strange Loop, vendor engineering blogs), and long-lived reference articles.
4. Well-known course or tutorial providers, for labs especially.

Skip: SEO aggregators, AI-written summary pages, content farms, re-uploads of talks, "top 10" listicles, and anything written for a version that no longer behaves the same way.

## 4. Verify every link

A link is verified only when all of these hold:

- The URL appeared in a search or fetch result in this session, or it is in HQ with a `checked` date in the last 30 days.
- The title and the author or speaker match what you're claiming. For YouTube, the video ID appears in the results, ideally from the official conference or creator channel.
- It's current: while checking, note any changed APIs, CLI flags or config as a one-line gotcha. Learners carry these into real work, and outdated tutorials are where they break.
- It works in NotebookLM, if it's meant to be a source. YouTube must be public with captions. A web source is a single page, and NotebookLM doesn't follow links, so link the exact chapter or article rather than a homepage. Paywalled pages are "read directly".

If you confirmed an item but never saw its exact URL (for example, a YouTube ID mentioned on another page), save it to HQ with an empty `url` and a note, and search for the real link before it goes into a card. If you can't verify an item, leave it out. If the learner asked about it specifically, name it as unverified and offer the verified alternative.

## 5. Output format

When the learner asks for resources, group them by module, one line each:

    **M<n>: <short module title>**
    - **Watch:** [<Title> — <Speaker>](<url>). <Why it's worth it, ≤15 words.>
    - **Read:** [<Title>](<url>). <What to read: chapters, sections.>
    - **Docs:** [<Page title>](<url>). Gotcha: <version note, if any>.
    - **Lab:** <Exercise name> (<url>). <Time estimate.>

Then one line on anything dropped or replaced, and why. In module cards, the same sources appear as the "Add sources" step (see `module-card.md`).

## 6. Record and refresh

- Save each anchor to the topic's `sources` in HQ (format in `study-hq.md`) in the same batch as the topic.
- Re-check a module's sources when you reach it more than 30 days after the pass, or when the learner reports a dead link, a version mismatch, or an import NotebookLM refused.
