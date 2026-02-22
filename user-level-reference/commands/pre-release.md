# /pre-release - Pre-Release Checklist

Comprehensive pre-release validation to catch issues before deployment.

## Arguments

- `$ARGUMENTS` - Version number or release name (optional)

## Workflow

1. **Run all checks in parallel**
   - Call `build_and_extract_errors(project_or_sln, configuration="Release")`
   - Call `run_tests_summary(project_or_sln, configuration="Release")`
   - Call `nuget_check_vulnerabilities(project_or_sln, include_transitive=true)`
   - Call `ef_pending_migrations(project_path)` (if EF Core used)

2. **Build verification**
   - Release configuration builds without errors
   - No warnings treated as errors
   - All projects compile successfully

3. **Test verification**
   - All tests pass
   - No skipped tests without reason
   - Test coverage meets threshold (if configured)

4. **Security verification**
   - No known vulnerabilities in dependencies
   - No critical/high severity issues
   - Secrets not committed

5. **Database verification** (if applicable)
   - No pending migrations
   - Migration scripts reviewed
   - Rollback plan exists

6. **Documentation verification**
   - CHANGELOG updated
   - README reflects current state
   - API documentation current

7. **Configuration verification**
   - Environment-specific configs ready
   - Feature flags set correctly
   - Connection strings use env variables

8. **Generate release report**
   ```markdown
   ## Pre-Release Report: v$ARGUMENTS

   ### Overall Status: ✅ READY / ❌ NOT READY

   ### Build
   | Check | Status |
   |-------|--------|
   | Release build | ✅ Pass |
   | Warnings | ✅ 0 warnings |
   | All projects | ✅ 12/12 compiled |

   ### Tests
   | Check | Status |
   |-------|--------|
   | Unit tests | ✅ 156/156 passed |
   | Integration tests | ✅ 24/24 passed |
   | Skipped | ⚠️ 3 skipped |

   ### Security
   | Check | Status |
   |-------|--------|
   | Vulnerabilities | ✅ None found |
   | Secrets scan | ✅ No secrets detected |

   ### Database
   | Check | Status |
   |-------|--------|
   | Pending migrations | ✅ None |
   | Last migration | 20240115_AddUserPreferences |

   ### Blockers
   [List any issues that block release]

   ### Warnings
   [List non-blocking concerns]

   ### Sign-off
   - [ ] Development complete
   - [ ] Code review approved
   - [ ] QA testing passed
   - [ ] Security review passed
   - [ ] Documentation updated
   - [ ] Stakeholder approval

   ### Deployment Notes
   - Database migration required: No
   - Configuration changes: None
   - Breaking changes: None
   - Rollback procedure: [Link or description]
   ```

9. **Provide go/no-go recommendation**

## Pre-Release Checklist

### Code Quality
- [ ] All code reviewed and approved
- [ ] No TODO/FIXME for this release
- [ ] No debug code left in
- [ ] Error handling complete

### Testing
- [ ] All tests pass
- [ ] Edge cases covered
- [ ] Performance tested
- [ ] Load tested (if applicable)

### Security
- [ ] No vulnerabilities
- [ ] Security review complete
- [ ] Penetration testing (if applicable)
- [ ] OWASP checklist reviewed

### Documentation
- [ ] CHANGELOG updated
- [ ] Release notes written
- [ ] API docs updated
- [ ] Runbook updated

### Infrastructure
- [ ] Environment configs ready
- [ ] Monitoring configured
- [ ] Alerts configured
- [ ] Rollback plan documented

### Compliance
- [ ] License compliance checked
- [ ] Data privacy reviewed
- [ ] Audit logging in place

## Rules

- MUST run Release configuration, not Debug
- MUST have zero failing tests for approval
- MUST have zero critical/high vulnerabilities
- Any pending migrations MUST be flagged
- Provide clear go/no-go recommendation
