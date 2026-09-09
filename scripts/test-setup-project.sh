#!/usr/bin/env bash
# test-setup-project.sh
#
# Bootstrap fixtures for setup-project.sh / setup-project.ps1.
#
# WHY THIS FILE EXISTS, specifically:
#
# Both scripts render a file TWICE through two different code paths — one for
# `--dry-run` (report only) and one for the real write — and those two paths
# have now diverged twice, one release apart:
#
#   v2.2.0 PR16  `--dry-run` exited before the "Remaining placeholders" report
#                and the real-run version grepped files on disk. Fixed by
#                computing the report over the RENDERED content in memory.
#   v2.2.1 r5    the protected-branches rewrite was added to render_file (the
#                dry-run path) only. The dry run reported `develop`; the real
#                run wrote `main master`. Caught by running both by hand.
#
# The second one is the point: an adjacent comment saying "do not let these
# diverge" did not prevent the recurrence, because nothing executed both paths
# and compared them. That is what this file does. Anything a consumer's
# bootstrap depends on which is computed on BOTH paths belongs here.
#
# Run from repo root: bash scripts/test-setup-project.sh
# Exit 0 = all cases pass. Exit 1 = at least one FAIL.

set -u
pass=0
fail=0
skipped=0

ROOT=$(pwd)
TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t setuptest)
trap 'rm -rf "$TMPROOT"' EXIT

expect() { # <label> <want> <got>
  if [ "$2" = "$3" ]; then
    printf 'PASS  %-52s (%s)\n' "$1" "$3"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-52s (want %s, got %s)\n' "$1" "$2" "$3"
    fail=$((fail + 1))
  fi
}

skip() { # <label> <reason> [count]
  skipped=$((skipped + ${3:-1}))
  printf 'SKIP  %-52s (%s, %s assertion(s))\n' "$1" "$2" "${3:-1}"
}

# --- helpers ---------------------------------------------------------------

# The one line the branch-protection hooks read, from a generated project.
protected_line() { # <project dir>
  grep -E '^- \*\*Protected branches\*\*:' "$1/PROJECT_CONTEXT.md" 2>/dev/null | head -1
}

# The line setup-project PRINTS about branch protection, from either mode.
protected_report() { # <output file>
  grep -E '^Branch protection:' "$1" 2>/dev/null | head -1
}

run_sh() { # <target> <branch> <outfile> [--dry-run]
  mkdir -p "$1"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$1" --default-branch "$2" ${4:+"$4"} > "$3" 2>&1
}

echo "=== setup-project.sh: dry run and real run must agree ==="

# The divergence is only VISIBLE when the resolved trunk is not in the static
# default, so `develop` is the load-bearing case; `main` is the control that
# proves the comparison is not vacuous.
for branch in develop main; do
  DRY="$TMPROOT/$branch-dry"
  REAL="$TMPROOT/$branch-real"
  DRYOUT="$TMPROOT/$branch-dry.out"
  REALOUT="$TMPROOT/$branch-real.out"

  run_sh "$DRY"  "$branch" "$DRYOUT" --dry-run
  run_sh "$REAL" "$branch" "$REALOUT"

  dry_report=$(protected_report "$DRYOUT")
  real_report=$(protected_report "$REALOUT")
  real_line=$(protected_line "$REAL")

  # 1. The report a user reads before committing to the run must be the report
  #    they get from the run. This is the assertion that failed in r5.
  expect "[$branch] dry-run report == real-run report" "$dry_report" "$real_report"

  # 2. ... and the report must describe the file that was actually written.
  #    Report equality alone would still pass if BOTH paths were wrong.
  case "$branch" in
    develop) want_line="- **Protected branches**: develop" ;;
    *)       want_line="- **Protected branches**: main master" ;;
  esac
  expect "[$branch] written line matches the report" "$want_line" "$real_line"

  # 3. No placeholder survives on that line — the v2.2.0 fail-open shape.
  case "$real_line" in
    *'{{'*) got_ph=1 ;;
    *)      got_ph=0 ;;
  esac
  expect "[$branch] no placeholder on the protected line" 0 "$got_ph"
done

# A rerun over an existing PROJECT_CONTEXT.md must SAY the file was kept, not
# claim a protection it did not write.
RERUN_OUT="$TMPROOT/develop-rerun.out"
run_sh "$TMPROOT/develop-real" develop "$RERUN_OUT"
expect "rerun reports that the file was not written" 1 \
  "$(grep -c 'was NOT written' "$RERUN_OUT")"

