"""jev_route decision core: bounds, threshold, role floor, request and output shape (v4.4.0 Task 5)."""
import json
import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import jev_route as jr  # noqa: E402


def ans(choice, conf):
    return {"choice": choice, "confidence": conf, "probabilities": {}}


# Every value class an emitter could mangle (C1's C1TI, as a Python dict).
C1TI = {"subagent_type": "general-purpose", "prompt": "deep", "description": "d", "zz_unknown": 1,
        "nested": {"a": [1, 2, {"b": None}], "t": True, "f": False, "e": {}, "l": []},
        "__proto__": {"x": 1}, "u": "a b\u00e9\u2028", "tab": "x\ty"}


class DecideTests(unittest.TestCase):
    def test_floor_one_step_up_applies(self):
        self.assertEqual(jr.decide("floor", "sonnet", "general-purpose", ans("opus", 0.9), 0.8), ("opus", True, "applied"))

    def test_own_one_step_down_applies(self):
        self.assertEqual(jr.decide("own", "opus", "coder", ans("sonnet", 0.85), 0.8), ("sonnet", True, "applied"))

    def test_threshold_is_inclusive(self):
        self.assertEqual(jr.decide("floor", "sonnet", "Plan", ans("haiku", 0.8), 0.8), ("haiku", True, "applied"))

    def test_below_threshold_floor_emits_floor_own_emits_nothing(self):
        self.assertEqual(jr.decide("floor", "sonnet", "Plan", ans("haiku", 0.79), 0.8), ("sonnet", False, "low-confidence"))
        self.assertEqual(jr.decide("own", "opus", "coder", ans("sonnet", 0.79), 0.8), (None, False, "low-confidence"))

    def test_two_step_move_refused(self):
        self.assertEqual(jr.decide("floor", "haiku", "Explore", ans("opus", 0.99), 0.8), ("haiku", False, "out-of-bounds"))
        self.assertEqual(jr.decide("own", "fable", "architect", ans("sonnet", 0.99), 0.8), (None, False, "out-of-bounds"))

    def test_reviewer_never_below_sonnet(self):
        self.assertEqual(jr.decide("own", "sonnet", "code-reviewer", ans("haiku", 0.99), 0.8), (None, False, "role-floor"))
        self.assertEqual(jr.decide("floor", "sonnet", "my-Architect", ans("haiku", 0.99), 0.8), ("sonnet", False, "role-floor"))

    def test_role_floor_limits_the_choice_not_the_default(self):
        # A reviewer whose own model is haiku keeps it; Jev may raise it, never lower it.
        self.assertEqual(jr.decide("own", "haiku", "code-reviewer", ans("haiku", 0.99), 0.8), (None, False, "kept"))
        self.assertEqual(jr.decide("own", "haiku", "code-reviewer", ans("sonnet", 0.99), 0.8), ("sonnet", True, "applied"))

    def test_same_choice_kept(self):
        self.assertEqual(jr.decide("floor", "sonnet", "general-purpose", ans("sonnet", 0.99), 0.8), ("sonnet", False, "kept"))
        self.assertEqual(jr.decide("own", "opus", "coder", ans("opus", 0.99), 0.8), (None, False, "kept"))

    def test_full_id_maps_to_its_family(self):
        self.assertEqual(jr.family("claude-opus-4-1"), "opus")
        self.assertEqual(jr.decide("own", "claude-opus-4-1", "x", ans("sonnet", 0.9), 0.8), ("sonnet", True, "applied"))
        self.assertEqual(jr.decide("own", "claude-opus-4-1", "x", ans("opus", 0.9), 0.8), (None, False, "kept"))

    def test_unmappable_default_is_pinned(self):
        self.assertEqual(jr.decide("own", "gpt-5", "x", ans("sonnet", 0.99), 0.8), (None, False, "pinned"))

    def test_no_answer_is_bad_response(self):
        self.assertEqual(jr.decide("floor", "sonnet", "Plan", None, 0.8), ("sonnet", False, "bad-response"))
        self.assertEqual(jr.decide("own", "opus", "coder", None, 0.8), (None, False, "bad-response"))


