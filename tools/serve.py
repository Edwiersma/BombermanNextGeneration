"""Serve the Web export on localhost.

Usage: python tools/serve.py [--port 8060] [--dir build/web]

Binds to 127.0.0.1 on purpose: the browser Gamepad API only works in a secure
context, and plain http is only treated as secure on localhost.
"""
import argparse
import functools
import http.server
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
    }

    def end_headers(self):
        # Always load the latest export while iterating.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8060)
    parser.add_argument("--dir", default=str(ROOT / "build" / "web"))
    args = parser.parse_args()

    directory = Path(args.dir).resolve()
    if not (directory / "index.html").exists():
        raise SystemExit(f"No index.html in {directory}. Run tools/export_web.ps1 first.")

    handler = functools.partial(Handler, directory=str(directory))
    with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as httpd:
        print(f"Serving {directory} at http://localhost:{args.port}/")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
