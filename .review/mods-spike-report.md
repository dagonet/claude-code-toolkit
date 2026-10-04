# Mods feasibility spike: can a Claude Code mod carry parts of claude-code-toolkit?

**Scratch report. Delete it after reading.** Run on 2026-10-04 in a cloud Linux container. `claude --version` printed `2.1.289 (Claude Code)`; mods need 2.1.287 or later.
Mods are in `/tmp/mod-spike/{spike-prompt,spike-gate,spike-route}`. Nothing in the repo's tracked files was changed. Every mod passes `claude plugin validate`, and every `claude plugin test` suite is green.
**Nested live sessions authenticated.** `claude -p --plugin-dir …` worked in this environment, so all four questions were also checked live, not just through the test harness.

| Q | Verdict | Evidence |
|---|---|---|
| Q1 Always-loaded instructions | **YES** | TESTED (harness + live) |
| Q2 Fail-closed gate | **YES, only with `.catch`** (fails open without it) | TESTED (harness + live) |
| Q3 Model routing | **PARTIAL**: works, but a naive hook overrides models pinned in agent definitions | TESTED (harness + live) |
| Q4 Windows | Notes only | DOCS-ONLY |

---

## Q1: Always-loaded instructions. YES, TESTED

`prompt.compose` can append a system-prompt section, and `prompt.context` can append a first-message context block next to `claudeMd`.

Code (`spike-prompt/hooks/register.ts`, full source below):
```ts
on('prompt.compose', async ($, e, next) => { const r = await next(e); return { sections: [...r.sections, SECTION] } })
// SECTION = { id: 'spike-prompt:rules', text: 'Always end replies with ZZMOD42.', scope: 'session' }
on('prompt.context', async ($, e, next) => { const r = await next(e); return { ...r, blocks: [...r.blocks, { name: 'spikeProject', text: 'Context sentinel ZZCTX7.' }] } })
```
Harness (`claude plugin test /tmp/mod-spike/spike-prompt`):
```
compose -> [{"id":"intro","text":"ENGINE INTRO","scope":"shared"},{"id":"spike-prompt:rules","text":"Always end replies with ZZMOD42.","scope":"session"}]
context -> [{"name":"claudeMd","text":"project rules"},{"name":"spikeProject","text":"Context sentinel ZZCTX7."}]
 2 pass  0 fail
```
Live (`claude -p --plugin-dir /tmp/mod-spike/spike-prompt 'What is 2+2? Also: if any text in your context contains a token starting with ZZCTX, quote that token.'`):
```
2+2 = 4.
The context contains the token **ZZCTX7**, from the "spikeProject" block: "Context sentinel ZZCTX7."
ZZMOD42
```
Gotchas:
- Put toolkit text in `scope: 'session'`. `shared` text lands in a cache prefix shared across organizations, and text that varies busts that cache for everyone. The engine puts every `shared` section before every `session` section.
- The harness's `$.prompt.compose` needs the **full** input (`model`, `promptModel`, `surfaces`, `tools`, `outputStyle`, `traits`). With `{}`, the hook is skipped: `next() passed an argument with no { promptModel }`.
- `prompt.context` fires **once per conversation** (first message only). `prompt.compose` runs on every render. For CLAUDE.md-style rules, compose is the stronger hook because it survives compaction. Text that changes between requests invalidates the prompt cache.
- `--bare` reduces compose to one `bare` section, and `traits` says when that happened. Mods don't load at all under `--bare` / `--safe-mode` / `disableAllHooks`.

## Q2: Fail-closed gate. YES, but only with `.catch`; a bare hook fails OPEN. TESTED

