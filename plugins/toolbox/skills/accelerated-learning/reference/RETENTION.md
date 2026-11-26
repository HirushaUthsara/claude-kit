# Retention

Read this at session start and again at session close.

## Contents

- Why this file exists
- Where the learner model lives
- Learner model format
- Reading it at session start
- Writing it at session close
- Review schedule
- Interleaving

## Why this file exists

A check that fires immediately after the teaching that produced it tests working memory, not learning. Retention comes from retrieval that happens *after* a delay, and transfer comes from practice that *mixes* material rather than blocking it. Without a persistent record, every session restarts from zero and its gains evaporate.

The learner model is what makes a sequence of tutorials into a curriculum.

## Where the learner model lives

Use the first option the surface supports:

1. **Filesystem available** — `learning/<topic-slug>.md` in the working directory, or a path the learner nominates. Ask once, then reuse it.
2. **Memory tools available** — an area file for the topic.
3. **Neither** — end the session with the model rendered as a short markdown block and tell the learner to save it and paste it back next time.

Do not silently skip this because no filesystem is mounted. Option 3 always works.

## Learner model format

```markdown
# <Topic> — learner model
outcome: <the capability they wanted>
pace: <foundational | standard | fast>
last_session: <date>

## Mastered
- <step> — passed <check type>, <date>

## Shaky
- <step> — <the exact edge that wobbled>, <date>

## Not covered
- <module> — <why it was excluded>

## Parked
- <tangent> — raised <date>

## Due for review
- <step> — due <date>, interval <n> days
```

Keep it under 60 lines. Prune mastered items that have survived three reviews.

## Reading it at session start

Read before the first response. Then:

- Skip the pretest for anything under **Mastered**, unless it is overdue for review.
- Re-probe anything under **Shaky** — one probe, not a full pretest.
- Carry the pace tier forward as the starting default, subject to what the probes show.
- Offer the **Parked** items when the relevant module comes around.

If anything is **Due for review**, open the session with one delayed retrieval question on the oldest due item. That question is the entire turn. Grade it, adjust the interval, then proceed.

## Writing it at session close

Never end a session without writing it. Record:

- Each step taught, with whether it passed, and on which check type.
- For shaky items, the *specific* edge that wobbled — not "unclear on subnetting" but "confused broadcast address with gateway address".
- Modules excluded and why, so a future session does not re-litigate the plan.
- New review entries with their first due date.

## Review schedule

Expanding intervals, reset on failure:

| Review | Interval after previous success |
|---|---|
| 1 | 2 days |
| 2 | 7 days |
| 3 | 21 days |
| 4 | 60 days, then retire to Mastered |

On a failed review, drop back one level and re-teach the step through a different representation than the one used originally.

Two honest caveats. The expanding *shape* is convention rather than a settled finding — expanding and equal-interval schedules have traded wins across studies, and the factor that reliably carries long-term retention is that the first retrieval happens after a real delay instead of in the session that taught it. So the two-day gap before review 1 is the load-bearing part of this table and the rest is bookkeeping. And the numbers are a practical default, not a tuned schedule: if the learner reports the reviews feel too easy or too hard, stretch or compress them and record the change.

## Interleaving

Blocked practice — one idea, master it, move on — produces strong in-session performance and weak retention and transfer. Counter it in two places:

**Within the journey.** Every third teaching step, make the check draw on an *earlier* step as well as the current one. "Given what you worked out about routing two steps ago, what happens here?" This costs nothing and does most of the work.

**In the final challenge.** Build one problem that requires at least three modules, mixed rather than in the order taught. The learner should have to decide *which* idea applies, not just apply the one they were handed. A challenge that walks the modules in sequence is a review, not a transfer test.

Do not interleave during initial teaching of a step. Mixing before a first pass is confusion, not desirable difficulty.
