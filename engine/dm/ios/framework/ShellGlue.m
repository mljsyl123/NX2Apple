// Route C shell (LNPANDY/NX2Apple#451): compiled into each game's DmGame<title ID>.framework (project-framework.yml DmShellGame)
// alongside dm/host, front_ios.m and Gen/embed.S. ShellMain.m sets the environment, dlopens the chosen game's framework and calls
// dm_glue_start_game and dm_glue_present_game through dlsym.
// This file also provides the symbols front_ios.m takes from main.m and Launcher.swift in the one-game app, so the framework
// compiles front_ios.m, DmGamepad.m and GameMenu.swift unchanged.
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "front.h"
#include "../Shell/ShellGlue.h"

int dm_main(int argc, char **argv);   // dm/host/main.c compiled in with -Dmain=dm_main
UIViewController *front_ios_root(void);
void front_ios_focus_event(int ev);

__attribute__((used, visibility("default"))) const int dm_glue_version = DM_GLUE_VERSION;

static char **g_argv; static int g_argc; static int g_boot_ok;

__attribute__((used, visibility("default")))
const char *dm_glue_start_game(const char *const *argv, int argc, const void *game_image) {
    if (argc < 2 || !game_image) return "The game's start arguments are incomplete.";
    front_hud_env();   // before the early loading below can make a device (main.m's order)
    dm_set_game_image_header(game_image);
    g_argc = argc; g_argv = calloc((size_t)argc + 1, sizeof(char *));
    for (int i = 0; i < argc; i++) g_argv[i] = strdup(argv[i]);
    dm_host_preload_start(g_argc, g_argv);   // module tables, relocation and take-over in the background while the game view comes up
    g_boot_ok = 1;
    return NULL;
}

__attribute__((used, visibility("default")))
void dm_glue_present_game(void *win) {
    UIWindow *window = (__bridge UIWindow *)win;
    if (!window) { fprintf(stderr, "[RED] shell: no window for the game view\n"); return; }
    UIViewController *game = front_ios_root();   // DmRootVC: landscape, its viewDidAppear starts the game (no settings screen: dm_show_launcher)
    window.rootViewController = game;
    [game setNeedsUpdateOfSupportedInterfaceOrientations];
    [window.windowScene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape]
                                                errorHandler:^(NSError *e) { fprintf(stderr, "shell: landscape request: %s\n", e.localizedDescription.UTF8String); }];
}

__attribute__((used, visibility("default")))
void dm_glue_focus_event(int ev) {
    front_ios_focus_event(ev);
}

// ---- what front_ios.m takes from main.m and Launcher.swift ----
static void *boot_thread(void *p) {
    (void)p;
    static char alt[65536]; stack_t ss = {.ss_sp = alt, .ss_size = sizeof alt}; sigaltstack(&ss, 0);   // crash printing must work on the host thread too
    int rc = dm_main(g_argc, g_argv);
    fprintf(stderr, "boot: dm_main returned %d\n", rc);
    return NULL;
}
void front_ios_boot(void) {   // front_ios.m, once the game view exists
    static int once; if (once++ || !g_boot_ok) return;
    void front_ios_audio_session(void); front_ios_audio_session();
    pthread_attr_t a; pthread_attr_init(&a); pthread_attr_setstacksize(&a, 64u << 20);
    pthread_t t; pthread_create(&t, &a, boot_thread, NULL); pthread_detach(t);
}
int front_ios_boot_ok(void) { return g_boot_ok; }
const char *front_ios_boot_message(void) { return NULL; }
const char *front_ios_device_check(void) { return NULL; }   // main.m checks the GPU for the games (no BC textures, seedds#704) when Play is pressed, the shell does its own device handling: NULL = supported
// The shell found the data before Play (DataLocator, EngineLaunchPlan): DM_ROMFS is set and the game view only checks it is still there
int dm_locate_game_data(void) {
    const char *r = getenv("DM_ROMFS"); struct stat st;
    if (r && !stat(r, &st)) return 1;
    fprintf(stderr, "[RED] shell: the game data at %s is gone\n", r ?: "(not set)");
    return 0;
}
// The shell showed its own settings before Play: the game view starts the game at once
bool dm_show_launcher(void *view_controller, void (*done)(void)) { (void)view_controller; (void)done; return false; }
