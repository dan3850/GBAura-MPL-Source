# SPDX-License-Identifier: MPL-2.0
#
# GBAura mGBA Source Code Form modifications
#
# This module contains the source-transforming changes applied by GBAura to the
# MPL-2.0-licensed mGBA snapshot pinned by the parent CMakeLists.txt. It is kept
# separate from the proprietary frontend/build orchestration so this file can be
# distributed together with the corresponding mGBA Source Code Form as part of
# GBAura's MPL-2.0 compliance package.
#
# Upstream snapshot:
#   https://github.com/mgba-emu/mgba
#   c3c8e5e813f245028de118a56734e1dc0f35ce2a
#
# Expected caller variable:
#   mgba_v028_SOURCE_DIR - isolated writable copy of the pinned mGBA source tree.
#
# Keep this module and the resulting modified MPL-covered files available under
# MPL-2.0 when distributing an executable containing the covered mGBA code.

# Current upstream script/context.c uses pthread_once for active-context TLS.
# This native target deliberately keeps DISABLE_THREADING for the rest of the
# minimal core, so expose real pthread TLS only inside this translation unit.
# Patch the isolated build copy only; the pinned pristine snapshot is untouched.
set(MGBA_SCRIPT_CONTEXT_FILE "${mgba_v028_SOURCE_DIR}/src/script/context.c")
file(READ "${MGBA_SCRIPT_CONTEXT_FILE}" MGBA_SCRIPT_CONTEXT_TEXT)
set(_script_tls_marker "MGBA_ANDROID_SCRIPT_CONTEXT_PTHREAD_TLS")
string(FIND "${MGBA_SCRIPT_CONTEXT_TEXT}" "${_script_tls_marker}" _script_tls_patched)
if(_script_tls_patched EQUAL -1)
    set(_script_tls_old "#include <mgba-util/threading.h>")
    set(_script_tls_new "/* MGBA_ANDROID_SCRIPT_CONTEXT_PTHREAD_TLS */\n#if defined(DISABLE_THREADING) && defined(USE_PTHREADS)\n#undef DISABLE_THREADING\n#include <mgba-util/threading.h>\n#define DISABLE_THREADING\n#else\n#include <mgba-util/threading.h>\n#endif")
    string(FIND "${MGBA_SCRIPT_CONTEXT_TEXT}" "${_script_tls_old}" _script_tls_anchor)
    if(_script_tls_anchor EQUAL -1)
        message(FATAL_ERROR "mGBA Android: script/context.c threading include anchor changed")
    endif()
    string(REPLACE "${_script_tls_old}" "${_script_tls_new}"
            MGBA_SCRIPT_CONTEXT_TEXT "${MGBA_SCRIPT_CONTEXT_TEXT}")
    file(WRITE "${MGBA_SCRIPT_CONTEXT_FILE}" "${MGBA_SCRIPT_CONTEXT_TEXT}")
endif()

# Upstream removed the experimental MP2K/XQ HLE mixer in commit 89866aff
# ("Remove broken XQ audio pending rewrite"). Detect the source capability
# instead of carrying the removed 0.10.5 implementation into a newer core.
set(MGBA_ANDROID_HAS_MP2K_XQ FALSE)
if(EXISTS "${mgba_v028_SOURCE_DIR}/src/gba/extra/audio-mixer.c")
    set(MGBA_ANDROID_HAS_MP2K_XQ TRUE)
    message(STATUS "mGBA Android: upstream MP2K/XQ mixer is available")
else()
    message(STATUS "mGBA Android: upstream MP2K/XQ mixer unavailable; using official emulated audio")
endif()

# mGBA 0.10.5 predates an official Android frontend. These two feature probes
# are not needed for our Android Libretro build and can fail with some NDK/CMake
# combinations. Patch only the fetched build copy, never the user's source tree.
set(MGBA_CMAKE_FILE "${mgba_v028_SOURCE_DIR}/CMakeLists.txt")
file(READ "${MGBA_CMAKE_FILE}" MGBA_CMAKE_TEXT)

string(FIND "${MGBA_CMAKE_TEXT}" "if(NOT ANDROID)\n\tfind_function(snprintf_l)" _snprintf_already_patched)
if(_snprintf_already_patched EQUAL -1)
    string(REPLACE
            "find_function(snprintf_l)"
            "if(NOT ANDROID)\n\tfind_function(snprintf_l)\nendif()"
            MGBA_CMAKE_TEXT
            "${MGBA_CMAKE_TEXT}")
endif()

string(FIND "${MGBA_CMAKE_TEXT}" "if(NOT ANDROID)\n\tfind_function(popcount32)" _popcount_already_patched)
if(_popcount_already_patched EQUAL -1)
    string(REPLACE
            "find_function(popcount32)"
            "if(NOT ANDROID)\n\tfind_function(popcount32)\nendif()"
            MGBA_CMAKE_TEXT
            "${MGBA_CMAKE_TEXT}")
endif()

file(WRITE "${MGBA_CMAKE_FILE}" "${MGBA_CMAKE_TEXT}")