# --- WORKTREE_BASE: a DEFAULT, not a constant (v2.2.6) ---------------------
#
# The field used to default to empty, which left `{{WORKTREE_BASE}}` in the
# rendered PROJECT_CONTEXT.md of every bootstrap that did not pass the flag.
# Two things have to hold and neither is implied by the other: a plain run
# fills the field, and an explicit flag still overrides it.
#
# The expected value is read from setup-project.sh rather than restated here —
# verify-template-consistency.sh check 26b is what pins that value across the
# .ps1 and the six gitignores. This fixture asserts it REACHES the file.
WTB_DEFAULT=$(grep -E '^WORKTREE_BASE="' "$ROOT/setup-project.sh" | head -1 | sed 's/^WORKTREE_BASE="//; s/".*$//')

worktree_line() { # <project dir>
  grep -E '^- \*\*Worktree base\*\*:' "$1/PROJECT_CONTEXT.md" 2>/dev/null | head -1
}

if [ -z "$WTB_DEFAULT" ]; then
  # Refuse rather than compare against an empty string, which every line matches.
  expect "WORKTREE_BASE default is readable from setup-project.sh" "non-empty" ""
else
  # Fresh dirs: a rerun over an existing PROJECT_CONTEXT.md is not written at
  # all, and the assertion would read a stale file.
  WTBDIR="$TMPROOT/wtb-default"
  mkdir -p "$WTBDIR"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$WTBDIR" > "$TMPROOT/wtb-default.out" 2>&1
  expect "default bootstrap fills the worktree base" \
    "- **Worktree base**: $WTB_DEFAULT" "$(worktree_line "$WTBDIR")"

  WTBOVR="$TMPROOT/wtb-override"
  mkdir -p "$WTBOVR"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$WTBOVR" --worktree-base "custom/wt" > "$TMPROOT/wtb-override.out" 2>&1
  expect "--worktree-base still overrides the default" \
    "- **Worktree base**: custom/wt" "$(worktree_line "$WTBOVR")"
fi

# --- the autoMode snippet is GENERIC and USER-scoped (v3.0.3, item 23) -----
#
# `permissions.autoMode.environment` applies to every project on the machine.
# A snippet naming ONE repository as THE trusted repo makes the classifier read
# every other repo as outside the trust boundary: 58 denials across 11 sessions
# were measured, 50 of them in one consumer whose commands began with a
# `Set-Location` into a path the live environment had declared untrusted.
#
# The wanted line is READ from the reference, never restated here — the whole
# point of the fix is that the snippet cannot drift from
# user-level-reference/settings.json.
AMDIR="$TMPROOT/automode"
mkdir -p "$AMDIR"
bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
  --target-path "$AMDIR" > "$TMPROOT/automode.out" 2>&1

am_want() { # the generic entry, straight out of the reference
  grep -F '**Trusted repos**' "$ROOT/user-level-reference/settings.json" \
    | head -1 | sed 's/^[[:space:]]*"//; s/",*[[:space:]]*$//'
}
AM_WANT=$(am_want)

if [ -z "$AM_WANT" ]; then
  # Refuse rather than compare against an empty string, which every line matches.
  expect "trusted-repos entry is readable from the reference" "non-empty" ""
else
  expect "sh snippet prints the reference's generic entry" 1 \
    "$(grep -cF -- "$AM_WANT" "$TMPROOT/automode.out")"
fi
# The paired negative: the singular, path-naming form must be gone. Without it
# the row above would pass while the defective line was still printed too.
expect "sh snippet names no single repo as THE trusted repo" 0 \
  "$(grep -cF -- '**Trusted repo**:' "$TMPROOT/automode.out")"

# --- the PowerShell half, where it can run ---------------------------------
#
# The two scripts are independent implementations of the same contract, and the
# same two-path shape exists in both — so parity is asserted, not assumed.
PSBIN=""
for c in pwsh powershell; do
  command -v "$c" >/dev/null 2>&1 && { PSBIN=$c; break; }
