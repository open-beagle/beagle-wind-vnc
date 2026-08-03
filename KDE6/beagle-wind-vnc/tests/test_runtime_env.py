import os
import shlex
import subprocess
import unittest
from pathlib import Path


RUNTIME_ENV = Path(__file__).resolve().parents[1] / "runtime-env.sh"
SMITHAY_DISPLAY = Path(__file__).resolve().parents[1] / "smithay-display.py"
KEYS = (
    "BDWIND_RESOLUTION",
    "BDWIND_PHYSICAL_RESOLUTION",
    "BDWIND_FRAMERATE",
    "BDWIND_ENCODER",
    "BDWIND_VIDEO_BITRATE",
    "BDWIND_SMITHAY_VIDEO_BITRATE",
    "BDWIND_POST_ENC_QUEUE_MAX_TIME_MS",
    "BDWIND_SETTINGS_ENV_PRIORITY_KEYS",
)


def load_runtime_env(overrides=None):
    process_env = os.environ.copy()
    for key in KEYS + ("DISPLAY_SIZEW", "DISPLAY_SIZEH", "DISPLAY_REFRESH"):
        process_env.pop(key, None)
    process_env.update(overrides or {})
    command = f". {shlex.quote(str(RUNTIME_ENV))}; env"
    completed = subprocess.run(
        ["bash", "-c", command],
        check=True,
        capture_output=True,
        text=True,
        env=process_env,
    )
    exported = dict(
        line.split("=", 1) for line in completed.stdout.splitlines() if "=" in line
    )
    return {key: exported.get(key) for key in KEYS}


class RuntimeEnvironmentTest(unittest.TestCase):
    def test_smithay_defaults_match_the_fixed_release_baseline(self):
        values = load_runtime_env()
        self.assertEqual(values["BDWIND_RESOLUTION"], "1920x1080")
        self.assertEqual(values["BDWIND_PHYSICAL_RESOLUTION"], "1920x1080")
        self.assertEqual(values["BDWIND_FRAMERATE"], "60")
        self.assertEqual(values["BDWIND_ENCODER"], "nvh264enc")
        self.assertEqual(values["BDWIND_VIDEO_BITRATE"], "12000")
        self.assertEqual(values["BDWIND_SMITHAY_VIDEO_BITRATE"], "12000")
        self.assertEqual(values["BDWIND_POST_ENC_QUEUE_MAX_TIME_MS"], "120")
        for key in (
            "BDWIND_RESOLUTION",
            "BDWIND_PHYSICAL_RESOLUTION",
            "BDWIND_ENCODER",
            "BDWIND_FRAMERATE",
            "BDWIND_VIDEO_BITRATE",
        ):
            self.assertIn(key, values["BDWIND_SETTINGS_ENV_PRIORITY_KEYS"].split(","))

    def test_display_and_bitrate_overrides_stay_in_sync(self):
        values = load_runtime_env(
            {
                "DISPLAY_SIZEW": "3840",
                "DISPLAY_SIZEH": "2160",
                "DISPLAY_REFRESH": "60",
                "BDWIND_VIDEO_BITRATE": "16000",
            }
        )
        self.assertEqual(values["BDWIND_RESOLUTION"], "3840x2160")
        self.assertEqual(values["BDWIND_PHYSICAL_RESOLUTION"], "3840x2160")
        self.assertEqual(values["BDWIND_FRAMERATE"], "60")
        self.assertEqual(values["BDWIND_SMITHAY_VIDEO_BITRATE"], "16000")

    def test_explicit_smithay_bitrate_can_override_the_webrtc_default(self):
        values = load_runtime_env(
            {
                "BDWIND_VIDEO_BITRATE": "8000",
                "BDWIND_SMITHAY_VIDEO_BITRATE": "24000",
            }
        )
        self.assertEqual(values["BDWIND_VIDEO_BITRATE"], "8000")
        self.assertEqual(values["BDWIND_SMITHAY_VIDEO_BITRATE"], "24000")

    def test_smithay_worker_encoder_cannot_override_the_fixed_h264_path(self):
        values = load_runtime_env({"BDWIND_ENCODER": "nvav1enc"})
        self.assertEqual(values["BDWIND_ENCODER"], "nvh264enc")

    def test_smithay_bitrate_limit_matches_the_webrtc_bridge(self):
        source = SMITHAY_DISPLAY.read_text(encoding="utf-8")
        self.assertIn(
            'env_int("BDWIND_SMITHAY_VIDEO_BITRATE", 12000, 100, 50000)',
            source,
        )
        self.assertIn("max(100, min(50000, int(bitrate)))", source)


if __name__ == "__main__":
    unittest.main()