class PayloadTests(unittest.TestCase):
    def test_state_is_type_description_prompt(self):
        state, findings = jr.build_state({"subagent_type": "coder", "description": "fix it", "prompt": "Do X."})
        self.assertEqual(state, "agent_type: coder\ndescription: fix it\n\nDo X.")
        self.assertEqual(findings, [])

    def test_state_untyped_reads_general_purpose(self):
        state, _ = jr.build_state({"prompt": "p"})
        self.assertTrue(state.startswith("agent_type: general-purpose\n"))

    def test_state_redacted_then_capped_at_4000(self):
        mail = "jane.doe" + "@" + "example.org"
        state, findings = jr.build_state({"subagent_type": "coder", "description": "d", "prompt": mail + " " + "word " * 3000})
        self.assertNotIn(mail, state)
        self.assertLessEqual(len(state), 4000)
        self.assertEqual(findings, [])

    def test_residual_secret_reported(self):
        _, findings = jr.build_state({"prompt": "value Zq8vN2kLpX4rT7wY1mB6cF9hJ3sD5gA0eU"})
        self.assertTrue(findings)

    def test_request_pins_model_and_phase0_questions(self):
        body = json.loads(jr.build_request("S", "jev-1.13.0").decode("utf-8"))
        self.assertEqual((body["state"], body["model"]), ("S", "jev-1.13.0"))
        self.assertEqual(sorted(body["questions"]), ["effort", "model"])
        self.assertEqual(sorted(body["questions"]["model"]["criteria"]), ["fable", "haiku", "opus", "sonnet"])
        self.assertEqual(sorted(body["questions"]["effort"]["criteria"]), ["high", "low", "medium", "xhigh"])
        self.assertEqual(body["questions"]["model"]["instructions"],
                         "Which Claude model is the least costly one that can complete this delegated task correctly on the first attempt?")

    def test_parse_answers_ok(self):
        raw = json.dumps({"answers": {
            "model": {"type": "choice", "choice": "opus", "confidence": 0.91, "probabilities": {"opus": 0.91, "sonnet": 0.09}},
            "effort": {"type": "choice", "choice": "high", "confidence": 0.6, "probabilities": {}}}}).encode("utf-8")
        m, e = jr.parse_answers(raw)
        self.assertEqual((m["choice"], m["confidence"], m["probabilities"]), ("opus", 0.91, {"opus": 0.91, "sonnet": 0.09}))
        self.assertEqual((e["choice"], e["confidence"]), ("high", 0.6))

    def test_parse_answers_rejects_bad_shapes(self):
        for raw in (b"not json", b"[]", b'{"answers": 1}',
                    b'{"answers": {"model": {"choice": "gpt", "confidence": 0.9}}}',
                    b'{"answers": {"model": {"choice": "opus", "confidence": true}}}',
                    b'{"answers": {"model": {"choice": "opus", "confidence": 1.5}}}',
                    b'{"answers": {"model": {"choice": "opus", "confidence": NaN}}}'):
            self.assertIsNone(jr.parse_answers(raw)[0], raw)

    def test_emit_copies_whole_tool_input_and_sets_model(self):
        out = json.loads(jr.emit(dict(C1TI), "opus").decode("utf-8"))
        self.assertEqual(sorted(out), ["hookSpecificOutput"])
        hso = out["hookSpecificOutput"]
        self.assertEqual(sorted(hso), ["hookEventName", "updatedInput"])  # never a permissionDecision
        self.assertEqual(hso["hookEventName"], "PreToolUse")
        ui = dict(hso["updatedInput"])
        self.assertEqual(ui.pop("model"), "opus")
        self.assertEqual(ui, C1TI)

    def test_emit_refuses_non_json_numbers(self):
        self.assertEqual(jr.emit({"prompt": "p", "n": float("inf")}, "sonnet"), b"")
        # A lone surrogate must still emit (ASCII escapes), so a floor spawn always leaves with a model.
        lone = {"subagent_type": "Plan", "prompt": "cut " + chr(0xd83d) + " x"}
        out = jr.emit(dict(lone), "sonnet")
        self.assertTrue(out)
        self.assertEqual(json.loads(out.decode("utf-8"))["hookSpecificOutput"]["updatedInput"], dict(lone, model="sonnet"))
        jr.build_request("cut " + chr(0xd83d) + " x", "jev-1.13.0")


if __name__ == "__main__":
    unittest.main()
