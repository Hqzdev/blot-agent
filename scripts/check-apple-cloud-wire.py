#!/usr/bin/env python3
"""Exercise real Swift CryptoKit + three SQLite replicas against the separate Java HTTP relay.
Seeds only isolated test identities; SMTP, Google and real devices remain separate acceptance checks.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"


def run(command, env, log):
    with log.open("w") as output:
        subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, check=True)


def seed_database(path, seed, directory):
    now = int(time.time() * 1000)
    owner = seed["devices"][0]["identity"]["ownerID"].lower()
    workspace = seed["devices"][0]["identity"]["workspaceID"].lower()
    sessions = []
    with sqlite3.connect(path) as db:
        db.execute("PRAGMA foreign_keys = ON")
        db.execute("INSERT INTO accounts(id,email,password_hash,name,verified,bootstrap_used,created_at) VALUES (?,?,?,?,1,0,?)",
                   (owner, "wire-isolated@example.org", "wire-test-never-used-for-password-login", "Wire verification", now))
        db.execute("INSERT INTO workspaces(id,owner_id) VALUES (?,?)", (workspace, owner))
        for index, device in enumerate(seed["devices"]):
            session_id = str(uuid.uuid4())
            sessions.append(session_id)
            digest = lambda value: hashlib.sha256(value.encode()).hexdigest()
            db.execute("INSERT INTO sessions(id,owner_id,access_hash,refresh_hash,access_expires,refresh_expires,bootstrap_allowed) VALUES (?,?,?,?,?,?,?)",
                       (session_id, owner, digest(device["accessToken"]), digest(device["refreshToken"]), now + 900_000, now + 86_400_000, 1 if index == 0 else 0))
    (directory / "session-ids.json").write_text(json.dumps(sessions))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    env = os.environ.copy()
    env["JAVA_HOME"] = str(BUILD / "tools/jdk-25.0.4.1+1/Contents/Home")
    env["GRADLE_USER_HOME"] = str(BUILD / "gradle-home")
    env["CLANG_MODULE_CACHE_PATH"] = str(BUILD / "apple-module-cache")
    env["SWIFTPM_MODULECACHE_OVERRIDE"] = str(BUILD / "apple-module-cache")
    swift = ["swift", "build", "--disable-sandbox", "--package-path", "packages/BlotWorkspace/Integration", "--scratch-path", ".build/apple-v1-wire"]
    if not args.skip_build:
        run(["backend/gradlew", "--offline", "--no-daemon", "-p", "backend", ":cloud:bootJar"], env, BUILD / "apple-v1-cloud-build.log")
        run(swift, env, BUILD / "apple-v1-wire-build.log")
    bin_path = Path(subprocess.check_output(swift + ["--show-bin-path"], cwd=ROOT, env=env, text=True).strip()) / "CloudWireVerification"
    with tempfile.TemporaryDirectory(prefix="apple-cloud-wire-", dir=BUILD) as temporary:
        directory = Path(temporary)
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))
            port = reserved.getsockname()[1]
        origin = f"http://127.0.0.1:{port}"
        db_path = directory / "relay.sqlite"
        env.update(BLOT_CLOUD_ADDRESS="127.0.0.1", BLOT_CLOUD_PORT=str(port), BLOT_CLOUD_DATABASE=str(db_path),
                   BLOT_CLOUD_CHALLENGE_KEY=base64.b64encode(secrets.token_bytes(32)).decode())
        # A developer's mounted production secret is never used for this isolated process.
        env.pop("BLOT_CLOUD_CHALLENGE_KEY_FILE", None)
        with (BUILD / "apple-v1-cloud-wire-server.log").open("w") as server_log:
            server = subprocess.Popen([str(Path(env["JAVA_HOME"]) / "bin/java"), "--enable-native-access=ALL-UNNAMED", "-jar",
                                       str(ROOT / "backend/cloud/build/libs/blot-cloud.jar")], cwd=directory, env=env,
                                      stdout=server_log, stderr=subprocess.STDOUT)
            try:
                for _ in range(200):
                    if server.poll() is not None:
                        raise RuntimeError("Cloud process exited; inspect .build/apple-v1-cloud-wire-server.log")
                    try:
                        with urllib.request.urlopen(origin + "/v1/health", timeout=1) as response:
                            if json.load(response)["service"] == "blot-cloud":
                                break
                    except (urllib.error.URLError, TimeoutError):
                        time.sleep(0.1)
                else:
                    raise RuntimeError("Cloud health timeout")
                try:
                    urllib.request.urlopen(origin + "/v1/relay/changes", timeout=2)
                    raise RuntimeError("Unauthenticated relay request was accepted")
                except urllib.error.HTTPError as error:
                    if error.code != 401:
                        raise
                subprocess.run([str(bin_path), "prepare", str(directory), origin], env=env, check=True, timeout=30)
                seed = json.loads((directory / "wire-seed.json").read_bytes())
                seed_database(db_path, seed, directory)
                subprocess.run([str(bin_path), "verify", str(directory), origin], env=env, check=True, timeout=120)
                with sqlite3.connect(db_path) as db:
                    packets = db.execute("SELECT packet FROM relay_packets").fetchall()
                    if not packets:
                        raise RuntimeError("No durable relay packets")
                    allowed = {"kind", "workspaceID", "originDeviceID", "changeID", "sequence", "keyEpoch", "ciphertext", "signature"}
                    if any(set(json.loads(row[0])) != allowed for row in packets):
                        raise RuntimeError("Unexpected relay payload fields")
                private_strings = ["Изолированное сообщение A", "Офлайн A", "Офлайн B", "После отзыва", "SECRET-WIRE-ATTACHMENT-DO-NOT-LOG", "SECRET-WIRE-SNAPSHOT-DO-NOT-LOG"]
                private_strings += [device[field] for device in seed["devices"] for field in ("accessToken", "refreshToken")]
                for file in (db_path, Path(str(db_path) + "-wal"), BUILD / "apple-v1-cloud-wire-server.log"):
                    if file.exists() and any(value.encode() in file.read_bytes() for value in private_strings):
                        raise RuntimeError("Plaintext or bearer credential found in relay storage/log")
                evidence = {"checkedAt": datetime.now(timezone.utc).isoformat(), "result": "PASS", "replicas": 3,
                            "transport": "real loopback HTTP", "encryption": "Swift CryptoKit AES-GCM + P256 verified by Java JCE",
                            "scenarios": ["offline convergence", "durable relay", "idempotent delivery", "native bootstrap and signed pairing", "ECDH wrapped key transfer", "signed snapshot donor request and multi-chunk resume", "snapshot rejects tampered manifest and preserves local changes", "snapshot watermark followed by tail replay", "native key rotation and revoked-device fencing", "process lease fencing", "encrypted multi-chunk file transfer", "rotating session", "logout fences suspended credential write", "no plaintext in relay/log"],
                            "physicalDevices": False, "google": False, "smtp": False, "externalModel": False}
                (BUILD / "apple-v1-cloud-wire-evidence.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
                print("PASS: relay storage/log contains neither message plaintext nor bearer credentials.")
            finally:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait()


if __name__ == "__main__":
    main()
