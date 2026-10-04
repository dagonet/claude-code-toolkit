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

# Fake secrets, assembled at runtime so no token-shaped literal is committed.
AWS_SECRET = "wJalrXUtnFEMI/K7MDENG/" + "bPxRfiCYEXAMPLEKEY"
YA29 = "ya29." + "a0AfH6SMBx1234567890abcdefghijklmnop"
SENDGRID = "SG." + "aB3dE6gH9jK2mN5pQ8sT1u" + "." + "xY7zA1bC4dE8fG2hI5jK9lM3nO6pQ0rS5tUvWxYz2a3"[:43]
SLACK_HOOK = "https://hooks.slack" + ".com/services/T0ABCDEFG/B0ABCDEFG/" + "aB3dE6gH9jK2mN5pQ8sT1uV4"
PATHS = [
    "/home/user/projects/MyApp2/src/Components/Button.tsx",
    "C:\\Users\\x\\Source\\Repos\\Proj1\\src\\Components\\Button2.cs",
    "com.example.Service2.impl.UserRepositoryImpl",
    "Microsoft.Extensions.DependencyInjection.ServiceCollectionServiceExtensions2",
    "https://github.com/Org/Repo2/blob/main/src/File.py",
    "/usr/local/lib/python3.11/site-packages/requests/adapters.py",
    "/opt/google-cloud-sdk/lib/googlecloudsdk/schemas/compute/v1/Int64RangeMatch.yaml",
    "/usr/share/ca-certificates/mozilla/HiPKI_Root_CA_-_G1.crt",
    "/usr/lib/x86_64-linux-gnu/libSvtAv1Enc.so.1.7.0",
    "/usr/share/cmake-3.28/Modules/Platform/Windows3x-OpenWatcom-CXX.cmake",
    "bin/Debug/net8.0/Extensions/IsNullOrEmpty.cs",
    "src/Api.V2/Services/ToJsonString.cs",
    "tests/UnitTests2/Helpers/IsNullOrEmptyTests.cs",
    "/usr/share/cmake-3.28/Modules/FindPerlLibs.cmake",
    "Windows.Win32.UI.WindowsAndMessaging.PInvoke.SetWindowPos",
    "Avalonia.Win32.WindowImpl.HandleWindowMessage",
    "MyNamespace.Sub1.Sub2.Sub3.ViewModels.MainWindowViewModel",
    "src/IoT/MQTTv5/X509CertLoader.cs",
    "src/Extensions/AddDbContext.cs and src/Native/UsePkgConfig.cs",
]
# Random AWS-style secrets (base64 over [A-Za-z0-9+/]) that earlier heuristics missed, bare and behind paths.
RANDOM_B64 = [
    "IrmQc+JxVJVi9bboAqZIWqgivxAVa+ygJVtg/nek",
    "+EZ513oVM+ivdobwrglvLPsAJhggzFVTL+FEIHMH",
    "aws/" + AWS_SECRET,
    "/home/user/" + AWS_SECRET,
    "s3://bucket/" + AWS_SECRET,
    AWS_SECRET + "/config",
]


