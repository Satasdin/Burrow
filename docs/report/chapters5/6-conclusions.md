# Chapter 6:  Conclusions, Recommendations and Future Works

## 6.1 Conclusions

This project set out to design, develop and evaluate a private memory engine that keeps the decisions made during AI-assisted work, with their reasons, and hands them to the local and cloud AI tools that a person uses. The review of the literature showed that such decisions are lost because they are recorded by people after the fact, if at all, and because each AI tool starts from what its own program supplies, and that no existing memory both records decisions as they are made and checks new work against them. Burrow was built to fill that gap as a vault, a Ledger of decisions tied to the files they rest on, an MCP server with hooks and plugins, a check of new work, and a desktop application, all running on the person's own computer.

The evaluation showed that Burrow met these objectives. A local model with Burrow answered 102 of 120 questions on private material, against 9 alone and 75 with a vector database, and a decision worded unlike the task still reached the tool in 19 of 20 cases. Once its reason was kept with it, Claude Code kept to an earlier decision in every run, a different program carried earlier work on in every run instead of none, and every change that broke a decision was held before the work was reported as done. A small local model sometimes broke a decision it had read, which showed that memory delivers decisions reliably but that a check at the end is needed to make every tool keep them.

## 6.2 Recommendations

Based on these findings, several recommendations can be made for people and developers who adopt this approach. First, AI tools should be made to record each decision together with its reason and the options that were rejected, not the decision alone. The evaluation showed that a decision without its reason could be kept in letter and defeated in purpose, while the same decision with its reason was kept in every run.

Second, developers of AI programs should run a check of the work against recorded decisions before the work is reported as done, and should let that check hold the program until the person or the model has dealt with it. Memory alone did not stop a small model from breaking a decision, and whether a held change was then undone depended on the program around the model.

Finally, developers of AI programs should pass the instructions of the memory servers they connect to on to their model. Two of the programs tested passed none of Burrow's connection instructions to their model, so the decisions reached it only after Burrow began sending them with the first tool result.

## 6.3 Future Works

Several directions remain open for extending this work. The most important is a comparison with a file of decisions kept by hand in the repository, which is the simplest alternative a developer would try. Running the same tasks with such a file in place of Burrow, with enough runs to tell a difference, would show what Burrow adds beyond it.

Another direction is to repeat the evaluation on several projects and kinds of decision, with more runs for each condition, since most results came from one fixture project and between 3 and 30 runs. A study with real users and small teams working in their own projects would show whether the Ledger and the check help them in practice and what they cost in attention.

Finally, Burrow could be extended beyond its present limits. Signing each shared decision cryptographically would make team use safer, and building Burrow for other operating systems would let the approach reach people who do not use a Mac. These extensions would move Burrow from a working study system towards a memory that larger teams could rely on.
