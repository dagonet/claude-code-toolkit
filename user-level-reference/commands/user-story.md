# /user-story - Generate User Stories

Generate well-structured user stories with acceptance criteria from requirements.

## Arguments

- `$ARGUMENTS` - Feature description or requirement text

## Workflow

1. **Get requirement input**
   - Parse `$ARGUMENTS` for feature description
   - If unclear, ASK for:
     - What is the feature?
     - Who is the primary user?
     - What problem does it solve?

2. **Identify personas**
   - Determine who will use this feature:
     - End User
     - Administrator
     - System (automated)
     - API Consumer
     - etc.

3. **Generate user stories**
   Using the format: "As a [persona], I want [goal], so that [benefit]"

   ```markdown
   ## Feature: [Feature Name]

   ### User Story 1
   **As a** registered user
   **I want to** reset my password via email
   **So that** I can regain access to my account if I forget my password

   #### Acceptance Criteria
   - [ ] User can request password reset from login page
   - [ ] System sends email with reset link within 2 minutes
   - [ ] Reset link expires after 24 hours
   - [ ] User must enter new password twice for confirmation
   - [ ] Password must meet complexity requirements
   - [ ] User receives confirmation email after successful reset
   - [ ] Old password no longer works after reset

   #### Edge Cases
   - [ ] User requests multiple reset links
   - [ ] User tries to use expired link
   - [ ] Email address not found in system
   - [ ] User is locked out

   #### Technical Notes
   - Use secure token generation
   - Rate limit reset requests
   - Log all reset attempts for security audit

   ---

   ### User Story 2
   ...
   ```

4. **Define acceptance criteria**
   Each criterion should be:
   - Specific and measurable
   - Testable (can verify pass/fail)
   - Independent of implementation
   - Written in user terms

5. **Identify edge cases**
   - Error conditions
   - Boundary values
   - Concurrent usage
   - Security scenarios

6. **Add technical notes**
   - Non-functional requirements
   - Security considerations
   - Performance expectations
   - Integration points

7. **Estimate complexity**
   ```
   | Story | Points | Rationale |
   |-------|--------|-----------|
   | Password Reset | 5 | Email integration, security |
   | View Profile | 2 | Simple CRUD |
   ```

8. **Present for review**
   - Full user story document
   - Ask for refinements

## INVEST Criteria

Good user stories follow INVEST:
- **I**ndependent: Can be developed separately
- **N**egotiable: Details can be discussed
- **V**aluable: Delivers value to user
- **E**stimable: Can estimate effort
- **S**mall: Fits in one sprint
- **T**estable: Can verify completion

## Acceptance Criteria Patterns

### Given-When-Then (BDD)
```gherkin
Given I am on the login page
When I click "Forgot Password"
Then I see the password reset form
```

### Checklist Style
```markdown
- [ ] User can do X
- [ ] System responds with Y
- [ ] Error Z is handled gracefully
```

## Story Templates

### Feature Story
```
As a [user type]
I want [functionality]
So that [business value]
```

### Improvement Story
```
As a [user type]
I want [improvement to existing feature]
So that [enhanced value]
```

### Bug Fix Story
```
As a [user type]
I need [bug to be fixed]
So that [expected behavior works]
```

## Rules

- MUST use standard user story format
- MUST include measurable acceptance criteria
- MUST identify edge cases
- Stories should be small enough for one sprint
- Each story must deliver user value
- Technical tasks are NOT user stories
