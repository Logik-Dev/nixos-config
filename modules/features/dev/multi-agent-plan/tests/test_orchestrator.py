"""Tests unitaires de l'orchestrateur multi-agent-plan.

Lancement : `python3 -m unittest discover tests` depuis le dossier du module,
ou via le check Nix `multi-agent-plan`.
"""

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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
CORPS_BRIEF = "Brief concis mais suffisamment long pour dépasser le seuil minimal imposé."
PLAN_TEXTE = (
    f"<<<BRIEF>>>\n{CORPS_BRIEF}\n<<<END_BRIEF>>>\n\n"
    f"<<<FINAL_PLAN>>>\n{CORPS_PLAN}\n<<<END_FINAL_PLAN>>>"
)


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

    def test_bloc_plan_headless(self):
        text = f"<<<PLAN>>>\n{CORPS_PLAN}\n<<<END_PLAN>>>"
        self.assertEqual(parse_block(text, *orchestrator.SENTINELS["PLAN"]), CORPS_PLAN)

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
                "PLAN": ("<<<PLAN>>>", "<<<END_PLAN>>>"),
                "REVIEW": ("<<<REVIEW>>>", "<<<END_REVIEW>>>"),
                "FINAL_PLAN": ("<<<FINAL_PLAN>>>", "<<<END_FINAL_PLAN>>>"),
            },
        )


def make_session_db(path, rows=(), messages=(), parts=()):
    connection = sqlite3.connect(path)
    connection.execute(
        "CREATE TABLE session ("
        "id TEXT PRIMARY KEY,"
        "directory TEXT NOT NULL,"
        "time_created INTEGER NOT NULL,"
        "cost REAL DEFAULT 0 NOT NULL,"
        "tokens_input INTEGER DEFAULT 0 NOT NULL,"
        "tokens_output INTEGER DEFAULT 0 NOT NULL,"
        "tokens_reasoning INTEGER DEFAULT 0 NOT NULL,"
        "tokens_cache_read INTEGER DEFAULT 0 NOT NULL,"
        "tokens_cache_write INTEGER DEFAULT 0 NOT NULL)"
    )
    connection.execute(
        "CREATE TABLE message ("
        "id TEXT PRIMARY KEY,"
        "session_id TEXT NOT NULL,"
        "time_created INTEGER NOT NULL,"
        "time_updated INTEGER NOT NULL,"
        "data TEXT NOT NULL)"
    )
    connection.execute(
        "CREATE TABLE part ("
        "id TEXT PRIMARY KEY,"
        "message_id TEXT NOT NULL,"
        "session_id TEXT NOT NULL,"
        "time_created INTEGER NOT NULL,"
        "time_updated INTEGER NOT NULL,"
        "data TEXT NOT NULL)"
    )
    connection.executemany(
        "INSERT INTO session (id, directory, time_created, cost, tokens_input,"
        " tokens_output, tokens_reasoning, tokens_cache_read, tokens_cache_write)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        rows,
    )
    connection.executemany(
        "INSERT INTO message (id, session_id, time_created, time_updated, data)"
        " VALUES (?, ?, ?, ?, ?)",
        messages,
    )
    connection.executemany(
        "INSERT INTO part (id, message_id, session_id, time_created, time_updated, data)"
        " VALUES (?, ?, ?, ?, ?, ?)",
        parts,
    )
    connection.commit()
    connection.close()


def message_row(identifier, session_id, time_created, role):
    data = json.dumps({"role": role})
    return (identifier, session_id, time_created, time_created, data)


def part_row(identifier, message_id, session_id, time_created, part_type, text):
    data = json.dumps({"type": part_type, "text": text})
    return (identifier, message_id, session_id, time_created, time_created, data)


class SessionMetricsTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.db = Path(tmp.name) / "opencode.db"

    def fixture(self, rows=()):
        make_session_db(self.db, rows)
        return str(self.db)

    def test_lit_cout_et_tokens(self):
        path = self.fixture([("ses_1", "/repo", 1000, 0.25, 10, 20, 5, 30, 40)])
        self.assertEqual(
            orchestrator.session_metrics(path, "ses_1"),
            {
                "cost_usd": 0.25,
                "tokens": {
                    "input": 10,
                    "output": 20,
                    "reasoning": 5,
                    "cache_read": 30,
                    "cache_write": 40,
                },
            },
        )

    def test_session_inconnue(self):
        path = self.fixture()
        self.assertIsNone(orchestrator.session_metrics(path, "ses_absente"))

    def test_base_absente_ne_leve_pas(self):
        self.assertIsNone(orchestrator.session_metrics(str(self.db), "ses_1"))

    def test_schema_mouvant_ne_leve_pas(self):
        sqlite3.connect(self.db).close()
        self.assertIsNone(orchestrator.session_metrics(str(self.db), "ses_1"))

    def test_newest_session_filtre_repertoire_et_date(self):
        path = self.fixture(
            [
                ("ses_ancienne", "/repo", 1000, 0, 0, 0, 0, 0, 0),
                ("ses_autre", "/autre", 9000, 0, 0, 0, 0, 0, 0),
                ("ses_recente", "/repo", 3000, 0, 0, 0, 0, 0, 0),
                ("ses_derniere", "/repo", 8000, 0, 0, 0, 0, 0, 0),
            ]
        )
        with mock.patch.object(orchestrator, "db_path", return_value=path):
            self.assertEqual(orchestrator.newest_session("/repo", 2.0), "ses_derniere")

    def test_newest_session_aucune_correspondance(self):
        path = self.fixture([("ses_ancienne", "/repo", 1000, 0, 0, 0, 0, 0, 0)])
        with mock.patch.object(orchestrator, "db_path", return_value=path):
            self.assertIsNone(orchestrator.newest_session("/repo", 2.0))


class SessionPlanTextTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.db = Path(tmp.name) / "opencode.db"

    def fixture(self, messages=(), parts=()):
        make_session_db(
            self.db,
            rows=[("ses_1", "/repo", 1000, 0, 0, 0, 0, 0, 0)],
            messages=messages,
            parts=parts,
        )
        return str(self.db)

    def test_retient_le_dernier_texte_balise(self):
        path = self.fixture(
            messages=[
                message_row("msg_1", "ses_1", 1000, "assistant"),
                message_row("msg_2", "ses_1", 2000, "assistant"),
                message_row("msg_3", "ses_1", 3000, "assistant"),
            ],
            parts=[
                part_row("prt_1", "msg_1", "ses_1", 1000, "text", PLAN_TEXTE),
                part_row("prt_2", "msg_2", "ses_1", 2000, "text", PLAN_TEXTE),
                part_row("prt_3", "msg_3", "ses_1", 3000, "text", "Merci, à bientôt !"),
            ],
        )
        self.assertEqual(orchestrator.session_plan_text(path, "ses_1"), PLAN_TEXTE)

    def test_ignore_user_et_parts_non_textuelles(self):
        path = self.fixture(
            messages=[
                message_row("msg_user", "ses_1", 3000, "user"),
                message_row("msg_tool", "ses_1", 2000, "assistant"),
                message_row("msg_plan", "ses_1", 1000, "assistant"),
            ],
            parts=[
                part_row("prt_user", "msg_user", "ses_1", 3000, "text", PLAN_TEXTE),
                part_row("prt_tool", "msg_tool", "ses_1", 2000, "tool", PLAN_TEXTE),
                part_row("prt_plan", "msg_plan", "ses_1", 1000, "text", PLAN_TEXTE),
            ],
        )
        self.assertEqual(orchestrator.session_plan_text(path, "ses_1"), PLAN_TEXTE)

    def test_exige_les_deux_sentinelles(self):
        partiel = f"<<<FINAL_PLAN>>>\n{CORPS_PLAN}\n<<<END_FINAL_PLAN>>>"
        path = self.fixture(
            messages=[
                message_row("msg_partiel", "ses_1", 2000, "assistant"),
                message_row("msg_plan", "ses_1", 1000, "assistant"),
            ],
            parts=[
                part_row("prt_partiel", "msg_partiel", "ses_1", 2000, "text", partiel),
                part_row("prt_plan", "msg_plan", "ses_1", 1000, "text", PLAN_TEXTE),
            ],
        )
        self.assertEqual(orchestrator.session_plan_text(path, "ses_1"), PLAN_TEXTE)

    def test_borne_les_parts_parcourues(self):
        messages = [
            message_row(f"msg_{index}", "ses_1", 2000 + index, "assistant")
            for index in range(orchestrator.MAX_CAPTURE_PARTS)
        ]
        parts = [
            part_row(f"prt_{index}", f"msg_{index}", "ses_1", 2000 + index, "text", "Merci !")
            for index in range(orchestrator.MAX_CAPTURE_PARTS)
        ]
        messages.append(message_row("msg_vieux", "ses_1", 1000, "assistant"))
        parts.append(part_row("prt_vieux", "msg_vieux", "ses_1", 1000, "text", PLAN_TEXTE))
        path = self.fixture(messages=messages, parts=parts)
        self.assertIsNone(orchestrator.session_plan_text(path, "ses_1"))
        self.assertEqual(
            orchestrator.session_plan_text(
                path, "ses_1", limit=orchestrator.MAX_CAPTURE_PARTS + 1
            ),
            PLAN_TEXTE,
        )

    def test_sans_plan_ou_base_absente_sans_erreur(self):
        path = self.fixture(
            messages=[message_row("msg_1", "ses_1", 1000, "assistant")],
            parts=[part_row("prt_1", "msg_1", "ses_1", 1000, "text", "Merci !")],
        )
        self.assertIsNone(orchestrator.session_plan_text(path, "ses_1"))
        self.assertIsNone(orchestrator.session_plan_text(path, "ses_absente"))
        self.assertIsNone(orchestrator.session_plan_text(None, "ses_1"))
        self.assertIsNone(orchestrator.session_plan_text(path, None))
        self.assertIsNone(orchestrator.session_plan_text(path + ".absente", "ses_1"))

    def test_schema_inattendu_sans_erreur(self):
        sqlite3.connect(self.db).close()
        self.assertIsNone(orchestrator.session_plan_text(str(self.db), "ses_1"))


class InteractiveCaptureTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.run = orchestrator.Run.__new__(orchestrator.Run)
        self.run.repo = Path("/repo")
        self.run.args = mock.Mock(opencode_bin="opencode")
        self.run.run_dir = Path(tmp.name)

    def test_plan_lu_dans_la_base_sans_repli(self):
        with mock.patch.multiple(
            orchestrator,
            newest_session=mock.DEFAULT,
            db_path=mock.DEFAULT,
            session_plan_text=mock.DEFAULT,
        ) as mocks:
            mocks["newest_session"].return_value = "ses_1"
            mocks["db_path"].return_value = "/db"
            mocks["session_plan_text"].return_value = PLAN_TEXTE
            with mock.patch.object(self.run, "run_opencode") as fallback:
                self.assertEqual(
                    self.run.capture_interactive_plan(100.0, "capture"),
                    (CORPS_PLAN, CORPS_BRIEF),
                )
        fallback.assert_not_called()
        mocks["session_plan_text"].assert_called_once_with("/db", "ses_1")

    def test_repli_headless_cible_la_session(self):
        with mock.patch.multiple(
            orchestrator,
            newest_session=mock.DEFAULT,
            db_path=mock.DEFAULT,
            session_plan_text=mock.DEFAULT,
        ) as mocks:
            mocks["newest_session"].return_value = "ses_1"
            mocks["db_path"].return_value = "/db"
            mocks["session_plan_text"].return_value = None
            with mock.patch.object(self.run, "run_opencode", return_value=PLAN_TEXTE) as fallback:
                self.assertEqual(
                    self.run.capture_interactive_plan(100.0, "prompt capture"),
                    (CORPS_PLAN, CORPS_BRIEF),
                )
        fallback.assert_called_once_with("plan-capture", "prompt capture", session="ses_1")

    def test_session_non_resolue_sans_repli(self):
        with mock.patch.object(orchestrator, "newest_session", return_value=None):
            with mock.patch.object(self.run, "run_opencode") as fallback:
                self.assertEqual(
                    self.run.capture_interactive_plan(100.0, "capture"), (None, None)
                )
        fallback.assert_not_called()

    def test_texte_incomplet_rend_none(self):
        avec_repli = mock.patch.multiple(
            orchestrator,
            newest_session=mock.DEFAULT,
            db_path=mock.DEFAULT,
            session_plan_text=mock.DEFAULT,
        )
        with avec_repli as mocks:
            mocks["newest_session"].return_value = "ses_1"
            mocks["db_path"].return_value = "/db"
            mocks["session_plan_text"].return_value = f"<<<FINAL_PLAN>>>\n{CORPS_PLAN}\n"
            self.assertEqual(
                self.run.capture_interactive_plan(100.0, "capture"), (None, None)
            )

    def test_repli_en_echec_rend_none(self):
        with mock.patch.multiple(
            orchestrator,
            newest_session=mock.DEFAULT,
            db_path=mock.DEFAULT,
            session_plan_text=mock.DEFAULT,
        ) as mocks:
            mocks["newest_session"].return_value = "ses_1"
            mocks["db_path"].return_value = "/db"
            mocks["session_plan_text"].return_value = None
            with mock.patch.object(self.run, "run_opencode", side_effect=Failure("boom")):
                self.assertEqual(
                    self.run.capture_interactive_plan(100.0, "capture"), (None, None)
                )


