#!/usr/bin/env python3
"""
mock_esp32_server.py - Mock ESP32-CAM Server for Development/Testing
=====================================================================
Simulates an ESP32-CAM HTTP server so the Flutter app and data collection
scripts can be tested without actual hardware.

Endpoints:
  GET /capture           → Returns a random JPEG from the dataset
  GET :81/stream         → MJPEG stream (boundary=123456789000000000000987654321) ~5fps
  GET /status            → JSON mimicking real ESP32-CAM status
  GET /control?var=&val= → Accepts and logs control commands, returns 200

Usage:
    python mock_esp32_server.py --dataset-dir ../dataset/downSyndrome/Happy
    python mock_esp32_server.py --host 0.0.0.0 --port 80 --stream-port 81

NOTE: Requires dataset images to serve. Point --dataset-dir to a folder of JPEGs.
"""

import argparse
import glob
import json
import os
import random
import sys
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler


def find_images(dataset_dir: str) -> list:
    """Recursively find all JPEG images in the dataset directory."""
    patterns = ["*.jpg", "*.jpeg", "*.JPG", "*.JPEG"]
    images = []
    for pattern in patterns:
        images.extend(glob.glob(os.path.join(dataset_dir, "**", pattern), recursive=True))
    if not images:
        # Try the directory itself
        images = [f for f in glob.glob(os.path.join(dataset_dir, "*"))
                  if f.lower().endswith(('.jpg', '.jpeg'))]
    return images


# Global image list (populated at startup)
IMAGE_FILES = []


class CaptureHandler(BaseHTTPRequestHandler):
    """Handler for the main HTTP server (port 80) - /capture, /status, /control."""

    def log_message(self, format, *args):
        """Suppress default logging for cleaner output."""
        pass

    def do_GET(self):
        if self.path == "/capture":
            self._handle_capture()
        elif self.path == "/status":
            self._handle_status()
        elif self.path.startswith("/control"):
            self._handle_control()
        else:
            self.send_error(404, f"Not Found: {self.path}")

    def _handle_capture(self):
        """Return a random JPEG from the dataset."""
        if not IMAGE_FILES:
            self.send_error(503, "No images available")
            return
        
        img_path = random.choice(IMAGE_FILES)
        try:
            with open(img_path, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self.send_error(500, str(e))

    def _handle_status(self):
        """Return a JSON status mimicking a real ESP32-CAM."""
        status = {
            "framesize": 8,       # VGA (640x480)
            "quality": 10,
            "brightness": 0,
            "contrast": 0,
            "saturation": 0,
            "sharpness": 0,
            "special_effect": 0,
            "wb_mode": 0,
            "awb": 1,
            "awb_gain": 1,
            "aec": 1,
            "aec2": 0,
            "ae_level": 0,
            "aec_value": 168,
            "agc": 1,
            "agc_gain": 0,
            "gainceiling": 0,
            "bpc": 0,
            "wpc": 1,
            "raw_gma": 1,
            "lenc": 1,
            "vflip": 0,
            "hmirror": 0,
            "dcw": 1,
            "colorbar": 0,
            "face_detect": 0,
            "face_enroll": 0,
            "face_recognize": 0,
            "led_intensity": 0,
            "mock_server": True,
            "image_count": len(IMAGE_FILES),
        }
        body = json.dumps(status).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _handle_control(self):
        """Accept control commands and log them (no-op for mock)."""
        # Parse query string
        from urllib.parse import urlparse, parse_qs
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        var = params.get("var", ["?"])[0]
        val = params.get("val", ["?"])[0]
        print(f"  [control] var={var}, val={val}")
        
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b"OK")


class StreamHandler(BaseHTTPRequestHandler):
    """Handler for the MJPEG streaming server (port 81)."""

    BOUNDARY = "123456789000000000000987654321"

    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == "/stream" or self.path == "/":
            self._handle_stream()
        else:
            self.send_error(404)

    def _handle_stream(self):
        """Serve an MJPEG stream at ~5 fps using dataset images."""
        if not IMAGE_FILES:
            self.send_error(503, "No images available")
            return

        self.send_response(200)
        self.send_header(
            "Content-Type",
            f"multipart/x-mixed-replace; boundary={self.BOUNDARY}"
        )
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        try:
            idx = 0
            while True:
                img_path = IMAGE_FILES[idx % len(IMAGE_FILES)]
                idx += 1

                with open(img_path, "rb") as f:
                    frame = f.read()

                header = (
                    f"--{self.BOUNDARY}\r\n"
                    f"Content-Type: image/jpeg\r\n"
                    f"Content-Length: {len(frame)}\r\n"
                    f"\r\n"
                ).encode("utf-8")

                self.wfile.write(header)
                self.wfile.write(frame)
                self.wfile.write(b"\r\n")
                self.wfile.flush()

                time.sleep(0.2)  # ~5 fps
        except (BrokenPipeError, ConnectionResetError):
            pass  # Client disconnected


def run_server(handler_class, host, port, name):
    """Start an HTTP server in a thread."""
    server = HTTPServer((host, port), handler_class)
    print(f"  {name} server: http://{host}:{port}")
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def main():
    parser = argparse.ArgumentParser(
        description="Mock ESP32-CAM server for testing without hardware."
    )
    parser.add_argument(
        "--dataset-dir",
        default=os.path.join(os.path.dirname(__file__), "..", "dataset", "downSyndrome"),
        help="Directory containing JPEG images to serve (searches recursively)."
    )
    parser.add_argument("--host", default="0.0.0.0", help="Bind host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=80, help="Main HTTP port (default: 80)")
    parser.add_argument("--stream-port", type=int, default=81, help="Stream port (default: 81)")
    args = parser.parse_args()

    global IMAGE_FILES
    IMAGE_FILES = find_images(args.dataset_dir)

    if not IMAGE_FILES:
        print(f"ERROR: No JPEG images found in {args.dataset_dir}")
        print("Provide a directory with images via --dataset-dir")
        sys.exit(1)

    print(f"=== Mock ESP32-CAM Server ===")
    print(f"Dataset     : {os.path.abspath(args.dataset_dir)}")
    print(f"Images found: {len(IMAGE_FILES)}")

    # Start servers
    capture_server = run_server(CaptureHandler, args.host, args.port, "Capture")
    stream_server = run_server(StreamHandler, args.host, args.stream_port, "Stream")

    print(f"\nEndpoints:")
    print(f"  GET http://{args.host}:{args.port}/capture  → random JPEG")
    print(f"  GET http://{args.host}:{args.port}/status   → JSON status")
    print(f"  GET http://{args.host}:{args.port}/control  → control (logged)")
    print(f"  GET http://{args.host}:{args.stream_port}/stream   → MJPEG stream (~5fps)")
    print(f"\nPress Ctrl+C to stop.\n")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        capture_server.shutdown()
        stream_server.shutdown()
        print("Done.")


if __name__ == "__main__":
    main()
