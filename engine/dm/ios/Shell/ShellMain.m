// Route C shell (docs/launcher-c-plan.md M2, LNPANDY/NX2Apple#451): the app that hosts several games' frameworks. It starts on the
// library (frontend-ios's ShellHost views, ShellApp.swift) instead of booting a game at launch as dm/ios/Sources/main.m does, and
// when the player presses Play, dm_shell_start_game() sets the log and the environment (EngineLaunchPlan in ShellHost computes it),
// dlopens the chosen game's DmGame<title ID>.framework (which links its own dm/host, front_ios.m and shaders), and calls its
// dm_glue_start_game() entry point (ShellGlue.h, framework/ShellGlue.m). dm_shell_present_game() then hands the window to the
// framework's dm_glue_present_game(), which shows front_ios.m's game view and starts dm_main on the big-stack thread.
// One game per process: dm_profile() and dm_host_preload_start() run once, so returning to the library is a relaunch of the app.
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "ShellEngine.h"
#include "ShellGlue.h"
#import "DmShell-Swift.h"

static dm_glue_present_fn g_present;
static dm_glue_focus_fn g_focus;
static int g_boot_ok;

static NSString *documents(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0]; }

// One log file per run, the previous one kept beside it (<name>.prev.txt): the shell's own lines go to Documents/shell-log.txt until a
// game starts, the game's (the host's stderr) to Documents/log.txt, the file the per-game app writes and the issue forms ask for.
static void log_to(NSString *log) {
    NSString *prev = [[log stringByDeletingPathExtension] stringByAppendingString:@".prev.txt"];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:prev error:nil]; [fm moveItemAtPath:log toPath:prev error:nil];
    fflush(stderr);
    if (freopen(log.fileSystemRepresentation, "w", stderr)) setvbuf(stderr, NULL, _IOLBF, 0);
    NSString *fork_patches = [NSBundle.mainBundle objectForInfoDictionaryKey:@"DMForkPatches"];
    fprintf(stderr, "fork patches: %s\n", [fork_patches isKindOfClass:NSString.class] && fork_patches.length ? fork_patches.UTF8String : "none");
}

const char *dm_shell_start_game(const char *const *keys, const char *const *values, int n, const char *const *argv, int argc,
                                const char *executable, const char *marker, const char *log_path, const char *cwd) {
    static char err[512];
    static int started;
    if (started++) return "A game was already started in this session. Close the app and open it again.";
    if (argc < 2) return "The game's start arguments are incomplete.";
    log_to(@(log_path));
    fprintf(stderr, "shell: starting %s (%s)\n", argv[1], executable);
    for (int i = 0; i < n; i++) {
        setenv(keys[i], values[i], 1);
        fprintf(stderr, "boot: %s=%s\n", keys[i], values[i]);   // every one: a report then shows which of the game's settings reached the engine
    }
    if (cwd && *cwd) chdir(cwd);
    // dlopen + dlsym + dladdr verify the framework's image and find its own host's entry points (ShellGlue.h, framework/ShellGlue.m),
    // after the environment is set and before the framework's host starts loading.
    void *h = dlopen(executable, RTLD_LAZY | RTLD_LOCAL);
    if (!h) {
        snprintf(err, sizeof err, "The game's code could not be loaded: %s", dlerror() ?: "no reason given");
        fprintf(stderr, "[RED] boot: dlopen %s failed: %s\n", executable, err);
        return err;
    }
    dlerror();
    void *sym = dlsym(h, marker);
    Dl_info info;
    if (!sym || !dladdr(sym, &info) || !info.dli_fbase) {
        snprintf(err, sizeof err, "The game's code is damaged (no %s symbol). Install the game again.", marker);
        fprintf(stderr, "[RED] boot: %s: %s\n", executable, err);
        return err;
    }
    const int *ver = dlsym(h, "dm_glue_version");
    dm_glue_start_fn start = (dm_glue_start_fn)dlsym(h, "dm_glue_start_game");
    dm_glue_present_fn present = (dm_glue_present_fn)dlsym(h, "dm_glue_present_game");
    dm_glue_focus_fn focus = (dm_glue_focus_fn)dlsym(h, "dm_glue_focus_event");
    if (!ver || *ver != DM_GLUE_VERSION || !start || !present || !focus) {
        snprintf(err, sizeof err, "This game's framework was built without its host (glue version %d, expected %d). Rebuild the game in the launcher.",
                 ver ? *ver : 0, DM_GLUE_VERSION);
        fprintf(stderr, "[RED] boot: %s: %s\n", executable, err);
        return err;
    }
    fprintf(stderr, "boot: game framework %s (handle %p, image base %p, glue v%d)\n", executable, h, info.dli_fbase, *ver);
    const char *why = start(argv, argc, info.dli_fbase);
    if (why) {
        snprintf(err, sizeof err, "%s", why);
        fprintf(stderr, "[RED] boot: %s: %s\n", executable, err);
        return err;
    }
    g_present = present;
    g_focus = focus;
    g_boot_ok = 1;
    return NULL;
}

