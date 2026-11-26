import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release


class HostedReleaseTest(unittest.TestCase):
    def build(self, directory, *, fail=False):
        commit = "a" * 40
        branch = "ci/ios-release/test"
        workflow = ".github/workflows/ios-release.yml"
        matched = dict(id=42, head_sha=commit, head_branch=branch, path=workflow,
                       html_url="https://example.test/run/42")
        runs = [dict(matched, id=1, head_sha="b" * 40),
                dict(matched, id=2, head_branch="another-run"),
                dict(matched, id=3, path="another.yml"), matched]
        calls = []

        def run(*args, **kwargs):
            calls.append(args)
            if args[:3] == ("gh", "run", "watch") and fail:
                raise subprocess.CalledProcessError(1, args)
            if args[:3] == ("gh", "run", "download"):
                folder = args[args.index("--dir") + 1]
                folder.mkdir()
                (folder / "app.ipa").write_bytes(b"from this run")

        ipa = directory / "app.ipa"
        with patch.object(release.uuid, "uuid4") as nonce, patch.object(release, "run", run), \
                patch.object(release, "output", return_value=json.dumps({"workflow_runs": runs})), \
                patch.object(release.subprocess, "run") as cleanup:
            nonce.return_value.hex = "test"
            cleanup.return_value.returncode = 0
            if fail:
                with self.assertRaises(subprocess.CalledProcessError):
                    release.actions_ios(commit, ipa)
            else:
                release.actions_ios(commit, ipa)
            self.assertIn(f"--force-with-lease=refs/heads/{branch}:{commit}", cleanup.call_args.args[0])
        return ipa, calls

    def test_selects_exact_run_and_downloads_its_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa, calls = self.build(Path(tmp))
            self.assertEqual(ipa.read_bytes(), b"from this run")
            watch, download = calls[-2:]
            self.assertEqual(watch[:4], ("gh", "run", "watch", "42"))
            self.assertIn("--exit-status", watch)
            self.assertEqual(download[:4], ("gh", "run", "download", "42"))
            self.assertIn("ios-" + "a" * 40, download)

    def test_failed_workflow_stops_before_download(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa, calls = self.build(Path(tmp), fail=True)
            self.assertFalse(ipa.exists())
            self.assertFalse(any("download" in args for args in calls))

    def test_draft_is_only_published_with_both_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            assets = [Path(tmp, "app.apk"), Path(tmp, "app.ipa")]
            for asset in assets:
                asset.write_bytes(b"test")
            uploaded = [dict(name=p.name, state="uploaded", size=4) for p in assets]
            for count in (1, 2):
                with self.subTest(count=count), patch.object(release, "run") as run, \
                        patch.object(release.subprocess, "run") as view, \
                        patch.object(release, "output", return_value=json.dumps(
                            {"isDraft": True, "assets": uploaded[:count]})):
                    view.return_value.returncode = 1
                    if count == 1:
                        with self.assertRaises(ValueError):
                            release.publish("v1.0.0", "a" * 40, assets)
                    else:
                        release.publish("v1.0.0", "a" * 40, assets)
                    create = next(c.args for c in run.call_args_list if "create" in c.args)
                    self.assertTrue(all(asset in create for asset in assets))
                    self.assertEqual(any("--draft=false" in c.args for c in run.call_args_list), count == 2)


if __name__ == "__main__":
    unittest.main()
