#!/usr/bin/env node
// manifest-merge.mjs — merge this run's manifest file-entries with the
// entries already on disk, so a rerun that only touches a SUBSET of files
// does not silently reclassify every file it left alone as project-owned.
// (Under manifest v3, absence from `files` means project-owned by
// definition -- see templates/ownership.json and the v3.1 spec.)
//
// Input:  argv[2] = path to the existing manifest.json (may not exist yet,
//                    e.g. the first bootstrap run).
//         stdin   = this run's new entries as TSV lines "key\towner\thash"
//                   (hash column is empty for `once` entries).
// Output: merged entries as TSV lines "key\towner\thash", stdout, sorted by
//         key. New entries win for keys this run wrote; every other old
//         entry is carried forward VERBATIM -- including one whose file no
//         longer exists in the target. Dropping that row would be the same
//         silent reclassification in slower motion; the sync server is the
//         right place to report a vanished file, not this script.
import { readFileSync, existsSync } from "node:fs";

const [, , oldManifestPath] = process.argv;
const stdinText = readFileSync(0, "utf8");

const merged = new Map();

if (oldManifestPath && existsSync(oldManifestPath)) {
  try {
    const old = JSON.parse(readFileSync(oldManifestPath, "utf8"));
    for (const [key, entry] of Object.entries(old.files ?? {})) {
      merged.set(key, [entry.ownership ?? "", entry.hash ?? ""]);
    }
  } catch {
    // Unreadable/corrupt old manifest -- proceed with this run's entries only.
  }
}

for (const line of stdinText.split("\n")) {
  if (!line) continue;
  const [key, own, hash = ""] = line.split("\t");
  if (!key) continue;
  merged.set(key, [own, hash]);
}

for (const key of [...merged.keys()].sort()) {
  const [own, hash] = merged.get(key);
  console.log(`${key}\t${own}\t${hash}`);
}
