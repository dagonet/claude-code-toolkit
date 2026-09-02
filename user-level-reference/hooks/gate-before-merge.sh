#!/usr/bin/env bash
# PreToolUse hook: block PR merge/auto-merge without a fresh gate artifact
# Matcher: Bash|PowerShell|mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge
#
# v2.0: `gh pr merge`, a `git merge` while on main/master, and a push that
# targets main/master (fast-forward merge by push) are gated too, because the
# native git/gh CLI is allowed again. The MCP branch is unchanged -- those are
# GitHub tools, not the retired git-tools server. Escape hatch:
# <cwd>/.claude/git-guard-off.
#
# v2.4.0 (A6): a merge initiated while the checkout is on a PROTECTED branch is
# refused outright, before the artifact is even read — on that topology the
# merge lands the other side's content, so no comparison against this
# checkout's HEAD can say anything about it. See the block above that check.
#
# ---------------------------------------------------------------------------
# v3.0.1 — WHAT IS AND IS NOT GATED ON A PROTECTED BRANCH. Read this before
# reaching for the kill switch; it is the contract, and it lives HERE because
# this file syncs to consumers while docs/verification.md does not.
#
#   git merge --abort / --continue / --quit   ALLOWED, always. They land nothing
#       new, and a conflicted merge on a protected branch is exactly the state
#       this gate exists to worry about — you must be able to get out of it.
#   git merge --ff-only <upstream>            ALLOWED when it is a pure CATCH-UP:
#       the ref named is this branch's own configured upstream and HEAD is
#       already an ancestor of it. Catching up lands nothing the upstream has
#       not already accepted. --no-ff and --squash are gated even then, because
#       both produce a result the upstream does not have.
#   git merge <anything else>                 GATED.
#   git pull --ff-only   (no remote, no refspec)   ALLOWED — THE SAFE CATCH-UP
#       FORM, and the one to reach for. Refspec-free means the target is the
#       configured upstream by construction; --ff-only means git itself refuses
#       if the result would not be a fast-forward.
#   git pull <any other form>                 GATED, including a bare `git pull`
#       on a branch that would fast-forward cleanly. That is deliberate: the
#       remedy is one word, and it is the safer command.
#   gh pr merge / the GitHub merge tools      GATED from a protected branch.
#
# THE STATED LIMIT: every decision above is taken BEFORE any fetch, so the
# CONTENT of a remote ref is unknown to this hook — it can only read the form of
# the command and refs that already exist locally. That is why `pull` is gated
# by form rather than by content: a remote-tracking ref that is merely STALE
# answers "adds nothing" confidently and wrongly about an object that is not the
# one the pull will land.
# ---------------------------------------------------------------------------
#
# Requires .gate/last-pass.json (written by hooks/run-gate.sh) at the repo
# toplevel of the merging session's cwd — worktree-aware, since developer
# agents self-merge from their worktrees. Blocks (exit 2) unless:
#   - the artifact exists,
#   - its "sha" equals the current HEAD of that checkout OR its "tree" equals
#     that checkout's HEAD^{tree} — as of v2.1.5 "tree" is the WORKING tree at
#     gate time, so a commit of exactly what was gated (chained
#     `git add … && git commit`, or `git commit -a`) matches by tree even
#     though the artifact's sha is the parent commit's, and
#   - the artifact file is younger than 60 minutes (mtime).
#
# CONSEQUENCE, by construction, on a repo that commits straight to trunk: the
# artifact is STALE most of the time. Any commit moves HEAD and changes the
# tree — a docs-only commit included, because docs are tracked content — so both
# keys miss. That is correct. The artifact blesses one specific tree, that tree
# genuinely changed, and the gate cannot know which changes are harmless. The
# tree key was added in v2.1.5 to fix a different problem (the artifact's `sha`
# being the PARENT commit when an agent chains `git add … && git commit`), not
# to make an artifact outlive later commits. It costs nothing in practice: this
# gate only fires on merge-shaped commands, so staleness is invisible until an
# actual merge — at which point re-running the gate is exactly the requirement.
# Do NOT add a path-filtered or docs-excluding tree key to "fix" it: deciding
# which file changes are safe to skip is the judgement a gate must not make.
#
# No-op (exit 0) when PROJECT_CONTEXT.md has no Gate command or the field is
# still a {{...}} placeholder — same graceful degradation as pre-commit-test.sh.
#
# v2.2.0: "main/master" above means the protected set, which an optional
# PROJECT_CONTEXT.md line configures:
#
#   - **Protected branches**: develop release
#
# Default (field absent) is `main master`; `none` protects nothing — a
# `gh pr merge` is still gated, since that is a merge whatever the branch is.
# The payload is parsed through hooks/lib/json.sh (node, python3 or jq); with
# none of the three on PATH this gate fails CLOSED.

