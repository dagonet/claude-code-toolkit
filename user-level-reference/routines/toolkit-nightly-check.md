# Routine: toolkit-nightly-check

**What this is.** The prompt body below is a *cloud routine* — an Anthropic-managed (or
self-hosted) Claude Code session that runs on a schedule over a **clone** of the repo.
It never sees this machine: no `~/.claude`, no uncommitted work. Everything it needs
must be committed to the repo it clones.

**Create it** with `/schedule` from a `claude-code-toolkit` checkout (Claude Code
>= 2.1.225), or at <https://claude.ai/code/routines>. Configure:

- **Repository:** `dagonet/claude-code-toolkit` — the only repo it needs.
- **Connectors:** GitHub, with issue read + write on that repo.
- **Triggers:** scheduled daily at a local-time hour you are asleep; optionally also a
  GitHub `push` trigger on `main` for immediate post-merge drift detection.
- **Permissions:** nothing to grant — a routine never prompts. That is why the prompt
  below has to be explicit about what to do and what success looks like.

**Prompt body — paste verbatim from here down:**

---

You are running unattended in a clone of `dagonet/claude-code-toolkit`. No one will
answer a question, so do not ask one: finish the checks and either open an issue or
produce no output at all.

Work from the repository root on the default branch. Run these four checks and record,
for each, PASS or FAIL plus the verbatim tail of its real output:

1. `bash scripts/verify-template-consistency.sh` — FAIL if it exits non-zero or prints
   any line starting with `FAIL`. Record the number of `PASS` lines.
2. `bash scripts/test-hooks.sh` — FAIL if it exits non-zero. Record the
   `N passed, M failed` line.
3. Stale references to artifacts removed in v2.0/v2.1. Run
   `grep -rn -E 'tier-before-coder|block-bash-vcs|require-teammate-report|effortLevel|Plan Challenge Protocol' --include='*.md' --include='*.sh' --include='*.json' .`
   and treat a hit as FAIL **unless** the file is `CHANGELOG.md`, is
   `user-level-reference/routines/toolkit-nightly-check.md` (this prompt's own copy of
   the pattern), or sits under `docs/plans/` or `.superpowers/` — those are history and
   may name dead things.
4. Version drift. Compare line 1 of `VERSION` with the newest release tag. FAIL if
   `VERSION` is behind it. A `VERSION` *ahead* of the tags is normal between a release
   commit and its tag: report that as PASS with a one-line note.

**If every check passed, do nothing at all.** Write no file, open no issue, leave no
comment. Silence is this routine's success signal — an issue appearing means something
needs a human.

**If any check failed**, search open issues for one whose title starts with
`nightly-check: `. If one exists, retitle it `nightly-check: <today, YYYY-MM-DD>` and
replace its body; otherwise create a new issue with that title. Exactly one such issue
may be open at a time — never open a second. Body: one section per failed check, each
with the command, the verbatim tail of its output, and one sentence naming the most
likely cause. Do not attempt a fix, do not push a branch, and do not close the issue
yourself.
