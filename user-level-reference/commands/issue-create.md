# /issue-create - Create GitHub Issue

Create a properly formatted GitHub issue using MCP tools.

## Arguments

- `$ARGUMENTS` - Issue title or description (optional)

## Workflow

1. **Get repository info**
   - Call `gh_repo_from_origin(repo_path)` to get OWNER/REPO
   - If not in a git repo, ASK user for the repository

2. **Check for duplicates**
   - Call `gh_issue_list(repo, state="open", limit=20)`
   - Search for issues with similar titles or content
   - If potential duplicate found, WARN user before proceeding

3. **Gather issue details**
   - If `$ARGUMENTS` provided, use as starting point
   - Otherwise, ASK user for:
     - Title (short, action-oriented)
     - Problem description
     - Acceptance criteria
     - Any relevant context/links

4. **Format issue body**
   ```markdown
   ## Problem
   [Clear description of the issue]

   ## Acceptance Criteria
   - [ ] [Criterion 1]
   - [ ] [Criterion 2]

   ## Notes
   [Additional context, links, or technical details]
   ```

5. **Create issue**
   - Call `gh_issue_create(repo, title, body, labels)`
   - Only use labels that exist in the repo (omit if unsure)
   - Report the new issue URL to user

## Rules

- MUST use MCP GitHub tools, NOT `gh` CLI or curl
- MUST check for duplicates before creating
- MUST NOT create issues without user confirmation of content
- MUST NOT guess labels - only use known repo labels