done
if [ -n "$PSBIN" ] && [ -f "$ROOT/setup-project.ps1" ]; then
  PSDIR="$TMPROOT/ps-develop"
  mkdir -p "$PSDIR"
  "$PSBIN" -NoProfile -ExecutionPolicy Bypass -File "$ROOT/setup-project.ps1" \
    -Variant general -ProjectName SetupFixture -TargetPath "$PSDIR" \
    -DefaultBranch develop > "$TMPROOT/ps-develop.out" 2>&1
  PS_DEVELOP_RC=$?
  expect "ps1 writes the same protected line as sh" \
    "- **Protected branches**: develop" "$(protected_line "$PSDIR")"
  # No -WorktreeBase passed: the .ps1 parameter default must reach the file
  # through BOTH `if ($WorktreeBase)` sites, exactly as the .sh default does.
  expect "ps1 writes the same worktree base as sh" \
    "- **Worktree base**: $WTB_DEFAULT" "$(worktree_line "$PSDIR")"
  if [ -n "$AM_WANT" ]; then
    expect "ps1 snippet prints the reference's generic entry" 1 \
      "$(grep -cF -- "$AM_WANT" "$TMPROOT/ps-develop.out")"
  else
    expect "trusted-repos entry is readable from the reference (ps1)" "non-empty" ""
  fi
  expect "ps1 snippet names no single repo as THE trusted repo" 0 \
    "$(grep -cF -- '**Trusted repo**:' "$TMPROOT/ps-develop.out")"
  # v3.1 (open-brain): :861 used to run `git -C $PSScriptRoot rev-parse --short
  # HEAD` unguarded under `$ErrorActionPreference = "Stop"`. On this fixture
  # PowerShell IS present and the toolkit tree DOES carry .git, so :861 never
  # throws here and the exit code was always 0 -- this row is the assertion
  # that was MISSING (only the snippet count was checked), not a row that
  # exercises the defect. See the no-.git arm below for the row that does.
  expect "ps1 exits 0 on the develop fixture" 0 "$PS_DEVELOP_RC"

  # --- BOM: PS 5.1's `-Encoding UTF8` writes a byte-order mark on every write.
  # The MCP server tolerates it, but the sync skill's own
  # `json.load(encoding="utf-8")` on the manifest raises
  # `JSONDecodeError: Unexpected UTF-8 BOM`, crashing mid-sync on every
  # ps1-bootstrapped consumer (open-brain, measured 2026-09-05).
  bom_files=$(cd "$PSDIR" && find . -type f -exec sh -c 'head -c3 "$1" | od -An -tx1 | tr -d " \n" | grep -q "^efbbbf" && echo "$1"' _ {} \;)
  expect "ps1 bootstrap writes no UTF-8 BOM" "" "$bom_files"
  expect "ps1 manifest has no BOM" "7b" "$(head -c1 "$PSDIR/.claude/template-manifest.json" | od -An -tx1 | tr -d ' ')"
  SHDIR="$TMPROOT/develop-real"
  sh_list=$(cd "$SHDIR" && find . -type f | sort)
  ps_list=$(cd "$PSDIR" && find . -type f | sort)
  expect "sh and ps1 bootstraps write the same file set" "$sh_list" "$ps_list"

  # --- v3.1 ownership-cutover: manifest v3 contract ---------------------------
  #
  # Both writers now emit a manifest v3 (ownership per file, sha256 for
  # `template` class, variant/templateRepo/placeholders, v-prefixed
  # template_version) instead of the old flat v2 `files{}`. Node does the
  # parsing/comparison (it is already required by the hooks) so this stays a
  # structural check rather than a brittle text diff — ConvertTo-Json's escaping
  # and PS's key order differ from jq's by design and must not fail the row.
  #
  # Fresh directories, not $SHDIR/$PSDIR: those two are reused/mutated later
  # by the rerun-over-an-existing-project fixture, whose manifest legitimately
  # carries only the one file that fixture actually rewrites.
  SHMDIR="$TMPROOT/manifest-sh"
  PSMDIR="$TMPROOT/manifest-ps"
  mkdir -p "$SHMDIR" "$PSMDIR"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$SHMDIR" --default-branch develop > "$TMPROOT/manifest-sh.out" 2>&1
  "$PSBIN" -NoProfile -ExecutionPolicy Bypass -File "$ROOT/setup-project.ps1" \
    -Variant general -ProjectName SetupFixture -TargetPath "$PSMDIR" \
    -DefaultBranch develop > "$TMPROOT/manifest-ps.out" 2>&1
  SH_MANIFEST="$SHMDIR/.claude/template-manifest.json"
  PS_MANIFEST="$PSMDIR/.claude/template-manifest.json"
  MANIFEST_CHECK="$TMPROOT/manifest-check.cjs"
  cat > "$MANIFEST_CHECK" <<'NODE_EOF'
const fs = require("fs");
const [, , shPath, psPath, shDir, wantVersion] = process.argv;
const sh = JSON.parse(fs.readFileSync(shPath, "utf8"));
const ps = JSON.parse(fs.readFileSync(psPath, "utf8"));

