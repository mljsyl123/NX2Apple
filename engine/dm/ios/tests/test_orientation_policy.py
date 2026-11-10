"""Keep the production and harness phone/iPad orientation contracts aligned."""
import re
import unittest
from pathlib import Path

IOS = Path(__file__).resolve().parents[1]


class OrientationPolicyTests(unittest.TestCase):
    def test_phone_landscape_and_ipad_resizing(self):
        landscape = {"UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}
        all_orientations = landscape | {"UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown"}
        for project in (IOS / "project.yml", IOS / "tests/duo/project.yml", IOS / "project-shell.yml"):
            source = project.read_text()
            phone = landscape | {"UIInterfaceOrientationPortrait"} if project.name == "project-shell.yml" else landscape
            for key, expected in (("UISupportedInterfaceOrientations", phone),
                                  ("UISupportedInterfaceOrientations~ipad", all_orientations)):
                with self.subTest(project=str(project.relative_to(IOS)), key=key):
                    match = re.search(r"^        " + re.escape(key) + r":[^\n]*\n((?:          - .*\n)+)", source, re.MULTILINE)
                    assert match is not None, f"Missing orientation array: {key}"
                    self.assertEqual(set(re.findall(r"- (\w+)", match[1])), expected)
            self.assertNotIn("UIRequiresFullScreen:", source)


if __name__ == "__main__":
    unittest.main()
