# /spec-to-issues - Convert Specification to GitHub Issues

Convert a requirements document or specification into structured GitHub issues.

## Arguments

- `$ARGUMENTS` - Path to spec file, or paste spec text directly

## Workflow

1. **Get specification content**
   - If file path in `$ARGUMENTS`, read the file
   - If text provided, use directly
   - If empty, ASK for specification input

2. **Compress and structure** (for large specs)
   - If > 200 lines, call `local_first_pass(text, goal="extract requirements")`
   - Call `extract_json(text, schema)` with requirements schema:
   ```json
   {
     "features": [{
       "name": "string",
       "description": "string",
       "priority": "must|should|could|wont",
       "acceptance_criteria": ["string"],
       "dependencies": ["string"],
       "estimated_complexity": "small|medium|large"
     }]
   }
   ```

3. **Get repository info**
   - Call `gh_repo_from_origin(repo_path)` to get OWNER/REPO
   - Call `list_issues` to check for existing issues

4. **Check for duplicates**
   - Compare extracted features against existing issues
   - Flag potential duplicates

5. **Present issue plan**
   ```markdown
   ## Issues to Create

   ### Epic: [Main Feature Name]

   #### Issue 1: [Feature Name]
   **Priority:** Must Have
   **Complexity:** Medium
   **Labels:** feature, backend

   **Description:**
   [Feature description]

   **Acceptance Criteria:**
   - [ ] Criterion 1
   - [ ] Criterion 2

   **Dependencies:** None

   ---

   #### Issue 2: ...

   ### Summary
   | Priority | Count |
   |----------|-------|
   | Must Have | 5 |
   | Should Have | 3 |
   | Could Have | 2 |

   ### Potential Duplicates
   - "Issue 3" may overlap with existing #42
   ```

6. **Get approval**
   - ASK user to confirm before creating issues
   - Allow user to modify, skip, or merge items

7. **Create issues**
   - Use `issue_write(method="create")` for each approved issue
   - Apply appropriate labels
   - Link related issues

8. **Report results**
   ```
   ## Created Issues

   | # | Title | Priority |
   |---|-------|----------|
   | #101 | Implement user login | Must |
   | #102 | Add password reset | Should |
   ```

## Issue Template

```markdown
## Description
[Clear description of what needs to be implemented]

## Acceptance Criteria
- [ ] [Specific, testable criterion]
- [ ] [Another criterion]

## Technical Notes
[Any technical considerations or constraints]

## Dependencies
- Depends on #XX (if applicable)

## Priority
[Must Have / Should Have / Could Have]

## Estimated Complexity
[Small / Medium / Large]
```

## Requirements Schema

Use MoSCoW prioritization:
- **Must Have**: Critical for release
- **Should Have**: Important but not critical
- **Could Have**: Desirable if time permits
- **Won't Have**: Explicitly out of scope

## Rules

- MUST extract structured data from spec
- MUST check for duplicate issues before creating
- MUST get user approval before creating issues
- MUST use consistent labels and formatting
- Each issue should be independently implementable
- Link related issues for traceability
