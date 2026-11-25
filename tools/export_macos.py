#!/usr/bin/env python3
"""Build the universal macOS app and test its packaged PCK before publishing it."""

import argparse
import configparser
import ctypes
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


PROJECT = Path(__file__).resolve().parents[1]
NOTICES = (
    "assets/licenses/Asset-Credits.txt",
    "assets/licenses/Godot-and-Third-Party.txt",
    "assets/fonts/Fandol-COPYING.txt",
    "assets/icons/LUCIDE-LICENSE.txt",
)
PLAY_CHECKS = (
    ("landing_salvage_play", ()),
    ("opening_flow", ()),
    ("opening_flow", ("--craft",)),
    ("gear_patrol_play", ()),
    ("field_gear_rules", ()),
    ("radar_play", ()),
    ("radar_rules", ()),
)


def run_godot(executable, args, temp, name, check_play=False):
    log = temp / (name + ".log")
    cmd = [executable, "--headless", "--log-file", log, *args]
    run = subprocess.run(cmd, cwd=temp, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, errors="replace", timeout=180)
    output = run.stdout
    if log.is_file():
        output += "\n" + log.read_text(errors="replace")
    lines = output.splitlines()
    errors = []
    for idx, line in enumerate(lines):
        if 'Condition "ret != noErr"' in line and idx + 1 < len(lines) and "get_system_ca_certificates" in lines[idx + 1]:
            continue
        if "SCRIPT ERROR" in line or line.startswith("ERROR:"):
            errors.append(line)
    if run.returncode or errors or (check_play and "PASS:" not in output):
        detail = "\n".join(errors + lines[-35:])
        raise RuntimeError(f"{name} failed (exit {run.returncode})\n{detail}")
    print(f"{name}: OK", flush=True)


def stage_project(stage, template):
    stage.mkdir()
    # Stage the entire runtime, without importing course documents, tests, or user caches.
    for folder in ("assets", "scenes", "scripts"):
        shutil.copytree(PROJECT / folder, stage / folder, ignore=shutil.ignore_patterns(".DS_Store"))
    shutil.copy2(PROJECT / "project.godot", stage)
    preset = stage / "export_presets.cfg"
    shutil.copy2(PROJECT / preset.name, preset)
    config = configparser.ConfigParser(interpolation=None)
    config.read(preset, encoding="utf-8")
    section = next(key for key in config if config[key].get("name") == '"macOS"')
    options = config[section + ".options"]
    if template:
        options["custom_template/release"] = json.dumps(str(template), ensure_ascii=False)
        with preset.open("w", encoding="utf-8") as out:
            config.write(out, space_around_delimiters=False)
    return {key: json.loads(options["application/" + key])
            for key in ("name", "bundle_identifier", "short_version", "version")}


def verify_bundle(app, settings):
    contents = app / "Contents"
    with (contents / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    for plist_key, preset_key in (("CFBundleIdentifier", "bundle_identifier"),
                                 ("CFBundleVersion", "version"),
                                 ("CFBundleShortVersionString", "short_version")):
        if info.get(plist_key) != settings[preset_key]:
            raise ValueError(f"Incorrect {plist_key} in exported bundle: {info.get(plist_key)}")
    engine = contents / "MacOS" / info["CFBundleExecutable"]
    arches = subprocess.check_output(["/usr/bin/lipo", "-archs", engine], text=True).split()
    if set(arches) != {"arm64", "x86_64"}:
        raise ValueError(f"Universal executable required, got {arches}")
    packs = list((contents / "Resources").glob("*.pck"))
    if len(packs) != 1 or not packs[0].stat().st_size:
        raise ValueError("The exported bundle needs one nonempty PCK")
    notices = contents / "Resources" / "Licenses"
    notices.mkdir(exist_ok=True)
    for name in NOTICES:
        shutil.copy2(PROJECT / name, notices)
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", app], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app], check=True)
    return engine, packs[0]


def test_bundle(engine, pack, temp):
    checks = temp / "checks"
    checks.mkdir()
    # The exported PCK omits tests. Its engine can execute an external test script
    # whose dependencies refer to the same temporary directory.
    for script in (PROJECT / "tests").glob("*.gd"):
        source = script.read_text()
        external_dir = json.dumps(str(checks) + "/", ensure_ascii=False)[1:-1]
        scratch_dir = json.dumps(str(temp) + "/", ensure_ascii=False)[1:-1]
        source = source.replace("res://tests/", external_dir).replace("/private/tmp/", scratch_dir)
        (checks / script.name).write_text(source)
    for index, (name, extra) in enumerate(PLAY_CHECKS):
        args = ["--main-pack", pack, "--script", checks / (name + ".gd")]
        if extra:
            args.extend(["--", *extra])
        run_godot(engine, args, temp, f"{index + 1}-{name}", check_play=True)
    for region in ("camp", "highlands"):
        fixture = PROJECT / "tools" / "fixtures" / (region + "-040.json")
        args = ["--main-pack", pack, "--script", PROJECT / "tools" / "migration_play.gd",
                "--", fixture, temp / (region + "-upgrade.json")]
        run_godot(engine, args, temp, "upgrade-" + region, check_play=True)


def publish(app, destination):
    # RENAME_EXCL atomically refuses an output that appeared during the tests.
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    if rename(os.fsencode(app), os.fsencode(destination), 0x00000004):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(destination))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot editor executable (tested with 4.5.1)")
    parser.add_argument("--template", type=Path, help="matching macos.zip, or use installed export templates")
    parser.add_argument("--output", type=Path, required=True, help="new .app path (never overwrites)")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Run on macOS with lipo and codesign.")
    engine = shutil.which(os.path.expanduser(args.godot))
    if not engine:
        parser.error("Godot editor executable not found; use --godot.")
    engine = Path(engine).resolve()
    template = args.template.expanduser().resolve() if args.template else None
    if template and not template.is_file():
        parser.error("The macos.zip export template could not be found.")
    destination = args.output.expanduser().absolute()
    if destination.suffix != ".app" or os.path.lexists(destination):
        parser.error("--output must be a new .app path.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="starfire-build-") as work, tempfile.TemporaryDirectory(
        prefix=".starfire-export-", dir=destination.parent
    ) as candidate:
        temp = Path(work)
        stage = temp / "project"
        settings = stage_project(stage, template)
        app = Path(candidate) / (settings["name"] + ".app")
        run_godot(engine, ["--path", stage, "--editor", "--import"], temp, "import")
        run_godot(engine, ["--path", stage, "--export-release", "macOS", app], temp, "export")
        binary, pack = verify_bundle(app, settings)
        test_bundle(binary, pack, temp)
        publish(app, destination)
    print(f"Verified macOS {settings['short_version']} (arm64, x86_64)\n{destination}")


if __name__ == "__main__":
    main()
