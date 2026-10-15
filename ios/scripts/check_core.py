#!/usr/bin/env python3
"""Run Swift core test bodies on macOS even if XCTest/SwiftPM are unavailable.

This is a direct behavioral harness, NOT XCTest. It compiles the actual current
WerkstattCore sources and adapts only the test framework imports. Production
sources and the original XCTest test files remain unchanged. All generated
modules, adapted tests, and test inventory files live in a temporary directory.
Use `swift test --package-path ios/WerkstattCore` with a working Xcode toolchain
for normal XCTest execution and full toolchain validation.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


HARNESS = r'''
import Foundation

var failed = 0
var executed = 0
func failure(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failed += 1
    print("FAIL \(file):\(line) \(message)")
}
class XCTestCase {
    required init() {}
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
func run(_ name: String, _ body: () throws -> Void) {
    executed += 1
    let previous = failed
    do { try body() } catch { failure("\(name): \(error)") }
    print("\(failed == previous ? "PASS" : "FAIL") \(name)")
}
func XCTAssertEqual<T: Equatable>(_ first: @autoclosure () throws -> T, _ second: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try first(), b = try second()
        if a != b { failure("Expected \(a) == \(b). \(message)", file: file, line: line) }
    } catch { failure("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { failure("Expected true. \(message)", file: file, line: line) } }
    catch { failure("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { failure("Expected false. \(message)", file: file, line: line) } }
    catch { failure("Unexpected error: \(error)", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() != nil { failure("Expected nil. \(message)", file: file, line: line) } }
    catch { failure("Unexpected error: \(error)", file: file, line: line) }
}
struct UnwrapError: Error {}
func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let result = try value() else { throw UnwrapError() }
    return result
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    do { _ = try expression(); failure("Expected error. \(message)", file: file, line: line) }
    catch { handler(error) }
}
'''


def prepare_tests(package: Path, destination: Path) -> int:
    test_files = sorted((package / "Tests" / "WerkstattCoreTests").glob("*.swift"))
    if not test_files:
        raise ValueError("No XCTest sources found; refusing an empty successful run.")
    invocations = []
    for source in test_files:
        text = source.read_text()
        classes = re.findall(r"(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase", text)
        if len(classes) != 1:
            raise ValueError(f"Expected exactly one XCTestCase class in {source.name}.")
        # Async tests need a real async/XCTest harness. Never silently skip them.
        methods = re.findall(r"func\s+(test\w+)\s*\(\s*\)\s*([^\{\n]*)\{", text)
        raw_count = len(re.findall(r"func\s+test\w+\s*\(", text))
        if raw_count != len(methods):
            raise ValueError(f"Unsupported test signature in {source.name}.")
        for name, modifiers in methods:
            if "async" in modifiers:
                raise ValueError(f"Async test {name} requires real XCTest.")
            call = ("try " if "throws" in modifiers else "") + f"test.{name}()"
            invocations.append(f'''run("{classes[0]}.{name}") {{
    let test = {classes[0]}()
    try test.setUpWithError()
    defer {{
        do {{ try test.tearDownWithError() }}
        catch {{ failure("Teardown for {name}: \\(error)") }}
    }}
    {call}
}}''')
        adapted, count = re.subn(r"(?m)^import XCTest\s*$", "import Foundation", text)
        if count != 1:
            raise ValueError(f"Expected one framework import in {source.name}.")
        (destination / source.name).write_text(adapted)
    if not invocations:
        raise ValueError("No test methods found; refusing an empty successful run.")
    (destination / "Harness.swift").write_text(HARNESS)
    (destination / "main.swift").write_text(
        "import Foundation\nimport Darwin\n\n"
        + "\n".join(invocations)
        + '\nprint("Direct Swift behavioral harness (not XCTest): '
        '\\(executed) cases, \\(failed) failed assertions/errors")\n'
        'exit(failed == 0 ? 0 : 1)\n'
    )
    return len(invocations)


def check(package: Path, work: Path) -> int:
    if sys.platform != "darwin":
        raise ValueError("This Apple CryptoKit core requires a macOS Swift toolchain.")
    compiler = shutil.which("swiftc")
    if not compiler:
        raise ValueError("swiftc is unavailable. Install a working Xcode toolchain.")
    sources = sorted((package / "Sources" / "WerkstattCore").glob("*.swift"))
    if not sources:
        raise ValueError("WerkstattCore sources are missing.")
    adapted = work / "tests"
    adapted.mkdir()
    count = prepare_tests(package, adapted)
    print(f"Direct Swift behavioral harness: {count} test bodies. XCTest is not loaded.", flush=True)
    print("This does not validate the iOS SDK, SwiftUI, signing, or simulator UI.", flush=True)
    cache = work / "module-cache"
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(cache)
    common = [compiler, "-swift-version", "5", "-module-cache-path", str(cache)]
    subprocess.run(common + [
        "-module-name", "WerkstattCore", "-emit-module", "-emit-library", "-enable-testing",
        *(str(source) for source in sources),
        "-emit-module-path", str(work / "WerkstattCore.swiftmodule"),
        "-o", str(work / "libWerkstattCore.dylib"),
    ], check=True, env=environment)
    executable = work / "WerkstattCoreHarness"
    subprocess.run(common + [
        "-module-name", "WerkstattCoreHarness", "-I", str(work), "-L", str(work),
        "-lWerkstattCore", "-Xlinker", "-rpath", "-Xlinker", str(work),
        *(str(source) for source in sorted(adapted.glob("*.swift"))), "-o", str(executable),
    ], check=True, env=environment)
    return subprocess.run([str(executable)], env=environment).returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, default=Path(__file__).resolve().parents[1] / "WerkstattCore")
    parser.add_argument("--keep", action="store_true", help="Keep generated files in the system temporary directory for debugging.")
    args = parser.parse_args()
    try:
        if args.keep:
            work = Path(tempfile.mkdtemp(prefix="werkstatt-core-harness-"))
            print(f"Generated files: {work}", flush=True)
            return check(args.package.resolve(), work)
        with tempfile.TemporaryDirectory(prefix="werkstatt-core-harness-") as directory:
            return check(args.package.resolve(), Path(directory))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Core check failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