# Fail CLOSED when the sourced lib is missing: without it every gc_* helper is
# undefined, GC_TOOL stays empty, and this gate would exit 0 on every merge.
lib="$(dirname "$0")/lib/git-cmd.sh"
[ -f "$lib" ] || { echo "BLOCKED: $lib missing — run /sync-template step 6b (hooks/lib/git-cmd.sh)" >&2; exit 2; }
. "$lib"

gc_read_stdin
gc_guard_off && exit 0

CWD="$GC_CWD"

# What the block message reports about. Defaults describe the MCP merge tools,
# which carry no command string at all; the Bash branch overrides them.
A6_KIND=mcp
A6_SEG=""
A6_ARGS=""

# --- v3.0.1 (A6 fix) argument parsing, deliberately LOCAL to this hook -------
#
# Not added to hooks/lib/git-cmd.sh: that library is covered by the three-parser
# matrix (~90 minutes), nothing else needs these shapes, and keeping them here
# means the A6 fix costs one suite run rather than three.

# a6_args <segment> <subcommand> -- everything after `<subcommand>` in a segment.
a6_args() {
  printf '%s\n' "$1" | sed -n "s/.*[[:space:]]$2\\([[:space:]]\\|\$\\)/\\1/p" | head -1
}

# a6_nonflag <args> -- the tokens that are not flags (a target ref, a remote).
a6_nonflag() {
  printf '%s\n' "$1" | tr ' \t' '\n\n' | grep -E '^[^-][^[:space:]]*$'
}

# a6_nonflag_count <args>
a6_nonflag_count() {
  a6_nonflag "$1" | grep -c . || true
}

# a6_has_flag <args> <alternation> -- a long flag from the alternation is present.
a6_has_flag() {
  printf '%s\n' "$1" | grep -qE "(^|[[:space:]])--($2)([[:space:]]|=|\$)"
}

# a6_merge_exempt <merge-args> -- `git merge --abort|--continue|--quit`.
#
# HIGHEST-PRIORITY ARM OF THE v3.0.1 FIX, and it is checked before every other
# question. All three were measured exiting 2 on a protected branch, which left
# a consumer in a CONFLICTED MERGE ON `main` — precisely the state this gate
# exists to worry about — with no way out except `.claude/git-guard-off`. A
# guard whose only exit is its own kill switch teaches the kill switch.
# None of the three lands anything new: abort restores the pre-merge state,
# continue completes work already begun (and already gated when it began), quit
# leaves the index alone.
#
# The exemption requires NO non-flag token to be present. gc_segments strips
# quotes, so `git merge -m "retry after --abort" feature/x` otherwise hands us a
# bare `--abort` token and buys a real merge the exemption. The three real forms
# take no operand, so the requirement costs nothing and closes that door.
a6_merge_exempt() {
  [ "$(a6_nonflag_count "$1")" -eq 0 ] || return 1
  a6_has_flag "$1" 'abort|continue|quit'
}

