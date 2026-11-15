# Chapter 6:  Conclusions, Recommendations and Future Works

## 6.1 Introduction

This chapter closes the chain from the problem of Chapter 1 to the evidence of Chapter 5. Section 6.2 states what the study established for each specific objective, Section 6.3 recommends what should be done on the strength of it, and Section 6.4 names the work that remains open. No new result or source is introduced; each statement rests on a section of Chapter 5.

## 6.2 Conclusions

The study began from a problem that grows as people work with more AI tools: a decision reached with one tool, and the reason for it, does not reach the next tool, which then brings back what was already turned down. Its purpose was to build a private memory on the person's own computer that keeps such decisions and hands them to every tool, and to measure whether it works.

**Objectives i to iii.** The review established that decisions and their reasons vaporise when they are recorded by people after the fact, that today's AI memory keeps facts or instructions delivered always or by similarity, and that no reviewed system has AI tools record decisions with their reasons, hand them to every later tool, know when they are stale, and check new work against them (Section 5.9.1). These objectives were met.

**Objective iv.** Burrow was designed and built as a vault, a Ledger of decisions tied to files, an MCP server with hooks and plugins, a check of new work, and a desktop application, all on one Mac. Every requirement was verified by the 24 test cases, all 553 automated tests passed, and six real AI programs used it without changes (Section 5.9.2). The objective was met.

**Objective v.** With Burrow, a local model answered 102 of 120 questions on private material against 9 alone and 75 with a vector database; a decision worded unlike the request reached the tool in 19 of 20 tasks; Claude Code kept to an earlier decision in every run once its reason was kept; a different program carried on the right step in 3 of 3 runs instead of none; and every change that broke a decision was judged so and held (Section 5.9.3). The objective was met, with a clear limit: Burrow delivers a decision reliably, but a small model may still break it, and only the check, together with a program that lets it act, turns delivery into keeping.

The contribution of the study is a working answer to the problem it set. Decisions made during AI work can be kept by the tools themselves, with their reasons, on the person's own computer, and handed to every later tool; the reason is what makes a strong model keep a decision; and a check at the moment work is finished catches what a weaker model lets through.

## 6.3 Recommendations

The recommendations below follow from the results and limitations of Chapter 5. The first two are essential for anyone who adopts the approach; the others are improvements.

i) **People who work with several AI tools should have the tools record decisions with their reasons, not decisions alone.** Without the reason a strong model broke a decision in 3 of 15 runs by adding a safeguard that defeated it; with the reason it kept to it in every run (Section 5.5.4).

ii) **Developers of AI programs should run a check of the work against recorded decisions before the work is reported done, and let it hold the program.** Memory alone did not stop a small model from breaking a decision it had read, and the same check undid the change in one program and not in another depending on whether the program acted on it (Section 5.5.6).

iii) **Developers of AI programs should pass a memory server's instructions to their model.** Two programs passed none of Burrow's connection instructions to their model, and decisions reached it only once they were sent with the first tool result (Section 5.4.4).

iv) **Researchers evaluating memory for AI tools should measure delivery and obedience separately.** A decision that reached the model and a decision the model kept gave different answers for the same memory (Section 5.5.4).

v) **The maintainer of Burrow should freeze one build and rerun the evaluations on it before further changes, so that every result in this report rests on the same code (Section 5.9.4).**

## 6.4 Future Works

The following directions arise from the limitations of Section 5.9.4. Each extends the research rather than completing promised work.

i) **A comparison with a context file kept by hand.** The simplest alternative a developer would try is a file of decisions in the repository that every coding tool reads. Running the same tasks with that file in place of Burrow, with enough runs per arm to tell a difference, would show what Burrow adds beyond it.

ii) **More projects, decisions and runs.** Most results came from one fixture project and one decision, with 3 to 30 runs per condition. Repeating them on several projects and kinds of decision, with more runs, would show how far the results generalise and how much they vary.

iii) **A study with real users and teams.** No person other than the developer used Burrow. A study of people and small teams using it in their own work would show whether the Ledger and the check help them, and what they cost in attention.

iv) **Signed team decisions and other platforms.** Team members' names are not cryptographically signed, and Burrow runs only on a Mac. Signing each shared decision, and building for other operating systems, would let the approach serve larger teams.
