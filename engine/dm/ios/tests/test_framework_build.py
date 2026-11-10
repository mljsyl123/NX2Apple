"""Route C M1 (docs/launcher-c-plan.md): the opt-in framework build's packaging and signing, off a device.

Four parts, each on synthetic inputs, no game files or Xcode:
  - gen_manifest.py writes the schema's keys, and refuses values the schema cannot carry;
  - build_ipa.sh's --prepare-xcode block copies project-framework.yml in as the project when DM_FRAMEWORK=1, and
    project.yml when it is not (the default template is never edited);
  - the framework is signed before the app's executable, the framework's signature carries no entitlements, the app's
    keeps the Increased Memory Limit request, and the packed IPA has the framework where the app dlopens it. A default
    pack (no DM_FRAMEWORK) still has no Frameworks/ entry at all;
  - DM_FRAMEWORK_ONLY puts the game's shader libraries into the framework in the form they have: an NVN game's one file
    b-<chain>.img (dm/tools/shader_lib.py) as msl/b-<chain>.img, a folder as msl/<folder>, and a rebuild leaves only that one.
Only the signing and packing steps run (a stand-in app and framework, no Xcode); codesign is required for the third part.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/games'))
import game

GAME = '010015100B514000'
SCRIPT = (REPO / 'dm/ios/tools/build_ipa.sh').read_text()
# The three steps, each self-contained: the framework's signature, the app executable's entitlements, the pack.
FRAMEWORK_SIGNING = SCRIPT[SCRIPT.index('# Route C: the framework is signed first'):SCRIPT.index('# The entitlements of an unsigned IPA')]
SIGNING = SCRIPT[SCRIPT.index('# The entitlements of an unsigned IPA'):SCRIPT.index('\nP=Payload/DmIOS.app\n')]
PACKING = SCRIPT[SCRIPT.index('\nP=Payload/DmIOS.app\n'):]
PREPARE = SCRIPT[SCRIPT.index('if [ "$PREPARE_XCODE" = YES ]; then'):SCRIPT.index('\nelse DM_SCHEME_NAME=DmIOS; fi')] + '\nfi\n'
# DM_FRAMEWORK_ONLY's block, after the helper it finds the shader libraries with
FRAMEWORK_ONLY = (next(line for line in SCRIPT.splitlines() if line.startswith('lib_path() ')) + '\n' +
                  SCRIPT[SCRIPT.index('# DM_FRAMEWORK_ONLY: the framework target alone'):SCRIPT.index('\nt "xcodebuild (Release, unsigned, iPhone + iPad)"')] + '\n')
PREAMBLE = 'set -u\nt() { :; }; die() { echo "$*" >&2; exit 1; }\ngp() { python3 "$PROFILE_TOOL" "$GAME" "$1"; }\n'
CAN_SIGN = sys.platform == 'darwin' and shutil.which('codesign') and shutil.which('cc')


def run_step(script, root, **extra):
    env = {k: v for k, v in os.environ.items() if not k.startswith('DM_') and k not in ('IOS_PULL', 'AOC', 'PSO', 'FRAMEWORK')}
    env.update(GAME=GAME, DM=str(root / 'dm'), PROFILE_TOOL=str(REPO / 'dm/games/game.py'), **extra)
    return subprocess.run(['/bin/bash', '-c', PREAMBLE + script], cwd=root, env=env, capture_output=True, text=True)


class ManifestTests(unittest.TestCase):
    def manifest(self, *extra, nro=True):
        """gen_manifest.py's output for the fixture's profile; a two-row nro.tsv (one loadable, one refused)."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'nro.tsv').write_text('# name\tpath\nnrotest\tfixture.nro\nrefused\tonline.nro\n')
            out = root / 'game.manifest.json'
            args = [sys.executable, str(REPO / 'dm/ios/tools/gen_manifest.py'), str(out), '--game', GAME, '--name', 'Fixture Game',
                    '--display-version', '1.2.1', '--package-version', 'v327680', '--modules', 'main sdk', '--chain', 'b-fixture',
                    '--romfs-marker', 'System/Resource/marker', '--romfs-identity', 'DMROMFSID1 title=x size=1 index=2', *extra]
            if nro: args += ['--nro-table', str(root / 'nro.tsv')]
            result = subprocess.run(args, capture_output=True, text=True)
            return result, (json.loads(out.read_text()) if out.exists() else None)

    def test_the_schema_keys_and_values(self):
        result, data = self.manifest()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(data), ['schema', 'title_id', 'name', 'display_version', 'package_version', 'modules', 'nro_count',
                                      'chain', 'loader', 'framework', 'framework_executable', 'image_marker', 'profile', 'shader_map',
                                      'launcher', 'romfs_marker', 'romfs_identity', 'min_os'])
        self.assertEqual(data['schema'], 1)
        self.assertEqual(data['title_id'], GAME)
        self.assertEqual(data['modules'], ['main', 'sdk'])
        self.assertEqual(data['nro_count'], 1, 'the refused row is not an NRO gen_embed.py packs')
        self.assertEqual(data['chain'], 'b-fixture')
        self.assertEqual(data['loader'], 'FR')
        self.assertEqual(data['framework'], 'DmGame.framework')
        self.assertEqual(data['framework_executable'], 'DmGame')
        self.assertEqual(data['image_marker'], 'dmgame_image_marker')
        self.assertEqual(data['profile'], 'profile.tsv')
        self.assertEqual(data['shader_map'], 'dm/shader_map.tsv')
        self.assertEqual(data['launcher'], 'dm/launcher.json')
        self.assertEqual(data['romfs_marker'], 'System/Resource/marker')
        self.assertEqual(data['romfs_identity'], 'DMROMFSID1 title=x size=1 index=2')
        self.assertEqual(data['min_os'], '26.0')

    def test_a_romfs_folder_has_no_identity_and_no_nro_table_counts_zero(self):
        result, data = self.manifest('--romfs-identity', '', nro=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(data['romfs_identity'], '')
        self.assertEqual(data['nro_count'], 0)

    def test_values_the_schema_cannot_carry_are_refused(self):
        cases = [('--game', '1234'), ('--modules', ''), ('--modules', 'main_sdk'), ('--chain', 'fixture'),
                 ('--romfs-identity', 'not-an-identity')]
        for flag, value in cases:
            with self.subTest(flag=flag, value=value):
                base = [sys.executable, str(REPO / 'dm/ios/tools/gen_manifest.py'), '/dev/null', '--game', GAME, '--name', 'x',
                        '--display-version', '1', '--package-version', 'v0', '--modules', 'main', '--chain', 'b-1',
                        '--romfs-marker', 'marker', '--romfs-identity', 'DMROMFSID1 title=x size=1 index=2']
                base[base.index(flag) + 1] = value
                self.assertNotEqual(subprocess.run(base, capture_output=True).returncode, 0)


class ProjectTemplateTests(unittest.TestCase):
    """build_ipa.sh --prepare-xcode copies the template the build asks for in as project.yml."""

    def prepare(self, framework):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = root / 'ios'
            for name in ('Sources', 'tools', 'framework'):
                (source / name).mkdir(parents=True)
            (source / 'project.yml').write_text('name: default\n')
            (source / 'project-framework.yml').write_text('name: framework\n')
            environment = dict(IOS_SOURCE=str(source), DM_XCODE_PROJECT_DIR=str(root / 'xcode'), W=str(root), GAME=GAME,
                               DM_DISPLAY_NAME='Fixture Game', FRAMEWORK=str(framework))
            result = subprocess.run(['/bin/bash', '-c', PREAMBLE + 'PREPARE_XCODE=YES\n' + PREPARE], env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            copied = (root / 'xcode/project.yml').read_text()
            linked = (root / 'xcode/framework').is_symlink()
            return copied, linked

    def test_framework_mode_selects_project_framework_yml(self):
        self.assertEqual(self.prepare(1), ('name: framework\n', True))

    def test_the_default_mode_still_selects_project_yml(self):
        self.assertEqual(self.prepare(0), ('name: default\n', False))


class FrameworkEnvironmentTests(unittest.TestCase):
    def test_build_environment_stays_with_its_framework(self):
        block = SCRIPT[SCRIPT.index('if [ "$FRAMEWORK" = 1 ]; then\n  rm -rf Gen/framework'):SCRIPT.index('# A prepared Xcode project is signed')]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Gen/dm/font').mkdir(parents=True)
            (root / 'patched').mkdir()
            (root / 'dm').symlink_to(REPO / 'dm', target_is_directory=True)
            (root / 'Gen/dm/env.txt').write_text('DM_PROF_TEX_BC_CPU=1\n')
            (root / 'Gen/dm/font/font.ttf').write_text('font')
            (root / 'Gen/dm/launcher.json').write_text('{}')
            (root / 'tools').symlink_to(REPO / 'dm/ios/tools', target_is_directory=True)
            result = run_step(block, root, FRAMEWORK='1', FRAMEWORK_ONLY='out', FW_NAME='DmGame' + GAME,
                              PATCHED=str(root / 'patched'), ROMFS=str(root / 'none'), PREPARE_XCODE='NO', DM_COPY_ROMFS='NO',
                              DM_DISPLAY_NAME='Fixture', DM_APP_VERSION='1.0', MODS='main', V='fixture', MARKER='marker', F='')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((root / 'Gen/framework/dm/env.txt').is_file(), 'the built framework must carry its environment')
            self.assertEqual((root / 'Gen/framework/dm/env.txt').read_text(), 'DM_PROF_TEX_BC_CPU=1\n')
            self.assertFalse((root / 'Gen/framework/dm/font').exists())


class FrameworkPackagingTests(unittest.TestCase):
    """The signing and pack steps on a stand-in app; no Xcode, no game files."""

    def stand_in(self, root, compiled):
        header = root / 'dm/host/gen' / GAME / 'game_profile.h'
        header.parent.mkdir(parents=True)
        header.write_text(game.header(game.Game(REPO / 'dm/games' / GAME)))
        for folder in ('DmIOS.app', 'shaders/b-fixture', 'romfs', 'aoc/0', 'pkg'): (root / folder).mkdir(parents=True)
        (root / 'shaders/b-fixture/fixture_b.metallib').write_text('lib')
        (root / 'romfs/marker').write_text('romfs')
        (root / 'aoc/0/file').write_text('aoc')
        (root / 'tools').symlink_to(REPO / 'dm/ios/tools', target_is_directory=True)
        (root / 'dm/tools').symlink_to(REPO / 'dm/tools', target_is_directory=True)
        if compiled:   # only the signing step needs a Mach-O executable
            (root / 'main.c').write_text('int main(void) { return 0; }\n')
            subprocess.run(['cc', '-o', str(root / 'DmIOS.app/DmIOS'), str(root / 'main.c')], check=True)
        else:
            (root / 'DmIOS.app/DmIOS').write_text('app')
        (root / 'DmIOS.app/Info.plist').write_text(
            '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>' +
            '<key>CFBundleExecutable</key><string>DmIOS</string>' +
            '<key>CFBundleIdentifier</key><string>org.nxnative.fixture</string></dict></plist>\n')

    def framework(self, root):
        """What project-framework.yml embeds: the dylib, its Info.plist and the resources at the framework's root."""
        framework = root / 'DmIOS.app/Frameworks/DmGame.framework'
        (framework / 'dm').mkdir(parents=True)
        (root / 'marker.c').write_text('const char dmgame_image_marker[] = "DmGame";\n')
        subprocess.run(['cc', '-dynamiclib', '-install_name', '@rpath/DmGame.framework/DmGame',
                        '-o', str(framework / 'DmGame'), str(root / 'marker.c')], check=True)
        (framework / 'Info.plist').write_text(
            '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>' +
            '<key>CFBundleExecutable</key><string>DmGame</string>' +
            '<key>CFBundleIdentifier</key><string>org.nxnative.fixture.DmGame</string>' +
            '<key>CFBundlePackageType</key><string>FMWK</string>' +
            '<key>CFBundleVersion</key><string>1.0</string></dict></plist>\n')
        (framework / 'dm/shader_map.tsv').write_text('key\tfixture\n')
        (framework / 'profile.tsv').write_text('id\t' + GAME + '\n')
        (framework / 'game.manifest.json').write_text('{"schema": 1}\n')
        return framework

    def pack(self, framework):
        """Sign what the build signs and pack a stand-in app; the files outlive the call for the caller's checks."""
        root = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, root)
        self.stand_in(root, compiled=framework)
        signing = []
        if framework:
            self.framework(root)
            signing = [(FRAMEWORK_SIGNING, dict(FRAMEWORK='1')), (SIGNING, {})]   # the build's order: framework, then the app's executable
        for script, extra in signing:
            result = run_step(script, root, APP=str(root / 'DmIOS.app'), O=str(root / 'pkg'), **extra)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = run_step(PACKING, root, APP=str(root / 'DmIOS.app'), MSL_IOS=str(root / 'shaders'), MSLDIR='b-fixture',
                          ROMFS=str(root / 'romfs'), AOC=str(root / 'aoc'), OUT_IPA=str(root / 'out.ipa'), O=str(root / 'pkg'),
                          DM_APP_VERSION='1.2.1', PKG='v327680')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with zipfile.ZipFile(root / 'out.ipa') as archive:
            names = set(archive.namelist())
            archive.extractall(root / 'extracted')
        return names, root

    def test_the_default_build_has_no_frameworks(self):
        names, _ = self.pack(framework=False)
        self.assertFalse([n for n in names if '/Frameworks/' in n], 'the default project has no framework target')
        self.assertIn('Payload/DmIOS.app/DmIOS', names)

    @unittest.skipUnless(CAN_SIGN, 'needs macOS codesign and a C compiler')
    def test_the_framework_is_packed_and_signed_without_entitlements(self):
        names, root = self.pack(framework=True)
        base = 'Payload/DmIOS.app/Frameworks/DmGame.framework'
        for name in ('DmGame', 'Info.plist', 'dm/shader_map.tsv', 'profile.tsv', 'game.manifest.json'):
            self.assertIn(f'{base}/{name}', names)
        extracted = root / 'extracted/Payload/DmIOS.app'

        def entitlements(path):
            return subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)], capture_output=True, text=True).stdout

        self.assertEqual(entitlements(extracted / 'Frameworks/DmGame.framework/DmGame'), '',
                         'a dylib cannot carry entitlements; the request belongs to the app')
        self.assertIn('com.apple.developer.kernel.increased-memory-limit', entitlements(extracted / 'DmIOS'),
                      'the app executable keeps the Increased Memory Limit request')
        verified = subprocess.run(['codesign', '-vvv', '--verify', '--strict', str(extracted / 'Frameworks/DmGame.framework')],
                                  capture_output=True, text=True)
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)


