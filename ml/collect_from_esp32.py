#!/usr/bin/env python3
"""
collect_from_esp32.py - ESP32-CAM Data Collection Tool
======================================================
Captures JPEG frames from an ESP32-CAM and saves them into labelled folders
for dataset expansion.

Usage:
    python collect_from_esp32.py --ip 192.168.1.100 --label Happy --output dataset/collected/
    python collect_from_esp32.py --ip 192.168.1.100 --label Sad --interval 2

Press Ctrl+C to stop collection. The script prints the total count on exit.

NOTE: Do NOT hardcode any camera IP. Always pass via --ip argument.
"""

import argparse
import os
import sys
import time
from datetime import datetime

import requests
from PIL import Image
import io


def capture_frame(ip: str, timeout: float = 5.0) -> bytes:
    """
    Capture a single JPEG frame from the ESP32-CAM.
    
    The ESP32-CAM exposes a /capture endpoint that returns a single JPEG frame.
    
    Args:
        ip: IP address (and optional port) of the ESP32-CAM.
        timeout: Request timeout in seconds.
    
    Returns:
        Raw JPEG bytes.
    
    Raises:
        requests.RequestException: On network errors.
        ValueError: If the response is not a valid JPEG.
    """
    url = f"http://{ip}/capture"
    response = requests.get(url, timeout=timeout)
    response.raise_for_status()
    
    # Verify it's a JPEG
    content_type = response.headers.get("Content-Type", "")
    if "image/jpeg" not in content_type and not response.content[:2] == b'\xff\xd8':
        raise ValueError(f"Response is not JPEG (Content-Type: {content_type})")
    
    return response.content


def validate_image(jpeg_bytes: bytes) -> bool:
    """Verify the JPEG bytes can be decoded as a valid image."""
    try:
        img = Image.open(io.BytesIO(jpeg_bytes))
        img.verify()
        return True
    except Exception:
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Collect labelled face images from ESP32-CAM for dataset expansion."
    )
    parser.add_argument(
        "--ip", required=True,
        help="IP address of the ESP32-CAM (e.g., 192.168.1.100 or 192.168.1.100:80)"
    )
    parser.add_argument(
        "--label", required=True, choices=["Happy", "Neutral", "Sad"],
        help="Emotion label for the captured images."
    )
    parser.add_argument(
        "--output", default="dataset/collected/",
        help="Base output directory (default: dataset/collected/)"
    )
    parser.add_argument(
        "--interval", type=float, default=1.0,
        help="Seconds between captures (default: 1.0)"
    )
    parser.add_argument(
        "--timeout", type=float, default=5.0,
        help="HTTP request timeout in seconds (default: 5.0)"
    )
    args = parser.parse_args()

    # Create output directory
    save_dir = os.path.join(args.output, args.label)
    os.makedirs(save_dir, exist_ok=True)

    print(f"=== ESP32-CAM Data Collection ===")
    print(f"Camera IP   : {args.ip}")
    print(f"Label       : {args.label}")
    print(f"Save to     : {os.path.abspath(save_dir)}")
    print(f"Interval    : {args.interval}s")
    print(f"Press Ctrl+C to stop.\n")

    count = 0
    errors = 0

    try:
        while True:
            try:
                jpeg_bytes = capture_frame(args.ip, timeout=args.timeout)
                
                if not validate_image(jpeg_bytes):
                    print(f"  [!] Invalid image received, skipping...")
                    errors += 1
                    time.sleep(args.interval)
                    continue

                # Save with timestamp filename
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
                filename = f"{args.label}_{timestamp}.jpg"
                filepath = os.path.join(save_dir, filename)

                with open(filepath, "wb") as f:
                    f.write(jpeg_bytes)

                count += 1
                size_kb = len(jpeg_bytes) / 1024
                print(f"  [{count:4d}] Saved: {filename} ({size_kb:.1f} KB)")

            except requests.RequestException as e:
                errors += 1
                print(f"  [!] Network error: {e}")
            except Exception as e:
                errors += 1
                print(f"  [!] Error: {e}")

            time.sleep(args.interval)

    except KeyboardInterrupt:
        print(f"\n\n=== Collection Complete ===")
        print(f"Total captured : {count}")
        print(f"Total errors   : {errors}")
        print(f"Saved to       : {os.path.abspath(save_dir)}")
        sys.exit(0)


if __name__ == "__main__":
    main()