function checkShape(m, label) {
  const errs = [];
  if (m.manifest_version !== 3) errs.push(`manifest_version !== 3 (${m.manifest_version})`);
  if (typeof m.variant !== "string" || !m.variant) errs.push("variant missing/not a string");
  if (typeof m.templateRepo !== "string" || !m.templateRepo) errs.push("templateRepo missing/not a string");
  if (typeof m.placeholders !== "object" || m.placeholders === null) errs.push("placeholders missing/not an object");
  // Asserted against VERSION, never against a literal. The previous literal
  // matched the emitter's literal, so both went stale at the v3.1.1 bump and
  // the fixture stayed green while the manifest named a tag that did not match
  // its own template_commit. An assertion that repeats the emitter's constant
  // tests nothing; this one fails if either writer stops tracking VERSION.
  if (m.template_version !== wantVersion) errs.push(`template_version !== "${wantVersion}" (${m.template_version})`);
  if (m.requires_server !== ">=0.3.2") errs.push(`requires_server !== ">=0.3.2" (${m.requires_server})`);
  if (!/^[0-9a-f]{40}$/.test(m.template_commit) && m.template_commit !== "unknown") {
    errs.push(`template_commit not a 40-hex sha or "unknown" (${m.template_commit})`);
  }
  console.log(`ROW1_${label}: ${errs.length ? "FAIL " + errs.join("; ") : "PASS"}`);
}
checkShape(sh, "SH");
checkShape(ps, "PS");

function checkFiles(m, label) {
  const errs = [];
  for (const [key, entry] of Object.entries(m.files)) {
    if (entry.ownership !== "template" && entry.ownership !== "once") {
      errs.push(`${key}: ownership is "${entry.ownership}"`);
    }
  }
  console.log(`ROW2_${label}: ${errs.length ? "FAIL " + errs.join("; ") : "PASS"}`);
}
checkFiles(sh, "SH");
checkFiles(ps, "PS");

function checkHashes(m, label) {
  const errs = [];
  for (const [key, entry] of Object.entries(m.files)) {
    if (entry.ownership === "template") {
      if (!/^sha256:[0-9a-f]{64}$/.test(entry.hash || "")) errs.push(`${key}: hash malformed (${entry.hash})`);
    } else if (entry.ownership === "once") {
      if (Object.prototype.hasOwnProperty.call(entry, "hash")) errs.push(`${key}: once entry carries a hash key`);
    }
  }
  console.log(`ROW3_${label}: ${errs.length ? "FAIL " + errs.join("; ") : "PASS"}`);
}
checkHashes(sh, "SH");
checkHashes(ps, "PS");

function checkGitignoreKeys(m, label) {
  const errs = [];
  if (!m.files[".gitignore"]) errs.push("no .gitignore entry under the project-path key");
  if (m.files["gitignore"]) errs.push("a bare 'gitignore' key is present (should be renamed to .gitignore)");
  if (m.files["CLAUDE.local.md"]) errs.push("CLAUDE.local.md is present (should be absent, unclassified_template_files)");
  console.log(`ROW4_${label}: ${errs.length ? "FAIL " + errs.join("; ") : "PASS"}`);
}
checkGitignoreKeys(sh, "SH");
checkGitignoreKeys(ps, "PS");

// Row 5: identical after normalising template_commit, templateRepo, and (if
// present) classifier. Key order is deliberately not part of the comparison
// (sortObj below) -- sh and ps1 build their placeholder maps in different
// orders and that is not drift.
//
// templateRepo needs normalising too, beyond what the brief names: on this
// harness `$PSBIN -File "$ROOT/setup-project.ps1"` is MSYS invoking a native
// (non-MSYS) exe, and MSYS silently rewrites a POSIX-looking argument
// (`$ROOT`, e.g. `/g/git/...`) to its Windows spelling (`G:/git/...`) before
// PowerShell ever sees it -- so `$PSScriptRoot` resolves Windows-style while
// bash's own `$SCRIPT_DIR` stays POSIX-style. Both name the identical
// directory; the difference is the launching shell's argv translation, not
// the two writers disagreeing. Row 1 already asserts both are non-empty
// strings, so the field is not going unchecked -- only the exact spelling
// is exempted here.
function sortObj(o) {
  if (Array.isArray(o)) return o.map(sortObj);
  if (o && typeof o === "object") {
    const out = {};
    for (const k of Object.keys(o).sort()) out[k] = sortObj(o[k]);
    return out;
  }
  return o;
}
const shN = JSON.parse(JSON.stringify(sh));
const psN = JSON.parse(JSON.stringify(ps));
shN.template_commit = "NORM";
psN.template_commit = "NORM";
shN.templateRepo = "NORM";
psN.templateRepo = "NORM";
delete shN.classifier;
delete psN.classifier;
const shStr = JSON.stringify(sortObj(shN));
const psStr = JSON.stringify(sortObj(psN));
if (shStr === psStr) {
  console.log("ROW5: PASS");
} else {
  console.log("ROW5: FAIL manifests differ after normalisation");
}

