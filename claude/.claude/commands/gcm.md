---
description: Create a git commit
---

Create a clear and concise git commit with the current changes.

The subject should be the "what", max 50 characters.

Always include a description of the "why", wrapping at 72 characters. The
description should be only 1 paragraph, 1-3 sentences.

Do not write bullet points.

Do not add a "Claude Code" attribution footer.

Use `git log -n 10` before and look at the last commits to copy the same style.
Ignore dependabot commits.

Use Tim Pope's style:

```
Commit message style guide for Git

The first line of a commit message serves as a summary.  When displayed
on the web, it's often styled as a heading, and in emails, it's
typically used as the subject.  As such, you should capitalize it and
omit any trailing punctuation.  Aim for about 50 characters, give or
take, otherwise it may be painfully truncated in some contexts.  Write
it, along with the rest of your message, in the imperative tense: "Fix
bug" and not "Fixed bug" or "Fixes bug".  Consistent wording makes it
easier to mentally process a list of commits.

Oftentimes a subject by itself is sufficient.  When it's not, add a
blank line (this is important) followed by one or more paragraphs hard
wrapped to 72 characters.  Git is strongly opinionated that the author
is responsible for line breaks; if you omit them, command line tooling
will show it as one extremely long unwrapped line.  Fortunately, most
text editors are capable of automating this.
```
