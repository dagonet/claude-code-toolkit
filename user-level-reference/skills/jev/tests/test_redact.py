"""Tests for the Jev redactor (Phase 0's 15, trim tightened to the exact cap, + 1).

Run: python3 -B -m unittest discover -s user-level-reference/skills/jev/tests -v
Fake secrets are assembled at runtime so no token-shaped literal is committed.
"""
import getpass
import os
import sys
import time
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from redact import redact, residual_findings, trim  # noqa: E402

USER = getpass.getuser()


class RedactTests(unittest.TestCase):
    def assertMasked(self, text, secret, kind):
        out, counts = redact(text)
        self.assertNotIn(secret, out)
        self.assertIn("[REDACTED:" + kind + "]", out)
        self.assertGreaterEqual(counts.get(kind, 0), 1)

    def test_anthropic_and_openai_style_keys(self):
        k1 = "sk-" + "ant-api03-AbCdEf0123456789xyzXYZ"
        k2 = "sk-" + "proj-1234567890abcdefghij"
        self.assertMasked("key " + k1 + " done", k1, "api_key")
        self.assertMasked("export OPENAI=" + k2, k2, "api_key")

    def test_github_tokens(self):
        t1 = "ghp_" + "a1B2" * 9
        t2 = "github_" + "pat_11ABCDEFG0123456789_abcdefghijklmnop"
        self.assertMasked("t=" + t1, t1, "github_token")
        self.assertMasked(t2, t2, "github_token")

    def test_aws_slack_jwt(self):
        aws = "AKIA" + "ABCDEFGHIJKLMNOP"
        slack = "xox" + "b-1234567890-abcdefghijkl"
        jwt = "eyJ" + "hbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        self.assertMasked(aws, aws, "aws_key")
        self.assertMasked(slack, slack, "slack_token")
        self.assertMasked("cookie " + jwt, jwt, "jwt")

    def test_bearer_header(self):
        self.assertMasked("Authorization: Bearer abcdef0123456789ABCDEF", "abcdef0123456789ABCDEF", "bearer")

    def test_pem_block(self):
        pem = "-----BEGIN RSA " + "PRIVATE KEY-----\nMIIEow\nabc\n-----END RSA " + "PRIVATE KEY-----"
        self.assertMasked("x\n" + pem + "\ny", "MIIEow", "private_key")

    def test_key_value_keeps_name_masks_value(self):
        out, counts = redact('password = "hunter2hunter2"')
        self.assertNotIn("hunter2hunter2", out)
        self.assertIn("password", out)
        self.assertGreaterEqual(counts.get("key_value", 0), 1)
        out, _ = redact("TYPESAFE_API_KEY=sk-abc")  # short value still masked via key=value
        self.assertNotIn("sk-abc", out)
        out, _ = redact('{"password": "' + "hunter2" * 2 + '", "api_key":"abcdEF12"}')
        self.assertNotIn("hunter2", out)
        self.assertNotIn("abcdEF12", out)
        out, _ = redact('password="p@ss w0rd" secret: \'has space inside\'')
        for leak in ("w0rd", "space", "inside"):
            self.assertNotIn(leak, out)
        out, _ = redact("SPRING_DATASOURCE_HIKARI_CONNECTION_PROPERTIES_PASSWORD=hunter2")
        self.assertNotIn("hunter2", out)

    def test_url_credentials(self):
        self.assertMasked("https://bob:s3cretPass@example.com/x", "s3cretPass", "url_credentials")

    def test_email_and_user_paths(self):
        u = USER
        mail = "jane.doe" + "@" + "example.org"
        out, _ = redact("mail " + mail + " path C:\\Users\\" + u + "\\x and /c/Users/" + u + "/y and C:/Users/" + u + "/z")
        self.assertNotIn(mail, out)
        self.assertNotIn(u, out)
        self.assertIn("[REDACTED:email]", out)
        self.assertIn("~", out)

    def test_bare_username_masked(self):
        out, _ = redact("owned by " + USER + " on this box")
        self.assertNotIn(USER, out)

    def test_git_shas_and_ordinary_text_untouched(self):
        text = "commit b43b14010ee2f9c5ec2825b6f2b9d972b0250ea7 merged; tokens counted: 1250 passed"
        out, counts = redact(text)
        self.assertEqual(out, text)
        self.assertEqual(sum(counts.values()), 0)
        start = time.monotonic()  # linear-time patterns: the hook timeout is 5 s
        redact("a." * 50000)
        self.assertLess(time.monotonic() - start, 2)


class TrimTests(unittest.TestCase):
    def test_short_text_unchanged(self):
        self.assertEqual(trim("abc", 10), "abc")

    def test_long_text_keeps_head_and_tail(self):
        text = "H" * 3000 + "M" * 5000 + "T" * 3000
        out = trim(text, 4000)
        self.assertTrue(out.startswith("H" * 1900))
        self.assertTrue(out.endswith("T" * 1900))
        self.assertIn("[trimmed 7029 chars]", out)
        self.assertLessEqual(len(out), 4000)

    def test_trim_never_exceeds_cap(self):
        for n in (4000, 4001, 4029, 5000, 100000):
            self.assertLessEqual(len(trim("x" * n, 4000)), 4000, n)


class ResidualTests(unittest.TestCase):
    def test_flags_unknown_high_entropy_token(self):
        self.assertTrue(residual_findings("value Zq8vN2kLpX4rT7wY1mB6cF9hJ3sD5gA0eU"))
        self.assertTrue(residual_findings("key Zq8vN2kLpX4rT7wY1mB6cF9hJ3sD5gA0eU."))
        hook = "https://hooks.slack" + ".com/services/T0ABCDEFG/B0ABCDEFG/" + "aB3dE6gH9jK2mN5pQ8sT1uV4"
        self.assertTrue(residual_findings("post to " + hook))

    def test_ignores_hex_hashes_and_paths(self):
        self.assertEqual(residual_findings("sha b43b14010ee2f9c5ec2825b6f2b9d972b0250ea7 and sha256 " + "a" * 64), [])
        self.assertEqual(residual_findings("see templates/general/.claude/agents/code-reviewer.md"), [])

    def test_flags_leftover_private_key_marker(self):
        self.assertTrue(residual_findings("-----BEGIN OPENSSH " + "PRIVATE KEY-----"))


if __name__ == "__main__":
    unittest.main()