@unittest.skipUnless(sys.platform == 'darwin', 'build_ipa.sh copies an image with macOS cp -c (clonefile)')
class FrameworkOnlyShaderLibrariesTests(unittest.TestCase):
    """DM_FRAMEWORK_ONLY's copy of the shader libraries into the game's framework, after a stand-in xcodebuild; no Xcode, no game files."""
    FW = 'DmGame' + GAME

    def setUp(self):
        self.root = root = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, root)
        (root / 'dm').mkdir()
        (root / 'dm/tools').symlink_to(REPO / 'dm/tools', target_is_directory=True)
        (root / 'bin').mkdir()
        (root / 'bin/xcodebuild').write_text('#!/bin/sh\nexit 0\n')
        (root / 'bin/xcodebuild').chmod(0o755)
        built = root / 'dd/Build/Products/Release-iphoneos' / f'{self.FW}.framework'   # what the framework target builds
        built.mkdir(parents=True)
        (built / self.FW).write_text('dylib')
        (built / 'game.manifest.json').write_text(json.dumps({'framework_executable': self.FW}))
        self.out = root / 'out' / f'{self.FW}.framework'

    def library(self, packed, content='shader'):
        """The NSP script's shader libraries: the folder dmsh_build.py writes, or the one file shader_lib.py packs it into."""
        folder, image = self.root / 'shaders/b-fixture', self.root / 'shaders/b-fixture.img'
        shutil.rmtree(folder, ignore_errors=True)
        image.unlink(missing_ok=True)
        folder.mkdir(parents=True)
        (folder / 'fixture_b.metallib').write_text(content)
        if packed:
            result = subprocess.run([sys.executable, str(REPO / 'dm/tools/shader_lib.py'), 'pack', str(folder)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(folder.exists())
            self.assertTrue(image.is_file())
        return image if packed else folder

    def build(self):
        root = self.root
        result = run_step(FRAMEWORK_ONLY, root, FRAMEWORK_ONLY=str(root / 'out'), FW_NAME=self.FW, O=str(root / 'pkg'), DD=str(root / 'dd'),
                          DM_BUNDLE_ID='org.nxnative.fixture', MSL_IOS=str(root / 'shaders'), MSLDIR='b-fixture', PSO='',
                          ICON=str(root / 'no-icon.jpg'), PATH=f'{root / "bin"}:{os.environ["PATH"]}')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.out / self.FW).is_file())

    def shaders(self):
        return sorted(p.name for p in (self.out / 'msl').iterdir())

    def test_a_packed_library_goes_in_as_its_one_file(self):
        image = self.library(packed=True)
        self.build()
        self.assertEqual(self.shaders(), ['b-fixture.img'])
        self.assertEqual((self.out / 'msl/b-fixture.img').read_bytes(), image.read_bytes())

    def test_a_library_folder_goes_in_as_a_folder(self):
        self.library(packed=False)
        self.build()
        self.assertEqual(self.shaders(), ['b-fixture'])
        self.assertEqual((self.out / 'msl/b-fixture/fixture_b.metallib').read_text(), 'shader')

    def test_a_rebuild_leaves_only_the_current_library(self):
        (self.out / 'msl/b-fixture').mkdir(parents=True)   # an earlier build's folder, and another chain's library
        (self.out / 'msl/b-fixture/stale_b.metallib').write_text('stale')
        (self.out / 'msl/b-otherchain.img').write_text('other chain')
        self.library(packed=True)
        self.build()
        self.assertEqual(self.shaders(), ['b-fixture.img'])
        image = self.library(packed=True, content='a newer shader')
        self.build()
        self.assertEqual((self.out / 'msl/b-fixture.img').read_bytes(), image.read_bytes())
        self.library(packed=False)
        self.build()
        self.assertEqual(self.shaders(), ['b-fixture'])


if __name__ == '__main__':
    unittest.main()
