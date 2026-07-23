import base64
import json
import os
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class LangfuseApiHandler(BaseHTTPRequestHandler):
    deleted_ids: list[str] = []

    def do_GET(self) -> None:
        self._assert_auth()
        query = parse_qs(urlparse(self.path).query)
        page = int(query["page"][0])
        ids = ["old-1", "old-2"] if page == 1 else ["old-3"]
        self._json(
            {
                "data": [{"id": trace_id} for trace_id in ids],
                "meta": {"page": page, "limit": 100, "totalItems": 3, "totalPages": 2},
            }
        )

    def do_DELETE(self) -> None:
        self._assert_auth()
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.__class__.deleted_ids.extend(json.loads(body)["traceIds"])
        self._json({"message": "scheduled"})

    def log_message(self, *_: object) -> None:
        pass

    def _assert_auth(self) -> None:
        expected = base64.b64encode(b"lf_pk_test:lf_sk_test").decode()
        if self.headers.get("Authorization") != f"Basic {expected}":
            self.send_error(401)

    def _json(self, body: dict[str, object]) -> None:
        payload = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class PruneLangfuseTracesTest(unittest.TestCase):
    def test_deletes_all_pages_older_than_cutoff(self) -> None:
        LangfuseApiHandler.deleted_ids = []
        server = ThreadingHTTPServer(("127.0.0.1", 0), LangfuseApiHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            with tempfile.TemporaryDirectory() as directory:
                langfuse_dir = Path(directory)
                (langfuse_dir / ".env").write_text(
                    "LANGFUSE_INIT_PROJECT_PUBLIC_KEY=lf_pk_test\n"
                    "LANGFUSE_INIT_PROJECT_SECRET_KEY=lf_sk_test\n",
                    encoding="utf-8",
                )
                env = {
                    **os.environ,
                    "LANGFUSE_DIR": directory,
                    "LANGFUSE_API_BASE": (
                        f"http://127.0.0.1:{server.server_port}/api/public"
                    ),
                }
                result = subprocess.run(
                    ["bash", "scripts/prune-langfuse-traces.sh"],
                    check=True,
                    capture_output=True,
                    text=True,
                    env=env,
                )
        finally:
            server.shutdown()
            thread.join()
            server.server_close()

        self.assertCountEqual(LangfuseApiHandler.deleted_ids, ["old-1", "old-2", "old-3"])
        self.assertIn("Scheduled deletion for 3", result.stdout)


if __name__ == "__main__":
    unittest.main()
