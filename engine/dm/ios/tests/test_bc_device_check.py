"""Exercise the one-game iOS device check with synthetic GPU capabilities and a runtime profile."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == 'darwin', 'needs Foundation and Metal')
class BCDeviceCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        main = (REPO / 'dm/ios/Sources/main.m').read_text()
        check = main[main.index('const char *front_ios_device_check(void)'):main.index('static void romfs_identity_report')]
        source = root / 'check.m'
        source.write_text('''#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
#define DM_GAME_TEX_BC_CPU 0
static int supports_bc, cpu_decode;
typedef struct { int tex_bc_cpu; } dm_game_profile;
static const dm_game_profile *dm_profile(void) { static dm_game_profile p; p.tex_bc_cpu = cpu_decode; return &p; }
@interface FixtureGPU : NSObject
@property(readonly) BOOL supportsBCTextureCompression;
@property(readonly) NSString *name;
@end
@implementation FixtureGPU
- (BOOL)supportsBCTextureCompression { return supports_bc; }
- (NSString *)name { return @"Fixture GPU"; }
@end
static id<MTLDevice> fixture_device(void) { return (id<MTLDevice>)[FixtureGPU new]; }
#define MTLCreateSystemDefaultDevice fixture_device
''' + check + '''
int main(int argc, char **argv) { @autoreleasepool {
    supports_bc = atoi(argv[1]); cpu_decode = atoi(argv[2]);
    return front_ios_device_check() ? 1 : 0;
} }
''')
        cls.executable = root / 'check'
        subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-framework', 'Metal', str(source), '-o', str(cls.executable)], check=True)

    def test_effective_runtime_profile_allows_cpu_decoding_on_older_gpu(self):
        for supports_bc, cpu_decode, expected in [(0, 0, 1), (0, 1, 0), (1, 0, 0)]:
            with self.subTest(supports_bc=supports_bc, cpu_decode=cpu_decode):
                result = subprocess.run([str(self.executable), str(supports_bc), str(cpu_decode)], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)


if __name__ == '__main__':
    unittest.main()
