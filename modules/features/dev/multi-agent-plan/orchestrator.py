#!/usr/bin/env python3
"""multi-agent-plan — planification multi-agents et exécution supervisée.

Pipeline :
  1. Claude planifie le dépôt en lecture seule        -> 01-plan.md
  2. OpenCode et Claude relisent le plan en parallèle -> 02/03-review-*.md
  3. OpenCode fusionne le tout en plan atomique       -> 04-final-plan.md
  4. Exécution interactive, étape par étape, un commit
     atomique par étape (l'agent committe, l'utilisateur
     approuve via les permissions "ask")               -> 05-execution.md + progress.json

Tous les artefacts d'un run vivent dans le dossier de run (défaut :
<repo>/.agent-plans/<horodatage>). Le script n'écrit jamais dans le dépôt cible
en dehors de ce dossier ; l'exécution passe par une TUI opencode supervisée.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import textwrap
import threading
import time
from datetime import datetime
from pathlib import Path

VERSION = "0.1.0"
ORDER = ("plan", "reviews", "final", "execute")
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
SENTINEL_RE = re.compile(r"<<<[A-Z_]+>>>\s*(.*?)\s*<<<END>>>", re.DOTALL)
STEP_RE = re.compile(r"^##\s+Step\s+(\d+)\s*[—–:-]\s*(.+?)\s*$", re.MULTILINE)
COMMIT_RE = re.compile(r"^\*\*Commit\*\*\s*:\s*(.+?)\s*$", re.MULTILINE)
TEST_TAIL = 30


class Failure(Exception):
    """Échec attendu d'une phase : message affiché, artefacts conservés."""


def log(message):
    print(f"[multi-agent-plan] {message}", flush=True)


def die(message, code=2):
    print(f"[multi-agent-plan] erreur: {message}", file=sys.stderr, flush=True)
    sys.exit(code)


def stamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def render(template, **values):
    out = template
    for key, value in values.items():
        out = out.replace("{{" + key + "}}", str(value))
    return out


def tail(text, lines=TEST_TAIL):
    rows = text.strip().splitlines()
    return "\n".join(rows[-lines:])


def parse_claude_json(raw):
    text = raw.strip()
    if not text:
        raise Failure("sortie claude vide")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        match = SENTINEL_RE.search(ANSI_RE.sub("", text))
        if match:
            return match.group(1).strip(), {}
        raise Failure(f"sortie claude illisible : {text[:300]!r}")
    if isinstance(payload, dict):
        result = payload.get("result")
        if isinstance(result, str) and result.strip():
            return result.strip(), payload
    raise Failure("champ 'result' absent de la sortie claude")


def parse_steps(markdown):
    matches = list(STEP_RE.finditer(markdown))
    steps = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(markdown)
        body = markdown[match.end():end].strip()
        commit_match = COMMIT_RE.search(body)
        commit = commit_match.group(1).strip().strip("`").strip() if commit_match else None
        steps.append(
            {
                "number": int(match.group(1)),
                "title": match.group(2).strip(),
                "body": body,
                "commit": commit,
            }
        )
    return steps


def run_streamed(cmd, cwd, log_path, tag, timeout=None, verbose=False):
    log_path.parent.mkdir(parents=True, exist_ok=True)
    timed_out = False
    with log_path.open("w", encoding="utf-8") as handle:
        handle.write(f"$ {shlex.join(cmd)}\n\n")
        handle.flush()
        proc = subprocess.Popen(
            cmd,
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )

        def on_timeout():
            nonlocal timed_out
            timed_out = True
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

        timer = threading.Timer(timeout, on_timeout) if timeout else None
        if timer:
            timer.start()
        chunks = []
        try:
            assert proc.stdout is not None
            for line in proc.stdout:
                chunks.append(line)
                handle.write(line)
                handle.flush()
                if verbose:
                    print(f"[{tag}] {line.rstrip()}", flush=True)
        finally:
            returncode = proc.wait()
            if timer:
                timer.cancel()
        if timed_out:
            raise Failure(f"{tag}: délai dépassé ({timeout}s), processus tué — voir {log_path}")
        return returncode, "".join(chunks)


def head_commit(repo):
    proc = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
    )
    return proc.stdout.strip() if proc.returncode == 0 else None


def commit_count(repo, before, after):
    proc = subprocess.run(
        ["git", "-C", str(repo), "rev-list", "--count", f"{before}..{after}"],
        capture_output=True,
        text=True,
    )
    try:
        return int(proc.stdout.strip())
    except ValueError:
        return 1


