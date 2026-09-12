#!/usr/bin/env node
// ownership-classify.mjs — first-match-wins over the rules in templates/ownership.json.
// Globs: PurePosixPath-style; `**` matches across `/`, `*` within a segment.
// Classifies TEMPLATE-tree relative paths only (spec §4/§6); never consumer files.
// Feed TEMPLATE-relative names, not the project path: the `gitignore` rule is
// `^gitignore$` and will NOT match `.gitignore`. setup-project.sh:581 already
// holds the renamed `.gitignore` in FILE_RELS — classify the template name and
// take the manifest key from column 3 (`target`) when it is not `-`.
//
// Output per path: `<rel-path>\t<ownership>\t<target|->\t<rule-index>`
// rule-index is the 0-based index into rules[] that matched, or `-` if UNCLASSIFIED.
// Exit 0 always — the caller decides pass/fail.
import { readFileSync } from "node:fs";
const [, , tablePath, ...paths] = process.argv;
const table = JSON.parse(readFileSync(tablePath, "utf8"));
function globToRe(g) {
  let re = "^";
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === "*" && g[i + 1] === "*") { re += ".*"; i++; if (g[i + 1] === "/") i++; }
    else if (c === "*") re += "[^/]*";
    else if (".+?^${}()|[]\\".includes(c)) re += "\\" + c;
    else re += c;
  }
  return new RegExp(re + "$");
}
const compiled = table.rules.map((r, idx) => ({ re: globToRe(r.pattern), r, idx }));
for (const p of paths) {
  const hit = compiled.find(x => x.re.test(p));
  if (!hit) { console.log(`${p}\tUNCLASSIFIED\t-\t-`); continue; }
  console.log(`${p}\t${hit.r.ownership}\t${hit.r.target ?? "-"}\t${hit.idx}`);
}