# a6_upstream_facts <repo> -- populate A6_UP / A6_UPSHA / A6_HEADSHA for both
# the discriminator and the block message. Local reads only, no network.
a6_upstream_facts() {
  A6_UP=$(git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
  A6_UPSHA=""
  [ -n "$A6_UP" ] && A6_UPSHA=$(git -C "$1" rev-parse --verify --quiet "$A6_UP^{commit}" 2>/dev/null)
  A6_HEADSHA=$(git -C "$1" rev-parse --verify --quiet HEAD 2>/dev/null)
}

# a6_merge_catchup <repo> <merge-args> -- true when the merge merely makes this
# protected branch match ITS OWN CONFIGURED UPSTREAM.
#
# THE RULE IS PROVENANCE, NOT ANCESTRY, and the difference is not academic. The
# rule this replaced — "allow when the target is already an ancestor of HEAD" —
# blocks the single most common protected-branch operation there is: after a PR
# merge, local `main` is one commit BEHIND `origin/main`, so the target is not
# an ancestor of HEAD and a routine catch-up would demand a multi-minute gate
# run for content that already passed the PR gate, CI and this gate. That is the
# highest-frequency false positive available, and it lands when the consumer is
# most task-focused.
#
# "Foreign to local HEAD" and "not yet accepted upstream" are different facts.
# A6 only cares about the second: catching up to your own upstream lands nothing
# the upstream has not already accepted.
#
# --no-ff and --squash are refused even when the target IS the upstream: both
# produce a result the upstream does not have, which is exactly what the rule
# excludes. Ancestry is measured directly rather than by trusting --ff-only,
# because the flag states an intent while merge-base states the fact.
a6_merge_catchup() {
  a6cu_repo=$1; a6cu_args=$2
  A6_TARGET=""; A6_TARGETSHA=""; A6_ANCESTOR_RC=""
  a6_upstream_facts "$a6cu_repo"
  a6_has_flag "$a6cu_args" 'no-ff|squash' && return 1
  [ "$(a6_nonflag_count "$a6cu_args")" -eq 1 ] || return 1
  A6_TARGET=$(a6_nonflag "$a6cu_args" | head -1)
  [ -n "$A6_UPSHA" ] || return 1
  A6_TARGETSHA=$(git -C "$a6cu_repo" rev-parse --verify --quiet "$A6_TARGET^{commit}" 2>/dev/null)
  [ -n "$A6_TARGETSHA" ] || return 1
  [ "$A6_TARGETSHA" = "$A6_UPSHA" ] || return 1
  git -C "$a6cu_repo" merge-base --is-ancestor HEAD "$A6_UPSHA" 2>/dev/null
  A6_ANCESTOR_RC=$?
  # BRANCH ON THE EXACT CODE. `--is-ancestor` returns 1 for "not an ancestor"
  # and 128 for "could not resolve"; a caller testing truthiness collapses the
  # two, and "could not resolve" would read as a definite answer.
  case "$A6_ANCESTOR_RC" in
    0) return 0 ;;   # HEAD is contained in the upstream -> pure fast-forward to it
    1) return 1 ;;   # diverged -> the result is a merge commit the upstream lacks
    *) return 1 ;;   # 128 and anything else: not provable catch-up, so gate
  esac
}

# v2.2.6 round 2 -- THE 14th FAIL-OPEN, third instance. Checked BEFORE the tool
# case below, because that case's `*)` arm is exactly the door an unreadable
# tool_name walks through. See gc_cmd_unreadable in hooks/lib/git-cmd.sh.
if gc_cmd_unreadable; then
  echo "BLOCKED: gate-before-merge: the payload carries a command this gate could not read, so it cannot rule out a merge -- refusing. Re-run the command. (If it repeats: create '.claude/git-guard-off' under this cwd, make the one fix, then delete it.)" >&2
  exit 2
fi

# Branch on the TOOL, never on the parsed string. This hook is registered on
# Bash|PowerShell, so if node is missing or the JSON does not parse, GC_CMD is
# empty -- and treating that as "not a Bash call" would fall through to the
# artifact check and block every Bash call in the session. A Bash payload with
# NO COMMAND KEY is a Bash payload with no merge in it; only the GitHub merge
# tools are gated unconditionally.
#
# v2.2.6 round 2 narrows what "we cannot read it" means here: a payload that
# HAS a `command` key we could not read no longer reaches this case at all --
# it was refused above. What still falls open below is the genuinely absent
# key and the genuinely unknown tool, which are not cannot-determine states.
case "$GC_TOOL" in
  Bash|PowerShell) ;;   # gate only merge-shaped commands (scanned below)
  mcp__*)          ;;   # the GitHub merge tools: always gated
  *) exit 0 ;;          # unknown tool, or a payload with no command key at all
esac