def show_commit(repo, commit):
    subprocess.run(["git", "-C", str(repo), "show", "--stat", "--oneline", "--no-renames", commit])


def append_journal(path, line):
    with path.open("a", encoding="utf-8") as handle:
        handle.write(line)


def ask_choice(question, options):
    keys = "/".join(key for key, _ in options)
    while True:
        try:
            answer = input(f"{question} [{keys}] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            return "q"
        for key, _ in options:
            if answer == key:
                return key
        print(f"Réponse attendue : {keys}")


class Progress:
    def __init__(self, path):
        self.path = path
        self.data = {"steps": {}}
        if path.exists():
            try:
                self.data.update(json.loads(path.read_text(encoding="utf-8")))
            except json.JSONDecodeError:
                pass

    def status(self, number):
        return self.data["steps"].get(str(number), {}).get("status")

    def mark(self, number, **values):
        entry = self.data["steps"].setdefault(str(number), {})
        entry.update(values)
        entry["at"] = stamp()
        self.save()

    def save(self):
        tmp = self.path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(self.data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        tmp.replace(self.path)


class Run:
    def __init__(self, args):
        self.args = args
        self.repo = Path(args.repo).expanduser().resolve()
        self.prompt_dir = self._prompt_dir()
        self.task = self._task()
        self.run_dir = self._run_dir()
        self.exit_code = 0
        self.meta = {
            "tool": "multi-agent-plan",
            "version": VERSION,
            "started": stamp(),
            "repo": str(self.repo),
            "task": (self.task or "")[:4000],
            "phases": {},
            "steps": {},
        }

    def _prompt_dir(self):
        if self.args.prompt_dir:
            path = Path(self.args.prompt_dir).expanduser()
            if not path.is_dir():
                die(f"dossier de prompts introuvable : {path}")
            return path.resolve()
        env = os.environ.get("MULTI_AGENT_PLAN_PROMPTS")
        if env and Path(env).is_dir():
            return Path(env).resolve()
        default = Path(__file__).resolve().parent / "prompts"
        if default.is_dir():
            return default
        die("dossier de prompts introuvable (--prompt-dir ou MULTI_AGENT_PLAN_PROMPTS)")
        raise AssertionError

    def _task(self):
        if self.args.task_file:
            return Path(self.args.task_file).expanduser().read_text(encoding="utf-8").strip()
        return (self.args.task or "").strip()

    def _run_dir(self):
        if self.args.out:
            path = Path(self.args.out).expanduser().resolve()
            if not self.args.dry_run:
                path.mkdir(parents=True, exist_ok=True)
            return path
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        path = self.repo / ".agent-plans" / timestamp
        if not self.args.dry_run:
            path.mkdir(parents=True, exist_ok=True)
            ignore = self.repo / ".agent-plans" / ".gitignore"
            if not ignore.exists():
                ignore.write_text("*\n", encoding="utf-8")
        return path

    def vcs(self):
        if self.args.vcs != "auto":
            return self.args.vcs
        if (self.repo / ".jj").exists():
            return "jj"
        if (self.repo / ".git").exists():
            return "git"
        return "none"

    def preflight(self):
        if not self.repo.is_dir():
            die(f"dépôt introuvable : {self.repo}")
        for name in ("claude_bin", "opencode_bin"):
            binary = getattr(self.args, name)
            if not shutil.which(binary):
                die(f"binaire introuvable dans le PATH : {binary}")
        if self.vcs() == "none":
            log("attention : ni .git ni .jj dans le dépôt — pas de vérification de commit possible")
        elif not self.args.dry_run:
            self._warn_dirty()

    def _warn_dirty(self):
        proc = subprocess.run(
            ["git", "-C", str(self.repo), "status", "--porcelain"],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            log("attention : working tree non propre — les commits d'étape s'ajouteront par-dessus")

    def prompt_path(self, phase, agent):
        explicit = {
            ("plan", "claude"): self.args.plan_prompt,
            ("review", "claude"): self.args.review_claude_prompt,
            ("review", "opencode"): self.args.review_opencode_prompt,
            ("synth", "opencode"): self.args.synth_prompt,
            ("exec", "opencode"): self.args.exec_prompt,
        }.get((phase, agent))
        path = Path(explicit).expanduser() if explicit else self.prompt_dir / f"{phase}.{agent}.md"
        if not path.is_file():
            die(f"prompt introuvable : {path}")
        return path

    def prompt(self, phase, agent):
        return self.prompt_path(phase, agent).read_text(encoding="utf-8")

    def write_artifact(self, filename, text):
        path = self.run_dir / filename
        path.write_text(text.rstrip() + "\n", encoding="utf-8")
        log(f"écrit {path}")

    def read_artifact(self, filename):
        path = self.run_dir / filename
        if not path.is_file():
            raise Failure(f"artefact manquant : {path} (relance la phase amont)")
        return path.read_text(encoding="utf-8")

    def save_meta(self):
        if self.args.dry_run:
            return
        self.meta["finished"] = stamp()
        self.meta["run_dir"] = str(self.run_dir)
        self.meta["vcs"] = self.vcs()
        path = self.run_dir / "meta.json"
        path.write_text(json.dumps(self.meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    def call_claude(self, tag, prompt):
        cmd = [
            self.args.claude_bin,
            "-p",
            "--model",
            self.args.claude_model,
            "--permission-mode",
            "plan",
            "--output-format",
            "json",
            prompt,
        ]
        log_path = self.run_dir / "logs" / f"{tag}.log"
        started = time.time()
        returncode, output = run_streamed(
            cmd, self.repo, log_path, tag, self.args.timeout, self.args.verbose
        )
        duration = round(time.time() - started, 1)
        if returncode != 0:
            raise Failure(f"{tag}: claude a échoué (code {returncode}) — voir {log_path}")
        text, payload = parse_claude_json(output)
        if payload.get("is_error"):
            raise Failure(f"{tag}: claude a signalé une erreur — voir {log_path}")
        cost = payload.get("total_cost_usd")
        self.meta["phases"][tag] = {
            "duration_s": duration,
            "exit_code": returncode,
            "session_id": payload.get("session_id"),
            "cost_usd": cost,
            "num_turns": payload.get("num_turns"),
        }
        suffix = f" ({cost:.4f} $)" if isinstance(cost, (int, float)) else ""
        log(f"{tag}: terminé en {duration}s{suffix}")
        return text

    def call_opencode(self, tag, prompt):
        # --auto : en headless, une permission "ask" (dont external_directory)
        # est auto-rejetée sans TTY, ce qui fait échouer l'exploration du dépôt.
        # L'agent plan est en lecture seule (edit/write absents), le risque est
        # donc limité à la lecture ; l'exécution interactive, elle, garde les
        # permissions "ask" pour l'utilisateur.
        cmd = [
            self.args.opencode_bin,
            "run",
            "--agent",
            self.args.plan_agent,
            "--auto",
            "-m",
            self.args.opencode_model,
            prompt,
        ]
        log_path = self.run_dir / "logs" / f"{tag}.log"
        started = time.time()
        returncode, output = run_streamed(
            cmd, self.repo, log_path, tag, self.args.timeout, self.args.verbose
        )
        duration = round(time.time() - started, 1)
        if returncode != 0:
            raise Failure(f"{tag}: opencode a échoué (code {returncode}) — voir {log_path}")
        clean = ANSI_RE.sub("", output)
        match = SENTINEL_RE.search(clean)
        if not match:
            raise Failure(f"{tag}: marqueurs <<<...>>> absents de la sortie — voir {log_path}")
        self.meta["phases"][tag] = {"duration_s": duration, "exit_code": returncode}
        log(f"{tag}: terminé en {duration}s")
        return match.group(1).strip()

    def phase_plan(self):
        log("Phase 1/4 — Claude analyse le dépôt et rédige le plan")
        prompt = render(self.prompt("plan", "claude"), task=self.task, repo=str(self.repo))
        self.write_artifact("01-plan.md", self.call_claude("plan", prompt))

    def phase_reviews(self):
        log("Phase 2/4 — relectures parallèles (OpenCode + Claude)")
        plan = self.read_artifact("01-plan.md")

        def review_opencode():
            prompt = render(
                self.prompt("review", "opencode"),
                repo=str(self.repo),
                task=self.task,
                plan=plan,
            )
            return self.call_opencode("review-opencode", prompt)

        def review_claude():
            prompt = render(
                self.prompt("review", "claude"),
                repo=str(self.repo),
                task=self.task,
                plan=plan,
            )
            return self.call_claude("review-claude", prompt)

        jobs = {"review-opencode": review_opencode, "review-claude": review_claude}
        results = {}
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = {name: pool.submit(job) for name, job in jobs.items()}
            for name, future in futures.items():
                try:
                    results[name] = future.result()
                except Failure as exc:
                    log(f"échec de {name} : {exc}")
        if not results:
            raise Failure("les deux reviews ont échoué")
        for name, filename in (
            ("review-opencode", "02-review-opencode.md"),
            ("review-claude", "03-review-claude.md"),
        ):
            if name in results:
                self.write_artifact(filename, results[name])
        if len(results) == 1:
            log("une seule review disponible — la synthèse continuera sans l'autre")

    def phase_final(self):
        log("Phase 3/4 — OpenCode fusionne le plan et les reviews")
        plan = self.read_artifact("01-plan.md")
        parts = []
        for filename, label in (
            ("02-review-opencode.md", "OpenCode"),
            ("03-review-claude.md", "Claude"),
        ):
            path = self.run_dir / filename
            if path.exists():
                parts.append(f"### Review {label}\n\n{path.read_text(encoding='utf-8')}")
        prompt = render(
            self.prompt("synth", "opencode"),
            repo=str(self.repo),
            task=self.task,
            plan=plan,
            reviews="\n\n".join(parts),
            test_cmd=self.args.test_cmd or "aucune — l'agent exécutera les tests du projet",
        )
        text = self.call_opencode("synth", prompt)
        self.write_artifact("04-final-plan.md", text)
        steps = parse_steps(text)
        if not steps:
            raise Failure(
                "aucune étape '## Step N' détectée dans le plan final — vérifie prompts/synth.opencode.md"
            )
        log(f"{len(steps)} étapes atomiques détectées")
        self.meta["steps"] = {
            str(step["number"]): {"title": step["title"], "commit": step["commit"]}
            for step in steps
        }

    def phase_execute(self):
        if not sys.stdin.isatty():
            raise Failure("la phase d'exécution nécessite un terminal interactif (TTY)")
        steps = parse_steps(self.read_artifact("04-final-plan.md"))
        if not steps:
            raise Failure("aucune étape '## Step N' détectée dans 04-final-plan.md")
        progress = Progress(self.run_dir / "progress.json")
        journal = self.run_dir / "05-execution.md"
        if not journal.exists():
            journal.write_text(
                f"# Exécution — {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n",
                encoding="utf-8",
            )
        vcs = self.vcs()
        test_cmd = self.args.test_cmd or ""
        if not test_cmd:
            log("aucune --test-cmd fournie : l'agent devra lancer les tests du projet lui-même")
        for step in steps:
            number = step["number"]
            if progress.status(number) == "done":
                log(f"Étape {number} déjà terminée — ignorée")
                continue
            if self.args.step and number < self.args.step:
                continue
            commits = [
                entry["commit"][:12]
                for entry in progress.data["steps"].values()
                if entry.get("commit")
            ]
            if not self._execute_step(step, steps, progress, journal, vcs, test_cmd, commits):
                return 1
        log("exécution terminée")
        return 0

    def _execute_step(self, step, steps, progress, journal, vcs, test_cmd, commits):
        number = step["number"]
        base_prompt = render(
            self.prompt("exec", "opencode"),
            repo=str(self.repo),
            step=step["body"],
            step_number=number,
            step_total=len(steps),
            step_title=step["title"],
            commit_message=step["commit"] or "type(scope): description conventionnelle",
            test_cmd=test_cmd or "aucune fournie — utilise les tests du projet",
            vcs=vcs,
            commits="\n".join(f"- {commit}" for commit in commits) or "(aucun)",
        )
        prompt = base_prompt
        while True:
            before = head_commit(self.repo)
            log(f"Étape {number}/{len(steps)} — {step['title']} : ouverture de la TUI opencode")
            returncode = subprocess.call(self._tui_cmd(prompt), cwd=str(self.repo))
            if returncode not in (0, 130):
                log(f"TUI terminée avec le code {returncode}")
            after = head_commit(self.repo)
            if after is None or after == before:
                action = ask_choice(
                    f"Aucun nouveau commit détecté pour l'étape {number}.",
                    [
                        ("r", "réouvrir la TUI"),
                        ("m", "marquer faite sans commit"),
                        ("s", "skip"),
                        ("q", "quitter"),
                    ],
                )
                if action == "r":
                    prompt = (
                        base_prompt
                        + "\n\nNote : la tentative précédente n'a produit aucun commit — "
                        "vérifie l'état du dépôt et reprends l'étape."
                    )
                    continue
                if action == "m":
                    progress.mark(number, status="done", commit=None, tests="unverified")
                    append_journal(
                        journal,
                        f"- Step {number} — {step['title']} : ⚠️ faite sans commit vérifiable\n",
                    )
                    return True
                if action == "s":
                    progress.mark(number, status="skipped", commit=None, tests="unverified")
                    append_journal(journal, f"- Step {number} — {step['title']} : ⏭️ skip (aucun commit)\n")
                    return True
                return False

            commit = after
            count = commit_count(self.repo, before, after)
            if count > 1:
                log(f"attention : {count} commits créés pour l'étape {number} (atomicité non respectée)")
            show_commit(self.repo, commit)

            test_status = "skipped"
            if test_cmd:
                test_returncode, test_output = self._run_tests(number, test_cmd)
                if test_returncode != 0:
                    print(tail(test_output, TEST_TAIL))
                    log(f"tests rouges — log complet : {self.run_dir}/logs/tests-step-{number}.log")
                    action = ask_choice(
                        f"Tests rouges pour l'étape {number}.",
                        [
                            ("r", "réouvrir la TUI pour corriger"),
                            ("c", "continuer quand même"),
                            ("s", "skip"),
                            ("q", "quitter"),
                        ],
                    )
                    if action == "r":
                        prompt = (
                            base_prompt
                            + "\n\nLes tests échouent encore :\n\n```\n"
                            + tail(test_output, 60)
                            + "\n```"
                        )
                        continue
                    if action == "c":
                        test_status = "failed_accepted"
                    elif action == "s":
                        progress.mark(number, status="skipped", commit=commit, tests="failed")
                        append_journal(
                            journal,
                            f"- Step {number} — {step['title']} : ⏭️ skip après tests rouges ({commit[:12]})\n",
                        )
                        return True
                    else:
                        return False
                else:
                    test_status = "ok"
                    log("tests verts")

            action = ask_choice(
                f"Étape {number} commitée ({commit[:10]}).",
                [("n", "étape suivante"), ("r", "réouvrir la TUI"), ("q", "quitter")],
            )
            if action == "r":
                prompt = base_prompt
                continue
            if action == "q":
                return False
            progress.mark(number, status="done", commit=commit, tests=test_status)
            append_journal(
                journal, f"- Step {number} — {step['title']} : ✅ {commit[:12]} (tests: {test_status})\n"
            )
            return True

    def _tui_cmd(self, prompt):
        return [
            self.args.opencode_bin,
            "--agent",
            self.args.build_agent,
            "-m",
            self.args.opencode_model,
            "--prompt",
            prompt,
        ]

    def _run_tests(self, number, test_cmd):
        log(f"tests : {test_cmd}")
        log_path = self.run_dir / "logs" / f"tests-step-{number}.log"
        return run_streamed(
            ["bash", "-lc", test_cmd],
            self.repo,
            log_path,
            f"tests-step-{number}",
            self.args.timeout,
            self.args.verbose,
        )

    def print_plan(self, phases):
        args = self.args
        print(f"dry-run — repo    : {self.repo}")
        print(f"dry-run — run_dir : {self.run_dir}")
        print(f"dry-run — prompts : {self.prompt_dir}")
        if "plan" in phases:
            print(
                f"  1. plan    : {args.claude_bin} -p --model {args.claude_model} "
                f"--permission-mode plan --output-format json <{self.prompt_path('plan', 'claude')}>"
            )
        if "reviews" in phases:
            print(
                f"  2. review  : {args.opencode_bin} run --agent {args.plan_agent} "
                f"-m {args.opencode_model} <{self.prompt_path('review', 'opencode')}>"
            )
            print(
                f"     review  : {args.claude_bin} -p --model {args.claude_model} "
                f"--permission-mode plan --output-format json <{self.prompt_path('review', 'claude')}>"
            )
        if "final" in phases:
            print(
                f"  3. synth   : {args.opencode_bin} run --agent {args.plan_agent} "
                f"-m {args.opencode_model} <{self.prompt_path('synth', 'opencode')}>"
            )
        if "execute" in phases:
            plan_file = self.run_dir / "04-final-plan.md"
            if plan_file.exists():
                for step in parse_steps(plan_file.read_text(encoding="utf-8")):
                    print(
                        f"     step {step['number']}: {step['title']} | commit: {step['commit']}"
                    )
            print(
                f"  4. exec    : {args.opencode_bin} --agent {args.build_agent} "
                f"-m {args.opencode_model} --prompt <{self.prompt_path('exec', 'opencode')}> (TUI)"
            )


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="multi-agent-plan",
        description=(
            "Planification multi-agents (Claude + OpenCode) puis exécution OpenCode "
            "interactive, étape par étape, avec un commit atomique par étape."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """\
            phases : plan -> reviews -> final -> execute (défaut : tout)
            exemples :
              multi-agent-plan --repo ~/projet --task "Ajouter l'auth OAuth2" --test-cmd "nix flake check"
              multi-agent-plan --repo ~/projet --task-file task.md --stop-after final
              multi-agent-plan --repo ~/projet --from execute --out ~/projet/.agent-plans/20261001-120000
            codes de sortie : 0 succès, 1 exécution interrompue/skippée, 2 erreur de configuration,
            3 échec de phase headless
            """
        ),
    )
    parser.add_argument("--version", action="version", version=f"multi-agent-plan {VERSION}")
    parser.add_argument("--repo", default=".", help="dépôt cible (défaut : répertoire courant)")
    parser.add_argument("--task", help="description de la tâche à planifier")
    parser.add_argument("--task-file", help="fichier contenant la tâche (alternative à --task)")
    parser.add_argument("--out", help="dossier du run (défaut : <repo>/.agent-plans/<horodatage>)")
    parser.add_argument("--from", dest="from_phase", choices=ORDER, help="phase de départ (reprise)")
    parser.add_argument(
        "--stop-after",
        choices=ORDER + ("all",),
        default="all",
        help="dernière phase à exécuter (défaut : all)",
    )
    parser.add_argument("--step", type=int, help="ne reprendre l'exécution qu'à partir de cette étape")
    parser.add_argument("--claude-bin", default="claude")
    parser.add_argument("--claude-model", default="opus")
    parser.add_argument("--opencode-bin", default="opencode")
    parser.add_argument("--opencode-model", default="opencode-go/deepseek-v4.1-flash")
    parser.add_argument("--plan-agent", default="plan", help="agent opencode des phases d'analyse")
    parser.add_argument("--build-agent", default="build", help="agent opencode de la TUI d'exécution")
    parser.add_argument("--test-cmd", help="commande de test vérifiée avant chaque commit d'étape")
    parser.add_argument(
        "--vcs",
        choices=("auto", "git", "jj", "none"),
        default="auto",
        help="VCS indiqué à l'agent (défaut : auto = jj si .jj sinon git)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=1800,
        help="délai max par phase headless ou commande de test, en secondes (défaut : 1800)",
    )
    parser.add_argument(
        "--prompt-dir",
        help="dossier des prompts (défaut : MULTI_AGENT_PLAN_PROMPTS ou prompts/ du paquet)",
    )
    parser.add_argument("--plan-prompt", help="fichier de prompt pour la phase plan (Claude)")
    parser.add_argument("--review-claude-prompt", help="fichier de prompt pour la review Claude")
    parser.add_argument("--review-opencode-prompt", help="fichier de prompt pour la review OpenCode")
    parser.add_argument("--synth-prompt", help="fichier de prompt pour la synthèse (OpenCode)")
    parser.add_argument("--exec-prompt", help="fichier de prompt pour l'exécution (OpenCode)")
    parser.add_argument("--dry-run", action="store_true", help="afficher le déroulé sans rien exécuter")
    parser.add_argument("--verbose", action="store_true", help="streamer les sorties des phases headless")
    args = parser.parse_args(argv)
    if args.task and args.task_file:
        parser.error("--task et --task-file sont exclusifs")
    if not args.task and not args.task_file and (args.from_phase or "plan") == "plan":
        parser.error("--task ou --task-file est requis pour la phase de planification")
    if args.from_phase and args.from_phase != "plan" and not args.out:
        parser.error("--out est requis pour reprendre à une phase intermédiaire")
    return args


def main(argv):
    args = parse_args(argv)
    run = Run(args)
    run.preflight()
    start = args.from_phase or "plan"
    stop = args.stop_after or "all"
    if stop == "all":
        stop = "execute"
    phases = ORDER[ORDER.index(start): ORDER.index(stop) + 1]
    if args.dry_run:
        run.print_plan(phases)
        return 0
    try:
        for phase in phases:
            method = getattr(run, f"phase_{phase}")
            if phase == "execute":
                run.exit_code = method()
            else:
                method()
    except Failure as exc:
        run.save_meta()
        die(str(exc), 3)
    run.save_meta()
    return run.exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
