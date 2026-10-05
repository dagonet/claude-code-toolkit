# Empty-tree gate artifact — root-cause diagnosis (v4.3.1, read-only)

Scratch review note. Delete it once it has been read. No fix is committed here.

## TL;DR
- **Root cause:** the artifact's `"tree"` field is `4b825dc…`, git's empty tree, because `write-tree` ran against a temp index file that does not exist. The real index was never copied into it. `run-gate.sh` **detects** this (S-8, `RG_TREE_SUSPECT=true`). It still writes the sentinel into the artifact, and it prints nothing. You get exactly the reported shape: sha-named file, empty tree, `legs: []`, `GATE PASS`.
- **The consumer's merge was correctly allowed.** It matched by **sha**, the tree was clean, and the gate really ran on that content.
- **Safety impact:** there is one contrived **false ALLOW**, an empty-tree HEAD with an untracked `PROJECT_CONTEXT.md` (fixture D2). There is also one benign **false REFUSE**: past the 1 h TTL, the tree+env extension is lost (fixture F).
- **Windows-specific?** The code path is not. The *trigger* most likely is, but it can't be observed because the copy's stderr goes to `/dev/null`.

## 1. Code path (v4.3.1, b8608a8)

`hooks/run-gate.sh`:
- `:486` `TMPD=$(mktemp -d)`, `TMPIDX="$TMPD/index"`. The comment says it "must not pre-exist".
- `:498` `RG_IDX=$(git rev-parse --path-format=absolute --git-path index)`
- `:500` `cp -p "$RG_IDX" "$TMPIDX" 2>/dev/null` sets `RG_IDX_COPIED=true` only on success. **The error text is discarded.**
- `:504` `GIT_INDEX_FILE=$TMPIDX git add -u -- .`: on a missing index this adds nothing.
- `:505` `TREE_HASH=$(GIT_INDEX_FILE=$TMPIDX git write-tree)`: a **missing index file gives the empty tree `4b825dc…`**.
- `:509-513` `RG_TREE_SUSPECT=true` when the copy failed or the tree is empty.
- `:523-529` G4 naming: a suspect capture keeps the **sha** name (`last-pass.<sha>.json`). This is why the consumer got a sha-named file and not `tree-4b825….json`.
- `:562` the Gate-extra reuse is voided when suspect, which is correct. Plain `**Gate**` leaves `LEGS_JSON="[]"`, so `legs: []` is **normal** and not a symptom.
- `:761` the `printf` writes `"tree":"$TREE_HASH"` **unconditionally**. This is the defect: a value the script itself has flagged as non-measurement is persisted as if it were one, with no stderr line.

`hooks/pre-commit-test.sh:139-151` has the identical capture and the same `2>/dev/null` on `cp`. It sets `PCT_TREE_SUSPECT`, and the record path is already guarded there.

Readers in `hooks/gate-before-merge.sh`:
- `:1349` tier 1, exact sha: ignores `tree`.
- `:1359` tier 1b, `tree-<HEAD^{tree}>`: a suspect artifact is never tree-named, so this tier is unaffected.
- `:1371-1380` tier 2, mtime tree scan: matches `gbm_tree == HEAD_TREE`, **including the empty tree**.
- `:1427` sha-OR-tree check.
- `:1524` tree+env TTL extension: needs `ARTIFACT_TREE == HEAD_TREE`.
- Pruning (`run-gate.sh:777`) is by mtime only and is unaffected.

## 2. Reproduction (Linux, git 2.43, hooks/ from v4.3.1, `**Gate**: true`)

Script: `repro.sh` in the session scratchpad. Each row shows the artifact name and the `"tree"` it recorded, after a sync-style commit on a clean tree.

| variant | artifact | tree |
|---|---|---|
| clean tree (sync-commit shape) | `<sha>` | = HEAD^{tree} ✓ |
| cwd = `hooks/` | `<sha>` | ✓ |
| staged change / unstaged change | `tree-<t>` | = working tree ✓ |
| merge-commit HEAD | `<sha>` | ✓ |
| linked worktree | `<sha>` | ✓ |
| `GIT_INDEX_FILE` relative / absolute (valid) | `<sha>` | ✓ |
| `GIT_DIR=.git` / absolute | `<sha>` | ✓ |
| `TMPDIR` unwritable, `index.lock` present, split-index, skip-worktree | `<sha>` | ✓ |
| **`.git/index` absent** | `<sha>` | **4b825dc… ✗** |
| **`GIT_INDEX_FILE=/nonexistent/index`** | `<sha>` | **4b825dc… ✗** |
| **`cp` fails (PATH shim exiting 1)** | `<sha>` | **4b825dc… ✗** |
| MSYS-style non-translated `GIT_INDEX_FILE` (git cannot reach the temp dir) | `<sha>` | `""` (not the empty tree) |

**Reproducing variant:** any failure of the `cp -p "$RG_IDX" "$TMPIDX"` at `:500` gives exactly the consumer's artifact. The source path may be missing or unreadable, or `cp` may fail. The temp dir must exist but the temp index must not. Every git-topology variant on the list (merge HEAD, worktree, `GIT_DIR`/`GIT_INDEX_FILE`, Gate vs Test+Gate extra) is green on Linux.

