#!/usr/bin/env python3
"""Static file server for the exported web build.

    python tools/serve_web.py            # serves build/web on port 8791
    python tools/serve_web.py 9000       # or any other port

Two things this does that `python -m http.server` does not, and both matter for
a Godot build:

  * it serves .wasm as application/wasm, which is required for
    WebAssembly.instantiateStreaming to be used instead of a fallback path;
  * cross-origin isolation headers are only sent when the build was exported
    with threads enabled. Sending COOP/COEP on a non-threaded build (the
    project default) would break the plain <script> tags in index.html.

Because this project is exported with `variant/thread_support=false`, the build
needs no special headers and will also run from any plain static host — itch.io,
GitHub Pages, an S3 bucket — with no server configuration at all.
"""

import functools
import http.server
import mimetypes
import os
import socketserver
import sys

DEFAULT_PORT = 8791
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "build", "web")

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("application/octet-stream", ".pck")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Godot's loader revalidates the .pck and .wasm on every reload otherwise,
        # which makes iterating on the build painfully slow.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    if not os.path.isdir(ROOT):
        print("No web build at %s" % ROOT)
        print("Export it first:  godot --headless --path . "
              '--export-release "Web" build/web/index.html')
        return 1

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", port), functools.partial(Handler, directory=ROOT)) as httpd:
        print("Serving %s at http://127.0.0.1:%d/" % (ROOT, port))
        print("Press Ctrl+C to stop.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