if [ "$GC_TOOL" = "Bash" ] || [ "$GC_TOOL" = "PowerShell" ]; then
  is_merge=0
  base="$CWD"
  segments=$(gc_segments)

  while IFS= read -r seg; do
    [ -n "$seg" ] || continue

    cdt=$(gc_cd_target "$seg")
    if [ -n "$cdt" ]; then
      base=$(gc_resolve "$base" "$cdt")
      continue
    fi

    # 1. gh pr merge (any flags)
    if printf '%s\n' "$seg" | grep -qE '\bgh[[:space:]]+pr[[:space:]]+merge\b'; then
      is_merge=1
      A6_KIND=ghpr
      A6_SEG=$seg
      CWD=$(gc_repo_for "$seg" "$base")
      break
    fi

    # 2. git merge while the checkout is on a protected branch
    if gc_matches_subcommand "$seg" "merge"; then
      repo=$(gc_repo_for "$seg" "$base")
      margs=$(a6_args "$seg" "merge")
      # v3.0.1 item 1: the three merge-state subcommands are exempt on the
      # SUBCOMMAND PARSE, before the branch is even looked at. See
      # a6_merge_exempt.
      if a6_merge_exempt "$margs"; then
        continue
      fi
      if gc_on_main "$repo"; then
        # v3.0.1 item 2: a pure catch-up to this branch's own upstream lands
        # nothing the upstream has not already accepted. See a6_merge_catchup.
        if a6_merge_catchup "$repo" "$margs"; then
          continue
        fi
        is_merge=1
        A6_KIND=merge
        A6_SEG=$seg
        A6_ARGS=$margs
        CWD="$repo"
        break
      fi
    fi

    # 2b. v3.0.1 item 3: `git pull` while the checkout is on a protected branch.
    #
    # NO DISCRIMINATOR HERE, and that is a measured decision rather than a
    # shortcut. A pull FETCHES FIRST, so anything this hook resolves before the
    # command runs is an answer about a different object:
    #   - a CURRENT remote-tracking ref answers correctly (measured rc=0)
    #   - an ABSENT one is at least distinguishable (rc=128)
    #   - a STALE one answers CONFIDENTLY AND WRONGLY: `--is-ancestor` returns 0
    #     for the stale tip, the check reads "adds nothing", and the pull then
    #     lands every commit gained since. Resolve-after-fetch is too late, and
    #     refuse-when-unresolvable never fires because the ref does resolve.
    #   - `ls-remote` is ~1.4 s per PreToolUse call and FAILS OFFLINE, which for
    #     a fail-closed gate means "no pull on a protected branch without a
    #     network".
    #
    # So: gate every pull except the one form that cannot land foreign content.
    # Refspec-free means the target is the configured upstream by construction,
    # and --ff-only means git itself refuses if it is not a fast-forward. Both
    # are readable BEFORE the fetch, which is the constraint that defeated
    # everything else.
    #
    # NAMED RESIDUAL FALSE POSITIVE: a bare `git pull` on a cleanly
    # fast-forwardable protected branch is gated. That is deliberate — the
    # remedy is "use git pull --ff-only", a one-word fix and the safer command,
    # not a multi-minute gate run. Gating only refspec-bearing pulls would leave
    # bare `git pull` with divergent local history creating a real merge commit
    # on the protected branch, which is the topology A6 exists for.
    if gc_matches_subcommand "$seg" "pull"; then
      repo=$(gc_repo_for "$seg" "$base")
      pargs=$(a6_args "$seg" "pull")
      if gc_on_main "$repo" && { [ "$(a6_nonflag_count "$pargs")" -ne 0 ] || ! a6_has_flag "$pargs" 'ff-only'; }; then
        is_merge=1
        A6_KIND=pull
        A6_SEG=$seg
        A6_ARGS=$pargs
        CWD="$repo"
        break
      fi
    fi

    # 3. a push that targets a protected branch -- fast-forward merge by push
    if gc_matches_subcommand "$seg" "push"; then
      repo=$(gc_repo_for "$seg" "$base")
      args=$(gc_push_args "$seg")
      if gc_targets_main_ref "$args" "$repo"; then
        is_merge=1
        A6_KIND=push
        A6_SEG=$seg
        A6_ARGS=$args
        CWD="$repo"
        break
      fi
      if ! gc_has_refspec "$args" && ! gc_push_skips_branch_check "$args" && gc_on_main "$repo"; then
        is_merge=1
        A6_KIND=push
        A6_SEG=$seg
        A6_ARGS=$args
        CWD="$repo"
        break
      fi
    fi
  done <<GC_SEGMENTS
