#!/usr/bin/env bash
# Native git pre-push hook (v4.3.2, design P2). Git runs this for EVERY push --
# typed in a terminal, run by a script, an alias, an IDE or a GUI client -- and
# hands it the refs that push will update, already resolved:
#   argv:  <remote name> <remote url>
#   stdin: <local ref> <local sha> <remote ref> <remote sha>   (one line per ref)
# A remote ref refs/heads/<b> with <b> protected is refused: create, update,
# force and delete (local sha all zeros) alike. Tags and every other ref pass.
# One refused line fails the hook, and git then lands NOTHING of that push.
#
# The protected set is the one hooks/no-push-main.sh enforces:
# gc_protected_branches (hooks/lib/git-cmd.sh) over the '- **Protected
# branches**:' line of the top-level PROJECT_CONTEXT.md -- CALLED, never
# re-implemented, so the two cannot drift (consistency check 69). No line, an
# empty value or a placeholder: main master (+ the remote's trunk). `none`:
# nothing.
#
# FAIL CLOSED: a missing or corrupt lib, no top-level, or a PROJECT_CONTEXT.md
# that exists but cannot be read refuses every push.
#
# The ONE deliberate escape is `git push --no-verify` (git skips this hook);
# .claude/git-guard-off is NOT honoured here. The server-side layer is a GitHub
# ruleset that requires a pull request (docs/templates.md).
#
# Not registered in settings.json: installed per clone as a shim in
# <git common dir>/hooks/pre-push by `bash hooks/git-pre-push.sh --install`.

gpp_install() { # [<dir>] -- Task 2
  echo "pre-push: not installed: installer not implemented yet" >&2
  return 1
}

if [ "${1:-}" = --install ]; then gpp_install "${2:-.}"; exit $?; fi

gpp_lib="$(dirname "$0")/lib/git-cmd.sh"
if [ ! -f "$gpp_lib" ]; then
  echo "BLOCKED: pre-push: $gpp_lib missing -- the protected branches cannot be read, push refused. Run /sync-template (hooks/lib/git-cmd.sh), or push deliberately with 'git push --no-verify'." >&2
  exit 1
fi
. "$gpp_lib"
command -v gc_protected_branches >/dev/null 2>&1 || {
  echo "BLOCKED: pre-push: $gpp_lib is present but corrupt (gc_protected_branches undefined) -- push refused." >&2
  exit 1
}

gpp_top=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$gpp_top" ]; then
  echo "BLOCKED: pre-push: cannot find the repository top-level -- push refused." >&2
  exit 1
fi
if [ -e "$gpp_top/PROJECT_CONTEXT.md" ] && [ ! -r "$gpp_top/PROJECT_CONTEXT.md" ]; then
  echo "BLOCKED: pre-push: $gpp_top/PROJECT_CONTEXT.md exists but cannot be read, so the protected branches are unknown -- push refused." >&2
  exit 1
fi
gpp_prot=$(gc_protected_branches "$gpp_top")

gpp_rc=0
while read -r gpp_lref gpp_lsha gpp_rref gpp_rsha; do
  case "$gpp_rref" in refs/heads/?*) gpp_b=${gpp_rref#refs/heads/} ;; *) continue ;; esac
  case " $gpp_prot " in *" $gpp_b "*) ;; *) continue ;; esac
  case "$gpp_lsha" in *[!0]*) gpp_what=push ;; *) gpp_what=delete ;; esac
  echo "BLOCKED: pre-push: $gpp_what of protected branch '$gpp_b' on remote '${1:-?}' refused (protected: $gpp_prot). Push a feature branch and open a PR; to push it deliberately: git push --no-verify." >&2
  gpp_rc=1
done
exit "$gpp_rc"
