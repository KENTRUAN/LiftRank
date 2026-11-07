#!/usr/bin/env python3
"""LiftRank development relay. A non-loopback listener requires TLS."""
import argparse
import hmac
import json
import os
import ssl
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OPENAI_URL = "https://api.openai.com"
CHAT_PATH = "/v1/chat/completions"
IMAGE_PATH = "/v1/images/generations"


def make_handler(api_key, app_token, chat_model, image_limit):
    image_lock = threading.Lock()
    images_remaining = image_limit

    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, data):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def fail(self, status, message):
            self.reply(status, json.dumps({"error": {"message": message}}).encode())

        def do_POST(self):
            nonlocal images_remaining
            if self.path not in (CHAT_PATH, IMAGE_PATH):
                return self.fail(404, "Unsupported endpoint")
            auth = self.headers.get("Authorization", "").encode()
            if not hmac.compare_digest(auth, f"Bearer {app_token}".encode()):
                return self.fail(401, "Invalid LiftRank test token")

            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 256_000:
                    return self.fail(413, "Request too large or empty")
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    return self.fail(400, "Expected a JSON object")
            except (ValueError, UnicodeDecodeError):
                return self.fail(400, "Invalid JSON")

            if self.path == CHAT_PATH:
                messages = body.get("messages")
                if not isinstance(messages, list) or not messages:
                    return self.fail(400, "Expected chat messages")
                payload = {"model": chat_model, "messages": messages, "max_completion_tokens": 4096}
                return self.forward(payload)

            prompt = body.get("prompt")
            if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 2000:
                return self.fail(400, "Invalid portrait prompt")
            if not image_lock.acquire(blocking=False):
                return self.fail(429, "A portrait is already being generated")
            try:
                if images_remaining <= 0:
                    return self.fail(429, "Test relay portrait limit reached")
                images_remaining -= 1
                payload = {"model": "gpt-image-2", "prompt": prompt, "n": 1,
                           "size": "1024x1024", "quality": "low", "output_format": "jpeg"}
                self.forward(payload)
            finally:
                image_lock.release()

        def forward(self, payload):
            request = urllib.request.Request(
                OPENAI_URL + self.path,
                data=json.dumps(payload).encode(),
                headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            )
            try:
                with urllib.request.urlopen(request, timeout=170) as response:
                    self.reply(response.status, response.read())
            except urllib.error.HTTPError as error:
                # Keep upstream errors and credentials out of the device response.
                self.fail(error.code, f"OpenAI returned HTTP {error.code}. Check the project permissions and billing.")
            except (urllib.error.URLError, TimeoutError):
                self.fail(502, "OpenAI is unreachable or timed out")

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--tls-cert")
    parser.add_argument("--tls-key")
    parser.add_argument("--image-limit", type=int, default=5, help="maximum portrait requests per server run")
    args = parser.parse_args()
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    app_token = os.environ.get("LIFTRANK_RELAY_TOKEN", "").strip()
    if not api_key or len(app_token) < 24 or args.image_limit < 1:
        parser.error("Set OPENAI_API_KEY and a LIFTRANK_RELAY_TOKEN of at least 24 characters. Image limit must be positive.")
    if bool(args.tls_cert) != bool(args.tls_key) or (args.host != "127.0.0.1" and not args.tls_cert):
        parser.error("Provide a TLS certificate and key when listening outside loopback.")
    chat_model = os.environ.get("LIFTRANK_CHAT_MODEL", "gpt-4o")
    handler = make_handler(api_key, app_token, chat_model, args.image_limit)
    with ThreadingHTTPServer((args.host, args.port), handler) as server:
        if args.tls_cert:
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.minimum_version = ssl.TLSVersion.TLSv1_2
            tls.load_cert_chain(args.tls_cert, args.tls_key)
            server.socket = tls.wrap_socket(server.socket, server_side=True)
        print(f"LiftRank test relay listening on {args.host}:{args.port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
