#!/usr/bin/env python3
"""multi-agent-plan — planification multi-agents et exécution supervisée.

Pipeline :
  1. Plan :
     - sans --task/--task-file : session interactive OpenCode pour préciser le
       plan, capturée sans appel LLM depuis la base locale (messages assistant),
       avec repli `opencode run --session <id>` sinon ;
     - avec --task/--task-file : OpenCode planifie en headless (agent plan,
       --plan-with claude pour Claude)                 -> 00-brief.md, 01-plan.md
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
import sqlite3
import subprocess
import sys
import textwrap
import threading
import time
from datetime import datetime
from pathlib import Path

VERSION = "0.2.0"
ORDER = ("plan", "reviews", "final", "execute")
ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
END_MARKER = "<<<END>>>"
SENTINELS = {
    "BRIEF": ("<<<BRIEF>>>", "<<<END_BRIEF>>>"),
    "PLAN": ("<<<PLAN>>>", "<<<END_PLAN>>>"),
    "REVIEW": ("<<<REVIEW>>>", "<<<END_REVIEW>>>"),
    "FINAL_PLAN": ("<<<FINAL_PLAN>>>", "<<<END_FINAL_PLAN>>>"),
}
FENCE_RE = re.compile(r"^\s*(?:```|~~~)", re.MULTILINE)
MIN_BLOCK_CHARS = 40
STEP_RE = re.compile(r"^##\s+Step\s+(\d+)\s*[—–:-]\s*(.+?)\s*$", re.MULTILINE)
COMMIT_RE = re.compile(r"^\*\*Commit\*\*\s*:\s*(.+?)\s*$", re.MULTILINE)
TEST_TAIL = 30
TOKEN_KEYS = ("input", "output", "reasoning", "cache_read", "cache_write")
MAX_CAPTURE_PARTS = 20
CAPTURE_MARKERS = (SENTINELS["BRIEF"][0], SENTINELS["FINAL_PLAN"][0])
AGENT_LINE_RE = re.compile(r"^(\S+) \((?:primary|subagent|all)\)\s*$", re.MULTILINE)


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


def _block_failure(opener, reason, text, log_path=None):
    if log_path is not None:
        path = Path(log_path)
        size = path.stat().st_size if path.exists() else len(text)
        detail = f" — log de capture : {path} ({size} octets)"
    else:
        detail = f" — capture de {len(text)} caractères"
    return Failure(f"{opener} : {reason}{detail}")


def parse_block(text, opener, closer, log_path=None):
    """Extrait le corps d'un bloc délimité, sans troncature silencieuse.

    La fermeture unique (ex. <<<END_FINAL_PLAN>>>) est prioritaire ; l'ancien
    marqueur <<<END>>> reste accepté en repli pour les captures rétro-compat.
    Un bloc absent, trop court ou coupé dans un fence Markdown lève Failure.
    """
    start = text.find(opener)
    if start == -1:
        raise _block_failure(opener, "bloc absent", text, log_path)
    end = text.find(closer, start + len(opener))
    if end == -1:
        end = text.find(END_MARKER, start + len(opener))
    if end == -1:
        raise _block_failure(opener, "fermeture absente", text, log_path)
    body = text[start + len(opener):end].strip()
    if len(body) < MIN_BLOCK_CHARS:
        raise _block_failure(
            opener, f"bloc suspect (moins de {MIN_BLOCK_CHARS} caractères)", text, log_path
        )
    if len(FENCE_RE.findall(body)) % 2:
        raise _block_failure(opener, "bloc tronqué (fence Markdown non fermé)", text, log_path)
    return body


def parse_any_block(text, log_path=None):
    found = [
        (text.find(opener), opener, closer)
        for opener, closer in SENTINELS.values()
        if opener in text
    ]
    if not found:
        raise Failure("aucun marqueur <<<...>>> trouvé")
    _, opener, closer = min(found)
    return parse_block(text, opener, closer, log_path=log_path)


def parse_claude_json(raw):
    text = raw.strip()
    if not text:
        raise Failure("sortie claude vide")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        try:
            return parse_any_block(ANSI_RE.sub("", text)), {}
        except Failure as exc:
            raise Failure(f"sortie claude illisible : {text[:300]!r} ({exc})") from None
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


def empty_tokens():
    return {key: 0 for key in TOKEN_KEYS}


def int_or_zero(value):
    return int(value) if isinstance(value, (int, float)) else 0


def usage_tokens(usage):
    """Normalise l'objet `usage` de Claude en tokens comparables à OpenCode."""
    if not isinstance(usage, dict):
        return None
    return {
        "input": int_or_zero(usage.get("input_tokens")),
        "output": int_or_zero(usage.get("output_tokens")),
        "reasoning": int_or_zero(usage.get("reasoning_tokens")),
        "cache_read": int_or_zero(usage.get("cache_read_input_tokens")),
        "cache_write": int_or_zero(usage.get("cache_creation_input_tokens")),
    }