// Row 6: recompute sha256 over the file on disk for one `template` entry and
// compare to the manifest value — catches a hash computed pre-replacement.
const crypto = require("crypto");
const path = require("path");
const [pickKey] = Object.entries(sh.files).find(([, v]) => v.ownership === "template") || [];
if (!pickKey) {
  console.log("ROW6: FAIL no template entry found to check");
} else {
  const onDisk = fs.readFileSync(path.join(shDir, pickKey));
  const want = "sha256:" + crypto.createHash("sha256").update(onDisk).digest("hex");
  if (want === sh.files[pickKey].hash) {
    console.log(`ROW6: PASS (${pickKey})`);
  } else {
    console.log(`ROW6: FAIL ${pickKey} manifest=${sh.files[pickKey].hash} disk=${want}`);
  }
}
NODE_EOF

  WANT_TEMPLATE_VERSION="v$(head -1 "$ROOT/VERSION" | tr -d '\r\n')"
  MANIFEST_RESULTS="$(node "$MANIFEST_CHECK" "$SH_MANIFEST" "$PS_MANIFEST" "$SHMDIR" "$WANT_TEMPLATE_VERSION" 2>&1)"
  row_result() { echo "$MANIFEST_RESULTS" | grep "^$1:" | head -1; }

  expect "sh manifest: shape/required fields (row 1)" "ROW1_SH: PASS" "$(row_result ROW1_SH)"
  expect "ps1 manifest: shape/required fields (row 1)" "ROW1_PS: PASS" "$(row_result ROW1_PS)"
  expect "sh manifest: every files entry ownership template|once (row 2)" "ROW2_SH: PASS" "$(row_result ROW2_SH)"
  expect "ps1 manifest: every files entry ownership template|once (row 2)" "ROW2_PS: PASS" "$(row_result ROW2_PS)"
  expect "sh manifest: hash shape, once carries no hash key (row 3)" "ROW3_SH: PASS" "$(row_result ROW3_SH)"
  expect "ps1 manifest: hash shape, once carries no hash key (row 3)" "ROW3_PS: PASS" "$(row_result ROW3_PS)"
  expect "sh manifest: .gitignore key, no gitignore/CLAUDE.local.md keys (row 4)" "ROW4_SH: PASS" "$(row_result ROW4_SH)"
  expect "ps1 manifest: .gitignore key, no gitignore/CLAUDE.local.md keys (row 4)" "ROW4_PS: PASS" "$(row_result ROW4_PS)"
  expect "sh and ps1 manifests agree after normalisation (row 5)" "ROW5: PASS" "$(row_result ROW5)"
  # row 6's PASS line carries the picked filename; compare on the PASS/FAIL word only.
  row6_word=$(row_result ROW6 | sed -E 's/^ROW6: (PASS|FAIL).*/\1/')
  expect "manifest hash matches sha256 of the file as written (row 6)" "PASS" "$row6_word"

  # --- v3.1 Phase 3: a rerun must not shrink the manifest --------------------
  #
  # Under manifest v3 a file absent from `files` is project-owned BY
  # DEFINITION, so rebuilding the manifest from only this run's writes would
  # silently reclassify every file the run did not touch as project-owned,
  # and sync stops updating them for good. Bootstrap once, strip the
  # PROJECT-CUSTOM markers from the written CLAUDE.md (simulating an older
  # project that predates them), then rerun with
  # --wrap-existing-claude-md/-WrapExistingClaudeMd: that flag rewrites
  # CLAUDE.md ONLY -- every other file already exists and is skipped -- so it
  # is exactly the "writes a subset" shape the bug report describes, AND it
  # changes CLAUDE.md's content (the old body moves inside a new
  # PROJECT-CUSTOM region), giving row 3 a real hash change to check.
  RERUN_SH="$TMPROOT/rerun-sh"
  RERUN_PS="$TMPROOT/rerun-ps"
  mkdir -p "$RERUN_SH" "$RERUN_PS"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$RERUN_SH" --default-branch develop > "$TMPROOT/rerun-sh-1.out" 2>&1
  "$PSBIN" -NoProfile -ExecutionPolicy Bypass -File "$ROOT/setup-project.ps1" \
    -Variant general -ProjectName SetupFixture -TargetPath "$RERUN_PS" \
    -DefaultBranch develop > "$TMPROOT/rerun-ps-1.out" 2>&1
  cp "$RERUN_SH/.claude/template-manifest.json" "$TMPROOT/rerun-sh-manifest-1.json"
  cp "$RERUN_PS/.claude/template-manifest.json" "$TMPROOT/rerun-ps-manifest-1.json"

  # Strip the markers the same way in both trees so the wrap fires on rerun.
  sed -i '/<!-- Project-specific rules and plugin routing blocks/,$d' "$RERUN_SH/CLAUDE.md"
  sed -i '/<!-- Project-specific rules and plugin routing blocks/,$d' "$RERUN_PS/CLAUDE.md"

  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$RERUN_SH" --default-branch develop --wrap-existing-claude-md \
    > "$TMPROOT/rerun-sh-2.out" 2>&1
  "$PSBIN" -NoProfile -ExecutionPolicy Bypass -File "$ROOT/setup-project.ps1" \
    -Variant general -ProjectName SetupFixture -TargetPath "$RERUN_PS" \
    -DefaultBranch develop -WrapExistingClaudeMd > "$TMPROOT/rerun-ps-2.out" 2>&1
  cp "$RERUN_SH/.claude/template-manifest.json" "$TMPROOT/rerun-sh-manifest-2.json"
  cp "$RERUN_PS/.claude/template-manifest.json" "$TMPROOT/rerun-ps-manifest-2.json"

  RERUN_CHECK="$TMPROOT/rerun-check.cjs"
  cat > "$RERUN_CHECK" <<'NODE_EOF'
