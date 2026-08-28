#!/usr/bin/env bash
# DEPRECATED in v2.0 — agent teams retired; kept as a no-op for one release, removed in v2.1.
#
# This was the TeammateIdle gate for named teammates. v2.0 moved all parallelism
# to the Agent tool: Agent-tool subagents cannot go idle without returning, so
# there is nothing left to gate. PR1 already dropped the TeammateIdle
# registration from every settings.json; the file stays non-empty for one
# release so a downstream settings.json that still references it does not fail
# closed on a 127.
exit 0