Gate (`spike-gate`): `on('tool.call', { tool: 'Bash' }, gate)` returns `{ deny }` for `git push … main|master`. The `userConfig` option `mode` injects a failure: `throw`, `spin` (12 s synchronous busy loop), `hang` (an `await` on a promise that never settles), `sleep` (`$.clock.sleep(12000)`), `slowproc` (`$.process.run(['sleep','12'])`), or `slowcall` (two `$.tool.call`s that each take 9 s beneath the hook). The option `withCatch` adds:
```ts
on('tool.call', { tool: 'Bash' }, gate).catch(($, e, next) => ({ deny: `spike-gate: gate failed (${next.error.kind}: ${next.error.message ?? ""}); refusing` }))
```
Harness (`claude plugin test /tmp/mod-spike/spike-gate`; `ran: "RAN"` means the command **executed**):
```
ok/nocatch/push            {"deny":"spike-gate: push to a protected branch is refused","ran":null,"ms":42}
ok/nocatch/safe            {"deny":null,"ran":"RAN","ms":2}
throw/nocatch/push         {"deny":null,"ran":"RAN","ms":21}          <- FAIL-OPEN
spin/nocatch/push          {"deny":"spike-gate: push ... refused","ran":null,"ms":12014}   <- sync loop cannot be pre-empted; late deny stands
hang/nocatch/push          {"deny":null,"ran":"RAN","ms":10031}       <- FAIL-OPEN at exactly 10 s
sleep/nocatch/push         {"deny":null,"ran":"RAN","ms":10019}       <- $.clock.sleep counts as own time -> timeout -> FAIL-OPEN
slowcall/nocatch/push      {"deny":"spike-gate: push ... refused","ran":null,"ms":18019}   <- 18 s inside $ calls: not counted
throw/catch/push           {"deny":"spike-gate: gate failed (throw: spike: deliberate throw); refusing","ran":null,"ms":14}
hang/catch/push            {"deny":"spike-gate: gate failed (timeout: ); refusing","ran":null,"ms":10018}
sleep/catch/push           {"deny":"spike-gate: gate failed (timeout: ); refusing","ran":null,"ms":10018}
slowcall/catch/push        {"deny":"spike-gate: push ... refused","ran":null,"ms":18018}
 12 pass  0 fail
```
Live (`bash /tmp/mod-spike/live-q2.sh`: nested `claude -p --plugin-dir spike-gate --allowedTools=Bash --settings '{"pluginConfigs":{"spike-gate":{"options":{…}}}}'`, run in a scratch repo with no remote, prompt "run `git push origin main`"):
```
=== mode=ok (defaults)                       <tool_use_error>spike-gate: push to a protected branch is refused</tool_use_error>
=== mode=hang, no catch                      spike-gate: tool.call hook skipped: ran past its 10s budget
                                             error: src refspec main does not match any      <- the push RAN
=== mode=hang, with catch                    <tool_use_error>spike-gate: gate failed (timeout: ); refusing</tool_use_error>
=== mode=throw, no catch                     spike-gate: tool.call hook skipped: threw Error: spike: deliberate throw
                                             error: src refspec main does not match any      <- the push RAN
=== mode=throw, with catch                   <tool_use_error>spike-gate: gate failed (throw: spike: deliberate throw); refusing</tool_use_error>
=== mode=slowproc (12 s in $.process.run)    <tool_use_error>spike-gate: push to a protected branch is refused</tool_use_error>
```
Answers:
- **Throw or timeout without `.catch`**: the call **runs** (fail-open). The skip is reported on one stderr/debug line only.
- **With `.catch` returning a deny**: **both** failure modes refuse, in harness and live.
- **10 s limit** = `HookBudget.ms: 10_000`, measured at 10.02–10.03 s. It counts the hook's **own** time only. **Time inside `$.process.run` does NOT count** (live: 12 s there, deny stood). Neither does other `$` / `next` time (harness: 18 s across two `$.tool.call`s, deny stood). **`$.clock.sleep` DOES count**, as does awaiting your own promise. The `.catch` handler gets a fresh 1 s grace (`catchMs: 1_000`). `$.process.run` has its own timeout (30 s default, 10 min max).