const fs = require("fs");
const [, , m1Path, m2Path] = process.argv;
const m1 = JSON.parse(fs.readFileSync(m1Path, "utf8"));
const m2 = JSON.parse(fs.readFileSync(m2Path, "utf8"));
const k1 = Object.keys(m1.files);
const k2 = new Set(Object.keys(m2.files));

// Row 1: the discriminating row -- fails today. The second manifest's keys
// must be a SUPERSET of the first's; nothing this run left untouched may
// disappear from `files`.
const lost = k1.filter((k) => !k2.has(k));
console.log(`ROW1: ${lost.length ? "FAIL lost keys: " + lost.join(", ") : "PASS"}`);

// Row 2: an untouched entry -- anything but CLAUDE.md, which this run DID
// rewrite -- is byte-identical (same ownership, same hash) across the runs.
const untouchedKey = k1.find((k) => k !== "CLAUDE.md");
if (!untouchedKey) {
  console.log("ROW2: FAIL no untouched key to compare");
} else {
  const same = JSON.stringify(m1.files[untouchedKey]) === JSON.stringify(m2.files[untouchedKey]);
  console.log(`ROW2: ${same ? "PASS" : "FAIL " + untouchedKey + " changed"}`);
}

// Row 3: the touched entry (CLAUDE.md) has a refreshed hash -- its content
// genuinely changed (old body moved inside a new PROJECT-CUSTOM region).
const c1 = m1.files["CLAUDE.md"];
const c2 = m2.files["CLAUDE.md"];
if (!c1 || !c2) {
  console.log("ROW3: FAIL CLAUDE.md entry missing from one of the manifests");
} else if (c1.hash === c2.hash) {
  console.log("ROW3: FAIL hash did not change across the wrap rerun");
} else {
  console.log("ROW3: PASS");
}
NODE_EOF

  RERUN_SH_RESULTS="$(node "$RERUN_CHECK" "$TMPROOT/rerun-sh-manifest-1.json" "$TMPROOT/rerun-sh-manifest-2.json" 2>&1)"
  RERUN_PS_RESULTS="$(node "$RERUN_CHECK" "$TMPROOT/rerun-ps-manifest-1.json" "$TMPROOT/rerun-ps-manifest-2.json" 2>&1)"
  rerun_row() { echo "$1" | grep "^$2:" | head -1; }

  expect "sh rerun: second manifest is a superset of the first (row 1)" "ROW1: PASS" "$(rerun_row "$RERUN_SH_RESULTS" ROW1)"
  expect "sh rerun: an untouched entry is byte-identical across runs (row 2)" "ROW2: PASS" "$(rerun_row "$RERUN_SH_RESULTS" ROW2)"
  expect "sh rerun: touched entry's hash was refreshed (row 3)" "ROW3: PASS" "$(rerun_row "$RERUN_SH_RESULTS" ROW3)"
  expect "ps1 rerun: second manifest is a superset of the first (row 1)" "ROW1: PASS" "$(rerun_row "$RERUN_PS_RESULTS" ROW1)"
  expect "ps1 rerun: an untouched entry is byte-identical across runs (row 2)" "ROW2: PASS" "$(rerun_row "$RERUN_PS_RESULTS" ROW2)"
  expect "ps1 rerun: touched entry's hash was refreshed (row 3)" "ROW3: PASS" "$(rerun_row "$RERUN_PS_RESULTS" ROW3)"

  # --- v3.1 Phase 3: .claude/rules/project.md is seeded once, then left alone ---
  #
  # `once` ownership, no hash key at all (it is never rewritten so there is
  # nothing to hash against), and a rerun over the same target must not touch
  # it even where the rerun DOES touch other files (the CLAUDE.md wrap above).
  RULES_SH="$RERUN_SH/.claude/rules/project.md"
  RULES_PS="$RERUN_PS/.claude/rules/project.md"
  expect "sh: .claude/rules/project.md created" 1 "$([ -f "$RULES_SH" ] && echo 1 || echo 0)"
  expect "ps1: .claude/rules/project.md created" 1 "$([ -f "$RULES_PS" ] && echo 1 || echo 0)"
  SH_M2="$TMPROOT/rerun-sh-manifest-2.json"
  PS_M2="$TMPROOT/rerun-ps-manifest-2.json"
  RULES_CHECK="$TMPROOT/rules-check.cjs"
  cat > "$RULES_CHECK" <<'NODE_EOF'
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const e = m.files[".claude/rules/project.md"];
if (!e) { console.log("FAIL entry missing"); }
else if (e.ownership !== "once") { console.log(`FAIL ownership is "${e.ownership}"`); }
else if (Object.prototype.hasOwnProperty.call(e, "hash")) { console.log("FAIL once entry carries a hash key"); }
else { console.log("PASS"); }
NODE_EOF
  expect "sh: .claude/rules/project.md is once/no-hash in the manifest" "PASS" "$(node "$RULES_CHECK" "$SH_M2")"
  expect "ps1: .claude/rules/project.md is once/no-hash in the manifest" "PASS" "$(node "$RULES_CHECK" "$PS_M2")"

  # A user edit is the real test of "seed once, then leave alone" -- an
  # unchanged file would pass a naive comparison even if the script silently
  # regenerated it from the template. Edit it, rerun (the wrap flag proves the
  # rerun DOES write other files), and the edit must survive verbatim.
  printf '\nMY CUSTOM RULE\n' >> "$RULES_SH"
  printf '\nMY CUSTOM RULE\n' >> "$RULES_PS"
  RULES_SH_BEFORE="$(cat "$RULES_SH")"
  RULES_PS_BEFORE="$(cat "$RULES_PS")"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$RERUN_SH" --default-branch develop --wrap-existing-claude-md \
    > "$TMPROOT/rerun-sh-3.out" 2>&1
  "$PSBIN" -NoProfile -ExecutionPolicy Bypass -File "$ROOT/setup-project.ps1" \
    -Variant general -ProjectName SetupFixture -TargetPath "$RERUN_PS" \
    -DefaultBranch develop -WrapExistingClaudeMd > "$TMPROOT/rerun-ps-3.out" 2>&1
  expect "sh: user edit to project.md survives a rerun that touches other files" "$RULES_SH_BEFORE" "$(cat "$RULES_SH")"
  expect "ps1: user edit to project.md survives a rerun that touches other files" "$RULES_PS_BEFORE" "$(cat "$RULES_PS")"

  # --- the no-.git arm: the actual regression test for :861 -----------------
  #
  # A toolkit extracted without .git (a ZIP download, not a clone) is the
  # measured trigger: PS 5.1 turns git's stderr for "not a git repository"
  # into a terminating error under `Stop`, and the script exits 1 after most
  # files are already written but before the manifest and the auto-mode
  # snippet -- a bootstrap that LOOKS complete and can never sync.
  #
  # `setup-project.sh`'s own :844 already tolerates this
  # (`2>/dev/null || echo "unknown"`) and is the paired control: same
  # no-.git source tree, same target shape, asserted to exit 0 with a
  # manifest and the same file count as the .ps1 arm.
  NOGITSRC="$TMPROOT/nogit-src"
  mkdir -p "$NOGITSRC"
  # Copy the toolkit tree the two scripts actually ship from (setup-project.sh,
  # setup-project.ps1, templates/, scripts/, user-level-reference/), never the
  # harness's own temp/worktree scaffolding -- and drop `.git` so the fixture
  # models the ZIP-download shape the defect was measured against.
  cp "$ROOT/setup-project.sh" "$ROOT/setup-project.ps1" "$NOGITSRC/"
  cp -r "$ROOT/templates" "$ROOT/scripts" "$ROOT/user-level-reference" "$NOGITSRC/"
  rm -rf "$NOGITSRC/.git"

  NOGITSH="$TMPROOT/nogit-sh"
  NOGITPS="$TMPROOT/nogit-ps"
  mkdir -p "$NOGITSH" "$NOGITPS"
  bash "$NOGITSRC/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$NOGITSH" > "$TMPROOT/nogit-sh.out" 2>&1
  NOGIT_SH_RC=$?
  "$PSBIN" -NoProfile -ExecutionPolicy Bypass -File "$NOGITSRC/setup-project.ps1" \
    -Variant general -ProjectName SetupFixture -TargetPath "$NOGITPS" \
    > "$TMPROOT/nogit-ps.out" 2>&1
  NOGIT_PS_RC=$?

  expect "sh control: exits 0 on a no-.git toolkit" 0 "$NOGIT_SH_RC"
  expect "ps1: exits 0 on a no-.git toolkit (was 1)" 0 "$NOGIT_PS_RC"

  NOGIT_SH_MANIFEST="$NOGITSH/.claude/template-manifest.json"
  NOGIT_PS_MANIFEST="$NOGITPS/.claude/template-manifest.json"
  [ -f "$NOGIT_SH_MANIFEST" ] && got_sh_manifest=1 || got_sh_manifest=0
  [ -f "$NOGIT_PS_MANIFEST" ] && got_ps_manifest=1 || got_ps_manifest=0
  expect "sh control: manifest written on a no-.git toolkit" 1 "$got_sh_manifest"
  expect "ps1: manifest written on a no-.git toolkit (was absent)" 1 "$got_ps_manifest"

  NOGIT_SH_COUNT=$(find "$NOGITSH" -type f | wc -l | tr -d ' ')
  NOGIT_PS_COUNT=$(find "$NOGITPS" -type f | wc -l | tr -d ' ')
  expect "ps1 file count matches sh on a no-.git toolkit" "$NOGIT_SH_COUNT" "$NOGIT_PS_COUNT"

  # template_version when it CANNOT be determined. This source tree carries no
  # VERSION file (the copy above takes the scripts, templates and reference
  # trees, not VERSION), so both writers take the fallback branch -- the branch
  # that shipped a truthy "unknown" string past every previous run because
  # nothing asserted on it. The v3 contract says null here, and the sync server
  # emits null from the same condition, so a consumer testing `is None` must
  # see null from BOTH writers. Asserted as a JSON type, not a string compare:
  # "null" and null are the failure this row exists to tell apart.
  NOGIT_TV_CHECK="$TMPROOT/nogit-tv.js"
  cat > "$NOGIT_TV_CHECK" <<'TV_EOF'
