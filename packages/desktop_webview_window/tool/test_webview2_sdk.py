"""Exercise SDK acquisition with real CMake and a local NuGet-shaped archive."""

import hashlib
import http.server
import io
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import threading
import unittest
import zipfile


WINDOWS = Path(__file__).resolve().parents[1] / "windows"
MODULE = WINDOWS / "webview2_sdk.cmake"
FILES = [
    "build/native/include/WebView2.h",
    "build/native/include/WebView2EnvironmentOptions.h",
    "build/native/x64/WebView2LoaderStatic.lib",
    "build/native/arm64/WebView2LoaderStatic.lib",
]


class Webview2SdkTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dww sdk ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("Microsoft.Web.WebView2.nuspec", "fixture")
            for path in FILES:
                package.writestr(path, path)
        self.archive = archive.getvalue()
        self.sha256 = hashlib.sha256(self.archive).hexdigest()
        self.requests = 0
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                owner.requests += 1
                self.send_response(200)
                self.send_header("Content-Length", str(len(owner.archive)))
                self.end_headers()
                self.wfile.write(owner.archive)

            def log_message(self, *_args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()
        self.addCleanup(self.stop_server)
        self.url = f"http://127.0.0.1:{self.server.server_port}/sdk.nupkg"

    def stop_server(self):
        if self.thread.is_alive():
            self.server.shutdown()
            self.thread.join()
            self.server.server_close()

    def configure(self, name="app", *, sha256=None, wait=True, platform="ARM64"):
        source = self.root / name
        source.mkdir(exist_ok=True)
        (source / "CMakeLists.txt").write_text(
            "cmake_minimum_required(VERSION 3.14)\n"
            "project(sdk_cache_test NONE)\n"
            f'include("{MODULE.as_posix()}")\n'
            f'set(CMAKE_VS_PLATFORM_NAME "{platform}")\n'
            "dww_webview2_arch(arch)\n"
            f'dww_fetch_webview2_sdk(sdk "test" "{sha256 or self.sha256}" "{self.url}")\n'
            'file(WRITE "${CMAKE_BINARY_DIR}/selected.txt" "${sdk}/build/native/${arch}/WebView2LoaderStatic.lib")\n',
            encoding="utf-8",
        )
        process = subprocess.Popen(
            ["cmake", "-S", str(source), "-B", str(source / "build")],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            encoding="utf-8",
            errors="replace",
        )
        self.addCleanup(self.cleanup_process, process)
        return self.finish(process) if wait else process

    def cleanup_process(self, process):
        if process.poll() is None:
            process.kill()
        process.communicate()

    def finish(self, process, success=True):
        output, _ = process.communicate(timeout=60)
        if success:
            self.assertEqual(process.returncode, 0, output)
        else:
            self.assertNotEqual(process.returncode, 0, output)
        return output

    def test_repeated_build_reuses_project_sdk_offline(self):
        self.configure()
        selected = (self.root / "app/build/selected.txt").read_text()
        self.assertTrue(selected.endswith("arm64/WebView2LoaderStatic.lib"))
        self.assertTrue(Path(selected).is_file())
        self.assertTrue(Path(selected).is_relative_to(self.root / "app/build"))
        self.assertEqual(self.requests, 1)
        self.stop_server()
        self.configure()
        self.assertEqual(self.requests, 1)

    def test_clean_build_downloads_again(self):
        self.configure()
        self.assertEqual(self.requests, 1)
        shutil.rmtree(self.root / "app/build")
        self.configure()
        self.assertEqual(self.requests, 2)

    def test_another_project_has_its_own_sdk(self):
        self.configure()
        self.configure("another", platform="x64")
        selected = (self.root / "another/build/selected.txt").read_text()
        self.assertTrue(selected.endswith("x64/WebView2LoaderStatic.lib"))
        self.assertTrue(Path(selected).is_relative_to(self.root / "another/build"))
        self.assertEqual(self.requests, 2)

    def test_hash_mismatch_cannot_publish_sdk(self):
        bad_hash = "0" * 64
        source = self.root / "bad"
        self.finish(self.configure("bad", sha256=bad_hash, wait=False), success=False)
        self.assertFalse((source / "build/selected.txt").exists())
        self.assertFalse((source / "build/_deps/dww_webview2_sdk-src" / FILES[0]).exists())
        self.configure()

    def test_unsupported_target_fails_before_download(self):
        output = self.finish(self.configure(platform="Win32", wait=False), success=False)
        self.assertIn("Unsupported WebView2 target architecture", output)
        self.assertEqual(self.requests, 0)


@unittest.skipUnless(os.name == "nt", "requires MSVC")
class RealSdkLinkTest(unittest.TestCase):
    """Links the pinned NuGet loader into a probe for each target (#481)."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dww link ")
        self.addCleanup(self.temp.cleanup)
        plugin = (WINDOWS / "CMakeLists.txt").read_text(encoding="utf-8")
        self.version = re.search(r'set\(WEBVIEW2_VERSION "([^"]+)"\)', plugin)[1]
        self.sha256 = re.search(r'"([0-9a-f]{64})"', plugin)[1]
        self.url = re.search(r'"(https://api\.nuget\.org/[^"]+)"', plugin)[1].replace(
            "${WEBVIEW2_VERSION}", self.version)

    def has_arm64_tools(self):
        vswhere = Path(os.environ.get("ProgramFiles(x86)", "")) / (
            "Microsoft Visual Studio/Installer/vswhere.exe")
        if not vswhere.is_file():
            return False
        result = subprocess.run(
            [str(vswhere), "-latest", "-products", "*", "-requires",
             "Microsoft.VisualStudio.Component.VC.Tools.ARM64",
             "-property", "installationPath"],
            capture_output=True, encoding="utf-8", errors="replace")
        return bool(result.stdout.strip())

    def test_loader_links_for_each_architecture(self):
        for platform, machine in (("x64", 0x8664), ("ARM64", 0xAA64)):
            with self.subTest(platform=platform):
                if platform == "ARM64" and not self.has_arm64_tools():
                    self.skipTest("MSVC ARM64 build tools are not installed")
                self.assertEqual(self.build(platform), machine)

    def build(self, platform):
        source = Path(self.temp.name) / platform
        source.mkdir()
        (source / "probe.cc").write_text(
            "#include <windows.h>\n#include \"WebView2.h\"\n"
            "int main() {\n  LPWSTR version = nullptr;\n"
            "  GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);\n"
            "  return 0;\n}\n",
            encoding="utf-8")
        (source / "CMakeLists.txt").write_text(
            "cmake_minimum_required(VERSION 3.14)\n"
            "project(dww_link_probe CXX)\n"
            f'include("{MODULE.as_posix()}")\n'
            "dww_webview2_arch(arch)\n"
            f'dww_fetch_webview2_sdk(sdk "{self.version}" "{self.sha256}" "{self.url}")\n'
            "add_executable(probe probe.cc)\n"
            'target_include_directories(probe PRIVATE "${sdk}/build/native/include")\n'
            'target_link_libraries(probe PRIVATE '
            '"${sdk}/build/native/${arch}/WebView2LoaderStatic.lib" version)\n',
            encoding="utf-8")
        build = source / "build"
        for command in (
                ["cmake", "-S", str(source), "-B", str(build), "-A", platform],
                ["cmake", "--build", str(build), "--config", "Release"]):
            result = subprocess.run(command, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT,
                                    encoding="utf-8", errors="replace")
            self.assertEqual(result.returncode, 0, result.stdout)
        image = (build / "Release" / "probe.exe").read_bytes()
        offset = struct.unpack_from("<I", image, 0x3C)[0]
        self.assertEqual(image[offset:offset + 4], b"PE\0\0")
        return struct.unpack_from("<H", image, offset + 4)[0]


if __name__ == "__main__":
    unittest.main()
