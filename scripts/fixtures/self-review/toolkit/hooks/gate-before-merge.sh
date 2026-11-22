# fixture: the file name is the toolkit hook name; the refusal texts below feed the refusal table
echo "BLOCKED: gate-before-merge refuses this operation" >&2
echo "BLOCKED: No gate artifact found. Run '$cmd' on the PR branch head." >&2
echo "BLOCKED: Shared state file unreadable here." >&2