$segments
GC_SEGMENTS

  [ "$is_merge" = "1" ] || exit 0
fi

REPO_TOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_TOP" ]; then
  # Not a git checkout (nothing to gate against) — allow.
  exit 0
fi

# Read Gate command from PROJECT_CONTEXT.md through GC_KEY_PRE (see the header
# note on that constant in hooks/lib/git-cmd.sh: a leading UTF-8 BOM otherwise
# hides a key that sits on line 1).
# Tolerates: leading "- " / "* " list
# markers, the "**Gate Command**:" label style (java/python variants), and
# surrounding backticks — several variants write commands as `cmd`.
GATE_CMD=$(grep -E "${GC_KEY_PRE}\*\*Gate( Command)?\*\*:" "$REPO_TOP/PROJECT_CONTEXT.md" 2>/dev/null | sed 's/.*\*\*Gate\( Command\)\?\*\*:[[:space:]]*//;s/[[:space:]]*$//;s/^`//;s/`$//' | head -1)

# No-op: no PROJECT_CONTEXT.md or no Gate command configured
if [ -z "$GATE_CMD" ]; then
  exit 0
fi

# No-op: placeholder not yet filled in
case "$GATE_CMD" in
  *\{\{*\}\}*) exit 0 ;;
esac

# v2.4.0 (A6, found live merging PR #75) -- THE ARTIFACT CHECK BELOW COMPARES
# THE ARTIFACT TO **HEAD**, AND HEAD IS THE MERGE CONTENT ONLY ON SOME
# TOPOLOGIES. A controller sitting on `main` merges the PR BRANCH's tip, not
# HEAD; so "re-run the gate on the current head" gates content that is already
# merged, writes a green artifact, and then permits a merge of entirely
# different content -- a correct guard whose own remediation manufactures the
# false receipt. A flow of branch -> commit -> gate -> push -> PR -> merge has
# the controller ON the branch, where `artifact.sha == branch tip == merged
# content` and the same check is sound. Same hook, opposite validity.
#
# The split is purely local -- no API, no network, and both helpers are already
# in this hook: if the merge is initiated while HEAD is on a PROTECTED branch,
# the thing being merged is BY CONSTRUCTION not HEAD, so the comparison below
# verifies nothing. Say so and refuse; on a feature branch, fall through to the
# comparison, which is meaningful there.
#
# DELIBERATELY NOT UNCONDITIONALLY FAIL-CLOSED. Target resolvability varies by
# path: `git merge <ref>` resolves locally, the MCP merge tools carry
# pullNumber/owner/repo (identified, but needing an API call), and a bare
# `gh pr merge` names no target at all. Refusing on every unresolvable path
# hard-blocks every PR merge for anyone offline -- the "unconditional
# fail-closed blocks everything" hazard from the GC_CMD round. The
# protected-branch detector is what makes cannot-determine-must-refuse
# affordable here: it refuses exactly the case where the evidence is known to
# be irrelevant, and stays out of the way otherwise.
if gc_on_main "$CWD"; then
  # v3.0.1 item 5: DIAGNOSIS AND FIX, NOT ARGUMENT. The rationale for the
  # refusal lives in the comment block above, where the next editor will read
  # it; at block time nobody reads an argument. What a blocked consumer needs is
  # the configuration they are subject to, the segment that fired, the inputs
  # the decision used, the limit of what the hook can see, and — before the
  # escape hatch, never after it — the form that WOULD be allowed. Whichever of
  # those last two is read first is the one that gets used, and the toolkit has
  # plenty of hooks that name only the bypass.
  a6_upstream_facts "$CWD"
  A6_BRANCH=$(gc_current_branch "$CWD")
  A6_PROT=$(gc_protected_branches "$CWD")
  {
    echo "BLOCKED: gate-before-merge refuses this operation on a protected branch."
    echo "  branch:          $A6_BRANCH"
    echo "  protected set:   ${A6_PROT:-<empty>}  (set '- **Protected branches**:' in PROJECT_CONTEXT.md; 'none' protects nothing)"
    echo "  matched segment: ${A6_SEG:-<GitHub merge tool payload — no command string>}"
    echo "  upstream:        ${A6_UP:-<none configured for this branch>}${A6_UPSHA:+ ($A6_UPSHA)}"
    echo "  HEAD:            ${A6_HEADSHA:-<unresolvable>}"
    case "$A6_KIND" in
      merge)
        echo "  discriminator:   target ref: ${A6_TARGET:-<none named, or more than one>}${A6_TARGETSHA:+ -> $A6_TARGETSHA}"
        echo "                   --ff-only: $(a6_has_flag "$A6_ARGS" 'ff-only' && echo present || echo absent)   --no-ff/--squash: $(a6_has_flag "$A6_ARGS" 'no-ff|squash' && echo present || echo absent)"
        echo "                   HEAD already an ancestor of the upstream: $(case "${A6_ANCESTOR_RC:-}" in 0) echo yes ;; 1) echo no ;; 128) echo 'could not resolve (rc=128)' ;; *) echo 'not measured — an earlier condition already ruled out a catch-up' ;; esac)"
        echo "                   verdict: not a catch-up to this branch's own upstream."
        ;;
      pull)
        echo "  discriminator:   refspec/remote named: $([ "$(a6_nonflag_count "$A6_ARGS")" -eq 0 ] && echo absent || echo "present ($(a6_nonflag "$A6_ARGS" | tr '\n' ' '))")"
        echo "                   --ff-only: $(a6_has_flag "$A6_ARGS" 'ff-only' && echo present || echo absent)"
        echo "                   HEAD already equals the upstream: $([ -n "$A6_UPSHA" ] && { [ "$A6_UPSHA" = "$A6_HEADSHA" ] && echo yes || echo no; } || echo 'unknown — no upstream configured')"
        echo "                   verdict: not the one pull form that cannot land foreign content."
        ;;
      *)
        echo "  discriminator:   not applicable — this operation names no local ref that can be resolved before it runs."
        ;;
    esac
    echo "Could not determine: this check runs before any fetch, so the CONTENT of a remote target ref — what a fetch would bring in — is unknown to it. It decides on the FORM of the command and on refs that already exist locally. If your case is one only the content would settle, the hook cannot see it."
    case "$A6_KIND" in
      merge)
        echo "ALLOWED without a gate run: a pure catch-up — 'git merge --ff-only <upstream>' naming exactly this branch's configured upstream (${A6_UP:-none configured}) while HEAD is already an ancestor of it. Also always allowed: 'git merge --abort', '--continue', '--quit'."
        echo "Otherwise: gate the content that is actually being merged — check out the merge target (the PR branch head), run 'bash hooks/run-gate.sh' there, and merge from that checkout."
        ;;
      pull)
        echo "ALLOWED without a gate run: 'git pull --ff-only' with no remote and no refspec — the safe catch-up form. It targets the configured upstream by construction, and git itself refuses if the result would not be a fast-forward."
        ;;
      *)
        echo "ALLOWED without a gate run: nothing on this path — a merge run from a protected branch lands the OTHER side's content, not this checkout's HEAD, so comparing the gate artifact to HEAD verifies nothing and re-gating here would only bless content that is already merged."
        echo "Do this instead: check out the merge target (the PR branch head), run 'bash hooks/run-gate.sh' there, and merge from that checkout — or gate on the branch before opening the PR."
        ;;
    esac
    echo "(Last resort, and an admission of this guard's limits rather than a remedy: create '.claude/git-guard-off' under this cwd, make the one operation, then delete it.)"
  } >&2
  exit 2