**Why it happened on the consumer's Windows checkout:** this is not observable, because `cp`'s stderr is thrown away and the suspect state prints nothing. Here is what the evidence narrows it to:
- The artifact landed in `<common git dir>/gate`, so `--path-format=absolute` works. Git is ≥ 2.31, so `RG_IDX` was a real absolute path.
- A non-translated MSYS `GIT_INDEX_FILE` gives `""`, not the empty tree, so that cause is ruled out.
- What remains is `cp -p` failing to open or read `C:/…/.git/index` at that instant. The most plausible cause is Windows mandatory file locking: a concurrent `git status` from an IDE, a status line or AV holding or replacing the index while it is rewritten after the sync. Linux has no equivalent failure mode.

This cause is **unconfirmed**. The first step of the fix makes the next occurrence self-reporting.

## 3. Safety impact (fixtures: `safety.sh` in the session scratchpad)

The suspect artifact was produced by moving `.git/index` aside during `run-gate.sh`, on branch `feat`.

| fixture | expected | actual |
|---|---|---|
| B: same sha, clean tree (the consumer's case) | allow | rc=0, `matched: sha` ✓. **Legitimate:** the gate ran on exactly this content. |
| C2: other branch, new sha, real tree | refuse | rc=2 ✓ |
| D: worktree whose HEAD has the empty tree (`git rm -r .`), no `PROJECT_CONTEXT.md` | n/a | rc=0 with or without an artifact. The gate is unarmed there, so the empty-tree match is moot. |
| **D2: same as D, plus an untracked `PROJECT_CONTEXT.md` (gate armed)** | **refuse** | **rc=0, `matched: tree (last-pass.<feat sha>.json)`.** Control without the artifact gives rc=2. **FALSE ALLOW.** |
| **F: suspect artifact on its own sha, aged 2 h (> 3600 s TTL)** | allow (tree+env extension) | **rc=2 "expired"**. Control with a real tree gives rc=0. **FALSE REFUSE.** It fails closed and is benign. |

Verdict:
- **ALLOW:** reachable only when HEAD^{tree} is the empty tree *and* the gate is armed (an untracked `PROJECT_CONTEXT.md` or `hooks/`). That is contrived and low severity, but it is a real case of tier 2 blessing content that was never gated.
- **REFUSE:** the TTL extension is silently lost. The user is told to re-run.
- **The consumer's actual merge: no impact.** It was correctly allowed.

**Should the reader refuse an artifact whose tree is the empty tree while HEAD^{tree} is not?** No, not refuse. Tier 1 (sha match on that sha) is still sound, because the gate ran on HEAD's checkout. The reader should **treat `"tree":"4b825dc…"` as "no tree"**: never let it match in tier 2 or the TTL extension. The writer fix below makes this mostly redundant. The reader guard is defence in depth for artifacts already on disk, which are pruned within 24 h.

## 4. Branches
- `feat/v4.4.0` does not exist on origin.
- `feat/hook-slimming`, `feat/v4.3.2`, `feat/v4.3.2-f`, `feat/v4.3.2-p`, `feat/v4.5-build` and `feat/jev-on-431` make **0** changes to these lines in `run-gate.sh` and `gate-before-merge.sh`.
- `feat/v4.5-less-bureaucracy` *predates* v4.3.1 (its merge base is v4.3.0). Its diff only shows G4 as absent, and it makes no hook changes of its own.
- The defect is live on every branch.

## 5. Simplest fix (KISS)

`hooks/run-gate.sh`, right after `:513`:
```sh
if [ "$RG_TREE_SUSPECT" = true ]; then
  echo "run-gate: WARN could not snapshot the index (${RG_IDX:-unresolved}); artifact records no tree -- merge will need an exact-sha match" >&2
  TREE_HASH=""
fi
```
- With this, `"tree":""` is written. Every reader already treats an empty tree as "no tree match, no TTL extension", which is exactly what the S-8 header promises.
- G4 naming (`:524`) already refuses a non-hex value.
- The reuse lookup (`:562`) is already voided by suspect.
- The `rm -f …tree-.json` cleanups are harmless.
- Optional: drop `2>/dev/null` from the `cp` at `:500` (and `pre-commit-test.sh:141`) so the next Windows hit names its cause.

Reader guard (defence in depth), `hooks/gate-before-merge.sh` after `:1417` and in the scan at `:1376`:
```sh
[ "$ARTIFACT_TREE" = 4b825dc642cb6eb9a060e54bf8d69288fbee4904 ] && ARTIFACT_TREE=""   # S-8 sentinel, never a measurement
# scan: [ "$gbm_tree" = 4b825dc642cb6eb9a060e54bf8d69288fbee4904 ] && continue
```
The literal is a universal content hash, so there is nothing to drift. Per CLAUDE.md, edit `hooks/` first, then mirror to the variants and user-level copies where the consistency script expects it.

### Test rows that pin it (hook suite)
1. **Writer:** a repo with `**Gate**: true`. Run `run-gate.sh` with `.git/index` moved aside, or with a PATH-shim `cp` that exits 1. Assert all three:
   - the artifact `last-pass.<sha>.json` exists;
   - its `"tree"` is **not** `4b825dc…` (expect `""`);
   - stderr contains `could not snapshot the index`.

   Today this fails on the `tree` assertion.
2. **Reader (fixture D2):** the suspect artifact from row 1 sits on sha A. A linked worktree is on a commit whose tree is empty, with an untracked `PROJECT_CONTEXT.md` (`**Gate**: true`). Feed gate-before-merge a `gh pr <merge> …` payload with `cwd` set to that worktree. Expect **rc=2 "No gate artifact found"**. Today it is rc=0, `matched: tree`.

## 6. Windows-specific?
- **Code defect:** no. It reproduces on Linux whenever the index copy fails.
- **Trigger:** very likely yes (index locking or a replace race on NTFS). It is unconfirmed until the WARN or `cp` stderr above is shipped.