def token_total(tokens):
    if not isinstance(tokens, dict):
        return 0
    return sum(
        value
        for key, value in tokens.items()
        if key in TOKEN_KEYS and isinstance(value, (int, float))
    )


def phase_summary(phases):
    """Résumé agrégé (durées, tokens, coût, total) des phases mesurées."""
    duration = 0.0
    cost = 0.0
    tokens = empty_tokens()
    for phase in phases.values():
        duration += phase.get("duration_s") or 0
        cost += phase.get("cost_usd") or 0
        phase_tokens = phase.get("tokens") or {}
        for key in TOKEN_KEYS:
            value = phase_tokens.get(key)
            if isinstance(value, (int, float)):
                tokens[key] += value
    return {
        "duration_s": round(duration, 1),
        "cost_usd": round(cost, 6),
        "tokens": tokens,
        "total_tokens": sum(tokens.values()),
    }


def db_path(opencode_bin="opencode"):
    """Chemin de la base OpenCode (`opencode db path`), ou None."""
    try:
        proc = subprocess.run(
            [opencode_bin, "db", "path"],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def agent_names(opencode_bin="opencode"):
    """Noms des agents OpenCode disponibles, ou None si la liste est illisible.

    `opencode agent list` imprime chaque agent sur une ligne « nom (type) »
    suivie de sa config JSON. Lecture seule, jamais Failure : l'appelant replie
    sur l'agent plan en cas d'échec.
    """
    try:
        proc = subprocess.run(
            [opencode_bin, "agent", "list"],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    names = set(AGENT_LINE_RE.findall(proc.stdout))
    return names or None


def session_metrics(db_path, session_id):
    """Coût et tokens d'une session OpenCode, ou None — jamais Failure.

    Lecture seule (`file:<path>?mode=ro`) : schéma mouvant, WAL exigeant une
    récupération ou connexion ro refusée ne sont que des avertissements, la
    mesure ne doit jamais faire échouer une phase.
    """
    if not db_path:
        log("attention : base opencode introuvable — métriques de session indisponibles")
        return None
    try:
        connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5)
    except sqlite3.Error as exc:
        log(f"attention : base opencode illisible ({exc}) — métriques indisponibles")
        return None
    try:
        row = connection.execute(
            "SELECT cost, tokens_input, tokens_output, tokens_reasoning,"
            " tokens_cache_read, tokens_cache_write FROM session WHERE id = ?",
            (session_id,),
        ).fetchone()
    except sqlite3.Error as exc:
        log(f"attention : schéma opencode inattendu ({exc}) — métriques indisponibles")
        return None
    finally:
        connection.close()
    if row is None:
        log(f"attention : session opencode {session_id} introuvable — métriques indisponibles")
        return None
    cost, input_tokens, output_tokens, reasoning, cache_read, cache_write = row
    return {
        "cost_usd": cost if isinstance(cost, (int, float)) else 0.0,
        "tokens": {
            "input": int_or_zero(input_tokens),
            "output": int_or_zero(output_tokens),
            "reasoning": int_or_zero(reasoning),
            "cache_read": int_or_zero(cache_read),
            "cache_write": int_or_zero(cache_write),
        },
    }


def newest_session(repo, since, opencode_bin="opencode"):
    """Id de la session OpenCode du dépôt créée après `since` (epoch secondes).

    `session` porte `directory`, `time_created` (ms) et les métriques : un seul
    SELECT suffit, sans `opencode session list` ni SQL à placeholders.
    """
    path = db_path(opencode_bin)
    if not path:
        log("attention : base opencode introuvable (opencode db path) — session non résolue")
        return None
    try:
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5)
        try:
            row = connection.execute(
                "SELECT id FROM session WHERE directory = ? AND time_created >= ?"
                " ORDER BY time_created DESC LIMIT 1",
                (str(repo), int(since * 1000)),
            ).fetchone()
        finally:
            connection.close()
    except sqlite3.Error as exc:
        log(f"attention : base opencode illisible ({exc}) — session non résolue")
        return None
    if row is None:
        log(f"attention : aucune session opencode pour {repo} depuis {since:.0f} — session non résolue")
        return None
    return row[0]


