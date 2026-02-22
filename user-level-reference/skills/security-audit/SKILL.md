---
name: security-audit
description: Comprehensive security review including vulnerabilities, code patterns, and secrets. Triggers on security-related questions or audit requests.
---

# Security Audit Skill

Comprehensive security review including vulnerabilities, code patterns, and secrets.

## When to Use

This skill auto-activates when:
- User asks about security vulnerabilities
- User wants a security audit or review
- User mentions "security", "vulnerabilities", or "secrets"
- User asks about OWASP, CVE, or security best practices

## Workflow

1. **Check NuGet vulnerabilities**
   - Call `nuget_check_vulnerabilities(project_or_sln, include_transitive=true)`
   - Categorize by severity (Critical, High, Medium, Low)

2. **Scan for secrets** (using Grep)
   Search for patterns:
   ```
   - API keys: /api[_-]?key/i
   - Connection strings: /connectionstring.*password/i
   - Passwords: /password\s*=\s*["'][^"']+["']/i
   - Tokens: /bearer\s+[a-zA-Z0-9-_.]+/i
   - AWS keys: /AKIA[0-9A-Z]{16}/
   - Private keys: /-----BEGIN.*PRIVATE KEY-----/
   ```

3. **Check for vulnerable code patterns**

   ### SQL Injection
   ```csharp
   // VULNERABLE
   $"SELECT * FROM Users WHERE Id = {id}"
   string.Format("...{0}...", userInput)

   // SAFE
   command.Parameters.AddWithValue("@id", id)
   ```

   ### XSS
   ```csharp
   // VULNERABLE
   @Html.Raw(userInput)

   // SAFE
   @Html.Encode(userInput)
   ```

   ### Path Traversal
   ```csharp
   // VULNERABLE
   File.ReadAllText(userProvidedPath)

   // SAFE
   Path.GetFullPath() + validation
   ```

   ### Insecure Deserialization
   ```csharp
   // VULNERABLE
   BinaryFormatter, NetDataContractSerializer
   JsonConvert.DeserializeObject with TypeNameHandling

   // SAFE
   System.Text.Json with strict options
   ```

4. **Check authentication/authorization**
   - Controllers without [Authorize]
   - Missing authorization policies
   - Hardcoded roles instead of policies

5. **Check cryptography**
   - Weak algorithms (MD5, SHA1 for security)
   - Hardcoded keys/IVs
   - ECB mode usage
   - Insufficient key lengths

6. **Check logging**
   - Sensitive data in logs (passwords, tokens, PII)
   - Missing audit logging for sensitive operations

7. **Generate security report**
   ```markdown
   ## Security Audit Report

   ### Executive Summary
   | Severity | Count |
   |----------|-------|
   | Critical | 2 |
   | High | 5 |
   | Medium | 8 |
   | Low | 12 |

   ### Vulnerable Dependencies
   | Package | Version | Vulnerability | Severity |
   |---------|---------|---------------|----------|
   | Newtonsoft.Json | 12.0.1 | CVE-2024-... | High |

   ### Code Vulnerabilities

   #### 🔴 Critical

   ##### SQL Injection - UserRepository.cs:45
   ```csharp
   var sql = $"SELECT * FROM Users WHERE Email = '{email}'";
   ```
   **Risk:** Full database compromise
   **Fix:** Use parameterized queries

   #### 🟠 High

   ##### Hardcoded Secret - appsettings.json:12
   **Risk:** Credential exposure in source control
   **Fix:** Use environment variables or secret manager

   ### Secrets Detected
   | File | Line | Type | Status |
   |------|------|------|--------|
   | config.json | 5 | API Key | ❌ Exposed |

   ### Missing Security Controls
   - [ ] Rate limiting not implemented
   - [ ] CORS policy too permissive
   - [ ] Missing security headers

   ### Recommendations
   1. **Immediate**: Fix SQL injection vulnerabilities
   2. **Short-term**: Rotate exposed credentials
   3. **Medium-term**: Implement security headers
   4. **Long-term**: Add security scanning to CI/CD
   ```

## OWASP Top 10 Checklist

- [ ] A01: Broken Access Control
- [ ] A02: Cryptographic Failures
- [ ] A03: Injection
- [ ] A04: Insecure Design
- [ ] A05: Security Misconfiguration
- [ ] A06: Vulnerable Components
- [ ] A07: Auth Failures
- [ ] A08: Data Integrity Failures
- [ ] A09: Logging Failures
- [ ] A10: SSRF

## Rules

- MUST check NuGet vulnerabilities
- MUST scan for hardcoded secrets
- MUST check OWASP Top 10 patterns
- MUST NOT display actual secret values in report
- Severity ratings must follow CVSS guidelines
- Provide specific remediation for each finding