void dm_shell_present_game(void) {
    UIWindow *window = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow || !window) window = w;
    if (!window || !g_present) { fprintf(stderr, "[RED] shell: no window for the game view\n"); return; }
    g_present((__bridge void *)window);
}

@interface App : UIResponder <UIApplicationDelegate>
@end
// Browsing may be portrait; phone gameplay stays landscape. UIKit manages unrestricted rotation on the Duo inner display.
static UIInterfaceOrientationMask shell_orientations(UITraitCollection *traits) {
    if (traits.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return UIInterfaceOrientationMaskAll;
    return g_boot_ok ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskAllButUpsideDown;
}
@implementation App
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return shell_orientations(window.traitCollection);   // iOS 26
}
- (UISceneConfiguration *)application:(UIApplication *)a configurationForConnectingSceneSession:(UISceneSession *)s options:(UISceneConnectionOptions *)o {
    return [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:s.role];
}
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
@implementation SceneDelegate
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindowScene:(UIWindowScene *)windowScene {
    return shell_orientations(windowScene.traitCollection);   // iOS 27 and later
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)o {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [ShellLibrary makeController];
    [self.window makeKeyAndVisible];
}
// Forwarded to the running game framework's front_ios.m once a game has started
- (void)sceneWillResignActive:(UIScene *)s { (void)s; if (g_focus) g_focus(0); }
- (void)sceneDidEnterBackground:(UIScene *)s { (void)s; if (g_focus) g_focus(1); }
- (void)sceneWillEnterForeground:(UIScene *)s { (void)s; if (g_focus) g_focus(2); }
- (void)sceneDidBecomeActive:(UIScene *)s { (void)s; if (g_focus) g_focus(3); }
@end

// The performance HUD (the per-game setting DM_METAL_HUD) needs MTL_HUD_ENABLED in the environment before Metal starts in this
// process, and the library's views start it long before Play: set at Play it comes too late and the HUD stays off. So the shell turns
// Metal's HUD on for every start, here before UIApplicationMain, and the game's own setting decides at Play: front_ios.m sets the game
// layer's developerHUDProperties mode to default, or with DM_HUD_PER_LAYER to disabled. A change of the setting in the library applies
// at the next Play, as every other setting does (verified on an iPhone 2026-10-30: on and off in one start each, no HUD over the
// library). MTL_HUD_HIDE_METALFX_METRICS stays unset, so the HUD shows MetalFX's rows (input and output size) while the Upscaling
// setting MetalFX scales the picture.
static void metal_hud_per_layer(void) {
    if (getenv("MTL_HUD_ENABLED")) { fprintf(stderr, "shell: MTL_HUD_ENABLED given at launch, the HUD follows it\n"); return; }   // Xcode, devicectl: it wins
    setenv("MTL_HUD_ENABLED", "1", 1);
    setenv("DM_HUD_PER_LAYER", "1", 1);
    fprintf(stderr, "shell: Metal's HUD is ready, each game's Performance HUD setting turns it on at Play\n");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        log_to([documents() stringByAppendingPathComponent:@"shell-log.txt"]);
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        fprintf(stderr, "shell: %s %s, commit %s, shader chain %s, iOS %s\n", [info[@"CFBundleIdentifier"] UTF8String], [info[@"CFBundleShortVersionString"] UTF8String] ?: "?",
                [info[@"DMCommit"] UTF8String] ?: "not recorded", [info[@"DMChain"] UTF8String] ?: "?", UIDevice.currentDevice.systemVersion.UTF8String);
        // Free space where the game data goes: the Mac launcher reads this line before it copies a game's data (many GB)
        NSNumber *avail = [[NSURL fileURLWithPath:documents()] resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey] error:nil][NSURLVolumeAvailableCapacityForImportantUsageKey];
        fprintf(stderr, "shell: free space %lld bytes\n", avail ? avail.longLongValue : -1LL);
        for (NSString *fw in [NSFileManager.defaultManager contentsOfDirectoryAtPath:NSBundle.mainBundle.privateFrameworksPath error:nil])
            fprintf(stderr, "shell: framework %s\n", fw.UTF8String);
        metal_hud_per_layer();
    }
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(App.class)); }
}
