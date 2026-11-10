#!/usr/bin/env python3
"""Local protocol fixtures; no keys or paid API calls. Uses system speaker."""
import base64
import json
import hashlib
import math
import struct
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Quiet 220 Hz sine, exactly 800 ms at 24 kHz PCM16 mono.
PCM = b"".join(struct.pack("<h", int(300 * math.sin(i * 2 * math.pi * 220 / 24000))) for i in range(19200))


class Fixture(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.close_connection = True
        if not self.path.startswith("/cosy"):
            self.send_error(404)
            return
        # Minimal local RFC6455 fixture, not part of the shipped application.
        accept = base64.b64encode(hashlib.sha1((self.headers["Sec-WebSocket-Key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()

        def receive():
            first, second = self.rfile.read(2)
            length = second & 127
            if length == 126:
                length = struct.unpack("!H", self.rfile.read(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self.rfile.read(8))[0]
            mask = self.rfile.read(4) if second & 128 else b""
            data = self.rfile.read(length)
            if mask:
                data = bytes(v ^ mask[i % 4] for i, v in enumerate(data))
            assert first & 15 == 1 and length < 10000
            return json.loads(data)

        def send(data, opcode=1):
            prefix = bytes([0x80 | opcode])
            if len(data) < 126:
                prefix += bytes([len(data)])
            else:
                prefix += b"\x7e" + struct.pack("!H", len(data))
            self.wfile.write(prefix + data)
            self.wfile.flush()

        try:
            start = receive()
            assert start["header"]["action"] == "run-task"
            assert start["payload"]["parameters"]["format"] == "pcm"
            task = start["header"]["task_id"]
            send(json.dumps({"header": {"event": "task-started", "task_id": task}}).encode())
            assert receive()["header"]["action"] == "continue-task"
            assert receive()["header"]["action"] == "finish-task"
            for offset in range(0, len(PCM), 4800):
                send(PCM[offset:offset + 4800], opcode=2)
                time.sleep(0.012)
            if self.path != "/cosy-truncated":
                send(json.dumps({"header": {"event": "task-finished", "task_id": task}}).encode())
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        self.close_connection = True
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if self.path.startswith("/error"):
            self.send_response(401)
            self.end_headers()
            return
        raw = self.path.startswith(("/pcm", "/slow"))
        self.send_response(200)
        self.send_header("Content-Type", "audio/pcm" if raw else "text/event-stream")
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            for start in range(0, len(PCM), 4800):
                chunk = PCM[start:start + 4800]
                if raw:
                    event = chunk
                elif self.path.startswith("/minimax"):
                    event = ("data: " + json.dumps({"data": {"audio": chunk.hex(), "status": 1}}) + "\r\n\r\n").encode()
                elif self.path.startswith("/custom"):
                    event = ("data: " + json.dumps({"data": {"audio": base64.b64encode(chunk).decode()}}) + "\n\n").encode()
                else:
                    event = ("event: 352\ndata: " + json.dumps({"code": 0, "data": base64.b64encode(chunk).decode()}) + "\n\n").encode()
                # Split data across sample/event boundaries, not just JSON objects.
                self.wfile.write(event[:3])
                self.wfile.flush()
                self.wfile.write(event[3:])
                self.wfile.flush()
                time.sleep(0.15 if self.path.startswith("/slow") else 0.012)
            if self.path.startswith("/minimax"):
                self.wfile.write(b'data: {"data":{"status":2}}\n\n')
            elif self.path.startswith("/doubao"):
                self.wfile.write(b'event: 152\ndata: {"code":20000000}\n\n')
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    sources = ["ActionLibrary", "VoicePreferences", "TTSRequest", "TTSStreamDecoder", "PCMStreamPlayer", "StreamingVoice", "AudioOutputDevices"]
    subprocess.run(["swiftc", "-swift-version", "5", *[f"Sources/{s}.swift" for s in sources], "Tests/VoiceIntegrationTests.swift", "-framework", "AppKit", "-o", ".build/voice-integration-tests"], cwd=ROOT, check=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run([str(ROOT / ".build/voice-integration-tests"), f"http://127.0.0.1:{server.server_port}"], cwd=ROOT, check=True)
    finally:
        server.shutdown()
        server.server_close()
