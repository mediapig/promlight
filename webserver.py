#!/usr/bin/env python3
"""
PromLight 自定义 Web UI 代理服务

用法:
    python3 webserver.py [--port 8080] [--daemon-port 7800]

打开浏览器访问 http://localhost:8080
"""

import argparse
import os
import sys
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser(description="PromLight web UI proxy")
    ap.add_argument("--port",        type=int, default=8080,  help="本服务监听端口 (默认 8080)")
    ap.add_argument("--daemon-port", type=int, default=7800,  help="PromLight daemon Web 端口 (默认 7800)")
    args = ap.parse_args()

    daemon_base = f"http://127.0.0.1:{args.daemon_port}"

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *a):
            pass  # 关掉每次请求的噪音日志

        def do_GET(self):
            if self.path == "/" or self.path == "/index.html":
                self._serve_file("webui.html", "text/html; charset=utf-8")
            elif self.path.startswith("/api/"):
                self._proxy(daemon_base + self.path)
            else:
                self.send_error(404)

        def do_POST(self):
            if self.path.startswith("/api/"):
                length = int(self.headers.get("Content-Length", 0))
                body   = self.rfile.read(length) if length else None
                self._proxy(daemon_base + self.path, body)
            else:
                self.send_error(404)

        def _serve_file(self, filename, content_type):
            path = os.path.join(SCRIPT_DIR, filename)
            try:
                with open(path, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", len(data))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(data)
            except FileNotFoundError:
                self.send_error(404, f"{filename} not found")

        def _proxy(self, url, body=None):
            method = "POST" if body is not None else "GET"
            ct     = self.headers.get("Content-Type", "application/json")
            req    = urllib.request.Request(url, data=body, method=method)
            if body:
                req.add_header("Content-Type", ct)

            try:
                with urllib.request.urlopen(req, timeout=30) as resp:
                    resp_ct  = resp.headers.get("Content-Type", "application/octet-stream")
                    is_sse   = "text/event-stream" in resp_ct

                    self.send_response(resp.status)
                    self.send_header("Content-Type", resp_ct)
                    if is_sse:
                        self.send_header("Cache-Control", "no-cache")
                        self.send_header("X-Accel-Buffering", "no")
                    else:
                        cl = resp.headers.get("Content-Length")
                        if cl:
                            self.send_header("Content-Length", cl)
                    self.end_headers()

                    if is_sse:
                        # 流式转发 SSE，不缓冲
                        try:
                            while True:
                                chunk = resp.read(256)
                                if not chunk:
                                    break
                                self.wfile.write(chunk)
                                self.wfile.flush()
                        except (BrokenPipeError, ConnectionResetError):
                            pass
                    else:
                        self.wfile.write(resp.read())

            except urllib.error.URLError as e:
                self.send_error(502, f"daemon unreachable: {e.reason}")
            except Exception as e:
                self.send_error(500, str(e))

    addr = ("127.0.0.1", args.port)
    httpd = HTTPServer(addr, Handler)
    url   = f"http://localhost:{args.port}"
    print(f"PromLight Web UI  →  {url}")
    print(f"代理 daemon       →  {daemon_base}")
    print(f"按 Ctrl+C 停止")
    try:
        import webbrowser
        webbrowser.open(url)
    except Exception:
        pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    main()