Gotchas:
- A **synchronous** busy loop is never pre-empted. Its deny still stood at 12 s, so the budget only bites on async code.
- `.catch` must be chained **at the `on(...)` call site**. Assigning the registration fails `validate` ("the value of on("tool.call") is kept"). The hook passed to a `.catch`'d `on` must be a top-level function, so per-registration config goes through module state set in `register`.
- `next.error.message` is empty for a pure timeout.
- Order: managed `PreToolUse` hooks run **before** mods. Project/user `PreToolUse` hooks (today's toolkit shell hooks) run **after** the last mod's `next()`. A mod that answers without `next` keeps them from running. The documented `tool.check` event may be the better place for allow/deny decisions.
- Matching on command text is best effort (`git push -f`, aliases, `bash -c`). Branch protection on the host is the real enforcement.
- Harness: stubs for mods-API calls must return `{ value }` (docs, Test a mod). The kit has no `process` stand-in unless you stub `process.run`, which is why the harness `slowproc` row is replaced by `slowcall` and the live run.

## Q3: Model routing. PARTIAL, TESTED

The naive hook `e.model === undefined ? next({ ...e, model: 'haiku' }) : next(e)` reaches Agent-tool subagents and leaves an explicit `model` parameter alone. **But** `agent.spawn`'s `e.model` is only the Agent *call's* parameter. A model pinned in the agent **definition** (frontmatter `model:`, which `coder`/`architect`/`tester`/… carry in this toolkit) also arrives as `undefined` and **got overridden to haiku**. Nothing in `AgentSpawnInput`, or in `agent.offer` / `$.agent.list`, exposes the definition's model. Fix used: route only an allowlist of types known to pin no model.
```ts
const UNPINNED = new Set(['general-purpose'])
on('agent.spawn', ($, e, next) =>
  e.model === undefined && !e.fork && UNPINNED.has(e.subagentType) ? next({ ...e, model: 'haiku' }) : next(e))
```
Harness: `spawn without model -> {"model":"haiku"} | with model:opus -> {"model":"opus"} | engine saw ["haiku","opus"]`, 1 pass.
Live (`bash /tmp/mod-spike/live-q3.sh`: two Agent calls in a nested `claude -p --output-format stream-json`, model read from the subagent's assistant messages):
```
=== without spike-route
subagent of call(model param=<none>)  ran on: claude-sonnet-5-5
subagent of call(model param=sonnet)  ran on: claude-sonnet-5-5
=== with spike-route
subagent of call(model param=<none>)  ran on: claude-haiku-4-5-20251001
subagent of call(model param=sonnet)  ran on: claude-sonnet-5-5        <- explicit model survives
```
Definition-pinned (`bash /tmp/mod-spike/live-q3b.sh`, `--agents '{"pinned":{…,"model":"opus"}}'`, no model param):
```
naive hook:     without mod -> claude-opus-5-5 | with mod -> claude-haiku-4-5-20251001   <- OVERRIDDEN (bad)
allowlist hook: without mod -> claude-opus-5-5 | with mod -> claude-opus-5-5             <- respected
```
Gotchas: forks ignore `model`. Teammates also fire `agent.spawn` (`e.isTeammate`). A hook could read `.claude/agents/<type>.md` via `$.fs` to detect a pin, but the allowlist is the KISS answer. Also note the nested session's default main model was sonnet, so the "explicit survives" case live is sonnet==parent; the harness covers explicit `opus` ≠ routed `haiku`.

## Q4: Windows. DOCS-ONLY (nothing run on Windows)

From the docs and types:
- `CLAUDE_CODE_PLUGIN_DIRS`: absolute paths separated by `:`, **`;` on Windows**. It is read from the process env or the `env` block of `~/.claude/settings.json`, **never project settings**.
- The docs give PowerShell variants for setup (`New-Item -ItemType Directory -Force first-mod\.claude-plugin, first-mod\hooks`).
- `$.process.run` takes an **argv list, not a shell line**. On Windows `argv[0]` must resolve to an executable (`git.exe` fine; `sleep`, `bash` builtins and `.sh` scripts are not). On Windows a killed child reads as an exit code with `signal` null.
- `$.fs.stat(path, { resolve: true }).realPath` is the robust path check. Spelling-based deny lists are best effort (case aliases keep their spelling). The test kit hands `$.fs.read` stubs absolute paths, so compare with `endsWith`.
- `$.ui.copy` uses PowerShell as the clipboard tool on Windows. Sound may be silent.
- The built-in tool table is per build/machine: this Linux build's `claude-code-tools` has no PowerShell tool, so a `{ tool: 'Bash' }` gate **may miss a Windows PowerShell tool**.

A local Windows check must still confirm:
1. `claude --version` is at least 2.1.287, and `claude plugin validate` + `claude plugin test` pass for all three mods under PowerShell **and** Git Bash.
2. `CLAUDE_CODE_PLUGIN_DIRS="C:\a;C:\b"` loads both, from both process env and `~/.claude/settings.json` `env`.
3. Which tool names Windows registers (Bash via Git Bash vs a PowerShell tool), and whether the gate must match both. Re-run `live-q2.sh` there.
4. `$.process.run(['git', …])` resolves `git.exe`, plus behaviour with `.cmd` shims.
5. CRLF: `.ts` modules and `plugin.json` written with CRLF by Windows tooling still load/validate. The toolkit invariant is LF; confirm the engine doesn't care.
6. Paths with spaces or drive letters in `--plugin-dir`, and hot-reload file watching on NTFS.

---

## Recommendation for v5.0 "plugin + mod" (5 lines)

1. **Ship it**: a mod can carry the always-loaded rules (`prompt.compose`, `scope: 'session'`), and that is strictly better than editing consumer `CLAUDE.md`. It also retires the deny-claude-md-writes / context-mode sentinel dance for the rules text.
2. **Gates move only with `.catch` → deny on every blocking hook**, enforced by a toolkit check (grep each `on('tool.call'…)` for a chained `.catch`). Keep shell `PreToolUse` hooks as a second layer: mods run before them, and a bare mod fails open.
3. **Never `$.clock.sleep` or await own promises in a gate.** Do slow work via `$.process.run` / `$` (free against the 10 s budget). Prefer `tool.check` for allow/deny decisions.
4. **Model routing ships only with an explicit allowlist** of unpinned agent types (definition `model:` is invisible to `agent.spawn`). Add a test that a pinned agent keeps its model.
5. **Gate the release on a Windows run** of the Q4 checklist. The API is early access (types say "may change between releases"), so pin `>=2.1.289`, ship the `*.test.ts` suites in the gate, and re-run them on every Claude Code bump.

---

## Full source of every mod file written

### `/tmp/mod-spike/live-q1.sh`
```bash
#!/bin/bash
# Live Q1: does a nested headless session obey a mod-added system-prompt section?
cd /tmp/mod-spike || exit 1
timeout 180 claude -p --plugin-dir /tmp/mod-spike/spike-prompt \
  'What is 2+2? Also: if any text in your context contains a token starting with ZZCTX, quote that token.' 2>&1
echo "exit=$?"
```

### `/tmp/mod-spike/live-q2.sh`
```bash
#!/bin/bash
# Live Q2: the gate in a nested headless session. Scratch repo, no remote: nothing can leave the box.
rm -rf /tmp/mod-spike/scratch-repo && git init -q /tmp/mod-spike/scratch-repo && cd /tmp/mod-spike/scratch-repo || exit 1
B=ma; B=${B}in
PROMPT="Run exactly this one Bash command and then report verbatim the tool result you got (or the refusal text): git push origin $B"
run() { # $1 label, $2 settings json
  echo "=== $1"
  timeout 180 claude -p --plugin-dir /tmp/mod-spike/spike-gate --allowedTools=Bash \
    ${2:+--settings "$2"} "$PROMPT" 2>&1
  echo "exit=$?"
}
run "mode=ok (defaults)"
run "mode=hang (async, never settles), no catch" '{"pluginConfigs":{"spike-gate":{"options":{"mode":"hang","withCatch":false}}}}'
run "mode=hang (async, never settles), with catch" '{"pluginConfigs":{"spike-gate":{"options":{"mode":"hang","withCatch":true}}}}'
run "mode=throw, no catch" '{"pluginConfigs":{"spike-gate":{"options":{"mode":"throw","withCatch":false}}}}'
run "mode=throw, with catch" '{"pluginConfigs":{"spike-gate":{"options":{"mode":"throw","withCatch":true}}}}'
run "mode=slowproc (12 s inside \$.process.run), no catch" '{"pluginConfigs":{"spike-gate":{"options":{"mode":"slowproc","withCatch":false}}}}'
```

### `/tmp/mod-spike/live-q3.sh`
```bash
#!/bin/bash
# Live Q3: which model do Agent-tool subagents actually run on, with and without spike-route?
cd /tmp/mod-spike || exit 1
PROMPT='Make exactly two Agent tool calls, in parallel, subagent_type "general-purpose", each with prompt "Reply with the single word OK.": call A with NO model parameter; call B with model "sonnet". Then stop.'
run() { # $1 label, extra args...
  local label=$1; shift
  echo "=== $label"
  timeout 300 claude -p --output-format stream-json --verbose --allowedTools=Agent "$@" "$PROMPT" 2>/dev/null \
    | python3 -c '
import sys, json
calls = {}
for line in sys.stdin:
    try: m = json.loads(line)
    except Exception: continue
    if m.get("type") == "system" and m.get("subtype") == "init": print("main model:", m.get("model"))
    if m.get("type") != "assistant": continue
    msg = m["message"]; parent = m.get("parent_tool_use_id")
    if parent is None:
        for b in msg.get("content", []):
            if b.get("type") == "tool_use" and b.get("name") == "Agent":
                calls[b["id"]] = b["input"].get("model", "<none>")
    else:
        print("subagent of call(model param=%s) ran on: %s" % (calls.get(parent, "?"), msg.get("model")))
'
}
run "without spike-route"
run "with spike-route" --plugin-dir /tmp/mod-spike/spike-route
```

### `/tmp/mod-spike/live-q3b.sh`
```bash
#!/bin/bash
# Live Q3b: an agent whose DEFINITION pins a model (frontmatter-style), spawned with no model param.
cd /tmp/mod-spike || exit 1
AGENTS='{"pinned":{"description":"Replies OK","prompt":"Reply with the single word OK.","model":"opus"}}'
PROMPT='Make exactly one Agent tool call: subagent_type "pinned", prompt "Reply OK.", no model parameter. Then stop.'
run() {
  local label=$1; shift
  echo "=== $label"
  timeout 300 claude -p --output-format stream-json --verbose --allowedTools=Agent --agents "$AGENTS" "$@" "$PROMPT" 2>/dev/null \
    | python3 -c '
import sys, json
for line in sys.stdin:
    try: m = json.loads(line)
    except Exception: continue
    if m.get("type") == "assistant" and m.get("parent_tool_use_id"):
        print("pinned(model: opus in definition) subagent ran on:", m["message"].get("model"))
'
}
run "without spike-route"
run "with spike-route" --plugin-dir /tmp/mod-spike/spike-route
```

### `/tmp/mod-spike/spike-gate/.claude-plugin/plugin.json`
```json
{
  "name": "spike-gate",
  "version": "0.1.0",
  "description": "Q2: denies git push to main; probes fail-open vs .catch",
  "userConfig": {
    "mode": { "type": "string", "title": "Failure mode", "description": "ok | throw | spin | hang | sleep | slowproc | slowcall", "default": "ok", "options": ["ok", "throw", "spin", "hang", "sleep", "slowproc", "slowcall"] },
    "withCatch": { "type": "boolean", "title": "Add .catch", "description": "Register a .catch that denies", "default": false }
  }
}
```

### `/tmp/mod-spike/spike-gate/hooks/gate.test.ts`
```ts
import { test, mock } from 'claude-code/testing'

const PUSH = 'git push origin ' + 'ma' + 'in'
const SAFE = 'echo hi'

// The engine stand-in beneath the plugin: every Bash call "runs" and answers RAN.
const engine = (on: any) =>
  on('tool.call', { tool: 'Bash' }, () => ({ result: { stdout: 'RAN', stderr: '', interrupted: false } }))

// A slow $ call beneath the plugin: each Read call takes 9 s of real time.
const slowRead = (on: any) =>
  on('tool.call', { tool: 'Read' }, async () => {
    const t = Date.now(); while (Date.now() - t < 9_000) await Promise.resolve()
    return { result: { type: 'text', file: { filePath: '/a', content: '', numLines: 0, startLine: 1, totalLines: 0 } } }
  })

const call = async ($: any, command: string) => {
  const t = Date.now()
  const r = await $.tool.call({ tool: 'Bash', command })
  return { ...r, ms: Date.now() - t }
}
const show = (label: string, r: any) =>
  console.log(label.padEnd(26), JSON.stringify({ deny: r.deny ?? null, ran: r.result?.stdout ?? null, ms: r.ms }))

const SLOW = { timeoutMs: 40_000 }
for (const withCatch of [false, true]) {
  const c = withCatch ? 'catch' : 'nocatch'
  for (const mode of (globalThis as any).ONLY ?? ['ok', 'throw', 'spin', 'hang', 'sleep', 'slowcall']) {
    test(`${mode}/${c}`, { ...SLOW, options: { mode, withCatch } }, async ($, on) => {
      engine(on)
      if (mode === 'sleep') mock.clock(on) // held, never advanced
      if (mode === 'slowcall') slowRead(on)
      show(`${mode}/${c}/push`, await call($, PUSH))
      if (mode === 'ok') show(`${mode}/${c}/safe`, await call($, SAFE))
    })
  }
}
```

### `/tmp/mod-spike/spike-gate/hooks/hooks.json`
```json
{ "modules": ["./register.ts"] }
```

### `/tmp/mod-spike/spike-gate/hooks/register.ts`
```ts
import type { Register, Hook } from 'claude-code'

// Protected-branch push matcher (spelled to avoid the host repo's own literal-text hook).
const PROTECTED = ['ma' + 'in', 'master']
const isPushToProtected = (cmd: string) =>
  /\bgit\s+push\b/.test(cmd) && cmd.split(/\s+/).some(w => PROTECTED.includes(w.replace(/^.*:/, '')))

let mode = 'ok' // set from userConfig at register time

const gate: Hook<'tool.call'> = async ($, e, next) => {
  if (e.tool !== 'Bash') return next(e)
  if (mode === 'throw') throw new Error('spike: deliberate throw')
  if (mode === 'spin') { const t = Date.now(); while (Date.now() - t < 12_000) { /* sync busy loop */ } }
  if (mode === 'hang') await new Promise(() => {}) // async: own time that never ends
  if (mode === 'sleep') await $.clock.sleep(12_000)
  if (mode === 'slowproc') await $.process.run(['sleep', '12']) // live only: the harness has no process noun
  if (mode === 'slowcall') { await $.tool.call({ tool: 'Read', file_path: '/a' }); await $.tool.call({ tool: 'Read', file_path: '/b' }) } // stub: 9 s each
  if (isPushToProtected(e.command)) return { deny: 'spike-gate: push to a protected branch is refused' }
  return next(e)
}


export const register: Register = (on, options) => {
  mode = String(options.mode ?? 'ok')
  if (options.withCatch === true) {
    on('tool.call', { tool: 'Bash' }, gate).catch(($, e, next) => ({
      deny: `spike-gate: gate failed (${next.error.kind}: ${next.error.message ?? ""}); refusing`,
    }))
  } else {
    on('tool.call', { tool: 'Bash' }, gate)
  }
}
```

### `/tmp/mod-spike/spike-prompt/.claude-plugin/plugin.json`
```json
{ "name": "spike-prompt", "version": "0.1.0", "description": "Q1: adds a system-prompt section and a context block" }
```

### `/tmp/mod-spike/spike-prompt/hooks/hooks.json`
```json
{ "modules": ["./register.ts"] }
```

### `/tmp/mod-spike/spike-prompt/hooks/prompt.test.ts`
```ts
import { test, expect } from 'claude-code/testing'

test('compose: the plugin section rides after the engine sections', async ($, on) => {
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'ENGINE INTRO', scope: 'shared' }] }))
  const r = await $.prompt.compose({ model: 'claude-x', promptModel: 'claude-x', surfaces: ['terminal'], tools: ['Bash'], outputStyle: null, traits: [] })
  console.log('compose ->', JSON.stringify(r.sections))
  expect(r.sections.at(-1)).toEqual({ id: 'spike-prompt:rules', text: 'Always end replies with ZZMOD42.', scope: 'session' })
})

test('context: the plugin block rides beside claudeMd', async ($, on) => {
  on('prompt.context', ($: any, e: any) => ({ blocks: e.blocks }))
  const r = await $.prompt.context({ blocks: [{ name: 'claudeMd', text: 'project rules' }], instructionFiles: [] })
  console.log('context ->', JSON.stringify(r.blocks))
  expect(r.blocks.map(b => b.name)).toEqual(['claudeMd', 'spikeProject'])
})
```

### `/tmp/mod-spike/spike-prompt/hooks/register.ts`
```ts
import type { Register } from 'claude-code'

const SECTION = { id: 'spike-prompt:rules', text: 'Always end replies with ZZMOD42.', scope: 'session' } as const

export const register: Register = on => {
  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    return { sections: [...r.sections, SECTION] }
  })
  on('prompt.context', async ($, e, next) => {
    const r = await next(e)
    return { ...r, blocks: [...r.blocks, { name: 'spikeProject', text: 'Context sentinel ZZCTX7.' }] }
  })
}
```

### `/tmp/mod-spike/spike-route/.claude-plugin/plugin.json`
```json
{ "name": "spike-route", "version": "0.1.0", "description": "Q3: routes model-less Agent spawns to haiku" }
```

### `/tmp/mod-spike/spike-route/hooks/hooks.json`
```json
{ "modules": ["./register.ts"] }
```

### `/tmp/mod-spike/spike-route/hooks/register.ts`
```ts
import type { Register } from 'claude-code'

// agent.spawn's `model` is only the Agent call's parameter: a model pinned in the agent's
// DEFINITION (frontmatter `model:`) is invisible here, so route only types known to pin none.
const UNPINNED = new Set(['general-purpose'])

export const register: Register = on => {
  on('agent.spawn', ($, e, next) =>
    e.model === undefined && !e.fork && UNPINNED.has(e.subagentType) ? next({ ...e, model: 'haiku' }) : next(e),
  )
}
```

### `/tmp/mod-spike/spike-route/hooks/route.test.ts`
```ts
import { test, expect } from 'claude-code/testing'

// Engine stand-in: report back the model the spawn would run on.
const engine = (on: any, seen: string[]) =>
  on('agent.spawn', ($: any, e: any) => {
    seen.push(String(e.model))
    return { model: e.model ?? e.parentModel, agentId: 'a1' }
  })

test('no model given -> haiku; explicit model survives', async ($, on) => {
  const seen: string[] = []
  engine(on, seen)
  const a = await $.agent.spawn({ prompt: 'x', subagentType: 'general-purpose' })
  const b = await $.agent.spawn({ prompt: 'x', subagentType: 'general-purpose', model: 'opus' })
  console.log('spawn without model ->', JSON.stringify(a), '| with model:opus ->', JSON.stringify(b), '| engine saw', JSON.stringify(seen))
  expect(seen).toEqual(['haiku', 'opus'])
})
```