class UsageTokensTests(unittest.TestCase):
    def test_normalise_l_usage_claude(self):
        tokens = orchestrator.usage_tokens(
            {
                "input_tokens": 12,
                "output_tokens": 34,
                "cache_read_input_tokens": 56,
                "cache_creation_input_tokens": 78,
            }
        )
        self.assertEqual(
            tokens,
            {"input": 12, "output": 34, "reasoning": 0, "cache_read": 56, "cache_write": 78},
        )

    def test_usage_absent_ou_non_dict(self):
        self.assertIsNone(orchestrator.usage_tokens(None))
        self.assertIsNone(orchestrator.usage_tokens([1, 2]))


class PhaseSummaryTests(unittest.TestCase):
    def test_agrege_durees_tokens_et_cout(self):
        summary = orchestrator.phase_summary(
            {
                "plan": {
                    "duration_s": 10.0,
                    "cost_usd": 0.5,
                    "tokens": {
                        "input": 1,
                        "output": 2,
                        "reasoning": 0,
                        "cache_read": 3,
                        "cache_write": 0,
                    },
                },
                "review": {
                    "duration_s": 5.5,
                    "cost_usd": 0.25,
                    "tokens": {
                        "input": 10,
                        "output": 20,
                        "reasoning": 0,
                        "cache_read": 30,
                        "cache_write": 0,
                    },
                },
            }
        )
        self.assertEqual(summary["duration_s"], 15.5)
        self.assertEqual(summary["cost_usd"], 0.75)
        self.assertEqual(summary["tokens"]["cache_read"], 33)
        self.assertEqual(summary["total_tokens"], 66)

    def test_phase_sans_mesure(self):
        summary = orchestrator.phase_summary({"plan-capture": {"duration_s": 29.2, "exit_code": 0}})
        self.assertEqual(summary["cost_usd"], 0.0)
        self.assertEqual(summary["total_tokens"], 0)


class PlanWithArgsTests(unittest.TestCase):
    def parse(self, *argv):
        with mock.patch("sys.stderr"):
            return orchestrator.parse_args(list(argv))

    def test_defaut_opencode(self):
        args = self.parse("--repo", "/tmp")
        self.assertEqual(args.plan_with, "opencode")
        self.assertIsNone(args.planner_prompt)

    def test_choix_claude(self):
        args = self.parse("--plan-with", "claude")
        self.assertEqual(args.plan_with, "claude")

    def test_choix_invalide(self):
        with self.assertRaises(SystemExit):
            self.parse("--plan-with", "gemini")


class PromptPathTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        for name in ("planner.opencode.md", "plan.claude.md"):
            (self.dir / name).write_text("prompt de test", encoding="utf-8")
        self.run = orchestrator.Run.__new__(orchestrator.Run)
        self.run.prompt_dir = self.dir
        self.run.args = mock.Mock(
            plan_prompt=None,
            interactive_prompt=None,
            planner_prompt=None,
            capture_prompt=None,
            review_claude_prompt=None,
            review_opencode_prompt=None,
            synth_prompt=None,
            exec_prompt=None,
        )

    def custom_prompt(self, name):
        path = self.dir / name
        path.write_text("prompt surchargé", encoding="utf-8")
        return path

    def test_planner_opencode_par_defaut(self):
        self.assertEqual(
            self.run.prompt_path("planner", "opencode"),
            self.dir / "planner.opencode.md",
        )

    def test_planner_prompt_surcharge(self):
        custom = self.custom_prompt("custom-planner.md")
        self.run.args.planner_prompt = str(custom)
        self.assertEqual(self.run.prompt_path("planner", "opencode"), custom)

    def test_plan_prompt_claude_toujours_honore(self):
        custom = self.custom_prompt("custom-claude.md")
        self.run.args.plan_prompt = str(custom)
        self.assertEqual(self.run.prompt_path("plan", "claude"), custom)

    def test_interactive_prompt_toujours_honore(self):
        custom = self.custom_prompt("custom-interactif.md")
        self.run.args.interactive_prompt = str(custom)
        self.assertEqual(self.run.prompt_path("plan", "opencode"), custom)


class PhasePlanTests(unittest.TestCase):
    def make_run(self, **overrides):
        run = orchestrator.Run.__new__(orchestrator.Run)
        run.repo = Path("/repo")
        run.run_dir = Path("/run")
        run.task = "Ajouter une fonctionnalité"
        values = {"plan_with": "opencode", "test_cmd": "nix flake check"}
        values.update(overrides)
        run.args = mock.Mock(**values)
        run.vcs = mock.Mock(return_value="jj")
        run.prompt = mock.Mock(
            return_value="repo={{repo}} task={{task}} test={{test_cmd}} vcs={{vcs}}"
        )
        run.write_artifact = mock.Mock()
        return run

    def test_opencode_headless_par_defaut(self):
        run = self.make_run()
        run.call_opencode = mock.Mock(return_value=CORPS_PLAN)
        run.call_claude = mock.Mock()

        run.phase_plan()

        run.call_claude.assert_not_called()
        run.call_opencode.assert_called_once()
        tag, prompt, block = run.call_opencode.call_args.args
        self.assertEqual(tag, "plan")
        self.assertEqual(block, "PLAN")
        self.assertIn("task=Ajouter une fonctionnalité", prompt)
        self.assertIn("test=nix flake check", prompt)
        self.assertIn("vcs=jj", prompt)
        run.prompt.assert_called_once_with("planner", "opencode")
        run.write_artifact.assert_called_once_with("01-plan.md", CORPS_PLAN)

    def test_claude_avec_effort_high(self):
        run = self.make_run(plan_with="claude")
        run.call_opencode = mock.Mock()
        run.call_claude = mock.Mock(return_value=CORPS_PLAN)

        run.phase_plan()

        run.call_opencode.assert_not_called()
        run.call_claude.assert_called_once()
        tag, prompt = run.call_claude.call_args.args
        self.assertEqual(tag, "plan")
        self.assertEqual(run.call_claude.call_args.kwargs.get("effort"), "high")
        self.assertIn("test=nix flake check", prompt)
        self.assertIn("vcs=jj", prompt)
        run.prompt.assert_called_once_with("plan", "claude")
        run.write_artifact.assert_called_once_with("01-plan.md", CORPS_PLAN)


class CallClaudeEffortTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.run = orchestrator.Run.__new__(orchestrator.Run)
        self.run.repo = Path("/repo")
        self.run.run_dir = Path(tmp.name)
        self.run.meta = {"phases": {}}
        self.run.args = mock.Mock(
            claude_bin="claude", claude_model="opus", timeout=5, verbose=False
        )

    def call(self, **kwargs):
        payload = {"result": "contenu", "total_cost_usd": 0.0, "session_id": "s1"}
        with mock.patch.object(
            orchestrator, "run_streamed", return_value=(0, "{}")
        ) as streamed:
            with mock.patch.object(
                orchestrator, "parse_claude_json", return_value=("contenu", payload)
            ):
                self.run.call_claude("plan", "prompt", **kwargs)
        return streamed.call_args.args[0]

    def test_effort_high_ajoute(self):
        cmd = self.call(effort="high")
        self.assertEqual(cmd[cmd.index("--effort") + 1], "high")

    def test_sans_effort_par_defaut(self):
        self.assertNotIn("--effort", self.call())


if __name__ == "__main__":
    unittest.main()