# v0.62: DISABLE_DEPS normally disables the GDB stub together with optional
# third-party libraries. The stub itself uses mGBA's header-only socket layer
# and needs no external dependency on Android, so preserve it while leaving
# FFmpeg/PNG/SQLite/etc. disabled. This patch is narrow and version-pinned.
file(READ "${MGBA_CMAKE_FILE}" MGBA_CMAKE_TEXT)
set(_gdb_disable_old "if(DISABLE_DEPS)\n\tset(ENABLE_GDB_STUB OFF)")
set(_gdb_disable_new "if(DISABLE_DEPS)\n\tif(NOT ANDROID)\n\t\tset(ENABLE_GDB_STUB OFF)\n\tendif()")
string(FIND "${MGBA_CMAKE_TEXT}" "${_gdb_disable_new}" _gdb_guard_patched)
if(_gdb_guard_patched EQUAL -1)
    string(FIND "${MGBA_CMAKE_TEXT}" "${_gdb_disable_old}" _gdb_guard_anchor)
    if(_gdb_guard_anchor EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.62: DISABLE_DEPS GDB anchor changed")
    endif()
    string(REPLACE "${_gdb_disable_old}" "${_gdb_disable_new}" MGBA_CMAKE_TEXT "${MGBA_CMAKE_TEXT}")
    file(WRITE "${MGBA_CMAKE_FILE}" "${MGBA_CMAKE_TEXT}")
endif()

# v0.32 Android custom GB palette bridge. The desktop frontend can edit
# gb.pal[0..11] directly, while upstream Libretro only exposes named presets.
# Add a tiny Android-only extension to the fetched 0.10.5 Libretro source so
# our automatic fallback can consume the same 12 RGB values as native mCore.
set(MGBA_LIBRETRO_C "${mgba_v028_SOURCE_DIR}/src/platform/libretro/libretro.c")
file(READ "${MGBA_LIBRETRO_C}" MGBA_LIBRETRO_TEXT)
if(NOT MGBA_LIBRETRO_TEXT MATCHES "MGBA_ANDROID_CUSTOM_PALETTE_V032")
    set(_mgba_custom_palette_code [=[
	/* MGBA_ANDROID_CUSTOM_PALETTE_V032 */
	struct retro_variable customEnabled = { .key = "mgba_android_custom_palette", .value = 0 };
	if (environCallback(RETRO_ENVIRONMENT_GET_VARIABLE, &customEnabled) && customEnabled.value && strcmp(customEnabled.value, "ON") == 0) {
		for (int color = 0; color < 12; ++color) {
			char customKey[32];
			char configKey[24];
			snprintf(customKey, sizeof(customKey), "mgba_gb_pal_%d", color);
			struct retro_variable custom = { .key = customKey, .value = 0 };
			if (environCallback(RETRO_ENVIRONMENT_GET_VARIABLE, &custom) && custom.value) {
				snprintf(configKey, sizeof(configKey), "gb.pal[%d]", color);
				mCoreConfigSetUIntValue(&core->config, configKey, (uint32_t) strtoul(custom.value, NULL, 10) & 0xFFFFFFu);
			}
		}
		core->reloadConfigOption(core, "gb.pal", NULL);
		return;
	}
]=])
    string(REPLACE "static void _updateGbPal(void) {" "static void _updateGbPal(void) {${_mgba_custom_palette_code}" MGBA_LIBRETRO_TEXT "${MGBA_LIBRETRO_TEXT}")
    string(FIND "${MGBA_LIBRETRO_TEXT}" "MGBA_ANDROID_CUSTOM_PALETTE_V032" _custom_palette_marker)
    if(_custom_palette_marker EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.32: custom Libretro palette patch did not apply")
    endif()
    file(WRITE "${MGBA_LIBRETRO_C}" "${MGBA_LIBRETRO_TEXT}")
endif()

# v0.72.4.3.47 — optional legacy MP2K/XQ bridge.
# Current upstream removed the broken XQ implementation. Only patch Libretro
# when the pinned upstream source actually provides audio-mixer.c.
if(MGBA_ANDROID_HAS_MP2K_XQ)
# v0.72.4.3.47 — mirror the same upstream gba.audioHle setting into the
# automatic Libretro fallback. The fallback target uses MINIMAL_CORE=2, so the
# selective core.c guard below plus audio-mixer.c make MP2K/XQ available there
# too instead of silently losing the feature when the primary backend cannot load.
file(READ "${MGBA_LIBRETRO_C}" MGBA_LIBRETRO_TEXT)
string(FIND "${MGBA_LIBRETRO_TEXT}" "MGBA_ANDROID_MP2K_XQ_LIBRETRO_V0724347" _mp2k_libretro_patched)
if(_mp2k_libretro_patched EQUAL -1)
    set(_mp2k_libretro_anchor [=[#ifdef M_CORE_GBA
	var.key = "mgba_force_gbp";
	var.value = 0;
	if (environCallback(RETRO_ENVIRONMENT_GET_VARIABLE, &var) && var.value) {
		mCoreConfigSetDefaultIntValue(&core->config, "gba.forceGbp", strcmp(var.value, "ON") == 0);
	}
#endif]=])
    set(_mp2k_libretro_replacement [=[#ifdef M_CORE_GBA
	var.key = "mgba_force_gbp";
	var.value = 0;
	if (environCallback(RETRO_ENVIRONMENT_GET_VARIABLE, &var) && var.value) {
		mCoreConfigSetDefaultIntValue(&core->config, "gba.forceGbp", strcmp(var.value, "ON") == 0);
	}
	/* MGBA_ANDROID_MP2K_XQ_LIBRETRO_V0724347 */
	var.key = "mgba_android_audio_hle";
	var.value = 0;
	if (environCallback(RETRO_ENVIRONMENT_GET_VARIABLE, &var) && var.value) {
		mCoreConfigSetDefaultIntValue(&core->config, "gba.audioHle", strtol(var.value, NULL, 10) != 0);
	}
#endif]=])
    string(FIND "${MGBA_LIBRETRO_TEXT}" "${_mp2k_libretro_anchor}" _mp2k_libretro_anchor_pos)
    if(_mp2k_libretro_anchor_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.72.4.3.47: Libretro audio setting anchor changed")
    endif()
    string(REPLACE "${_mp2k_libretro_anchor}" "${_mp2k_libretro_replacement}" MGBA_LIBRETRO_TEXT "${MGBA_LIBRETRO_TEXT}")
    file(WRITE "${MGBA_LIBRETRO_C}" "${MGBA_LIBRETRO_TEXT}")
endif()

else()
    message(STATUS "mGBA Android: skipping Libretro audioHle bridge; upstream XQ is unavailable")
endif()

# v0.15 mGBA Core Internal Profiler.
# Instrument the pinned upstream GBA source at build time without maintaining a fork.
# Stage 0 = all GBA timing/event processing; stage 1 = software PPU renderer;
# stage 2 = HBlank/VBlank/display-start DMA. Event-other is derived by subtraction.
set(MGBA_GBA_C "${mgba_v028_SOURCE_DIR}/src/gba/gba.c")
set(MGBA_VIDEO_C "${mgba_v028_SOURCE_DIR}/src/gba/video.c")
file(READ "${MGBA_GBA_C}" MGBA_GBA_TEXT)
file(READ "${MGBA_VIDEO_C}" MGBA_VIDEO_TEXT)

set(MGBA_PROF_DECL "
/* MGBA_ANDROID_PROF_DECL_V028 */
#ifdef MGBA_ANDROID_INTERNAL_PROFILER
extern int mgba_android_internal_profiler_active;
extern void mgba_android_profiler_begin(int stage);
extern void mgba_android_profiler_end(int stage);
extern void mgba_android_profiler_event_count(const char* name);
extern int mgba_android_profiler_tick_sample_begin(void);
extern void mgba_android_profiler_tick_sample_end(int sampled);
extern void mgba_android_profiler_dma_event(int,uint32_t); extern void mgba_android_profiler_dma_service(int); extern void mgba_android_profiler_dma_update(int,int32_t);
/* v0.72.4.3.65: runtime mode 1 uses the outer GBAProcessEvents timer plus
 * integer-only structural counters. Mode 2 retains historical deep hooks for
 * manual development, but Diagnostic Lab never enables it. */
#define MGBA_AP_BEGIN(s) do { if (mgba_android_internal_profiler_active >= 2 || (mgba_android_internal_profiler_active == 1 && (s) == 0)) mgba_android_profiler_begin(s); } while (0)
#define MGBA_AP_END(s) do { if (mgba_android_internal_profiler_active >= 2 || (mgba_android_internal_profiler_active == 1 && (s) == 0)) mgba_android_profiler_end(s); } while (0)
#define MGBA_AP_EVENT_COUNT(n) do { if (mgba_android_internal_profiler_active >= 2) mgba_android_profiler_event_count(n); } while (0)
#define MGBA_AP_TICK_SAMPLE_BEGIN() (mgba_android_internal_profiler_active >= 2 ? mgba_android_profiler_tick_sample_begin() : 0)
#define MGBA_AP_TICK_SAMPLE_END(sampled) do { if (mgba_android_internal_profiler_active >= 2) mgba_android_profiler_tick_sample_end((sampled)); } while (0)
#else
#define MGBA_AP_BEGIN(s) ((void)0)
#define MGBA_AP_END(s) ((void)0)
#define MGBA_AP_EVENT_COUNT(n) ((void)0)
#define MGBA_AP_TICK_SAMPLE_BEGIN() 0
#define MGBA_AP_TICK_SAMPLE_END(sampled) ((void)(sampled))
#endif
")

# v0.26.2: declaration insertion is reconfigure-safe. A previous configure of the
# same Gradle project may reuse the populated FetchContent source directory.
string(FIND "${MGBA_GBA_TEXT}" "MGBA_ANDROID_PROF_DECL_V028" _gba_prof_decl_marker)
if(_gba_prof_decl_marker EQUAL -1)
    string(REPLACE "#include <mgba/internal/gba/gba.h>"
            "#include <mgba/internal/gba/gba.h>${MGBA_PROF_DECL}"
            MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
endif()

# v0.72.4.3.65 uses a separate marker so cached FetchContent sources from .64
# also receive the new integer-only macros instead of keeping the old declaration.
set(MGBA_EVENT_PRESSURE_DECL "
/* MGBA_ANDROID_EVENT_PRESSURE_DECL_V065 */
#ifdef MGBA_ANDROID_INTERNAL_PROFILER
extern int mgba_android_internal_profiler_active;
extern void mgba_android_profiler_pe_enter(void);
extern void mgba_android_profiler_pe_loop(void);
extern void mgba_android_profiler_pe_tick(int);
extern void mgba_android_profiler_pe_halt(void);
extern void mgba_android_profiler_pe_early_exit(void);
#define MGBA_AP_PE_ENTER() do { if (mgba_android_internal_profiler_active == 1) mgba_android_profiler_pe_enter(); } while (0)
#define MGBA_AP_PE_LOOP() do { if (mgba_android_internal_profiler_active == 1) mgba_android_profiler_pe_loop(); } while (0)
#define MGBA_AP_PE_TICK(b) do { if (mgba_android_internal_profiler_active == 1) mgba_android_profiler_pe_tick((b)); } while (0)
#define MGBA_AP_PE_HALT() do { if (mgba_android_internal_profiler_active == 1) mgba_android_profiler_pe_halt(); } while (0)
#define MGBA_AP_PE_EARLY() do { if (mgba_android_internal_profiler_active == 1) mgba_android_profiler_pe_early_exit(); } while (0)
#else
#define MGBA_AP_PE_ENTER() ((void)0)
#define MGBA_AP_PE_LOOP() ((void)0)
#define MGBA_AP_PE_TICK(b) ((void)(b))
#define MGBA_AP_PE_HALT() ((void)0)
#define MGBA_AP_PE_EARLY() ((void)0)
#endif
")
string(FIND "${MGBA_GBA_TEXT}" "MGBA_ANDROID_EVENT_PRESSURE_DECL_V065" _gba_pe_decl_marker)
if(_gba_pe_decl_marker EQUAL -1)
    string(REPLACE "#include <mgba/internal/gba/gba.h>"
            "#include <mgba/internal/gba/gba.h>${MGBA_EVENT_PRESSURE_DECL}"
            MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
endif()
# Avoid accumulating the stage-0 begin hook if CMake configures again.
string(REPLACE "\tMGBA_AP_BEGIN(0);\n" "" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "\tMGBA_AP_PE_ENTER();\n" "" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "static void GBAProcessEvents(struct ARMCore* cpu) {\n"
        "static void GBAProcessEvents(struct ARMCore* cpu) {\n\tMGBA_AP_BEGIN(0);\n\tMGBA_AP_PE_ENTER();\n"
        MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
# v0.72.4.3.65: structural counters are normalized before reinjection.
string(REPLACE "\t\tMGBA_AP_PE_LOOP();\n" "" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "\twhile (cpu->cycles >= nextEvent) {\n"
        "\twhile (cpu->cycles >= nextEvent) {\n\t\tMGBA_AP_PE_LOOP();\n"
        MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "\t\t\tMGBA_AP_PE_HALT();\n" "" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "\t\tif (cpu->halted) {\n"
        "\t\tif (cpu->halted) {\n\t\t\tMGBA_AP_PE_HALT();\n"
        MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "\t\t\tMGBA_AP_PE_EARLY();\n" "" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "\t\tif (gba->earlyExit) {\n"
        "\t\tif (gba->earlyExit) {\n\t\t\tMGBA_AP_PE_EARLY();\n"
        MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "\tgba->earlyExit = false;\n\tif (gba->cpuBlocked) {\n\t\tcpu->cycles = cpu->nextEvent;\n\t}\n}"
        "\tgba->earlyExit = false;\n\tif (gba->cpuBlocked) {\n\t\tcpu->cycles = cpu->nextEvent;\n\t}\n\tMGBA_AP_END(0);\n}"
        MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")

# v0.27 Libretro-safe adaptive randomized stratified sampling hook.
# The upstream 0.10.5 call site has THREE leading tabs. v0.26 searched for two,
# then accidentally validated the extern declaration instead of the injected call site.
# First normalize the sampled hook so repeated CMake configuration is safe.
set(MGBA_TICK_ORIGINAL "\t\t\tnextEvent = mTimingTick(&gba->timing, cycles < nextEvent ? nextEvent : cycles);")
set(MGBA_TICK_INSTRUMENTED_OLD "\t\t\tint _mgba_ap_tick_sample = MGBA_AP_TICK_SAMPLE_BEGIN();\n\t\t\tnextEvent = mTimingTick(&gba->timing, cycles < nextEvent ? nextEvent : cycles);\n\t\t\tif (_mgba_ap_tick_sample) MGBA_AP_TICK_SAMPLE_END(_mgba_ap_tick_sample);")
set(MGBA_TICK_INSTRUMENTED_V64 "\t\t\tint _mgba_ap_tick_sample = MGBA_AP_TICK_SAMPLE_BEGIN();\n\t\t\tnextEvent = mTimingTick(&gba->timing, cycles < nextEvent ? nextEvent : cycles);\n\t\t\tMGBA_AP_TICK_SAMPLE_END(_mgba_ap_tick_sample);")
set(MGBA_TICK_INSTRUMENTED "\t\t\tMGBA_AP_PE_TICK(gba->cpuBlocked ? 1 : 0);\n\t\t\tint _mgba_ap_tick_sample = MGBA_AP_TICK_SAMPLE_BEGIN();\n\t\t\tnextEvent = mTimingTick(&gba->timing, cycles < nextEvent ? nextEvent : cycles);\n\t\t\tMGBA_AP_TICK_SAMPLE_END(_mgba_ap_tick_sample);")
string(REPLACE "${MGBA_TICK_INSTRUMENTED_OLD}" "${MGBA_TICK_ORIGINAL}" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "${MGBA_TICK_INSTRUMENTED_V64}" "${MGBA_TICK_ORIGINAL}" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(REPLACE "${MGBA_TICK_INSTRUMENTED}" "${MGBA_TICK_ORIGINAL}" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
# v0.72.4.3.66.1 compile fix: a FetchContent source tree that was already
# configured by .65 can contain a standalone event-pressure tick hook in
# addition to the full sampled hook. Normalize the known full blocks first,
# then remove any stale standalone PE_TICK call before reinjecting exactly one.
# This keeps repeated Android Studio/CMake configure passes idempotent without
# weakening the final exactly-once validation below.
string(REGEX REPLACE "[ \t]*MGBA_AP_PE_TICK\\(gba->cpuBlocked[ \t]*\\?[ \t]*1[ \t]*:[ \t]*0\\);[ \t]*\n"
        "" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
# Also clean the one-line experimental spelling if a cached source ever contains it.
string(REPLACE "\t\tint _mgba_ap_sample = MGBA_AP_TICK_SAMPLE_BEGIN(); nextEvent = mTimingTick(&gba->timing, cycles < nextEvent ? nextEvent : cycles); MGBA_AP_TICK_SAMPLE_END(_mgba_ap_sample);"
        "${MGBA_TICK_ORIGINAL}" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
string(FIND "${MGBA_GBA_TEXT}" "${MGBA_TICK_ORIGINAL}" _prof_timing_source)
if(_prof_timing_source EQUAL -1)
    message(FATAL_ERROR "v0.28 profiler patch failed: exact mGBA 0.10.5 mTimingTick source site not found")
endif()
string(REPLACE "${MGBA_TICK_ORIGINAL}" "${MGBA_TICK_INSTRUMENTED}" MGBA_GBA_TEXT "${MGBA_GBA_TEXT}")
# Validate the injected assignment, not the declaration. This must occur exactly once.
string(REGEX MATCHALL "_mgba_ap_tick_sample = MGBA_AP_TICK_SAMPLE_BEGIN\\(\\)" _prof_tick_hooks "${MGBA_GBA_TEXT}")
list(LENGTH _prof_tick_hooks _prof_tick_hook_count)
if(NOT _prof_tick_hook_count EQUAL 1)
    message(FATAL_ERROR "v0.28 profiler patch invalid: sampled mTimingTick call-site hooks=${_prof_tick_hook_count}, expected=1")
endif()
string(REGEX MATCHALL "MGBA_AP_PE_TICK\\(gba->cpuBlocked" _pe_tick_hooks "${MGBA_GBA_TEXT}")
list(LENGTH _pe_tick_hooks _pe_tick_hook_count)
if(NOT _pe_tick_hook_count EQUAL 1)
    message(FATAL_ERROR "v0.72.4.3.66.1 event-pressure patch invalid after cache normalization: tick hooks=${_pe_tick_hook_count}, expected=1")
endif()
message(STATUS "mGBA Android v0.72.4.3.66.1: cached event-pressure hook normalized and validated exactly once")
# The fetched gba.c is compiled twice: native API WITH the profiler define and Libretro WITHOUT it.
# Never inject direct profiler function calls into gba.c; the wrappers above no-op for Libretro.
string(REGEX MATCHALL "_mgba_ap_tick_sample = mgba_android_profiler_tick_sample_begin\\(\\)" _prof_direct_tick_calls "${MGBA_GBA_TEXT}")
list(LENGTH _prof_direct_tick_calls _prof_direct_tick_call_count)
if(NOT _prof_direct_tick_call_count EQUAL 0)
    message(FATAL_ERROR "v0.28 safety check failed: direct tick profiler calls leaked into shared gba.c")
endif()

string(FIND "${MGBA_VIDEO_TEXT}" "MGBA_ANDROID_PROF_DECL_V028" _video_prof_decl_marker)
if(_video_prof_decl_marker EQUAL -1)
    string(REPLACE "#include <mgba/internal/gba/video.h>"
            "#include <mgba/internal/gba/video.h>${MGBA_PROF_DECL}"
            MGBA_VIDEO_TEXT "${MGBA_VIDEO_TEXT}")
endif()
string(REPLACE "\t\t\tvideo->renderer->finishFrame(video->renderer);"
        "\t\t\tMGBA_AP_BEGIN(1); video->renderer->finishFrame(video->renderer); MGBA_AP_END(1);"
        MGBA_VIDEO_TEXT "${MGBA_VIDEO_TEXT}")
string(REPLACE "\t\tvideo->renderer->drawScanline(video->renderer, video->vcount);"
        "\t\tMGBA_AP_BEGIN(1); video->renderer->drawScanline(video->renderer, video->vcount); MGBA_AP_END(1);"
        MGBA_VIDEO_TEXT "${MGBA_VIDEO_TEXT}")
string(REPLACE "\t\tGBADMARunVblank(video->p, -cyclesLate);"
        "\t\tMGBA_AP_BEGIN(2); GBADMARunVblank(video->p, -cyclesLate); MGBA_AP_END(2);"
        MGBA_VIDEO_TEXT "${MGBA_VIDEO_TEXT}")
string(REPLACE "\t\tGBADMARunHblank(video->p, -cyclesLate);"
        "\t\tMGBA_AP_BEGIN(2); GBADMARunHblank(video->p, -cyclesLate); MGBA_AP_END(2);"
        MGBA_VIDEO_TEXT "${MGBA_VIDEO_TEXT}")
string(REPLACE "\t\tGBADMARunDisplayStart(video->p, -cyclesLate);"
        "\t\tMGBA_AP_BEGIN(2); GBADMARunDisplayStart(video->p, -cyclesLate); MGBA_AP_END(2);"
        MGBA_VIDEO_TEXT "${MGBA_VIDEO_TEXT}")

string(FIND "${MGBA_GBA_TEXT}" "MGBA_AP_BEGIN(0);" _prof_events_begin)
string(FIND "${MGBA_GBA_TEXT}" "MGBA_AP_END(0);" _prof_events_end)
string(FIND "${MGBA_VIDEO_TEXT}" "MGBA_AP_BEGIN(1);" _prof_video)
string(FIND "${MGBA_VIDEO_TEXT}" "MGBA_AP_BEGIN(2);" _prof_dma)
if(_prof_events_begin EQUAL -1 OR _prof_events_end EQUAL -1 OR _prof_video EQUAL -1 OR _prof_dma EQUAL -1)
    message(FATAL_ERROR "mGBA Android profiler: an expected 0.10.5 instrumentation hook did not apply")
endif()

file(WRITE "${MGBA_GBA_C}" "${MGBA_GBA_TEXT}")
file(WRITE "${MGBA_VIDEO_C}" "${MGBA_VIDEO_TEXT}")

# Build 145 v287 — low-impact ARMRunLoop sampling.
# The native GBA core samples one event segment out of 32 and times only that
# segment's instruction loop vs processEvents. Libretro compiles the same file
# without MGBA_ANDROID_INTERNAL_PROFILER, so these calls become no-ops there.
set(MGBA_ARM_C "${mgba_v028_SOURCE_DIR}/src/arm/arm.c")
file(READ "${MGBA_ARM_C}" MGBA_ARM_TEXT)
set(MGBA_ARM_LIGHT_DECL "
/* MGBA_ANDROID_ARM_LIGHT_PROBE_V287 */
#ifdef MGBA_ANDROID_INTERNAL_PROFILER
extern int mgba_android_arm_light_probe_active;
extern int mgba_android_arm_light_probe_begin(int mode, uint32_t pc, int halted);
extern uint64_t mgba_android_arm_light_probe_clock(void);
extern void mgba_android_arm_light_probe_end(int sampled, int mode, uint32_t pc,
                                             uint64_t instruction_start_ns,
                                             uint64_t instruction_end_ns,
                                             uint64_t event_end_ns);
#define MGBA_ARM_LIGHT_BEGIN(mode,pc,halted) (mgba_android_arm_light_probe_active ? mgba_android_arm_light_probe_begin((mode),(pc),(halted)) : 0)
#define MGBA_ARM_LIGHT_CLOCK() mgba_android_arm_light_probe_clock()
#define MGBA_ARM_LIGHT_END(sampled,mode,pc,a,b,c) do { if (mgba_android_arm_light_probe_active && (sampled)) mgba_android_arm_light_probe_end((sampled),(mode),(pc),(a),(b),(c)); } while (0)
#else
#define MGBA_ARM_LIGHT_BEGIN(mode,pc,halted) 0
#define MGBA_ARM_LIGHT_CLOCK() 0
#define MGBA_ARM_LIGHT_END(sampled,mode,pc,a,b,c) ((void)0)
#endif
")
string(FIND "${MGBA_ARM_TEXT}" "MGBA_ANDROID_ARM_LIGHT_PROBE_V287" _arm_light_decl_marker)
if(_arm_light_decl_marker EQUAL -1)
    string(REPLACE "#include <mgba/internal/arm/arm.h>"
            "#include <mgba/internal/arm/arm.h>${MGBA_ARM_LIGHT_DECL}"
            MGBA_ARM_TEXT "${MGBA_ARM_TEXT}")
endif()

set(_arm_runloop_original [=[void ARMRunLoop(struct ARMCore* cpu) {
	if (cpu->executionMode == MODE_THUMB) {
		while (cpu->cycles < cpu->nextEvent) {
			ThumbStep(cpu);
		}
	} else {
		while (cpu->cycles < cpu->nextEvent) {
			ARMStep(cpu);
		}
	}
	cpu->irqh.processEvents(cpu);
}]=])
set(_arm_runloop_instrumented [=[void ARMRunLoop(struct ARMCore* cpu) {
	const int _mgba_probe_mode = cpu->executionMode == MODE_THUMB ? 1 : 0;
	const uint32_t _mgba_probe_pc = (uint32_t) cpu->gprs[ARM_PC];
	const int _mgba_probe_sample = MGBA_ARM_LIGHT_BEGIN(_mgba_probe_mode, _mgba_probe_pc, cpu->halted ? 1 : 0);
	const uint64_t _mgba_probe_instruction_start = _mgba_probe_sample ? MGBA_ARM_LIGHT_CLOCK() : 0;
	if (cpu->executionMode == MODE_THUMB) {
		while (cpu->cycles < cpu->nextEvent) {
			ThumbStep(cpu);
		}
	} else {
		while (cpu->cycles < cpu->nextEvent) {
			ARMStep(cpu);
		}
	}
	const uint64_t _mgba_probe_instruction_end = _mgba_probe_sample ? MGBA_ARM_LIGHT_CLOCK() : 0;
	cpu->irqh.processEvents(cpu);
	if (_mgba_probe_sample) {
		const uint64_t _mgba_probe_event_end = MGBA_ARM_LIGHT_CLOCK();
		MGBA_ARM_LIGHT_END(_mgba_probe_sample, _mgba_probe_mode, _mgba_probe_pc,
		                   _mgba_probe_instruction_start, _mgba_probe_instruction_end,
		                   _mgba_probe_event_end);
	}
}]=])
string(FIND "${MGBA_ARM_TEXT}" "_mgba_probe_instruction_start" _arm_light_hook_marker)
if(_arm_light_hook_marker EQUAL -1)
    string(FIND "${MGBA_ARM_TEXT}" "${_arm_runloop_original}" _arm_light_source_pos)
    if(_arm_light_source_pos EQUAL -1)
        message(FATAL_ERROR "Build 145 v287: exact mGBA 0.10.5 ARMRunLoop anchor changed")
    endif()
    string(REPLACE "${_arm_runloop_original}" "${_arm_runloop_instrumented}" MGBA_ARM_TEXT "${MGBA_ARM_TEXT}")
endif()
string(FIND "${MGBA_ARM_TEXT}" "_mgba_probe_instruction_start" _arm_light_final)
if(_arm_light_final EQUAL -1)
    message(FATAL_ERROR "Build 145 v287: ARMRunLoop sampling hook did not apply")
endif()
file(WRITE "${MGBA_ARM_C}" "${MGBA_ARM_TEXT}")

# v0.16 Event Subsystem Profiler: split "Events other".
set(MGBA_AUDIO_C "${mgba_v028_SOURCE_DIR}/src/gba/audio.c")
file(READ "${mgba_v028_SOURCE_DIR}/src/gba/dma.c" MGBA_DMA_TEXT)
# v0.21: reconfigure-safe hook cleanup before one clean application.
string(REPLACE "\tMGBA_AP_DMA_EVENT(memory->activeDMA, cyclesLate);\n" "" MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
string(REPLACE "\tMGBA_AP_DMA_SERVICE(number);\n" "" MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
string(REPLACE "\tMGBA_AP_DMA_TRANSFER(number, width, info->nextCount, wordsRemaining);\n" "" MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
string(REPLACE "\tMGBA_AP_DMA_TRANSFER(number, width, info->nextCount, info->nextCount - 1);\n" "" MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
string(REPLACE "\t\tMGBA_AP_DMA_UPDATE(memory->activeDMA, memory->dma[memory->activeDMA].when - currentTime);\n" "" MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")

set(MGBA_DMA_PROF_DECL "#include <stdint.h>\n#ifdef MGBA_ANDROID_INTERNAL_PROFILER\nextern int mgba_android_internal_profiler_active;\nextern void mgba_android_profiler_dma_event(int channel, uint32_t cyclesLate);\nextern void mgba_android_profiler_dma_service(int channel);\nextern void mgba_android_profiler_dma_update(int activeChannel, int32_t delay);\nextern void mgba_android_profiler_dma_transfer(int channel, uint32_t width, int32_t beforeCount, int32_t afterCount);\n#define MGBA_AP_DMA_EVENT(ch,late) do { if (mgba_android_internal_profiler_active >= 2) mgba_android_profiler_dma_event((ch),(late)); } while (0)\n#define MGBA_AP_DMA_SERVICE(ch) do { if (mgba_android_internal_profiler_active >= 2) mgba_android_profiler_dma_service((ch)); } while (0)\n#define MGBA_AP_DMA_UPDATE(ch,delay) do { if (mgba_android_internal_profiler_active >= 2) mgba_android_profiler_dma_update((ch),(delay)); } while (0)\n#define MGBA_AP_DMA_TRANSFER(ch,w,b,a) do { if (mgba_android_internal_profiler_active >= 2) mgba_android_profiler_dma_transfer((ch),(w),(b),(a)); } while (0)\n#else\n#define MGBA_AP_DMA_EVENT(ch,late) ((void)0)\n#define MGBA_AP_DMA_SERVICE(ch) ((void)0)\n#define MGBA_AP_DMA_UPDATE(ch,delay) ((void)0)\n#define MGBA_AP_DMA_TRANSFER(ch,w,b,a) ((void)0)\n#endif\n")
string(PREPEND MGBA_DMA_TEXT "${MGBA_DMA_PROF_DECL}")
string(REPLACE "\tstruct GBADMA* dma = &memory->dma[memory->activeDMA];" "\tstruct GBADMA* dma = &memory->dma[memory->activeDMA];\n\tMGBA_AP_DMA_EVENT(memory->activeDMA, cyclesLate);" MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
string(REPLACE "void GBADMAService(struct GBA* gba, int number, struct GBADMA* info) {" "void GBADMAService(struct GBA* gba, int number, struct GBADMA* info) {\n\tMGBA_AP_DMA_SERVICE(number);" MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
string(REPLACE "\t\tmTimingSchedule(&gba->timing, &memory->dmaEvent, memory->dma[memory->activeDMA].when - currentTime);" "\t\tMGBA_AP_DMA_UPDATE(memory->activeDMA, memory->dma[memory->activeDMA].when - currentTime);\n\t\tmTimingSchedule(&gba->timing, &memory->dmaEvent, memory->dma[memory->activeDMA].when - currentTime);" MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
string(FIND "${MGBA_DMA_TEXT}" "MGBA_AP_DMA_EVENT" _dma_prof_decl)
string(FIND "${MGBA_DMA_TEXT}" "MGBA_AP_DMA_EVENT(memory->activeDMA, cyclesLate)" _dma_prof_hook)
if(_dma_prof_decl EQUAL -1 OR _dma_prof_hook EQUAL -1)
    message(FATAL_ERROR "mGBA Android v0.20.1: DMA profiler declaration/hook did not apply")
endif()
string(FIND "${MGBA_DMA_TEXT}" "\tinfo->nextCount = wordsRemaining;" _dma_batch_transfer_anchor)
if(NOT _dma_batch_transfer_anchor EQUAL -1)
    string(REPLACE "\tinfo->nextCount = wordsRemaining;"
            "\tMGBA_AP_DMA_TRANSFER(number, width, info->nextCount, wordsRemaining);\n\tinfo->nextCount = wordsRemaining;"
            MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
else()
    # Current upstream services one DMA unit per GBADMAService call. Instrument
    # the equivalent count transition without changing the upstream decrement.
    string(FIND "${MGBA_DMA_TEXT}" "\t--info->nextCount;" _dma_unit_transfer_anchor)
    if(_dma_unit_transfer_anchor EQUAL -1)
        message(FATAL_ERROR "mGBA Android: DMA transfer-count anchor changed")
    endif()
    string(REPLACE "\t--info->nextCount;"
            "\tMGBA_AP_DMA_TRANSFER(number, width, info->nextCount, info->nextCount - 1);\n\t--info->nextCount;"
            MGBA_DMA_TEXT "${MGBA_DMA_TEXT}")
endif()
string(REGEX MATCHALL "MGBA_AP_DMA_EVENT\\(memory->activeDMA, cyclesLate\\)" _h1 "${MGBA_DMA_TEXT}")
string(REGEX MATCHALL "MGBA_AP_DMA_SERVICE\\(number\\)" _h2 "${MGBA_DMA_TEXT}")
string(REGEX MATCHALL "MGBA_AP_DMA_UPDATE\\(memory->activeDMA, memory->dma\\[memory->activeDMA\\]\\.when - currentTime\\)" _h3 "${MGBA_DMA_TEXT}")
list(LENGTH _h1 _n1)
list(LENGTH _h2 _n2)
list(LENGTH _h3 _n3)
string(REGEX MATCHALL "MGBA_AP_DMA_TRANSFER\\(number, width, info->nextCount, wordsRemaining\\)" _h4_batch "${MGBA_DMA_TEXT}")
string(REGEX MATCHALL "MGBA_AP_DMA_TRANSFER\\(number, width, info->nextCount, info->nextCount - 1\\)" _h4_unit "${MGBA_DMA_TEXT}")
list(LENGTH _h4_batch _n4_batch)
list(LENGTH _h4_unit _n4_unit)
math(EXPR _n4 "${_n4_batch} + ${_n4_unit}")
if(NOT _n1 EQUAL 1 OR NOT _n2 EQUAL 1 OR NOT _n3 EQUAL 1 OR NOT _n4 EQUAL 1)
 message(FATAL_ERROR "mGBA Android v0.21: DMA hooks are not unique: ${_n1}/${_n2}/${_n3}/${_n4}")
endif()
file(WRITE "${mgba_v028_SOURCE_DIR}/src/gba/dma.c" "${MGBA_DMA_TEXT}")
set(MGBA_TIMING_C "${mgba_v028_SOURCE_DIR}/src/core/timing.c")
file(READ "${MGBA_AUDIO_C}" MGBA_AUDIO_TEXT)
file(READ "${MGBA_TIMING_C}" MGBA_TIMING_TEXT)

string(FIND "${MGBA_AUDIO_TEXT}" "MGBA_ANDROID_PROF_DECL_V028" _audio_prof_decl_marker)
if(_audio_prof_decl_marker EQUAL -1)
    string(REPLACE "#include <mgba/internal/gba/audio.h>"
            "#include <mgba/internal/gba/audio.h>${MGBA_PROF_DECL}"
            MGBA_AUDIO_TEXT "${MGBA_AUDIO_TEXT}")
endif()

# Stage 3 = GBA audio/APU sample callback. Hook the recurring sample path
# that dominate GBA audio timing without changing their behavior.
string(REPLACE "static void _sample(struct mTiming* timing, void* user, uint32_t cyclesLate) {"
        "static void _sample(struct mTiming* timing, void* user, uint32_t cyclesLate) { MGBA_AP_BEGIN(3);"
        MGBA_AUDIO_TEXT "${MGBA_AUDIO_TEXT}")
string(REPLACE "\tmTimingSchedule(timing, &audio->sampleEvent, SAMPLE_INTERVAL - cyclesLate);\n}"
        "\tmTimingSchedule(timing, &audio->sampleEvent, SAMPLE_INTERVAL - cyclesLate);\n\tMGBA_AP_END(3);\n}"
        MGBA_AUDIO_TEXT "${MGBA_AUDIO_TEXT}")

# Stage 4 = generic mTiming callback dispatch. This is inclusive and is used to
# identify whether a spike is callback/event driven. Stage 3 is a child bucket; PPU/DMA are measured separately.
string(FIND "${MGBA_TIMING_TEXT}" "MGBA_ANDROID_PROF_DECL_V028" _timing_prof_decl_marker)
if(_timing_prof_decl_marker EQUAL -1)
    string(REPLACE "#include <mgba/core/timing.h>"
            "#include <mgba/core/timing.h>${MGBA_PROF_DECL}"
            MGBA_TIMING_TEXT "${MGBA_TIMING_TEXT}")
endif()
# Validate the exact pinned 0.10.5 callback BEFORE rewriting it. This avoids
# CMake post-rewrite parsing of the semicolon-heavy macro invocation.
string(FIND "${MGBA_TIMING_TEXT}" "next->callback(timing, next->context, -nextWhen)" _prof_dispatch_source)
if(_prof_dispatch_source EQUAL -1)
    message(FATAL_ERROR "mGBA Android event profiler: mTiming 0.10.5 callback source not found")
endif()
string(REPLACE "\t\tnext->callback(timing, next->context, -nextWhen);"
        "\t\tMGBA_AP_EVENT_COUNT(next->name); next->callback(timing, next->context, -nextWhen);"
        MGBA_TIMING_TEXT "${MGBA_TIMING_TEXT}")

string(FIND "${MGBA_TIMING_TEXT}" "MGBA_AP_EVENT_COUNT(next->name)" _prof_event_count)
if(_prof_event_count EQUAL -1)
    message(FATAL_ERROR "mGBA Android v0.18.2: pristine mGBA 0.10.5 low-overhead timing hook did not apply")
endif()

string(FIND "${MGBA_AUDIO_TEXT}" "MGBA_AP_BEGIN(3)" _prof_audio)
string(FIND "${MGBA_AUDIO_TEXT}" "MGBA_AP_END(3)" _prof_audio_end)
if(_prof_audio EQUAL -1 OR _prof_audio_end EQUAL -1)
    message(FATAL_ERROR "mGBA Android event profiler: expected 0.10.5 audio hooks did not apply")
endif()
file(WRITE "${MGBA_AUDIO_C}" "${MGBA_AUDIO_TEXT}")
file(WRITE "${MGBA_TIMING_C}" "${MGBA_TIMING_TEXT}")

# v0.48.1 e-Reader scanner link fix. In upstream 0.10.5 the complete image
# scanner is guarded by USE_FFMPEG because only its resize helper depends on
# FFmpeg. Android already supplies decoded 8-bit luma, so compile that scanner
# behind a private define and replace only the FFmpeg resize with a bounded
# bilinear CPU implementation. This avoids linking the desktop FFmpeg stack.
set(MGBA_EREADER_C "${mgba_v028_SOURCE_DIR}/src/gba/cart/ereader.c")
file(READ "${MGBA_EREADER_C}" MGBA_EREADER_TEXT)
if(NOT MGBA_EREADER_TEXT MATCHES "MGBA_ANDROID_EREADER_SCANNER_V0481")
    string(REPLACE
            "#ifdef USE_FFMPEG\n#include <mgba-util/convolve.h>"
            "#if defined(USE_FFMPEG) || defined(MGBA_ANDROID_EREADER_SCANNER)\n#include <mgba-util/convolve.h>\n#endif\n#ifdef MGBA_ANDROID_EREADER_SCANNER\n#include <mgba-util/vfs.h>\n#endif\n#ifdef USE_FFMPEG"
            MGBA_EREADER_TEXT "${MGBA_EREADER_TEXT}")
    string(REPLACE
            "#ifdef USE_FFMPEG\nstruct EReaderAnchor {"
            "#if defined(USE_FFMPEG) || defined(MGBA_ANDROID_EREADER_SCANNER)\n/* MGBA_ANDROID_EREADER_SCANNER_V0481 */\nstruct EReaderAnchor {"
            MGBA_EREADER_TEXT "${MGBA_EREADER_TEXT}")
    set(_mgba_ereader_ffmpeg_resize [=[static void _eReaderScanDownsample(struct EReaderScan* scan) {
	// TODO: Replace this logic with a value based on total area
	scan->scale = 400;
	if (scan->srcWidth > scan->srcHeight) {
		scan->height = 400;
		scan->width = scan->srcWidth * 400 / scan->srcHeight;
	} else {
		scan->width = 400;
		scan->height = scan->srcHeight * 400 / scan->srcWidth;
	}
	scan->buffer = malloc(scan->width * scan->height);
	FFmpegScale(scan->srcBuffer, scan->srcWidth, scan->srcHeight, scan->srcWidth, scan->buffer, scan->width, scan->height, scan->width, mCOLOR_L8, 3);
	free(scan->srcBuffer);
	scan->srcBuffer = NULL;
}]=])
    set(_mgba_ereader_android_resize [=[static void _eReaderScanDownsample(struct EReaderScan* scan) {
#ifdef MGBA_ANDROID_EREADER_SCANNER
	const unsigned maxDimension = 4096;
	scan->scale = 400;
	if (scan->srcWidth > scan->srcHeight) {
		scan->height = 400;
		uint64_t scaled = (uint64_t) scan->srcWidth * scan->height / scan->srcHeight;
		scan->width = scaled > maxDimension ? maxDimension : (unsigned) scaled;
	} else {
		scan->width = 400;
		uint64_t scaled = (uint64_t) scan->srcHeight * scan->width / scan->srcWidth;
		scan->height = scaled > maxDimension ? maxDimension : (unsigned) scaled;
	}
	scan->buffer = malloc((size_t) scan->width * scan->height);
	for (unsigned y = 0; y < scan->height; ++y) {
		uint64_t sy = scan->height > 1 ? (uint64_t) y * (scan->srcHeight - 1) * 65536 / (scan->height - 1) : 0;
		unsigned y0 = (unsigned) (sy >> 16);
		unsigned y1 = y0 + 1 < scan->srcHeight ? y0 + 1 : y0;
		uint32_t fy = (uint32_t) sy & 0xFFFF;
		for (unsigned x = 0; x < scan->width; ++x) {
			uint64_t sx = scan->width > 1 ? (uint64_t) x * (scan->srcWidth - 1) * 65536 / (scan->width - 1) : 0;
			unsigned x0 = (unsigned) (sx >> 16);
			unsigned x1 = x0 + 1 < scan->srcWidth ? x0 + 1 : x0;
			uint32_t fx = (uint32_t) sx & 0xFFFF;
			uint64_t top = (uint64_t) scan->srcBuffer[(size_t) y0 * scan->srcWidth + x0] * (65536 - fx)
			             + (uint64_t) scan->srcBuffer[(size_t) y0 * scan->srcWidth + x1] * fx;
			uint64_t bottom = (uint64_t) scan->srcBuffer[(size_t) y1 * scan->srcWidth + x0] * (65536 - fx)
			                + (uint64_t) scan->srcBuffer[(size_t) y1 * scan->srcWidth + x1] * fx;
			scan->buffer[(size_t) y * scan->width + x] = (uint8_t) ((top * (65536 - fy) + bottom * fy + (1ULL << 31)) >> 32);
		}
	}
#else
	// TODO: Replace this logic with a value based on total area
	scan->scale = 400;
	if (scan->srcWidth > scan->srcHeight) {
		scan->height = 400;
		scan->width = scan->srcWidth * 400 / scan->srcHeight;
	} else {
		scan->width = 400;
		scan->height = scan->srcHeight * 400 / scan->srcWidth;
	}
	scan->buffer = malloc(scan->width * scan->height);
	FFmpegScale(scan->srcBuffer, scan->srcWidth, scan->srcHeight, scan->srcWidth, scan->buffer, scan->width, scan->height, scan->width, mCOLOR_L8, 3);
#endif
	free(scan->srcBuffer);
	scan->srcBuffer = NULL;
}]=])
    string(REPLACE "${_mgba_ereader_ffmpeg_resize}" "${_mgba_ereader_android_resize}"
            MGBA_EREADER_TEXT "${MGBA_EREADER_TEXT}")
    string(FIND "${MGBA_EREADER_TEXT}" "MGBA_ANDROID_EREADER_SCANNER_V0481" _ereader_scanner_guard)
    string(FIND "${MGBA_EREADER_TEXT}" "const unsigned maxDimension = 4096" _ereader_resize_guard)
    if(_ereader_scanner_guard EQUAL -1 OR _ereader_resize_guard EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.48.1: e-Reader CPU scanner patch did not apply")
    endif()
    file(WRITE "${MGBA_EREADER_C}" "${MGBA_EREADER_TEXT}")
endif()

# v0.61 official mGBA scripting engine hardening for Android. Upstream 0.10.5
# uses mScriptContext + the Lua engine, but its desktop engine opens the complete
# Lua standard library and has no instruction/heap watchdog. Keep the official
# engine/API while applying an Android-only safety profile to the fetched build
# copy. Guard every replacement so an upstream drift fails loudly instead of
# silently producing an unsafe or partially patched engine.
set(MGBA_SCRIPT_LUA_C "${mgba_v028_SOURCE_DIR}/src/script/engines/lua.c")
if(EXISTS "${MGBA_SCRIPT_LUA_C}")
    file(READ "${MGBA_SCRIPT_LUA_C}" MGBA_SCRIPT_LUA_TEXT)
    string(FIND "${MGBA_SCRIPT_LUA_TEXT}" "MGBA_ANDROID_OFFICIAL_SCRIPTING_V061" _script_v061_already)
    if(_script_v061_already EQUAL -1)
        # v0.61.1: make the Android hardening patch line-ending agnostic.
        # Patch unique semantic anchors instead of replacing a whole struct
        # byte-for-byte, so LF/CRLF and harmless whitespace changes on Windows
        # cannot trip the configure step.
        set(_script_struct_field_old "char* lastError;")
        set(_script_struct_field_new [=[char* lastError;
	size_t androidHeapBytes;
	int androidInstructionBudget;]=])
        string(FIND "${MGBA_SCRIPT_LUA_TEXT}" "${_script_struct_field_old}" _script_struct_field_pos)
        if(_script_struct_field_pos EQUAL -1)
            message(FATAL_ERROR "mGBA Android v0.61.1: official Lua context field anchor changed; refusing unsafe patch")
        endif()
        string(REPLACE "${_script_struct_field_old}" "${_script_struct_field_new}" MGBA_SCRIPT_LUA_TEXT "${MGBA_SCRIPT_LUA_TEXT}")

        set(_script_ref_struct_anchor "struct mScriptEngineContextLuaRef {")
        set(_script_android_helpers [=[/* MGBA_ANDROID_OFFICIAL_SCRIPTING_V061 */
#define MGBA_ANDROID_LUA_MAX_HEAP (32u * 1024u * 1024u)
#define MGBA_ANDROID_LUA_HOOK_GRANULARITY 1000
#define MGBA_ANDROID_LUA_TOPLEVEL_BUDGET 500000
#define MGBA_ANDROID_LUA_CALLBACK_BUDGET 100000
static void* _luaAndroidAlloc(void* ud, void* ptr, size_t oldSize, size_t newSize) {
	struct mScriptEngineContextLua* ctx = ud;
	if (!newSize) {
		if (ptr) {
			ctx->androidHeapBytes = oldSize <= ctx->androidHeapBytes ? ctx->androidHeapBytes - oldSize : 0;
			free(ptr);
		}
		return NULL;
	}
	size_t previous = ptr ? oldSize : 0;
	if (newSize > previous) {
		size_t growth = newSize - previous;
		if (ctx->androidHeapBytes >= MGBA_ANDROID_LUA_MAX_HEAP ||
		    growth > MGBA_ANDROID_LUA_MAX_HEAP - ctx->androidHeapBytes) {
			return NULL;
		}
	}
	void* out = realloc(ptr, newSize);
	if (!out) return NULL;
	if (newSize >= previous) ctx->androidHeapBytes += newSize - previous;
	else ctx->androidHeapBytes -= previous - newSize;
	return out;
}
static void _luaAndroidBudgetHook(lua_State* lua, lua_Debug* ar) {
	UNUSED(ar);
	lua_pushliteral(lua, "mCtx");
	lua_rawget(lua, LUA_REGISTRYINDEX);
	struct mScriptEngineContextLua* ctx = lua_touserdata(lua, -1);
	lua_pop(lua, 1);
	if (!ctx) return;
	ctx->androidInstructionBudget -= MGBA_ANDROID_LUA_HOOK_GRANULARITY;
	if (ctx->androidInstructionBudget <= 0) luaL_error(lua, "Android Lua instruction budget exceeded");
}
static void _luaAndroidBudgetBegin(struct mScriptEngineContextLua* ctx, int budget) {
	ctx->androidInstructionBudget = budget;
	lua_sethook(ctx->lua, _luaAndroidBudgetHook, LUA_MASKCOUNT, MGBA_ANDROID_LUA_HOOK_GRANULARITY);
}
static void _luaAndroidBudgetEnd(struct mScriptEngineContextLua* ctx) {
	lua_sethook(ctx->lua, NULL, 0, 0);
	ctx->androidInstructionBudget = 0;
}

struct mScriptEngineContextLuaRef {]=])
        string(FIND "${MGBA_SCRIPT_LUA_TEXT}" "${_script_ref_struct_anchor}" _script_ref_struct_pos)
        if(_script_ref_struct_pos EQUAL -1)
            message(FATAL_ERROR "mGBA Android v0.61.1: official Lua ref-struct anchor changed; refusing unsafe patch")
        endif()
        string(REPLACE "${_script_ref_struct_anchor}" "${_script_android_helpers}" MGBA_SCRIPT_LUA_TEXT "${MGBA_SCRIPT_LUA_TEXT}")

        # v0.61.1: patch the two upstream create anchors independently. The
        # v0.61.0 guard matched three adjacent lines byte-for-byte, which was
        # unnecessarily fragile on Windows/reused FetchContent trees because a
        # newline/whitespace difference made configuration abort even though the
        # pinned 0.10.5 API was unchanged. These single-line anchors are unique
        # inside _luaCreate and work with LF or CRLF source text.
        set(_script_create_alloc_old "luaContext->lua = luaL_newstate();")
        set(_script_create_alloc_new [=[luaContext->lua = lua_newstate(_luaAndroidAlloc, luaContext);
	if (!luaContext->lua) {
		free(luaContext);
		return NULL;
	}]=])
        string(FIND "${MGBA_SCRIPT_LUA_TEXT}" "${_script_create_alloc_old}" _script_create_alloc_pos)
        if(_script_create_alloc_pos EQUAL -1)
            message(FATAL_ERROR "mGBA Android v0.61.1: official Lua allocator anchor changed")
        endif()
        string(REPLACE "${_script_create_alloc_old}" "${_script_create_alloc_new}" MGBA_SCRIPT_LUA_TEXT "${MGBA_SCRIPT_LUA_TEXT}")

        set(_script_openlibs_old "luaL_openlibs(luaContext->lua);")
        set(_script_openlibs_new [=[/* Android safety profile: open only the same safe Lua libraries used by
	 * the previous frontend sandbox. The mScript engine itself remains the
	 * upstream 0.10.5 implementation. */
	luaL_requiref(luaContext->lua, "_G", luaopen_base, 1); lua_pop(luaContext->lua, 1);
	luaL_requiref(luaContext->lua, LUA_COLIBNAME, luaopen_coroutine, 1); lua_pop(luaContext->lua, 1);
	luaL_requiref(luaContext->lua, LUA_TABLIBNAME, luaopen_table, 1); lua_pop(luaContext->lua, 1);
	luaL_requiref(luaContext->lua, LUA_STRLIBNAME, luaopen_string, 1); lua_pop(luaContext->lua, 1);
	luaL_requiref(luaContext->lua, LUA_MATHLIBNAME, luaopen_math, 1); lua_pop(luaContext->lua, 1);
	luaL_requiref(luaContext->lua, LUA_UTF8LIBNAME, luaopen_utf8, 1); lua_pop(luaContext->lua, 1);
	const char* androidBlockedGlobals[] = { "require", "dofile", "loadfile", "load", NULL };
	for (const char** blocked = androidBlockedGlobals; *blocked; ++blocked) {
		lua_pushnil(luaContext->lua);
		lua_setglobal(luaContext->lua, *blocked);
	}]=])
        string(FIND "${MGBA_SCRIPT_LUA_TEXT}" "${_script_openlibs_old}" _script_openlibs_pos)
        if(_script_openlibs_pos EQUAL -1)
            message(FATAL_ERROR "mGBA Android v0.61.1: official Lua openlibs anchor changed")
        endif()
        string(REPLACE "${_script_openlibs_old}" "${_script_openlibs_new}" MGBA_SCRIPT_LUA_TEXT "${MGBA_SCRIPT_LUA_TEXT}")

        # The lua_pcall signature below is unique to _luaInvoke in mGBA 0.10.5.
        # Patch only that call so line endings/adjacent whitespace cannot cause
        # the same false drift detection as v0.61.0.
        set(_script_invoke_old "int ret = lua_pcall(luaContext->lua, nargs, LUA_MULTRET, 0);")
        set(_script_invoke_new [=[_luaAndroidBudgetBegin(luaContext, frame ? MGBA_ANDROID_LUA_CALLBACK_BUDGET : MGBA_ANDROID_LUA_TOPLEVEL_BUDGET);
	int ret = lua_pcall(luaContext->lua, nargs, LUA_MULTRET, 0);
	_luaAndroidBudgetEnd(luaContext);]=])
        string(FIND "${MGBA_SCRIPT_LUA_TEXT}" "${_script_invoke_old}" _script_invoke_pos)
        if(_script_invoke_pos EQUAL -1)
            message(FATAL_ERROR "mGBA Android v0.61.1: official Lua invoke anchor changed")
        endif()
        string(REPLACE "${_script_invoke_old}" "${_script_invoke_new}" MGBA_SCRIPT_LUA_TEXT "${MGBA_SCRIPT_LUA_TEXT}")
        file(WRITE "${MGBA_SCRIPT_LUA_C}" "${MGBA_SCRIPT_LUA_TEXT}")
    endif()
endif()

if(MGBA_ANDROID_HAS_MP2K_XQ)
# v0.72.4.3.47 — Official mGBA MP2K/XQ audio mixer on Android.
# Upstream 0.10.5 keeps the HLE/XQ mixer creation behind !MINIMAL_CORE even
# though the mixer itself has no desktop UI dependency. Our Android core uses
# MINIMAL_CORE=1 to avoid unrelated frontend/feature code, so selectively open
# only this reset-time mixer hook. The source remains the pristine upstream
# src/gba/extra/audio-mixer.c and the existing gba.audioHle option controls it.
set(MGBA_GBA_CORE_C "${mgba_v028_SOURCE_DIR}/src/gba/core.c")
file(READ "${MGBA_GBA_CORE_C}" MGBA_GBA_CORE_TEXT)
string(FIND "${MGBA_GBA_CORE_TEXT}" "MGBA_ANDROID_MP2K_XQ_V0724347" _mp2k_xq_already_patched)
if(_mp2k_xq_already_patched EQUAL -1)
    set(_mp2k_xq_old [=[#ifndef MINIMAL_CORE
	int useAudioMixer;
	if (!gbacore->audioMixer && mCoreConfigGetIntValue(&core->config, "gba.audioHle", &useAudioMixer) && useAudioMixer) {
		gbacore->audioMixer = malloc(sizeof(*gbacore->audioMixer));
		GBAAudioMixerCreate(gbacore->audioMixer);
		((struct ARMCore*) core->cpu)->components[CPU_COMPONENT_AUDIO_MIXER] = &gbacore->audioMixer->d;
		ARMHotplugAttach(core->cpu, CPU_COMPONENT_AUDIO_MIXER);
	}
#endif]=])
    set(_mp2k_xq_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_MP2K_XQ)
	/* MGBA_ANDROID_MP2K_XQ_V0724347: keep the official upstream mixer hook
	 * available in the Android MINIMAL_CORE build without enabling unrelated
	 * desktop feature groups. */
	int useAudioMixer;
	if (!gbacore->audioMixer && mCoreConfigGetIntValue(&core->config, "gba.audioHle", &useAudioMixer) && useAudioMixer) {
		gbacore->audioMixer = malloc(sizeof(*gbacore->audioMixer));
		GBAAudioMixerCreate(gbacore->audioMixer);
		((struct ARMCore*) core->cpu)->components[CPU_COMPONENT_AUDIO_MIXER] = &gbacore->audioMixer->d;
		ARMHotplugAttach(core->cpu, CPU_COMPONENT_AUDIO_MIXER);
	}
#endif]=])
    string(FIND "${MGBA_GBA_CORE_TEXT}" "${_mp2k_xq_old}" _mp2k_xq_anchor)
    if(_mp2k_xq_anchor EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.72.4.3.47: upstream MP2K/XQ reset hook changed")
    endif()
    string(REPLACE "${_mp2k_xq_old}" "${_mp2k_xq_new}" MGBA_GBA_CORE_TEXT "${MGBA_GBA_CORE_TEXT}")
    file(WRITE "${MGBA_GBA_CORE_C}" "${MGBA_GBA_CORE_TEXT}")
endif()

else()
    message(STATUS "mGBA Android: skipping removed MP2K/XQ reset hook")
endif()

# v0.73 — Official mGBA Video Log (.mvl) recording on Android.
# Keep MINIMAL_CORE=1 and selectively expose only the official recording ABI.
# The upstream master no longer has MP2K/XQ, so MGBA_GBA_CORE_C must not
# depend on the optional XQ compatibility block above.
set(MGBA_GBA_CORE_C "${mgba_v028_SOURCE_DIR}/src/gba/core.c")
set(MGBA_CORE_H "${mgba_v028_SOURCE_DIR}/include/mgba/core/core.h")
set(MGBA_GBA_PUBLIC_CORE_H "${mgba_v028_SOURCE_DIR}/include/mgba/gba/core.h")
set(MGBA_GB_PUBLIC_CORE_H "${mgba_v028_SOURCE_DIR}/include/mgba/gb/core.h")
set(MGBA_GB_CORE_C "${mgba_v028_SOURCE_DIR}/src/gb/core.c")
file(READ "${MGBA_CORE_H}" MGBA_CORE_H_TEXT)
file(READ "${MGBA_GBA_PUBLIC_CORE_H}" MGBA_GBA_PUBLIC_CORE_H_TEXT)
file(READ "${MGBA_GB_PUBLIC_CORE_H}" MGBA_GB_PUBLIC_CORE_H_TEXT)
file(READ "${MGBA_GBA_CORE_C}" MGBA_GBA_CORE_TEXT)
file(READ "${MGBA_GB_CORE_C}" MGBA_GB_CORE_TEXT)

string(FIND "${MGBA_CORE_H_TEXT}" "MGBA_ANDROID_VIDEO_LOG_V073" _mvl_core_header_patched)
if(_mvl_core_header_patched EQUAL -1)
    set(_old [=[#ifndef MINIMAL_CORE
	void (*startVideoLog)(struct mCore*, struct mVideoLogContext*);
	void (*endVideoLog)(struct mCore*);
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
	/* MGBA_ANDROID_VIDEO_LOG_V073: official mVL recording hooks only. */
	void (*startVideoLog)(struct mCore*, struct mVideoLogContext*);
	void (*endVideoLog)(struct mCore*);
#endif]=])
    string(FIND "${MGBA_CORE_H_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: mCore video-log ABI anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_CORE_H_TEXT "${MGBA_CORE_H_TEXT}")
    file(WRITE "${MGBA_CORE_H}" "${MGBA_CORE_H_TEXT}")
endif()

# video-logger.c references the platform player factory descriptors even in a
# MINIMAL_CORE build.  The minimal core implementations already provide safe
# stubs; expose only their declarations so C11 never relies on an implicit
# function declaration while compiling the official logger.
string(FIND "${MGBA_GBA_PUBLIC_CORE_H_TEXT}" "MGBA_ANDROID_VIDEO_LOG_V073_GBA_DECL" _mvl_gba_decl_patched)
if(_mvl_gba_decl_patched EQUAL -1)
    set(_old [=[#ifndef MINIMAL_CORE
struct mCore* GBAVideoLogPlayerCreate(void);
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
/* MGBA_ANDROID_VIDEO_LOG_V073_GBA_DECL: declaration for official logger. */
struct mCore* GBAVideoLogPlayerCreate(void);
#endif]=])
    string(FIND "${MGBA_GBA_PUBLIC_CORE_H_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GBA video-log player declaration anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GBA_PUBLIC_CORE_H_TEXT "${MGBA_GBA_PUBLIC_CORE_H_TEXT}")
    file(WRITE "${MGBA_GBA_PUBLIC_CORE_H}" "${MGBA_GBA_PUBLIC_CORE_H_TEXT}")
endif()

string(FIND "${MGBA_GB_PUBLIC_CORE_H_TEXT}" "MGBA_ANDROID_VIDEO_LOG_V073_GB_DECL" _mvl_gb_decl_patched)
if(_mvl_gb_decl_patched EQUAL -1)
    set(_old [=[#ifndef MINIMAL_CORE
struct mCore* GBVideoLogPlayerCreate(void);
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
/* MGBA_ANDROID_VIDEO_LOG_V073_GB_DECL: declaration for official logger. */
struct mCore* GBVideoLogPlayerCreate(void);
#endif]=])
    string(FIND "${MGBA_GB_PUBLIC_CORE_H_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GB video-log player declaration anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GB_PUBLIC_CORE_H_TEXT "${MGBA_GB_PUBLIC_CORE_H_TEXT}")
    file(WRITE "${MGBA_GB_PUBLIC_CORE_H}" "${MGBA_GB_PUBLIC_CORE_H_TEXT}")
endif()

string(FIND "${MGBA_GBA_CORE_TEXT}" "MGBA_ANDROID_VIDEO_LOG_V073_GBA" _mvl_gba_patched)
if(_mvl_gba_patched EQUAL -1)
    # Current upstream added fields around this block. Patch only the unique
    # guard + first proxy field instead of requiring the whole 0.10.5 struct
    # layout to be byte-for-byte identical.
    set(_old "#ifndef MINIMAL_CORE\n\tstruct GBAVideoProxyRenderer vlProxy;")
    set(_new "#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)\n\t/* MGBA_ANDROID_VIDEO_LOG_V073_GBA: official recording proxy state. */\n\tstruct GBAVideoProxyRenderer vlProxy;")
    string(FIND "${MGBA_GBA_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GBA video-log struct guard anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GBA_CORE_TEXT "${MGBA_GBA_CORE_TEXT}")

    set(_old [=[#ifndef MINIMAL_CORE
	gbacore->logContext = NULL;
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
	gbacore->logContext = NULL;
#endif]=])
    string(FIND "${MGBA_GBA_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GBA video-log init anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GBA_CORE_TEXT "${MGBA_GBA_CORE_TEXT}")

    set(_old [=[#ifndef MINIMAL_CORE
	gbacore->vlProxy.logger = NULL;
	gbacore->proxyRenderer.logger = NULL;
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
	gbacore->vlProxy.logger = NULL;
	gbacore->proxyRenderer.logger = NULL;
#endif]=])
    string(FIND "${MGBA_GBA_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GBA video-log proxy-init anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GBA_CORE_TEXT "${MGBA_GBA_CORE_TEXT}")

    set(_old "#ifndef MINIMAL_CORE\nstatic void _GBACoreStartVideoLog")
    set(_new "#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)\nstatic void _GBACoreStartVideoLog")
    string(FIND "${MGBA_GBA_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GBA startVideoLog anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GBA_CORE_TEXT "${MGBA_GBA_CORE_TEXT}")

    set(_old [=[#ifndef MINIMAL_CORE
	core->startVideoLog = _GBACoreStartVideoLog;
	core->endVideoLog = _GBACoreEndVideoLog;
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
	core->startVideoLog = _GBACoreStartVideoLog;
	core->endVideoLog = _GBACoreEndVideoLog;
#endif]=])
    string(FIND "${MGBA_GBA_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GBA video-log assignment anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GBA_CORE_TEXT "${MGBA_GBA_CORE_TEXT}")
    file(WRITE "${MGBA_GBA_CORE_C}" "${MGBA_GBA_CORE_TEXT}")
endif()

string(FIND "${MGBA_GB_CORE_TEXT}" "MGBA_ANDROID_VIDEO_LOG_V073_GB" _mvl_gb_patched)
if(_mvl_gb_patched EQUAL -1)
    set(_old "#ifndef MINIMAL_CORE\n\tstruct GBVideoProxyRenderer proxyRenderer;")
    set(_new "#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)\n\t/* MGBA_ANDROID_VIDEO_LOG_V073_GB: official recording proxy state. */\n\tstruct GBVideoProxyRenderer proxyRenderer;")
    string(FIND "${MGBA_GB_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GB video-log struct guard anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GB_CORE_TEXT "${MGBA_GB_CORE_TEXT}")

    set(_old [=[#ifndef MINIMAL_CORE
	gbcore->logContext = NULL;
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
	gbcore->logContext = NULL;
#endif]=])
    string(FIND "${MGBA_GB_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GB video-log init anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GB_CORE_TEXT "${MGBA_GB_CORE_TEXT}")

    set(_old [=[#ifndef MINIMAL_CORE
	gbcore->proxyRenderer.logger = NULL;
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
	gbcore->proxyRenderer.logger = NULL;
#endif]=])
    string(FIND "${MGBA_GB_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GB video-log proxy-init anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GB_CORE_TEXT "${MGBA_GB_CORE_TEXT}")

    set(_old "#ifndef MINIMAL_CORE\nstatic void _GBCoreStartVideoLog")
    set(_new "#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)\nstatic void _GBCoreStartVideoLog")
    string(FIND "${MGBA_GB_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GB startVideoLog anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GB_CORE_TEXT "${MGBA_GB_CORE_TEXT}")

    set(_old [=[#ifndef MINIMAL_CORE
	core->startVideoLog = _GBCoreStartVideoLog;
	core->endVideoLog = _GBCoreEndVideoLog;
#endif]=])
    set(_new [=[#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG)
	core->startVideoLog = _GBCoreStartVideoLog;
	core->endVideoLog = _GBCoreEndVideoLog;
#endif]=])
    string(FIND "${MGBA_GB_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.73: GB video-log assignment anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GB_CORE_TEXT "${MGBA_GB_CORE_TEXT}")
    file(WRITE "${MGBA_GB_CORE_C}" "${MGBA_GB_CORE_TEXT}")
endif()

# v0.78.1 — Official mGBA Video Log player on Android.
# The upstream player implementation is inside the same core.c files as the
# normal emulator but is hidden by MINIMAL_CORE. Expose only the VLP block;
# keep every unrelated desktop feature group disabled.
file(READ "${MGBA_GBA_CORE_C}" MGBA_GBA_CORE_TEXT)
file(READ "${MGBA_GB_CORE_C}" MGBA_GB_CORE_TEXT)

string(FIND "${MGBA_GBA_CORE_TEXT}" "MGBA_ANDROID_MVL_PLAYER_V0781_GBA" _mvl_player_gba_patched)
if(_mvl_player_gba_patched EQUAL -1)
    set(_old "#ifndef MINIMAL_CORE\nstatic void _GBAVLPStartFrameCallback")
    set(_new "#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG_PLAYER)\n/* MGBA_ANDROID_MVL_PLAYER_V0781_GBA: official read-only mVL player. */\nstatic void _GBAVLPStartFrameCallback")
    string(FIND "${MGBA_GBA_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.78.1: GBA VLP player anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GBA_CORE_TEXT "${MGBA_GBA_CORE_TEXT}")
    file(WRITE "${MGBA_GBA_CORE_C}" "${MGBA_GBA_CORE_TEXT}")
endif()

string(FIND "${MGBA_GB_CORE_TEXT}" "MGBA_ANDROID_MVL_PLAYER_V0781_GB" _mvl_player_gb_patched)
if(_mvl_player_gb_patched EQUAL -1)
    set(_old "#ifndef MINIMAL_CORE\nstatic void _GBVLPStartFrameCallback")
    set(_new "#if !defined(MINIMAL_CORE) || defined(MGBA_ANDROID_VIDEO_LOG_PLAYER)\n/* MGBA_ANDROID_MVL_PLAYER_V0781_GB: official read-only mVL player. */\nstatic void _GBVLPStartFrameCallback")
    string(FIND "${MGBA_GB_CORE_TEXT}" "${_old}" _pos)
    if(_pos EQUAL -1)
        message(FATAL_ERROR "mGBA Android v0.78.1: GB VLP player anchor changed")
    endif()
    string(REPLACE "${_old}" "${_new}" MGBA_GB_CORE_TEXT "${MGBA_GB_CORE_TEXT}")
    file(WRITE "${MGBA_GB_CORE_C}" "${MGBA_GB_CORE_TEXT}")
endif()