fi

ARTIFACT="$REPO_TOP/.gate/last-pass.json"

if [ ! -f "$ARTIFACT" ]; then
  echo "BLOCKED: No gate artifact found. Run 'bash hooks/run-gate.sh' on the PR branch head (green gate writes .gate/last-pass.json), then merge." >&2
  exit 2
fi

# v2.4.0 (A6, consumer report): READ THE ARTIFACT AS JSON, NOT AS ONE SPELLING
# OF IT. Until now both reads were hardcoded to `"sha":"` — exactly the bytes
# our own run-gate.sh printf emits, with no space after the colon. A consumer
# whose project-owned gate writes the same fields pretty-printed
# (`{"sha": "…"}`, entirely valid JSON) got an EMPTY ARTIFACT_SHA and was
# blocked on every merge with `artifact sha: none` — a gate that passed,
# reported as stale, for a reason that has nothing to do with staleness. They
# carried a local widening for releases.
#
# REPLACING run-gate.sh WHOLESALE IS A SUPPORTED CONFIGURATION: the contract
# between the two halves is the `**Gate**` field plus the artifact FORMAT, not
# the script. So the reader must accept any valid JSON spelling of that format,
# not merely the one our writer happens to produce.
#
# THE `sed` IS WIDENED IN LOCKSTEP WITH THE `grep`, deliberately. Accepting
# `"sha": "` in the grep while stripping only `"sha":"` in the sed leaves a
# LEADING SPACE on the value — a sha that matches nothing, i.e. the same silent
# mismatch moved one step later and made harder to see. Both use the same
# tolerant pattern for that reason; do not "simplify" one of them.
ARTIFACT_SHA=$(grep -o '"sha"[[:space:]]*:[[:space:]]*"[^"]*"' "$ARTIFACT" | head -1 | sed 's/.*"sha"[[:space:]]*:[[:space:]]*"//;s/"$//')
ARTIFACT_TREE=$(grep -o '"tree"[[:space:]]*:[[:space:]]*"[^"]*"' "$ARTIFACT" | head -1 | sed 's/.*"tree"[[:space:]]*:[[:space:]]*"//;s/"$//')
HEAD_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null)
HEAD_TREE=$(git -C "$CWD" rev-parse 'HEAD^{tree}' 2>/dev/null)