def elapsed(fn, arg):
    start = time.monotonic()
    fn(arg)
    return time.monotonic() - start


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
        asia = "ASIA" + "ABCDEFGHIJKLMNOP"
        self.assertMasked("k " + asia, asia, "aws_key")
        for wrapped in ("id_" + asia, aws + "_x", "AWS_KEY_" + aws + "_V2"):  # no \\b between _ and A
            out, _ = redact(wrapped)
            self.assertNotIn(wrapped.replace("id_", "").replace("_x", "").replace("AWS_KEY_", "").replace("_V2", ""), out)
        out, _ = redact("AKIA" + "ABCDEFGHIJKLMNOPQ")  # 17 chars after the prefix is not a key id
        self.assertIn("AKIAABCDEFGHIJKLMNOPQ", out)
        # AWS secret key: shape-only (no prefix) -> the residual backstop must catch it raw
        self.assertTrue(residual_findings("AWS: " + AWS_SECRET))
        out, _ = redact("aws_secret_access_key=" + AWS_SECRET)
        self.assertNotIn("K7MDENG", out)
        for secret, kind in ((YA29, "google_oauth"), (SENDGRID, "sendgrid_key"), (SLACK_HOOK, "slack_webhook")):
            self.assertMasked("tok " + secret + " end", secret, kind)
            self.assertTrue(residual_findings("tok " + secret + " end"), secret)  # raw, unmasked
            out, _ = redact("tok " + secret + " end")
            self.assertEqual(residual_findings(out), [], out)
        self.assertNotIn("T0ABCDEFG", redact(SLACK_HOOK)[0])
        for secret, kind in (
            ("AIza" + "SyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q", "google_key"),
            ("glpat-" + "aB3dE6gH9jK2mN5pQ8sT", "gitlab_token"),
            ("sk_" + "live_51HabcDEF0123456789", "stripe_key"),
            ("rk_" + "test_51HabcDEF0123456789", "stripe_key"),
            ("pk_" + "live_51HabcDEF0123456789", "stripe_key"),
            ("hf_" + "aB3dE6gH9jK2mN5pQ8sT1uV4", "hf_token"),
            ("npm_" + "aB3dE6gH9jK2mN5pQ8sT1uV4", "npm_token"),
        ):
            self.assertMasked("v " + secret + " end", secret, kind)

    def test_bearer_header(self):
        self.assertMasked("Authorization: Bearer abcdef0123456789ABCDEF", "abcdef0123456789ABCDEF", "bearer")
        for hdr in ("authorization: bearer abcd1234efgh5678ijkl", "AUTHORIZATION: BEARER abcd1234efgh5678ijkl"):
            self.assertMasked(hdr, "abcd1234efgh5678ijkl", "bearer")
        basic = "dXNlcjpwYXNzd29yZDEyMw=="
        self.assertMasked("Authorization: Basic " + basic, basic, "basic")
        self.assertMasked("authorization: basic " + basic, basic, "basic")

    def test_pem_block(self):
        pem = "-----BEGIN RSA " + "PRIVATE KEY-----\nMIIEow\nabc\n-----END RSA " + "PRIVATE KEY-----"
        self.assertMasked("x\n" + pem + "\ny", "MIIEow", "private_key")
        out, _ = redact("before\n" + pem + "\nafter")  # terminated: text after END survives
        self.assertIn("after", out)
        begin = "-----BEGIN RSA " + "PRIVATE KEY-----\n"
        out, _ = redact("head\n" + begin + "MIIEowSECRETBODY\nmore\n" + "z" * 20000)  # no END: mask to end of text
        self.assertNotIn("MIIEowSECRETBODY", out)
        self.assertNotIn("zzzz", out)
        self.assertIn("head", out)
        self.assertIn("[REDACTED:private_key]", out)
        out, _ = redact("a " + begin + "ONE\n" + begin + "TWO")
        self.assertNotIn("ONE", out)
        self.assertNotIn("TWO", out)

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
        for line in ("private_key=zQ9xv", "PRIVATE-KEY: zQ9xv", "credentials: zQ9xv", "aws_access_key = zQ9xv",
                     "auth=zQ9xv", "auth: zQ9xv", "basic_auth=zQ9xv", '"auth": "zQ9xv"', "AccountKey=zQ9xv"):
            out, _ = redact(line)
            self.assertNotIn("zQ9xv", out, line)
        conn = "DefaultEndpointsProtocol=https;AccountName=x;AccountKey=" + "abc123DEF456ghi789JKL012mno345PQR678stu901vwx234yz5678AB==" + ";EndpointSuffix=core.windows.net"
        out, _ = redact(conn)
        self.assertNotIn("abc123DEF", out)
        self.assertNotIn("AB==", out)
        self.assertTrue(out.endswith(";EndpointSuffix=core.windows.net"), out)
        self.assertIn("AccountName=x;", out)

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
        for prose in ("author: Jane Doe", "authority = none", "OAuth flow; authenticate() returns", "auth is handled by the gateway",
                      "the authors: Jane", "basic usage and bearer of news", "see the Basic setup guide"):
            out, counts = redact(prose)
            self.assertEqual(out, prose)
            self.assertEqual(sum(counts.values()), 0, prose)
        for path in PATHS:
            out, counts = redact("see " + path + " now")
            self.assertEqual(out, "see " + path + " now", path)
            self.assertEqual(residual_findings(path), [], path)
        start = time.monotonic()  # linear-time patterns: the hook timeout is 5 s
        redact("a." * 50000)
        self.assertLess(time.monotonic() - start, 2)
        begin = "-----BEGIN RSA " + "PRIVATE KEY-----"
        for adversarial in ("a." * 50000, "Bearer " * 14300, "Bearer" + " " * 100000, "Basic " * 16700, "a/" * 50000,
                            "SG." + "a" * 100000, "SG." + "a" * 20 + "." + "a" * 100000, "SG.aaaaaaaaaaaaaaaaaaaa" * 4000,
                            begin * 3200, begin + "a" * 100000, (begin + "x" * 9990) * 10, "auth=" * 20000, "a.auth=" * 14000,
                            "password" * 12500, "a" * 100000, "A1" * 50000, "aB3/" * 25000, "aB3+" * 25000,
                            "ya29." * 20000, "hooks.slack.com/services/" * 4000, "AccountKey=" * 9000,
                            "".join(chr(97 + i % 26) + "/" for i in range(50000)),
                            "A" * 100000 + "a1/", "x/Aa" + "A" * 100000 + "1", "/" + "aB" * 50000 + "1",
                            ("A" * 10000 + "a1/ ") * 10, "/" + "aB1" * 33000, "A1/" * 33000, "a1" * 50000 + "/Aa",
                            "Ab" * 50000 + "/", ("A" * 399 + "a1/ ") * 250,
                            ("aB3d/" * 79 + "x ") * 250, ("aB3dE6/" * 56 + " ") * 250, ("Ab1.cD2." * 49 + " ") * 250,  # windowed runs
                            "aB3dE6gH9jK2mN5pQ8sT1uV4wX7yZ0cD2eF5gH8iJ1kL4mN7pQ" * 2000):
            self.assertLess(elapsed(redact, adversarial), 0.1, adversarial[:30])
            self.assertLess(elapsed(residual_findings, adversarial), 0.1, adversarial[:30])


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
        for secret in RANDOM_B64:
            self.assertTrue(residual_findings("AWS: " + secret), secret)
            self.assertTrue(residual_findings(secret), secret)
            self.assertTrue(residual_findings(redact("AWS: " + secret)[0]), secret)  # unmasked: backstop must hold
        for secret in (AWS_SECRET, YA29, SENDGRID, SLACK_HOOK, "key=" + AWS_SECRET + ".",
                       "Zq8vN2kLpX4rT7wY1mB6cF9hJ3sD5gA0eU+Zq8vN2kLpX4r/T7w=="):
            self.assertTrue(residual_findings("v " + secret + " end"), secret)

    def test_ignores_hex_hashes_and_paths(self):
        self.assertEqual(residual_findings("sha b43b14010ee2f9c5ec2825b6f2b9d972b0250ea7 and sha256 " + "a" * 64), [])
        self.assertEqual(residual_findings("see templates/general/.claude/agents/code-reviewer.md"), [])
        for path in PATHS:
            self.assertEqual(residual_findings("open " + path + " please"), [], path)

    def test_flags_leftover_private_key_marker(self):
        self.assertTrue(residual_findings("-----BEGIN OPENSSH " + "PRIVATE KEY-----"))


if __name__ == "__main__":
    unittest.main()
