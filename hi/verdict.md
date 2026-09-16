---
hi: 1
families: [VERDICT]
---

# Reading the verdict

## Intent

This is the whole point of augur: point it at a change and get back a judgement you can act on in the next five seconds. The answer should be one of three words, backed by a number, with the files ordered so the first thing you read is the thing you should look at, and every file able to say in a sentence why it stood out. Asking a question should never itself be a failure, and an answer you cannot reproduce tomorrow is worthless, so the same change must always come back the same way. When augur cannot do what was asked, it should say what went wrong in the words of whatever refused, not hand back a number.

## Criteria

- **VERDICT-1**  I point augur at a change and get one of three answers back: proceed, review, or block.
  - **VERDICT-1.a**  The answer carries a risk score out of 100, so I can see how close to the line it landed.
  - **VERDICT-1.b**  The same change assessed twice gives the same answer, on any machine and at any hour.
  - **VERDICT-1.c**  When the verdict is not proceed, the report says in plain words what should happen next.
- **VERDICT-2**  With no flags at all I get a read on whatever I have changed right now.
  - **VERDICT-2.a**  A file I created but never added to git still counts as a change.
  - **VERDICT-2.b**  I can ask about a branch's worth of work by naming a range like main..HEAD.
  - **VERDICT-2.c**  I can ask about only what is staged, so a hook can look before the commit lands.
  - **VERDICT-2.d**  Asking for two scopes at once is refused rather than one being quietly preferred.
  - **VERDICT-2.e**  I can point augur at a repository elsewhere on disk instead of the one I am standing in.
- **VERDICT-3**  The changed files are listed riskiest first, so the first thing I read is the thing to look at.
  - **VERDICT-3.a**  Each file carries its own risk score, not only the overall one.
  - **VERDICT-3.b**  Each file carries its own verdict, so I can see which single file is the problem.
  - **VERDICT-3.c**  Each file names the reason it scored that way, in a sentence I can act on.
  - **VERDICT-3.d**  I can ask to see every reason that contributed, not only the loudest one.
- **VERDICT-4**  One alarming file drags the whole change up to block even when everything around it is calm.
- **VERDICT-5**  A change spread across many files never reads as safe just because each piece of it is small.
- **VERDICT-6**  A change with nothing in it comes back as a clean zero rather than an error.
- **VERDICT-7**  Asking for a verdict never fails my command; only a gate does that.
- **VERDICT-8**  The report is colored by meaning when I am watching it in a terminal.
  - **VERDICT-8.a**  Output that is piped or redirected comes out plain, so nothing has to strip escape codes.
  - **VERDICT-8.b**  I can force color on or off myself, whatever augur would have guessed.
  - **VERDICT-8.c**  An environment that has asked for no color anywhere is obeyed without my passing a flag.
- **VERDICT-9**  When git refuses the range I gave, I see what git said rather than a bare exit code.
- **VERDICT-10**  I can tell at a glance that the confidence figure in the report is the flip side of risk, not a second opinion.
