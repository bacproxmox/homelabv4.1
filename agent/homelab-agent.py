#!/usr/bin/env python3
import datetime as dt
import hashlib
import json
import os
import socket
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(os.environ.get("HOMELABV4_ROOT", "/opt/homelabv4"))
AGENT = ROOT / "agent"
STATE = ROOT / "state"
LOGS = ROOT / "logs"
MANIFEST = AGENT / "manifests" / "guided-steps.json"
BRANDING = AGENT / "manifests" / "branding-packs.json"
SCRIPT_CATALOG = AGENT / "manifests" / "script-catalog.json"
PAYLOAD_MANIFEST = AGENT / ".payload-manifest.json"
RUNS_FILE = STATE / "runs.json"
STEPS_FILE = STATE / "steps.json"
SCRIPT_STATES_FILE = STATE / "script-states.json"
INSTALL_PROFILE_FILE = STATE / "install-profile.json"
VERSION = "0.1.3"
STARTED = time.time()

STATE.mkdir(parents=True, exist_ok=True)
LOGS.mkdir(parents=True, exist_ok=True)

running_processes: dict[str, subprocess.Popen] = {}
active_run_ids: set[str] = set()
lock = threading.Lock()
CORE_DISCOVERY_ROOTS = ("tasks", "vm", "services", "config", "maintenance", "flows", "additionals", "gpu")
PAYLOAD_HASH_EXCLUDE_NAMES = {".payload-manifest.json"}
PAYLOAD_HASH_EXCLUDE_DIRS = {"__pycache__", ".git", "node_modules"}
PAYLOAD_HASH_EXCLUDE_SUFFIXES = {".pyc", ".pyo"}


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def read_json(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def payload_manifest():
    return read_json(PAYLOAD_MANIFEST, {})


def should_hash_payload_file(path: Path) -> bool:
    if path.name in PAYLOAD_HASH_EXCLUDE_NAMES:
        return False
    if path.suffix in PAYLOAD_HASH_EXCLUDE_SUFFIXES:
        return False
    if any(part in PAYLOAD_HASH_EXCLUDE_DIRS for part in path.parts):
        return False
    return True


def payload_hash():
    digest = hashlib.sha256()
    file_count = 0
    byte_count = 0
    if not AGENT.exists():
        return {"payloadHash": "", "fileCount": 0, "byteCount": 0}
    for path in sorted(item for item in AGENT.rglob("*") if item.is_file() and should_hash_payload_file(item)):
        rel = path.relative_to(AGENT).as_posix()
        digest.update(rel.encode("utf-8"))
        digest.update(b"\0")
        with path.open("rb") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                byte_count += len(chunk)
                digest.update(chunk)
        digest.update(b"\0")
        file_count += 1
    return {"payloadHash": digest.hexdigest(), "fileCount": file_count, "byteCount": byte_count}


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    tmp.replace(path)


def guided_steps():
    return read_json(MANIFEST, {"steps": []}).get("steps", [])


def branding_packs():
    return read_json(BRANDING, {"packs": []}).get("packs", [])


def core_roots() -> list[Path]:
    candidates = [ROOT / "core", AGENT / "core", ROOT / "core" / "agent" / "core"]
    seen = set()
    roots = []
    for candidate in candidates:
        marker = candidate / "bin" / "homelab"
        if not marker.exists():
            continue
        resolved = candidate.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        roots.append(resolved)
    return roots


def active_core_root() -> Path | None:
    roots = core_roots()
    return roots[0] if roots else None


def title_from_path(path: str) -> str:
    stem = Path(path).stem
    parts = [part for part in stem.replace("_", "-").split("-") if part and not part.isdigit()]
    return " ".join(part.upper() if part.lower() in {"vm", "ai", "pbs", "nfs", "gpu", "smtp"} else part.capitalize() for part in parts)


def core_category(path: str) -> str:
    parts = path.split("/")
    joined = path.lower()
    if parts[0] in {"vm"} or "/vm/" in joined or parts[-1].startswith(tuple(str(num) for num in range(100, 120))):
        return "vm"
    if "/services/" in joined or parts[0] == "services":
        return "service"
    if "/config/" in joined or parts[0] == "config":
        return "config"
    if "branding" in joined or "theme" in joined:
        return "branding"
    if "health" in joined or "audit" in joined or "preflight" in joined:
        return "health"
    if "repair" in joined or "fix" in joined:
        return "repair"
    if parts[0] == "maintenance":
        return "maintenance"
    if parts[0] in {"additionals", "gpu"}:
        return "additional"
    if parts[0] == "flows":
        return "install"
    return "maintenance"


def core_risk(path: str) -> str:
    text = path.lower()
    if any(token in text for token in ("wipe", "reset", "rollback", "delete", "normalize-local-storage", "storage/normalize")):
        return "destructive"
    if any(token in text for token in ("install", "repair", "fix", "config", "bootstrap", "create", "attach", "import")):
        return "caution"
    return "safe"


def core_script_items():
    root = active_core_root()
    if not root:
        return []
    items = []
    for folder in CORE_DISCOVERY_ROOTS:
        base = root / folder
        if not base.exists():
            continue
        for script in sorted(base.rglob("*.sh")):
            rel = script.relative_to(root).as_posix()
            item_id = "core." + rel.replace("/", ".").replace("-", "_").replace(".sh", "")
            items.append(
                {
                    "id": item_id,
                    "title": f"Core: {title_from_path(rel)}",
                    "description": f"Imported from homelabv3.1.1-r2: {rel}",
                    "category": core_category(rel),
                    "target": f"core:{rel}",
                    "riskLevel": core_risk(rel),
                    "implementation": "ready",
                    "defaultOrder": 1000 + len(items),
                    "tags": ["v3.1.1-r2", *rel.split("/")[:2]],
                }
            )
    return items


def script_catalog():
    catalog = read_json(SCRIPT_CATALOG, {"items": [], "groups": []})
    items = list(catalog.get("items", []))
    seen_targets = {item.get("target") for item in items}
    for item in core_script_items():
        if item.get("target") in seen_targets:
            continue
        items.append(item)
        seen_targets.add(item.get("target"))
    return {"items": items, "groups": catalog.get("groups", [])}


def script_items():
    return script_catalog().get("items", [])


def script_groups():
    return script_catalog().get("groups", [])


def script_item_by_id(script_id: str):
    return next((item for item in script_items() if item.get("id") == script_id), None)


def script_item_by_target(target: str):
    return next((item for item in script_items() if item.get("target") == target), None)


def script_group_by_id(group_id: str):
    return next((group for group in script_groups() if group.get("id") == group_id), None)


def allowlisted_targets() -> set[str]:
    targets = {step["target"] for step in guided_steps()}
    targets.update(item["target"] for item in script_items())
    for pack in branding_packs():
        targets.update(pack.get("targets", {}).values())
    targets.update(
        {
            "tasks/health/full-health.sh",
            "tasks/repair/gpu-passthrough.sh",
            "tasks/support/create-support-bundle.sh",
        }
    )
    return targets


def resolve_target(target: str) -> Path:
    if target.startswith("core:"):
        root = active_core_root()
        if not root:
            raise FileNotFoundError("core script payload not found")
        relative = target.split(":", 1)[1]
        candidate = (root / relative).resolve()
        if not str(candidate).startswith(str(root)):
            raise ValueError("core target escapes core root")
        if not candidate.exists():
            raise FileNotFoundError(f"core target not found: {relative}")
        if target not in allowlisted_targets():
            raise PermissionError(f"target is not allowlisted: {target}")
        return candidate

    candidate = (AGENT / target).resolve()
    agent_root = AGENT.resolve()
    if not str(candidate).startswith(str(agent_root)):
        raise ValueError("target escapes agent root")
    if not candidate.exists():
        raise FileNotFoundError(f"target not found: {target}")
    if target not in allowlisted_targets():
        raise PermissionError(f"target is not allowlisted: {target}")
    return candidate


def runs():
    return read_json(RUNS_FILE, [])


def save_run(run):
    with lock:
        data = [item for item in runs() if item["id"] != run["id"]]
        data.insert(0, run)
        write_json(RUNS_FILE, data[:200])


def run_status(run_id: str) -> str | None:
    run = next((item for item in runs() if item.get("id") == run_id), None)
    return run.get("status") if run else None


def append_run_log(run, text: str) -> None:
    log_path = Path(run.get("logPath", ""))
    if not log_path:
        return
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("ab") as log:
            log.write(text.encode())
    except Exception:
        return


def read_log_tail(log_path: Path, max_bytes: int = 60000) -> str:
    if not log_path.exists():
        return ""
    with log_path.open("rb") as log:
        log.seek(0, os.SEEK_END)
        size = log.tell()
        log.seek(max(0, size - max_bytes), os.SEEK_SET)
        raw = log.read(max_bytes)
    return raw.decode("utf-8", errors="replace")


def pbs_failure_detected(log_path: Path) -> bool:
    tail = read_log_tail(log_path, 120000).lower()
    return (
        "config/pbs/01-pbs-backup-automation.sh" in tail
        or "pbs-backup-automation" in tail
        or "pbs-pi-a" in tail and "fingerprint" in tail
    )


def mark_pbs_needs_repair(run: dict, log) -> None:
    repair_id = "repair.pbs_backup_storage"
    repair_item = script_item_by_id(repair_id)
    if not repair_item:
        return
    run["needsRepair"] = {
        "id": repair_id,
        "title": repair_item.get("title", "Repair PBS backup storage"),
        "target": repair_item.get("target"),
        "reason": "PBS backup storage fingerprint/config failed during post-service config.",
    }
    update_script_status(repair_item["target"], "failed", repair_item.get("title", "Repair PBS backup storage"))
    log.write(
        b"\nNeeds repair: PBS backup storage.\n"
        b"Run repair.pbs_backup_storage from the panel, then resume Full Homelab install.\n"
    )


def reconcile_interrupted_runs() -> None:
    changed = False
    data = runs()
    with lock:
        live_ids = set(active_run_ids)
    for run in data:
        if run.get("status") not in ("running", "queued"):
            continue
        if run.get("id") in live_ids:
            continue
        run["status"] = "failed"
        run["exitCode"] = 130
        run["finishedAt"] = run.get("finishedAt") or now()
        run["interrupted"] = True
        append_run_log(run, f"\nInterrupted: {now()}\nThe agent restarted or lost the worker for this run. Reset install state and start again if needed.\n")
        changed = True
    if changed:
        write_json(RUNS_FILE, data[:200])


def reset_install_state() -> dict:
    cancelled = []
    with lock:
        process_items = list(running_processes.items())
    for run_id, proc in process_items:
        if proc.poll() is None:
            proc.terminate()
            cancelled.append(run_id)

    data = runs()
    for run in data:
        if run.get("status") in ("running", "queued"):
            run["status"] = "cancelled"
            run["exitCode"] = -15
            run["finishedAt"] = now()
            append_run_log(run, f"\nCancelled: {now()}\nInstall state was reset from the Homelabv4 panel.\n")
            if run.get("id") not in cancelled:
                cancelled.append(run.get("id"))
    write_json(RUNS_FILE, data[:200])

    write_json(STEPS_FILE, [])
    write_json(SCRIPT_STATES_FILE, [])
    return {
        "ok": True,
        "cancelledRuns": [run_id for run_id in cancelled if run_id],
        "steps": [],
        "scripts": [],
        "runs": runs(),
    }


def update_step_status(target: str, status: str, title: str = ""):
    steps = read_json(STEPS_FILE, [])
    step_id = None
    step_title = title
    for step in guided_steps():
        if step["target"] == target:
            step_id = step["id"]
            step_title = step["title"]
            break
    if not step_id:
        return
    steps = [item for item in steps if item.get("id") != step_id]
    steps.append({"id": step_id, "status": status, "updatedAt": now(), "title": step_title})
    write_json(STEPS_FILE, steps)


def update_script_status(target: str, status: str, title: str = ""):
    item = script_item_by_target(target)
    if not item:
        return
    states = read_json(SCRIPT_STATES_FILE, [])
    states = [entry for entry in states if entry.get("id") != item["id"]]
    states.append(
        {
            "id": item["id"],
            "status": status,
            "updatedAt": now(),
            "title": title or item["title"],
            "target": target,
        }
    )
    write_json(SCRIPT_STATES_FILE, states)


def run_environment():
    env = os.environ.copy()
    env.update(
        {
            "HOMELABV4_ROOT": str(ROOT),
            "HOMELABV4_AGENT": str(AGENT),
            "HOMELABV4_STATE": str(STATE),
        }
    )
    return env


def command_for_target(target: str, script: Path) -> list[str]:
    if target.startswith("core:"):
        root = active_core_root()
        if not root:
            raise FileNotFoundError("core script payload not found")
        relative = target.split(":", 1)[1]
        return ["bash", str(root / "bin" / "homelab"), "run", relative]
    return ["bash", str(script)]


REBOOT_REQUESTED_EXIT_CODE = 194


def run_completed_successfully(code: int) -> bool:
    return code in (0, REBOOT_REQUESTED_EXIT_CODE)


def spawn_run(target: str, title: str | None = None):
    script = resolve_target(target)
    catalog_item = script_item_by_target(target)
    run_title = title or (catalog_item.get("title") if catalog_item else target)
    run_id = str(uuid.uuid4())
    log_path = LOGS / f"{run_id}.log"
    run = {
        "id": run_id,
        "target": target,
        "title": run_title,
        "status": "running",
        "startedAt": now(),
        "logPath": str(log_path),
    }
    save_run(run)
    update_step_status(target, "running", run_title)
    update_script_status(target, "running", run_title)

    def worker():
        with log_path.open("ab") as log:
            log.write(f"Homelabv4 run {run_id}\nTarget: {target}\nStarted: {now()}\n\n".encode())
            proc = subprocess.Popen(command_for_target(target, script), stdout=log, stderr=subprocess.STDOUT, cwd=str(AGENT), env=run_environment())
            with lock:
                active_run_ids.add(run_id)
                running_processes[run_id] = proc
            code = proc.wait()
            with lock:
                running_processes.pop(run_id, None)
                active_run_ids.discard(run_id)
            log.write(f"\nFinished: {now()}\nExit code: {code}\n".encode())
        if run_status(run_id) == "cancelled":
            return
        run["exitCode"] = code
        run["finishedAt"] = now()
        run["status"] = "done" if run_completed_successfully(code) else "failed"
        save_run(run)
        final_status = "done" if run_completed_successfully(code) else "failed"
        update_step_status(target, final_status, run_title)
        update_script_status(target, final_status, run_title)

    threading.Thread(target=worker, daemon=True).start()
    return run


def spawn_script_item(script_id: str):
    item = script_item_by_id(script_id)
    if not item:
        raise ValueError(f"script not found: {script_id}")
    return spawn_run(item["target"], item["title"])


def spawn_script_group(group_id: str):
    group = script_group_by_id(group_id)
    if not group:
        raise ValueError(f"script group not found: {group_id}")
    group_items = []
    for item_id in group.get("itemIds", []):
        item = script_item_by_id(item_id)
        if not item:
            raise ValueError(f"group {group_id} references missing script: {item_id}")
        script = resolve_target(item["target"])
        group_items.append((item, script))

    run_id = str(uuid.uuid4())
    log_path = LOGS / f"{run_id}.log"
    run = {
        "id": run_id,
        "target": f"script-group:{group_id}",
        "title": group["title"],
        "status": "running",
        "startedAt": now(),
        "logPath": str(log_path),
    }
    save_run(run)

    def worker():
        final_code = 0
        with lock:
            active_run_ids.add(run_id)
        with log_path.open("ab") as log:
            log.write(f"Homelabv4 group run {run_id}\nGroup: {group['title']}\nStarted: {now()}\n\n".encode())
            for index, (item, script) in enumerate(group_items, start=1):
                if run_status(run_id) == "cancelled":
                    final_code = -15
                    log.write(b"\nStopping group because the run was cancelled.\n")
                    break
                target = item["target"]
                title = item["title"]
                log.write(f"\n=== [{index}/{len(group_items)}] {title} ===\nTarget: {target}\nStarted: {now()}\n\n".encode())
                update_step_status(target, "running", title)
                update_script_status(target, "running", title)
                proc = subprocess.Popen(command_for_target(target, script), stdout=log, stderr=subprocess.STDOUT, cwd=str(AGENT), env=run_environment())
                with lock:
                    running_processes[run_id] = proc
                code = proc.wait()
                with lock:
                    running_processes.pop(run_id, None)
                if run_status(run_id) == "cancelled":
                    final_code = -15
                    log.write(b"\nStopping group because the run was cancelled.\n")
                    break
                final_status = "done" if run_completed_successfully(code) else "failed"
                update_step_status(target, final_status, title)
                update_script_status(target, final_status, title)
                log.write(f"\nFinished step: {now()}\nExit code: {code}\n".encode())
                if code == REBOOT_REQUESTED_EXIT_CODE:
                    final_code = 0
                    log.write(b"\nStopping group because this step scheduled a Proxmox reboot. Reconnect after reboot and run the group again; completed steps are idempotent.\n")
                    break
                if code != 0:
                    if item.get("id") == "config.post_services" and pbs_failure_detected(log_path):
                        mark_pbs_needs_repair(run, log)
                    if item.get("stopOnFailure", True):
                        final_code = code
                        log.write(b"\nStopping group because this script failed and stopOnFailure is enabled.\n")
                        break
                    log.write(b"\nContinuing group because this script is marked stopOnFailure=false.\n")
            log.write(f"\nGroup finished: {now()}\nExit code: {final_code}\n".encode())
        with lock:
            active_run_ids.discard(run_id)
        if run_status(run_id) == "cancelled":
            return
        run["exitCode"] = final_code
        run["finishedAt"] = now()
        run["status"] = "done" if final_code == 0 else "failed"
        save_run(run)

    threading.Thread(target=worker, daemon=True).start()
    return run


def command_output(args: list[str], timeout: int = 12) -> str:
    try:
        return subprocess.check_output(args, stderr=subprocess.STDOUT, timeout=timeout, text=True)
    except Exception as exc:
        return str(exc)


def hardware_inventory():
    return {
        "collectedAt": now(),
        "lsblk": command_output(["bash", "-lc", "lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,TRAN,FSTYPE,MOUNTPOINTS 2>/dev/null || true"]),
        "nvme": command_output(["bash", "-lc", "nvme list 2>/dev/null || true"]),
        "pci": command_output(["bash", "-lc", "lspci -Dnn 2>/dev/null | grep -Ei 'vga|3d|display|nvidia|intel|jmicron|jmb|jms|sata|ahci' || true"]),
        "storage": command_output(["bash", "-lc", "pvesm status 2>/dev/null || true; echo; zpool list 2>/dev/null || true"]),
        "vmResources": command_output(["bash", "-lc", "for vmid in 101 102 103 104 105 106 107 110; do if qm status \"$vmid\" >/dev/null 2>&1; then echo \"VM $vmid\"; qm config \"$vmid\" | awk '/^(name|memory|balloon|cores):/ {print}'; echo; fi; done"]),
    }


def support_bundles():
    items = []
    seen = set()
    for pattern in ("homelabv4-support-*.tar.gz", "homelab-support-*.tar.gz"):
        for bundle in Path("/root").glob(pattern):
            if str(bundle) in seen or not bundle.is_file():
                continue
            seen.add(str(bundle))
            stat = bundle.stat()
            items.append(
                {
                    "path": str(bundle),
                    "fileName": bundle.name,
                    "sizeBytes": stat.st_size,
                    "modifiedAt": dt.datetime.fromtimestamp(stat.st_mtime, dt.timezone.utc).isoformat(),
                }
            )
    return sorted(items, key=lambda item: item["modifiedAt"], reverse=True)


class Handler(BaseHTTPRequestHandler):
    server_version = "Homelabv4Agent/0.1"

    def _body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def _json(self, data, status=200):
        raw = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _error(self, exc: Exception, status=500):
        self._json({"error": str(exc)}, status)

    def do_GET(self):
        try:
            path = urlparse(self.path).path
            if path == "/api/v1/health":
                self._json(
                    {
                        "ok": True,
                        "version": VERSION,
                        "hostname": socket.gethostname(),
                        "uptimeSeconds": int(time.time() - STARTED),
                        "stateDir": str(STATE),
                        "payloadManifest": payload_manifest(),
                    }
                )
            elif path == "/api/v1/payload":
                self._json(
                    {
                        "version": VERSION,
                        "agentRoot": str(AGENT),
                        "manifest": payload_manifest(),
                        **payload_hash(),
                    }
                )
            elif path == "/api/v1/manifest":
                self._json({"steps": guided_steps()})
            elif path == "/api/v1/state":
                reconcile_interrupted_runs()
                self._json(
                    {
                        "steps": read_json(STEPS_FILE, []),
                        "scripts": read_json(SCRIPT_STATES_FILE, []),
                        "runs": runs(),
                        "installProfile": read_json(INSTALL_PROFILE_FILE, {}),
                    }
                )
            elif path == "/api/v1/script-catalog":
                self._json(script_catalog())
            elif path == "/api/v1/inventory/hardware":
                self._json(hardware_inventory())
            elif path == "/api/v1/support/bundles":
                self._json({"bundles": support_bundles()})
            elif path == "/api/v1/branding/packs":
                self._json({"packs": branding_packs()})
            elif path.startswith("/api/v1/branding/packs/") and path.endswith("/status"):
                pack_id = path.split("/")[5]
                pack = next((item for item in branding_packs() if item["id"] == pack_id), None)
                if not pack:
                    self._error(ValueError("branding pack not found"), 404)
                    return
                self._json({"pack": pack, "target": pack["targets"]["status"]})
            elif path.startswith("/api/v1/runs/") and path.endswith("/logs"):
                run_id = path.split("/")[4]
                run = next((item for item in runs() if item["id"] == run_id), None)
                if not run:
                    self._error(ValueError("run not found"), 404)
                    return
                log_path = Path(run["logPath"])
                text = read_log_tail(log_path)
                self._json({"text": text})
            elif path.startswith("/api/v1/runs/"):
                run_id = path.split("/")[4]
                run = next((item for item in runs() if item["id"] == run_id), None)
                self._json(run or {"error": "run not found"}, 200 if run else 404)
            elif path == "/api/v1/runs":
                self._json({"runs": runs()})
            else:
                self._error(ValueError("not found"), 404)
        except Exception as exc:
            self._error(exc)

    def do_POST(self):
        try:
            path = urlparse(self.path).path
            if path == "/api/v1/runs":
                body = self._body()
                target = body.get("target")
                if not target:
                    self._error(ValueError("missing target"), 400)
                    return
                self._json(spawn_run(target))
            elif path == "/api/v1/script-catalog/runs":
                body = self._body()
                script_id = body.get("id")
                if not script_id:
                    self._error(ValueError("missing script id"), 400)
                    return
                self._json(spawn_script_item(script_id))
            elif path.startswith("/api/v1/script-catalog/groups/") and path.endswith("/run"):
                group_id = path.split("/")[5]
                self._json(spawn_script_group(group_id))
            elif path.startswith("/api/v1/runs/") and path.endswith("/cancel"):
                run_id = path.split("/")[4]
                proc = running_processes.get(run_id)
                if proc:
                    proc.terminate()
                    self._json({"ok": True})
                else:
                    self._json({"ok": False, "reason": "run is not active"})
            elif path == "/api/v1/install/reset":
                self._json(reset_install_state())
            elif path.startswith("/api/v1/branding/packs/"):
                parts = path.split("/")
                pack_id = parts[5]
                action = parts[6] if len(parts) > 6 else ""
                pack = next((item for item in branding_packs() if item["id"] == pack_id), None)
                if not pack:
                    self._error(ValueError("branding pack not found"), 404)
                    return
                if action not in ("apply", "restore"):
                    self._error(ValueError("unsupported branding action"), 400)
                    return
                target = pack["targets"][action]
                self._json(spawn_run(target, f"{pack['displayName']} {action}"))
            elif path == "/api/v1/support-bundle":
                self._json(spawn_run("tasks/support/create-support-bundle.sh", "Support Bundle"))
            else:
                self._error(ValueError("not found"), 404)
        except Exception as exc:
            self._error(exc)

    def log_message(self, fmt, *args):
        return


def main():
    reconcile_interrupted_runs()
    host = "127.0.0.1"
    port = int(os.environ.get("HOMELABV4_AGENT_PORT", "48114"))
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"Homelabv4 agent listening on http://{host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
