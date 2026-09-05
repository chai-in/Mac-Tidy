#!/usr/bin/env python3
"""Exercise the packaged bridge using disposable data and no administrator access."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path, help="Path to the packaged Mole executable")
    args = parser.parse_args()
    engine = args.engine.resolve(strict=True)

    with tempfile.TemporaryDirectory(prefix="mac-tidy-smoke-") as temporary:
        root = Path(temporary).resolve()
        environment = {
            "HOME": str(root),
            "XDG_CONFIG_HOME": str(root / ".config"),
            "XDG_CACHE_HOME": str(root / ".cache"),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "dumb",
            "NO_COLOR": "1",
            "MOLE_TEST_NO_AUTH": "1",
            "MOLE_GUI_MODE": "1",
        }

        def run(*arguments, confirmed=False, success=True):
            child_environment = dict(environment)
            if confirmed:
                child_environment["MOLE_GUI_CONFIRMED"] = "1"
            process = subprocess.Popen(
                [str(engine), *map(str, arguments)], env=child_environment,
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, start_new_session=True,
            )
            try:
                stdout, stderr = process.communicate(timeout=90)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
                raise AssertionError(f"Bridge command timed out: {arguments[0]}") from None
            if success != (process.returncode == 0):
                raise AssertionError(f"{arguments}: exit {process.returncode}\n{stdout}\n{stderr}")
            return stdout

        def read_json(*arguments):
            return json.loads(run(*arguments))

        assert "Mole version 1.53.0" in run("--version")
        status = read_json("status", "--json")
        assert "cpu" in status and "memory" in status and "disks" in status
        touchid = read_json("touchid", "--gui-status")
        assert isinstance(touchid["supported"], bool)
        assert isinstance(touchid["configured"], bool)
        assert isinstance(read_json("history", "--json", "--limit", "10")["sessions"], list)
        print("PASS: version, health, Touch ID status, and history JSON", flush=True)

        for command in (("clean",), ("optimize",), ("touchid", "enable"), ("touchid", "disable")):
            run(*command, success=False)
        print("PASS: native cleanup, optimization, and Touch ID reject missing confirmation", flush=True)

        for mode in ("clean", "optimize"):
            catalog = read_json(mode, "--gui-whitelist-list")
            assert catalog["mode"] == mode and isinstance(catalog["items"], list)
            pattern = "~/Library/Caches/MacTidySmoke/*" if mode == "clean" else "mac_tidy_smoke_task"
            saved = read_json(mode, "--gui-whitelist-save", pattern)
            assert saved["saved"] is True
            assert pattern in read_json(mode, "--gui-whitelist-list")["custom_patterns"]
        print("PASS: protection settings save and reload in a disposable home", flush=True)

        project = root / "Code" / "Example Project"
        artifacts = project / "node_modules"
        artifacts.mkdir(parents=True)
        (project / "package.json").write_text('{"name":"smoke-fixture"}\n')
        sentinel = project / "keep.txt"
        sentinel.write_text("User-authored file must remain.\n")
        payload = artifacts / "generated.bin"
        payload.write_bytes(b"x" * 8192)
        old_time = time.time() - 30 * 24 * 60 * 60
        os.utime(payload, (old_time, old_time))
        os.utime(artifacts, (old_time, old_time))
        assert read_json("purge", "--gui-paths-save", project)["saved"] is True
        paths = read_json("purge", "--gui-paths-list")
        assert [row["path"] for row in paths["paths"]] == [str(project)]
        candidates = read_json("purge", "--gui-list")
        assert str(artifacts) in [row["path"] for row in candidates]
        run("purge", "--gui-remove", artifacts, success=False)
        assert payload.exists() and sentinel.exists()
        run("purge", "--dry-run", "--gui-remove", artifacts)
        assert payload.exists() and sentinel.exists()
        run("purge", "--gui-remove", artifacts, confirmed=True)
        assert not artifacts.exists() and sentinel.exists()
        print("PASS: project selection, denied unconfirmed purge, preview, exact removal", flush=True)

        downloads = root / "Downloads"
        downloads.mkdir()
        installer = downloads / "Fixture Installer.dmg"
        installer.write_bytes(b"Disposable installer fixture" * 512)
        other = downloads / "keep.txt"
        other.write_text("Unselected file must remain.\n")
        installers = read_json("installer", "--gui-list")
        assert str(installer) in [row["path"] for row in installers]
        run("installer", "--gui-remove", installer, success=False)
        assert installer.exists()
        run("installer", "--dry-run", "--gui-remove", installer)
        assert installer.exists()
        run("installer", "--gui-remove", installer, confirmed=True)
        assert not installer.exists() and other.exists()
        print("PASS: installer selection, denied unconfirmed removal, preview, exact removal", flush=True)

        analysis = read_json("analyze", "--json", project)
        assert analysis["overview"] is False
        assert str(sentinel) in [row["path"] for row in analysis["entries"]]
        run("analyze", "--trash-json", sentinel, success=False)
        run("uninstall", f"--gui-path={project / 'Missing.app'}", success=False)
        assert sentinel.exists() and other.exists()
        print("PASS: folder analysis and denied unconfirmed Trash/uninstall", flush=True)

    print("All packaged bridge smoke checks passed.", flush=True)


if __name__ == "__main__":
    main()
