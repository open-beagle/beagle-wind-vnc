#!/usr/bin/env python3
"""Capture KWin's internal workspace and report pixel-validity statistics."""

import argparse
import json
import math
import os
import threading

import dbus


def plain(value):
    if isinstance(value, dict):
        return {str(key): plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    if isinstance(value, (dbus.Boolean, bool)):
        return bool(value)
    if isinstance(value, (dbus.Byte, dbus.Int16, dbus.Int32, dbus.Int64)):
        return int(value)
    if isinstance(value, (dbus.UInt16, dbus.UInt32, dbus.UInt64)):
        return int(value)
    if isinstance(value, (dbus.Double, float)):
        return float(value)
    return str(value)


def pixel_stats(data, metadata):
    width = int(metadata.get("width", 0))
    height = int(metadata.get("height", 0))
    stride = int(metadata.get("stride", width * 4 if width else 0))
    expected = stride * height
    if width <= 0 or height <= 0 or stride < width * 4 or len(data) < expected:
        return {
            "valid": False,
            "reason": "invalid geometry or truncated pixel payload",
            "width": width,
            "height": height,
            "stride": stride,
            "bytes": len(data),
            "expectedBytes": expected,
        }

    count = 0
    total = 0.0
    total_squared = 0.0
    nonblack = 0
    minimum = 255.0
    maximum = 0.0
    step = max(1, int(math.sqrt((width * height) / 200000)))
    for y in range(0, height, step):
        row = y * stride
        for x in range(0, width, step):
            offset = row + x * 4
            luminance = (
                int(data[offset]) + int(data[offset + 1]) + int(data[offset + 2])
            ) / 3.0
            total += luminance
            total_squared += luminance * luminance
            count += 1
            if luminance > 8:
                nonblack += 1
            minimum = min(minimum, luminance)
            maximum = max(maximum, luminance)

    mean = total / count
    variance = max(0.0, total_squared / count - mean * mean)
    return {
        "valid": True,
        "width": width,
        "height": height,
        "stride": stride,
        "bytes": len(data),
        "sampledPixels": count,
        "mean": round(mean, 4),
        "stddev": round(math.sqrt(variance), 4),
        "minimum": round(minimum, 4),
        "maximum": round(maximum, 4),
        "nonblackRatio": round(nonblack / count, 6),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", help="optional raw pixel output path")
    args = parser.parse_args()

    read_fd, write_fd = os.pipe()
    chunks = []
    read_error = []

    def drain():
        try:
            while True:
                chunk = os.read(read_fd, 1024 * 1024)
                if not chunk:
                    break
                chunks.append(chunk)
        except Exception as exc:  # pragma: no cover - diagnostic path
            read_error.append(str(exc))
        finally:
            os.close(read_fd)

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()

    bus = dbus.SessionBus()
    proxy = bus.get_object(
        "org.kde.KWin.ScreenShot2",
        "/org/kde/KWin/ScreenShot2",
    )
    screenshot = dbus.Interface(proxy, "org.kde.KWin.ScreenShot2")
    try:
        result = screenshot.CaptureWorkspace(
            dbus.Dictionary({}, signature="sv"),
            dbus.types.UnixFd(write_fd),
            timeout=15,
        )
    finally:
        os.close(write_fd)

    reader.join(timeout=15)
    data = b"".join(chunks)
    metadata = plain(result)
    report = {
        "metadata": metadata,
        "readerError": read_error,
        "pixels": pixel_stats(data, metadata),
    }
    if args.output:
        with open(args.output, "wb") as stream:
            stream.write(data)
        report["output"] = os.path.abspath(args.output)
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