def session_plan_text(database, session_id, limit=MAX_CAPTURE_PARTS):
    """Texte assistant le plus récent portant brief et plan final, ou None.

    Le dernier message de la session n'est pas forcément le plan (remerciement,
    question, appel d'outil, compaction) : on parcourt les textes assistant du
    plus récent au plus ancien, bornés, et on retient le premier qui contient
    les deux sentinelles. Lecture seule ; tout incident rend None, jamais
    Failure — le repli headless décide ensuite.
    """
    if not database or not session_id:
        return None
    try:
        connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=5)
    except sqlite3.Error as exc:
        log(f"attention : base opencode illisible ({exc}) — capture locale impossible")
        return None
    try:
        rows = connection.execute(
            "SELECT json_extract(p.data, '$.text') FROM part AS p"
            " JOIN message AS m ON m.id = p.message_id"
            " WHERE p.session_id = ?"
            " AND json_extract(m.data, '$.role') = 'assistant'"
            " AND json_extract(p.data, '$.type') = 'text'"
            " ORDER BY m.time_created DESC, p.time_created DESC"
            " LIMIT ?",
            (session_id, limit),
        ).fetchall()
    except sqlite3.Error as exc:
        log(f"attention : schéma opencode inattendu ({exc}) — capture locale impossible")
        return None
    finally:
        connection.close()
    for (text,) in rows:
        if isinstance(text, str) and all(marker in text for marker in CAPTURE_MARKERS):
            return text
    return None


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

    def resolve_agent(self, requested):
        """Agent demandé, ou repli sur l'agent plan s'il est introuvable.

        `opencode agent list` n'est interrogé qu'une fois par run ; le variant
        des agents vit dans leur définition (opencode.nix), pas dans des flags.
        """
        detected = getattr(self, "_available_agents", None)
        if detected is None:
            detected = agent_names(self.args.opencode_bin) or frozenset()
            self._available_agents = detected
        if requested in detected or requested == self.args.plan_agent:
            return requested
        log(f"agent opencode '{requested}' introuvable — repli sur '{self.args.plan_agent}'")
        return self.args.plan_agent

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
            ("plan", "opencode"): self.args.interactive_prompt,
            ("planner", "opencode"): self.args.planner_prompt,
            ("capture", "opencode"): self.args.capture_prompt,
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

    def effective_task(self):
        if self.task:
            return self.task
        brief = self.run_dir / "00-brief.md"
        if brief.is_file():
            text = brief.read_text(encoding="utf-8").strip()
            if text:
                return text
        return "(tâche précisée en session interactive — cf. 01-plan.md)"

    def save_meta(self):
        if self.args.dry_run:
            return
        self.meta["finished"] = stamp()
        self.meta["run_dir"] = str(self.run_dir)
        self.meta["vcs"] = self.vcs()
        self.meta["summary"] = phase_summary(self.meta["phases"])
        path = self.run_dir / "meta.json"
        path.write_text(json.dumps(self.meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    def call_claude(self, tag, prompt, effort=None):
        cmd = [
            self.args.claude_bin,
            "-p",
            "--model",
            self.args.claude_model,
            "--permission-mode",
            "plan",
            "--output-format",
            "json",
        ]
        if effort:
            cmd += ["--effort", effort]
        cmd.append(prompt)
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
        usage = payload.get("usage")
        tokens = usage_tokens(usage)
        self.meta["phases"][tag] = {
            "duration_s": duration,
            "exit_code": returncode,
            "session_id": payload.get("session_id"),
            "cost_usd": cost,
            "num_turns": payload.get("num_turns"),
            "usage": usage,
            "tokens": tokens,
        }
        suffix = f" ({cost:.4f} $)" if isinstance(cost, (int, float)) else ""
        if tokens:
            suffix += f" ({token_total(tokens)} tokens)"
        log(f"{tag}: terminé en {duration}s{suffix}")
        return text

    def run_opencode(self, tag, prompt, session=None, agent=None):
        # --auto : en headless, une permission "ask" (dont external_directory)
        # est auto-rejetée sans TTY, ce qui fait échouer l'exploration du dépôt.
        # Les agents d'analyse sont en lecture seule : plan n'édite pas,
        # reviewer/synth ont en plus bash=false (sinon un `tee`/`rm` écrirait
        # malgré tout) ; l'exécution interactive, elle, garde les permissions
        # "ask" pour l'utilisateur.
        cmd = [self.args.opencode_bin, "run"]
        if session:
            cmd += ["--session", session]
        cmd += [
            "--agent",
            agent or self.args.plan_agent,
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
        entry = {"duration_s": duration, "exit_code": returncode}
        session_id = session or newest_session(self.repo, started, self.args.opencode_bin)
        if session_id:
            metrics = session_metrics(db_path(self.args.opencode_bin), session_id)
            if metrics:
                entry.update(metrics)
                entry["session_id"] = session_id
        self.meta["phases"][tag] = entry
        suffix = ""
        if entry.get("cost_usd") is not None:
            suffix += f" ({entry['cost_usd']:.4f} $)"
        if entry.get("tokens"):
            suffix += f" ({token_total(entry['tokens'])} tokens)"
        log(f"{tag}: terminé en {duration}s{suffix}")
        return ANSI_RE.sub("", output)

    def call_opencode(self, tag, prompt, block, agent=None):
        clean = self.run_opencode(tag, prompt, agent=agent)
        opener, closer = SENTINELS[block]
        log_path = self.run_dir / "logs" / f"{tag}.log"
        return parse_block(clean, opener, closer, log_path=log_path)

    def phase_plan(self):
        if not self.task:
            self.phase_plan_interactive()
            return
        test_cmd = self.args.test_cmd or "aucune — l'agent exécutera les tests du projet"
        if self.args.plan_with == "claude":
            log("Phase 1/4 — Claude analyse le dépôt et rédige le plan")
            prompt = render(
                self.prompt("plan", "claude"),
                task=self.task,
                repo=str(self.repo),
                test_cmd=test_cmd,
                vcs=self.vcs(),
            )
            plan = self.call_claude("plan", prompt, effort="high")
        else:
            log("Phase 1/4 — OpenCode analyse le dépôt et rédige le plan (headless)")
            prompt = render(
                self.prompt("planner", "opencode"),
                task=self.task,
                repo=str(self.repo),
                test_cmd=test_cmd,
                vcs=self.vcs(),
            )
            plan = self.call_opencode("plan", prompt, "PLAN")
        self.write_artifact("01-plan.md", plan)

    def capture_interactive_plan(self, since, capture_prompt):
        """Capture le plan de la session interactive, sans appel LLM si possible.

        La base locale (`session_plan_text`) est lue en premier ; le repli
        `opencode run --session <id>` ne tourne que si aucun texte balisé n'y
        est trouvé. Retourne (plan, brief) ou (None, None).
        """
        session_id = newest_session(self.repo, since, self.args.opencode_bin)
        text = None
        if session_id:
            text = session_plan_text(db_path(self.args.opencode_bin), session_id)
        if text is None:
            if not session_id:
                log("attention : session interactive non résolue — capture locale impossible")
                return None, None
            log("aucun texte balisé dans la session — repli sur une capture headless")
            try:
                text = self.run_opencode("plan-capture", capture_prompt, session=session_id)
            except Failure as exc:
                log(f"capture inexploitable : {exc}")
                return None, None
        log_path = self.run_dir / "logs" / "plan-capture.log"
        try:
            plan = parse_block(text, *SENTINELS["FINAL_PLAN"], log_path=log_path)
        except Failure as exc:
            log(f"capture inexploitable : {exc}")
            return None, None
        try:
            brief = parse_block(text, *SENTINELS["BRIEF"], log_path=log_path)
        except Failure:
            brief = None
        return plan, brief

    def phase_plan_interactive(self):
        if not sys.stdin.isatty():
            raise Failure(
                "la phase de plan interactive nécessite un terminal interactif (TTY) — "
                "fournis --task/--task-file pour le mode headless"
            )
        log("Phase 1/4 — session interactive opencode pour préciser le plan")
        seed = render(self.prompt("plan", "opencode"), repo=str(self.repo))
        capture_prompt = render(self.prompt("capture", "opencode"), repo=str(self.repo))
        first = True
        started = time.time()
        while True:
            log(f"ouverture de la TUI opencode (agent {self.args.plan_agent})")
            returncode = subprocess.call(
                self._tui_cmd(seed, self.args.plan_agent, continue_session=not first),
                cwd=str(self.repo),
            )
            if returncode not in (0, 130):
                log(f"TUI terminée avec le code {returncode}")
            first = False
            log("capture du plan depuis la session interactive (lecture locale)")
            plan, brief = self.capture_interactive_plan(started, capture_prompt)
            if plan:
                if brief:
                    self.task = brief
                    self.meta["task"] = brief[:4000]
                    self.write_artifact("00-brief.md", brief)
                self.write_artifact("01-plan.md", plan)
                return
            action = ask_choice(
                "Aucun plan capturé depuis la session interactive.",
                [("r", "réouvrir la TUI"), ("q", "quitter")],
            )
            if action != "r":
                raise Failure("plan interactif non capturé — artefacts du run conservés")

    def phase_reviews(self):
        log("Phase 2/4 — relectures parallèles (OpenCode + Claude)")
        plan = self.read_artifact("01-plan.md")
        task = self.effective_task()
        test_cmd = self.args.test_cmd or "aucune — l'agent exécutera les tests du projet"
        vcs = self.vcs()
        agent = self.resolve_agent(self.args.review_agent)

        def review_opencode():
            prompt = render(
                self.prompt("review", "opencode"),
                repo=str(self.repo),
                task=task,
                plan=plan,
                test_cmd=test_cmd,
                vcs=vcs,
            )
            return self.call_opencode("review-opencode", prompt, "REVIEW", agent=agent)

        def review_claude():
            prompt = render(
                self.prompt("review", "claude"),
                repo=str(self.repo),
                task=task,
                plan=plan,
                test_cmd=test_cmd,
                vcs=vcs,
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
            task=self.effective_task(),
            plan=plan,
            reviews="\n\n".join(parts),
            test_cmd=self.args.test_cmd or "aucune — l'agent exécutera les tests du projet",
        )
        agent = self.resolve_agent(self.args.synth_agent)
        text = self.call_opencode("synth", prompt, "FINAL_PLAN", agent=agent)
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

    def _tui_cmd(self, prompt, agent=None, continue_session=False):
        cmd = [self.args.opencode_bin]
        if continue_session:
            cmd.append("--continue")
        cmd += [
            "--agent",
            agent or self.args.build_agent,
            "-m",
            self.args.opencode_model,
            "--prompt",
            prompt,
        ]
        return cmd

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
            if self.task:
                if args.plan_with == "claude":
                    print(
                        f"  1. plan    : {args.claude_bin} -p --model {args.claude_model} "
                        f"--permission-mode plan --effort high --output-format json "
                        f"<{self.prompt_path('plan', 'claude')}>"
                    )
                else:
                    print(
                        f"  1. plan    : {args.opencode_bin} run --agent {args.plan_agent} "
                        f"-m {args.opencode_model} "
                        f"<{self.prompt_path('planner', 'opencode')}>"
                    )
            else:
                print(
                    f"  1. plan    : {args.opencode_bin} --agent {args.plan_agent} "
                    f"-m {args.opencode_model} --prompt <{self.prompt_path('plan', 'opencode')}> (TUI interactif)"
                )
                print(
                    f"     capture : base opencode (part/message assistant) ; repli "
                    f"{args.opencode_bin} run --session <id> --agent {args.plan_agent} "
                    f"-m {args.opencode_model} <{self.prompt_path('capture', 'opencode')}>"
                )
        if "reviews" in phases:
            print(
                f"  2. review  : {args.opencode_bin} run --agent {args.review_agent} "
                f"-m {args.opencode_model} <{self.prompt_path('review', 'opencode')}>"
            )
            print(
                f"     review  : {args.claude_bin} -p --model {args.claude_model} "
                f"--permission-mode plan --output-format json <{self.prompt_path('review', 'claude')}>"
            )
        if "final" in phases:
            print(
                f"  3. synth   : {args.opencode_bin} run --agent {args.synth_agent} "
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
            "Planification multi-agents puis exécution OpenCode interactive, étape "
            "par étape, avec un commit atomique par étape. Sans --task/--task-file, "
            "la phase plan ouvre une session OpenCode interactive pour préciser le "
            "plan, capturé ensuite sans appel LLM ; avec, OpenCode planifie en "
            "headless (--plan-with claude pour Claude)."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """\
            phases : plan -> reviews -> final -> execute (défaut : tout)
            exemples :
              multi-agent-plan --repo ~/projet --test-cmd "nix flake check"       (plan interactif OpenCode)
              multi-agent-plan --repo ~/projet --task "Ajouter l'auth OAuth2" --test-cmd "nix flake check"
              multi-agent-plan --repo ~/projet --task-file task.md --plan-with claude --stop-after final
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
    parser.add_argument(
        "--review-agent",
        default="reviewer",
        help="agent opencode de la review (défaut : reviewer ; repli sur plan si absent)",
    )
    parser.add_argument(
        "--synth-agent",
        default="synth",
        help="agent opencode de la synthèse (défaut : synth ; repli sur plan si absent)",
    )
    parser.add_argument("--build-agent", default="build", help="agent opencode de la TUI d'exécution")
    parser.add_argument(
        "--test-cmd",
        default="nix flake check",
        help=(
            "commande de test vérifiée avant chaque commit d'étape "
            '(défaut : "nix flake check" ; chaîne vide pour désactiver)'
        ),
    )
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
    parser.add_argument(
        "--plan-with",
        choices=("opencode", "claude"),
        default="opencode",
        help=(
            "moteur du plan headless avec --task/--task-file (défaut : opencode ; "
            "claude avec --effort high)"
        ),
    )
    parser.add_argument("--plan-prompt", help="fichier de prompt pour la phase plan (Claude)")
    parser.add_argument(
        "--interactive-prompt",
        help="fichier de prompt de la session interactive de plan (OpenCode, sans --task)",
    )
    parser.add_argument(
        "--planner-prompt",
        help="fichier de prompt du plan OpenCode headless (avec --task/--task-file)",
    )
    parser.add_argument(
        "--capture-prompt",
        help="fichier de prompt de capture du plan interactif (OpenCode)",
    )
    parser.add_argument("--review-claude-prompt", help="fichier de prompt pour la review Claude")
    parser.add_argument("--review-opencode-prompt", help="fichier de prompt pour la review OpenCode")
    parser.add_argument("--synth-prompt", help="fichier de prompt pour la synthèse (OpenCode)")
    parser.add_argument("--exec-prompt", help="fichier de prompt pour l'exécution (OpenCode)")
    parser.add_argument("--dry-run", action="store_true", help="afficher le déroulé sans rien exécuter")
    parser.add_argument("--verbose", action="store_true", help="streamer les sorties des phases headless")
    args = parser.parse_args(argv)
    if args.task and args.task_file:
        parser.error("--task et --task-file sont exclusifs")
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
