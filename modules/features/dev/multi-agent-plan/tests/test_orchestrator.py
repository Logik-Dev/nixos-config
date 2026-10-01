"""Tests unitaires de l'orchestrateur multi-agent-plan.

Lancement : `python3 -m unittest discover tests` depuis le dossier du module,
ou via le check Nix `multi-agent-plan`.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import orchestrator
from orchestrator import (
    Failure,
    parse_any_block,
    parse_block,
    parse_claude_json,
    parse_steps,
    render,
)

CORPS_REVIEW = "Review détaillée du plan, assez longue pour franchir le seuil minimal."
CORPS_PLAN = "Plan détaillé, assez long lui aussi pour franchir le seuil minimal imposé."


class RenderTests(unittest.TestCase):
    def test_remplace_toutes_les_valeurs(self):
        self.assertEqual(render("a {{x}} b {{y}}", x=1, y="z"), "a 1 b z")

    def test_laisse_les_placeholders_inconnus(self):
        self.assertEqual(render("{{x}} et {{y}}", x="ok"), "ok et {{y}}")


class ParseStepsTests(unittest.TestCase):
    PLAN = (
        "# Plan\n\n"
        "## Step 1 — Premier\n"
        "**Files**: a.py\n"
        "**Tests**: nix flake check\n"
        "**Commit**: `feat(a): un`\n"
        "Corps un.\n\n"
        "## Step 2 — Deuxième\n"
        "**Files**: b.py\n"
        "**Tests**: aucune\n"
        "**Commit**: `fix(b): deux`\n"
        "Corps deux.\n"
    )

    def test_numeros_et_titres(self):
        steps = parse_steps(self.PLAN)
        self.assertEqual([step["number"] for step in steps], [1, 2])
        self.assertEqual(steps[0]["title"], "Premier")
        self.assertEqual(steps[1]["title"], "Deuxième")

    def test_commit_sans_backticks(self):
        steps = parse_steps(self.PLAN)
        self.assertEqual(steps[0]["commit"], "feat(a): un")
        self.assertEqual(steps[1]["commit"], "fix(b): deux")

    def test_corps_borne_a_letape(self):
        steps = parse_steps(self.PLAN)
        self.assertIn("Corps un.", steps[0]["body"])
        self.assertNotIn("Step 2", steps[0]["body"])
        self.assertIn("Corps deux.", steps[1]["body"])

    def test_sans_etape(self):
        self.assertEqual(parse_steps("aucune étape ici"), [])


class ParseClaudeJsonTests(unittest.TestCase):
    def test_json_valide(self):
        raw = json.dumps({"result": "contenu du plan", "session_id": "s1"})
        text, payload = parse_claude_json(raw)
        self.assertEqual(text, "contenu du plan")
        self.assertEqual(payload["session_id"], "s1")

    def test_sortie_vide(self):
        with self.assertRaises(Failure):
            parse_claude_json("   ")

    def test_json_sans_result(self):
        with self.assertRaises(Failure):
            parse_claude_json(json.dumps({"is_error": True}))

    def test_repli_sur_un_bloc_encadre(self):
        raw = f"<<<REVIEW>>>\n{CORPS_REVIEW}\n<<<END_REVIEW>>>"
        text, payload = parse_claude_json(raw)
        self.assertEqual(text, CORPS_REVIEW)
        self.assertEqual(payload, {})

    def test_json_illisible_sans_bloc(self):
        with self.assertRaises(Failure):
            parse_claude_json("pas du json")


class ParseBlockTests(unittest.TestCase):
    def test_fermeture_unique(self):
        text = f"<<<FINAL_PLAN>>>\n{CORPS_PLAN}\n<<<END_FINAL_PLAN>>>\n"
        self.assertEqual(
            parse_block(text, "<<<FINAL_PLAN>>>", "<<<END_FINAL_PLAN>>>"), CORPS_PLAN
        )

    def test_ne_tronque_pas_un_corps_citant_end(self):
        body = (
            "Le corps cite la sentinelle <<<END>>> en prose puis poursuit.\n\n"
            "## Step 2 — la suite reste intacte\n"
            "**Commit**: `feat(x): y`"
        )
        text = f"<<<FINAL_PLAN>>>\n{body}\n<<<END_FINAL_PLAN>>>\n"
        parsed = parse_block(text, "<<<FINAL_PLAN>>>", "<<<END_FINAL_PLAN>>>")
        self.assertEqual(parsed, body)
        self.assertIn("la suite reste intacte", parsed)

    def test_repli_ancien_marqueur(self):
        text = f"<<<REVIEW>>>\n{CORPS_REVIEW}\n<<<END>>>\n"
        self.assertEqual(parse_block(text, "<<<REVIEW>>>", "<<<END_REVIEW>>>"), CORPS_REVIEW)

    def test_bloc_absent(self):
        with self.assertRaises(Failure):
            parse_block("aucun bloc ici", "<<<REVIEW>>>", "<<<END_REVIEW>>>")

    def test_fermeture_absente(self):
        text = f"<<<REVIEW>>>\n{CORPS_REVIEW}\n"
        with self.assertRaises(Failure):
            parse_block(text, "<<<REVIEW>>>", "<<<END_REVIEW>>>")

    def test_capture_tronquee_trop_courte(self):
        text = "<<<REVIEW>>>\nOK\n<<<END_REVIEW>>>"
        with self.assertRaises(Failure):
            parse_block(text, "<<<REVIEW>>>", "<<<END_REVIEW>>>")

    def test_capture_tronquee_dans_un_fence(self):
        text = (
            "<<<FINAL_PLAN>>>\n"
            "## Step 1 — modifier le parseur\n\n"
            "```python\nprint('fence jamais fermé')\n"
            "<<<END_FINAL_PLAN>>>"
        )
        with self.assertRaises(Failure):
            parse_block(text, "<<<FINAL_PLAN>>>", "<<<END_FINAL_PLAN>>>")

    def test_fence_equilibre_accepte(self):
        body = (
            "## Step 1 — exemple\n\n"
            "```python\nprint('ok')\n```\n\n"
            "Fin de l'étape avec assez de texte pour le seuil minimal."
        )
        text = f"<<<FINAL_PLAN>>>\n{body}\n<<<END_FINAL_PLAN>>>"
        self.assertEqual(parse_block(text, "<<<FINAL_PLAN>>>", "<<<END_FINAL_PLAN>>>"), body)

    def test_message_avec_taille_du_log(self):
        with tempfile.NamedTemporaryFile("w", suffix=".log") as handle:
            handle.write("x" * 1234)
            handle.flush()
            with self.assertRaises(Failure) as ctx:
                parse_block(
                    "<<<REVIEW>>>\ntrop court",
                    "<<<REVIEW>>>",
                    "<<<END_REVIEW>>>",
                    log_path=handle.name,
                )
        self.assertIn("1234 octets", str(ctx.exception))

    def test_parse_any_block_choisit_le_premier(self):
        brief = "Brief concis mais suffisamment long pour dépasser le seuil minimal."
        text = (
            f"<<<BRIEF>>>\n{brief}\n<<<END_BRIEF>>>\n"
            f"<<<FINAL_PLAN>>>\n{CORPS_PLAN}\n<<<END_FINAL_PLAN>>>"
        )
        self.assertEqual(parse_any_block(text), brief)

    def test_parse_any_block_sans_marqueur(self):
        with self.assertRaises(Failure):
            parse_any_block("texte sans aucun marqueur")


class SentinelCompatTests(unittest.TestCase):
    def test_sentinelles_declarent_les_fermetures_uniques(self):
        self.assertEqual(
            orchestrator.SENTINELS,
            {
                "BRIEF": ("<<<BRIEF>>>", "<<<END_BRIEF>>>"),
                "REVIEW": ("<<<REVIEW>>>", "<<<END_REVIEW>>>"),
                "FINAL_PLAN": ("<<<FINAL_PLAN>>>", "<<<END_FINAL_PLAN>>>"),
            },
        )


if __name__ == "__main__":
    unittest.main()