# v2.1.3 fix round 1 (Critical 2 / penumbra #2c): accept either a sha match
# (the classic case: gate ran on this exact commit) or a tree match (the
# pre-commit-test.sh -> run-gate.sh chain: the gate ran against the INDEX
# just before `git commit`, so its "sha" is the PARENT commit but its "tree"
# is the tree the new commit just got). Both still gated by the freshness
# window below.
if [ -z "$ARTIFACT_SHA" ] || { [ "$ARTIFACT_SHA" != "$HEAD_SHA" ] && { [ -z "$ARTIFACT_TREE" ] || [ "$ARTIFACT_TREE" != "$HEAD_TREE" ]; }; }; then
  # v2.4.0 (A6, defect 1): the MESSAGE had drifted to the weaker half of the
  # check. The artifact matches by sha OR by tree, and the tree half is the one
  # that survives a squash -- a consumer measured a squash changing the sha and
  # leaving the tree byte-identical -- so a message naming only the sha sends
  # them to re-run a gate whose tree already matched. It also said "the current
  # head" without saying WHICH head, which is exactly the ambiguity that makes
  # gating `main` look like a remedy. The message is what a consumer acts on at
  # 2am; report both keys and name the head.
  {
    echo "BLOCKED: Gate artifact is stale — it matches this checkout by neither key."
    echo "  artifact sha:  ${ARTIFACT_SHA:-none}    HEAD:          $HEAD_SHA"
    echo "  artifact tree: ${ARTIFACT_TREE:-none}    HEAD^{tree}:   $HEAD_TREE"
    echo "Run 'bash hooks/run-gate.sh' on the head that is actually being MERGED — the PR branch tip, from a checkout of that branch — then merge from there. Gating some other head produces a fresh artifact that verifies nothing."
  } >&2
  exit 2
fi

# Freshness: artifact file mtime < 60 minutes (mtime avoids date-parsing portability issues)
ARTIFACT_EPOCH=$(stat -c %Y "$ARTIFACT" 2>/dev/null || stat -f %m "$ARTIFACT" 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
AGE=$((NOW_EPOCH - ARTIFACT_EPOCH))
if [ "$ARTIFACT_EPOCH" -eq 0 ] || [ "$AGE" -gt 3600 ]; then
  echo "BLOCKED: Gate artifact expired (${AGE}s old, max 3600s). Re-run 'bash hooks/run-gate.sh', then merge." >&2
  exit 2
fi

exit 0