const fs = require("fs");
const [, , shPath, psPath] = process.argv;
for (const [label, p] of [["sh", shPath], ["ps1", psPath]]) {
  let verdict;
  try {
    const v = JSON.parse(fs.readFileSync(p, "utf8")).template_version;
    verdict = v === null ? "null" : `${typeof v}:${JSON.stringify(v)}`;
  } catch (e) {
    verdict = `unreadable:${e.message}`;
  }
  console.log(`${label} ${verdict}`);
}
TV_EOF
  NOGIT_TV_OUT="$(node "$NOGIT_TV_CHECK" "$NOGIT_SH_MANIFEST" "$NOGIT_PS_MANIFEST" 2>&1)"
  expect "sh: template_version is JSON null when VERSION is absent" \
    "null" "$(printf '%s\n' "$NOGIT_TV_OUT" | awk '$1=="sh"{print $2}')"
  expect "ps1: template_version is JSON null when VERSION is absent" \
    "null" "$(printf '%s\n' "$NOGIT_TV_OUT" | awk '$1=="ps1"{print $2}')"
else
  skip "setup-project.ps1 parity" "no PowerShell on this host" 8
  skip "setup-project.ps1 no-.git bootstrap" "no PowerShell on this host" 7
fi

echo "----------------------------------------------------------------"
echo "test-setup-project.sh: $pass passed, $fail failed, $skipped skipped ($((pass + fail + skipped)) assertions)"
[ "$fail" -eq 0 ] || exit 1
echo "ALL SETUP FIXTURES PASSED"
exit 0
