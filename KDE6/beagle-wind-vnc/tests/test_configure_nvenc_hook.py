import os
import pathlib
import subprocess
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "configure-nvenc-hook.sh"


class ConfigureNvencHookTest(unittest.TestCase):
    def run_hook(self, **overrides):
        env = os.environ.copy()
        for name in (
            "BDWIND_NVENC_HOOK",
            "BDWIND_NVENC_HOOK_PATH",
            "LD_PRELOAD",
            "NVENC_HOOK_PROFILE",
            "NVENC_HOOK_REWRITE_OPEN",
            "NVENC_HOOK_REWRITE_RM",
            "NVENC_HOOK_SPOOF_CUDA",
        ):
            env.pop(name, None)
        env.update(overrides)
        command = (
            f'source "{SCRIPT}"; '
            "bdwind_configure_nvenc_hook; result=$?; "
            "printf '%s\\n' \"$result\" \"${LD_PRELOAD:-}\" "
            "\"${NVENC_HOOK_PROFILE:-}\" \"${NVENC_HOOK_REWRITE_OPEN:-}\" "
            "\"${NVENC_HOOK_REWRITE_RM:-}\" \"${NVENC_HOOK_SPOOF_CUDA:-}\""
        )
        return subprocess.run(
            ["bash", "-c", command],
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_auto_enables_bundled_hook_defaults(self):
        result = self.run_hook(BDWIND_NVENC_HOOK_PATH=str(SCRIPT))

        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            result.stdout.splitlines(),
            ["0", str(SCRIPT), "wayland-nvenc", "1", "1", "1"],
        )

    def test_off_leaves_preload_empty(self):
        result = self.run_hook(
            BDWIND_NVENC_HOOK="off", BDWIND_NVENC_HOOK_PATH=str(SCRIPT)
        )

        self.assertEqual(result.stdout.splitlines(), ["0", "", "", "", "", ""])

    def test_required_missing_hook_fails(self):
        result = self.run_hook(
            BDWIND_NVENC_HOOK="required",
            BDWIND_NVENC_HOOK_PATH="/definitely/missing/nvenc-hook.so",
        )

        self.assertEqual(result.stdout.splitlines()[0], "69")
        self.assertIn("required NVENC hook is missing", result.stderr)

    def test_explicit_low_level_overrides_are_preserved(self):
        result = self.run_hook(
            BDWIND_NVENC_HOOK_PATH=str(SCRIPT),
            NVENC_HOOK_PROFILE="custom-profile",
            NVENC_HOOK_REWRITE_OPEN="0",
            NVENC_HOOK_REWRITE_RM="0",
            NVENC_HOOK_SPOOF_CUDA="0",
        )

        self.assertEqual(
            result.stdout.splitlines(),
            ["0", str(SCRIPT), "custom-profile", "0", "0", "0"],
        )


if __name__ == "__main__":
    unittest.main()
