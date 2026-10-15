#!/usr/bin/env python3
"""Compile actual ImageIO and core code on macOS; validate an exported backup.

This integration check does not compile SwiftUI or use the iOS SDK.
The supplied ZIP is read only; restoration uses a temporary directory.
"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backup", type=Path)
    args = parser.parse_args()
    archive = args.backup.resolve(strict=True)
    ios = Path(__file__).resolve().parents[1]
    compiler = shutil.which("swiftc")
    if not compiler:
        parser.error("swiftc fehlt. Dieser Check benötigt die macOS-Toolchain.")
    with tempfile.TemporaryDirectory(prefix="werkstatt-native-check-") as directory:
        work = Path(directory)
        environment = os.environ.copy()
        cache = str(work / "cache")
        environment["CLANG_MODULE_CACHE_PATH"] = cache
        common = [compiler, "-swift-version", "5", "-module-cache-path", cache]
        sources = sorted((ios / "WerkstattCore/Sources/WerkstattCore").glob("*.swift"))
        subprocess.run(common + ["-emit-module", "-emit-library", "-module-name", "WerkstattCore",
            *(str(s) for s in sources), "-emit-module-path", str(work / "WerkstattCore.swiftmodule"),
            "-o", str(work / "libWerkstattCore.dylib")], check=True, env=environment)
        # Swift executable top-level statements require a file named main.swift.
        shutil.copyfile(ios / "tests/NativeIntegration.swift", work / "main.swift")
        executable = work / "verify"
        subprocess.run(common + ["-I", str(work), "-L", str(work), "-lWerkstattCore",
            "-Xlinker", "-rpath", "-Xlinker", str(work), str(ios / "WerkstattApp/PhotoRendering.swift"),
            str(work / "main.swift"), "-o", str(executable)], check=True, env=environment)
        subprocess.run([str(executable), str(archive)], check=True, env=environment)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
