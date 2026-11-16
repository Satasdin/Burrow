# Chapter 6:  Conclusions, Recommendations and Future Works

## 6.1 Conclusions

Local language models can run privately on a person's own computer but do not know that person's material, and every model, local or cloud, starts each session without the decisions made with earlier ones. This project set out to give both kinds of model one shared memory, and built Burrow: a vault of the person's notes, documents and code with a Ledger of decisions tied to the files they rest on, served to any program through the Model Context Protocol, with a check of new work against those decisions and a desktop application, all running on the person's own Mac.

### 6.1.1 The State of the Field and Its Gaps (Objective i)

On the first objective, the review found that memory for language models is tied to one agent or product, that the gap between local and cloud models had not been measured with a memory kept on the person's computer, that decisions are kept without their reasons or out of the models' reach, that what is recorded is not checked against later change, and that memories models write are not screened. These five gaps defined what Burrow had to do.

### 6.1.2 The Design (Objective ii)

On the second objective, Burrow was designed as one vault with a Ledger, an engine that decides whether the vault is needed and fits what it shows to the model, an MCP server shared by every program, and a check that judges each change against the decisions it touches, specified as 28 requirements in Chapter 4.

### 6.1.3 The Software (Objective iii)

On the third objective, the design was built as working software on one consumer laptop, every one of its 24 system test cases passed on the final build, the defects found in real use were corrected and retested, and three volunteers installed and used it on their own Macs.

### 6.1.4 The Knowledge Gap (Objective iv)

On the fourth objective, Burrow narrowed most of the knowledge gap on the laptop: with it, Gemma 4 12B answered 102 of 120 questions on material no model had seen, against 9 alone and 75 with a vector database, closing 93% of the gap to a cloud model given the same vault, while leaving the vault out of every reasoning problem. Much of its edge over plain retrieval came from showing the model more of the vault, and on the smaller Qwen3.5 4B it did no better than plain retrieval.

### 6.1.5 Decisions and Carrying Work On (Objective v)

On the fifth objective, models that shared the vault kept decisions and carried work on once the reasons were kept with the decisions: Claude Code kept an earlier decision in 9 of 9 sessions, against 12 of 15 before, and a different program continued the right step in 3 of 3 runs, against none before. Memory, however, did not make every model obey: Gemma 4 12B received a decision with its reason in every run and still broke it in some, which only the check, holding the change and naming the decision, could address.

### 6.1.6 Contribution and Boundaries

The contribution of this project is a shared memory that holds a person's material and the decisions made with their models together with the reasons for them, kept on their own computer, readable by any local or cloud model through one protocol, and paired with a check that does not depend on the model choosing to keep what it read. These conclusions hold within the conditions tested: one Apple silicon laptop, chiefly two local models and one cloud model, mostly one fixture project with one business decision, between 3 and 30 runs per condition, and a first usability test by three volunteers.

## 6.2 Recommendations

The recommendations below follow from the results and limitations of Chapter 5 and are listed by priority. The first two are essential safeguards for anyone who relies on AI tools to keep decisions; the rest are improvements.

### 6.2.1 Essential Safeguards

First, developers of AI coding tools and of memory systems for them should record every decision together with its reason and the options that were rejected, and should refuse a decision without a reason. Without the reason, Claude Code kept the letter of the payment decision and defeated its purpose in 3 of 15 sessions; with it, it kept the decision in 9 of 9.

Second, teams and individuals who let AI tools change their code should run a check of each change against the recorded decisions before the work is reported as done, inside the AI program and in the version control hook, rather than rely on the model having read the decisions. A small local model broke a decision it had read with its reason, and only the check held that change.

### 6.2.2 Improvements

Third, developers of AI programs that connect to MCP servers should pass each server's instructions on to their model. Two of the programs tested passed none of Burrow's connection instructions on, and the decisions reached their models only once Burrow also sent them with the first tool result.

Fourth, people who adopt Burrow should use it within the conditions that were evaluated: a local model of about 12 billion parameters for answers from their own material, with the check switched on whenever an AI tool changes code. For a model as small as Qwen3.5 4B, plain retrieval answered as well, so the engine should not be expected to add accuracy there.

Finally, as an optional improvement, tools that flag text written to steer an AI should repeat the flag at the end of the work, when the model reports to the person. Repeating the flag raised the runs in which Claude Code told the person about planted text from 1 of 3 to 5 of 6.

## 6.3 Future Works

Three directions arise from the limitations of this study, in order of value.

### 6.3.1 A Comparison with a Hand-Kept Decisions File

The most valuable is a controlled comparison with a file of decisions kept by hand in the repository, the simplest alternative a developer would try. The factor that would change is the memory given to the same tools on the same tasks: Burrow against a plain decisions file. It needs only the existing fixture and tasks, with at least 20 runs for each condition, and would be evaluated by the hidden decision tests and an exact paired test, so that it shows what Burrow adds beyond such a file.

### 6.3.2 More Projects and Kinds of Decision

The second is a broader evaluation across several projects and kinds of decision, since most results here rest on one fixture project with one business decision and a few runs per condition. It needs fixtures from several domains, each with decisions of different kinds and hidden tests, and would be evaluated by the same decision tests with enough runs to give each result a confidence interval, showing whether the effect of keeping the reason holds beyond payments.

### 6.3.3 A Study with Real Users and Teams

The third is a study with real users and small teams working in their own projects over several weeks, since only three volunteers tried Burrow, once each and with their AI program's help. It needs volunteers with Macs, the released build and a short task protocol, and would be evaluated by task completion, the problems met and the time spent on the Ledger and the check, showing whether the approach helps people in practice and what it costs them in attention. Cryptographic signing of team decisions and versions for other operating systems are extensions of the software rather than open research questions, and are left to later development.

# Author Oversight and Use of AI-Assisted Tools

Claude Code, a coding assistant from Anthropic running Claude Opus 5.5, wrote most of the code, tests and evaluation scripts at the author's direction and from the author's design, ran the evaluations, reviewed each change for security, drew the figures and drafted this report from the saved results and cited sources. Kimi K3 from Moonshot AI was used in an early increment as a model under test and as a judge of answers. Every output was checked against the automated tests, the saved transcripts and the cited sources, and the author chose the problem, the design and the experiments, made the final decisions and takes full responsibility for the submitted work. Appendix C records each material use of AI by period, with what was kept and how it was checked, and Appendix D gives the similarity report of the approved proposal.
