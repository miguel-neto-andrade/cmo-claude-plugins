---
name: firmware-conventions
description: Use when writing, reviewing, refactoring, or scaffolding any embedded firmware project — STM32 (HAL/LL/CubeMX), ESP32 (ESP-IDF or Arduino core), nRF (Zephyr/nRF Connect), RP2040, AVR, or any other bare-metal/RTOS target. Captures the layered architecture (drivers → handlers → managers → features), naming, language rules (C / C++17 or later), build systems (CMake, PlatformIO, ESP-IDF, STM32CubeIDE), error handling, logging, RTOS guidance, and the formatting toolchain. Target-agnostic and product-agnostic.
---

# Firmware Conventions

Conventions for embedded firmware in C-Mo repositories — written to apply to **every** firmware project regardless of MCU, framework, or product domain. Target-agnostic: the same architecture applies to STM32, ESP32, nRF52, RP2040, and other MCUs, whether using HAL/LL, ESP-IDF, Arduino core, or Zephyr. Target-specific advice (HAL APIs, partition tables, linker scripts) lives near the bottom under **Target adapters**. Pair this skill with `firmware-testing` whenever you touch test code, and with `firmware-sensor-integration` whenever you wire a new sensor.

## Layered architecture (load-bearing — read first)

Every firmware project separates concerns into four layers. Code that does not fit a layer either belongs in `common/` or is misplaced.

```
┌─────────────────────────────────────────────────────────────────┐
│  features/        — one folder per use case; thin Command/      │
│                     orchestration objects. No hardware access.  │
├─────────────────────────────────────────────────────────────────┤
│  manager/         — business-logic state machines, scheduling,  │
│                     power policy. Talks to handlers, never to   │
│                     drivers or HAL directly.                    │
├─────────────────────────────────────────────────────────────────┤
│  hardware/        — handlers: abstraction layer over a peripheral│
│   <peripheral>/     (one folder per sensor / actuator / radio). │
│                     Owns the device state machine and exposes a │
│                     domain API (`startAcquisition`,             │
│                     `getBatteryLevel`). Depends on drivers.     │
├─────────────────────────────────────────────────────────────────┤
│  drivers/         — register-level access to a specific chip    │
│                     (LIS2DW12, BQ27421, …) and the MCU HAL/LL   │
│                     wrappers (HalGpio, HalI2c, HalAdc, …).      │
│                     The only layer that touches vendor headers. │
└─────────────────────────────────────────────────────────────────┘
                  ↑ generated / vendor code lives outside `src/`:
                  drivers/ at repo root, middlewares/, libraries/
```

### Rules

- **Dependencies only flow downward.** A driver must never `#include` a handler; a handler must never `#include` a manager; a manager must never `#include` a feature. A linter / pre-commit check that greps include directions is welcome.
- **The handler is the unit of mock.** Tests replace handlers (and the HAL utility classes) with mocks; everything above the handler runs unmodified in the host-side test build. See `firmware-testing`.
- **Every handler inherits from a small interface** (e.g. `HardwareHandler` with `startup()`, `activatePower()`, `deactivatePower()`). This gives the manager a uniform lifecycle and makes power policy a one-liner.
- **Drivers are virtual classes (C++) or function-pointer vtables (C)** so a `*Mock` can substitute them in tests. The vendor's C register-access functions stay in the driver `.cpp`; the public surface is the virtual class.
- **Cross-cutting code lives in `common/`** — `Command` base, `ServiceLocator`, `Utils`, primitive value objects like `Axis3`. No business logic.
- **Wire dependencies in `main`, never via singletons or globals.** Use a `ServiceLocator` (or constructor injection) so each handler/manager receives its collaborators explicitly. Greppable wiring, testable in isolation. Avoid Singleton — it hides the dependency graph and breaks host-side tests.
- **`features/` are Command objects**, one per BLE / UART / CLI request: `StartAcquisitionCommand`, `GetBatteryLevelCommand`, `SetUsernameCommand`. The communication layer parses bytes into a command; `Command::execute()` calls the right manager/handler and returns a `CommandResponse`. This keeps the protocol layer trivial and makes adding a new request a copy-paste of an existing feature folder.

### Reference layout

```
firmware/
├── CMakeLists.txt                    # or platformio.ini, or CMakePresets.json
├── drivers/                           # vendor / generated — STM32 HAL, ESP-IDF
│   ├── BQ25180/
│   ├── LIS2DW12/
│   └── STM32L4xx_HAL_Driver/
├── middlewares/                       # vendor stacks: BLE, FatFs, USB, FreeRTOS
├── libraries/                         # third-party reusable (CMSIS-DSP, lwIP)
├── src/
│   ├── Core/                          # generated startup, SystemClock, IRQs
│   ├── common/                        # Command, ServiceLocator, Utils
│   ├── hardware/                      # handlers + driver-class wrappers
│   │   ├── HardwareHandler.{hpp,cpp}  # base interface
│   │   ├── accelerometer/
│   │   │   ├── Accelerometer.{hpp,cpp}        # virtual driver class
│   │   │   └── AccelerometerHandler.{hpp,cpp} # abstraction layer
│   │   ├── battery/
│   │   ├── ble/
│   │   └── utils/                     # HalGpio, HalI2c, HalAdc, HalSai, Timer
│   ├── communication/                 # BLE / UART transport, message factory
│   ├── manager/                       # ManagerState, StateController, PowerManager
│   ├── features/                      # one folder per use case (Commands)
│   ├── algorithms/                    # DSP / ML — pure functions on buffers
│   ├── constants.h                    # compile-time configuration
│   └── main.cpp                       # wires everything via ServiceLocator
├── tests/                             # host-side GoogleTest — see firmware-testing
├── bootloader/                        # optional second-stage / DFU
├── docs/
└── data/                              # firmware-side configuration assets
```

ESP-IDF / Arduino variants:

- ESP-IDF: replace `Core/` with `main/` (entry point) and use `components/` for what STM32 calls `middlewares/`. The `drivers/ ↔ hardware/ ↔ manager/ ↔ features/` split is identical.
- Arduino-core: keep the `.ino` to a thin `setup()` / `loop()` that calls `Main::startup()` and a manager tick. Everything else lives in `src/` exactly as above.

## Language rules

### C++ projects (default for new firmware)

- **C++17 minimum.** Prefer C++20 when the toolchain supports it (GCC 11+ for ARM, GCC 12+ for Xtensa). `std::span`, `std::optional`, `[[nodiscard]]`, `if constexpr`, structured bindings — use them.
- **No exceptions, no RTTI** on bare-metal / FreeRTOS targets. Compile with `-fno-exceptions -fno-rtti`. Errors are returned as `enum class`, `std::optional<T>`, or a small `Result<T>` value type.
- **No dynamic allocation in hot paths.** `new` / `malloc` is acceptable only at startup, in initialization, or behind a documented allocator with a fixed pool. Buffers in interrupt handlers and acquisition loops are static or stack-allocated.
- **STL containers** — `std::vector` and `std::array` are fine *outside* ISRs / acquisition loops. Prefer `std::array<T, N>` when the size is known at compile time; reserve `std::vector` capacity at construction to avoid reallocations.
- **`constexpr` everything that can be.** Compile-time configuration > runtime branching on flash strings.
- **One class per file.** `Foo.hpp` + `Foo.cpp`. Header guards (`#ifndef FOO_HPP / #define FOO_HPP / #endif`) — `#pragma once` is allowed but not enforced; pick one per repo and stick to it.
- **`override` and `[[nodiscard]]`** on every virtual override and every getter. Compiler catches the slips.
- **Pointer parameters for non-owning collaborators** — `Handler(Driver *driver)`. Use `std::unique_ptr` only when the handler owns the lifetime (rare — main owns everything). No raw `new` outside `main`.

### C projects (ESP-IDF default, legacy STM32)

- **C11 minimum.** Use `_Static_assert`, designated initializers, `<stdint.h>`/`<stdbool.h>`.
- **One module per file pair** — `accelerometer.h` + `accelerometer.c`. Public functions get an `<module>_` prefix (`accelerometer_start`, `battery_get_level`). Static (file-local) helpers stay unprefixed.
- **Opaque struct handles** for module instances: declare `typedef struct accelerometer accelerometer_t;` in the header, define the layout in the `.c`. Callers pass `accelerometer_t *` around — they cannot poke at the internals.
- **Error returns are `esp_err_t`** on ESP-IDF, **`HAL_StatusTypeDef`** on STM32 HAL APIs, or a project-defined `cmo_err_t` enum elsewhere. Always check the return; never `(void)foo()` an error-returning function without a comment.
- **No exceptions, no setjmp/longjmp** outside vendor stacks.

## Naming

Pick one casing per language and apply it everywhere:

| Kind | C++ | C |
|---|---|---|
| Class / type | `PascalCase` (`AccelerometerHandler`) | `snake_case_t` (`accelerometer_t`) |
| Namespace / module | `PascalCase` (`Cmo::Hardware::Accelerometer`) | `snake_case` prefix |
| Public method / function | `camelCase` (`startAcquisition`) | `snake_case` with module prefix (`accelerometer_start_acquisition`) |
| Member variable | `camelCase` (`numberOfSamples`) | `snake_case` |
| Local variable | `camelCase` | `snake_case` |
| Compile-time constant | `UPPER_SNAKE_CASE` | `UPPER_SNAKE_CASE` |
| Macro | `UPPER_SNAKE_CASE` | `UPPER_SNAKE_CASE` |
| File | matches the class (`AccelerometerHandler.hpp`) | matches the module (`accelerometer.c`) |

Rules that apply regardless of language:

- **No abbreviations** except universally understood domain terms (`i2c`, `gpio`, `adc`, `dma`, `irq`, `rtc`, `crc`, `pwm`, `fft`). `acquisition` not `acq`; `temperature` not `temp`; `battery` not `bat`.
- **No negated booleans** — `isInitialized` not `isNotInitialized`. Negate at the call site if you must.
- **Verb prefixes on actions** — `start*`, `stop*`, `enable*`, `disable*`, `get*`, `set*`, `is*`, `has*`. Pair complements: `acquire`/`release`, `lock`/`unlock`, `attach`/`detach`.
- **English everywhere** — identifiers, comments, log messages, register-bit names.
- **No `m_` / `_` prefixes on members** in C++. The class context disambiguates. In C, a trailing `_` on file-local statics is acceptable but not required.
- **Macros that aren't compile-time constants get a project prefix** — `CMO_ASSERT(...)`, `CMO_LOG_INFO(...)`. Bare `ASSERT` and `LOG_INFO` collide with vendor SDKs.
- **No shadowing of vendor / stdlib names.** No `min`, `max`, `printf`, `i2c_read` as local identifiers.

## Comments and documentation

- **Doxygen-style block comments on public headers** (`/** ... */` for C++ classes/methods, `/** ... */` over each `<module>_*` function in C). Brief description, `@param`, `@return`. Skip on trivial getters when the name is self-evident.
- **Implementation comments explain WHY.** Restating what the code does is noise — delete the comment and rename instead.
- **Workarounds always carry a ticket / datasheet reference.** Examples:
  - `// Errata 2.7.4 (STM32L4 ES0394) — keep ADC clock at 80MHz to avoid jitter.`
  - `// Datasheet §6.1.3: must wait 7 ms after RESET before reading WHO_AM_I.`
- **No file-header banners** beyond a one-line description (`/** Handles the accelerometer hardware. */`). The author/date/copyright belongs in `LICENSE`, not in every file.
- **Magic numbers from datasheets get named constants** — `constexpr uint8_t WHO_AM_I_VALUE = 0x44;` not `if (id == 0x44)`.

## Error handling

- **Never silently ignore a return value from a driver or HAL call.** Check it; either propagate, log + recover, or assert in debug builds. `(void)foo()` is acceptable only with a one-line comment explaining why.
- **Return error codes, don't throw.** On C++ targets without exceptions, use:
  - `bool` for binary success/failure on simple actions (`bool startAcquisition()`).
  - `std::optional<T>` when "absent" is a legitimate result (`std::optional<float> getTemperature()`).
  - A small `enum class` (`enum class BleError : uint8_t { Ok, Timeout, NotConnected, … }`) when callers need to branch on the failure type.
  - A reusable `Result<T, E>` template only when the codebase has multiple call sites that need both a value and an error reason.
- **Validate at boundaries.** Any byte coming off BLE / UART / SD card is untrusted — parse into a typed `Command` or value object before passing it deeper. The `Command` base class in `common/` is the single boundary for incoming messages.
- **`assert`s catch programmer errors only**, never user / environment failures. Use the vendor's `configASSERT` (FreeRTOS) or a project `CMO_ASSERT` that is a no-op in release builds. A failed I²C read is a runtime condition, not an assert.
- **Watchdog policy is explicit.** Every long-running loop documents whether it kicks the watchdog. Don't rely on "the main loop kicks it" — be specific.

## Concurrency / interrupts / RTOS

- **ISRs are short.** Capture data into a queue / lock-free ring buffer and exit. No `printf`, no I²C transactions, no `vTaskDelay`. Move work to a task / main loop.
- **Shared state between ISR and main code is `volatile` and protected** — by a critical section (`__disable_irq` / `taskENTER_CRITICAL`), atomic, or a queue. A plain global counter is a bug.
- **One owner per peripheral.** The handler owns its I²C bus reference; no other code touches that bus. If two handlers share a bus, route through a single arbitration layer.
- **FreeRTOS / Zephyr task priorities are documented in one place** — `constants.h` or `tasks.h`. Don't sprinkle priority numbers across files.
- **Power management is a manager concern, not a driver concern.** Drivers expose `activatePower()` / `deactivatePower()`; the `PowerManager` decides when to call them based on device state.

## Logging

- **Use the project / RTOS logger** (`ESP_LOGI`, `LOG_INF` on Zephyr, `printf`-over-ITM on STM32 Cortex-M, or a small `CMO_LOG_*` wrapper). Never raw `printf` in production code paths.
- **Levels follow the same semantics as the cloud:** `TRACE` / `DEBUG` for development; `INFO` for state transitions worth tracing in the field; `WARN` for recoverable anomalies; `ERROR` for failed operations; `FATAL` for system reset paths.
- **Never log secrets** — pairing keys, encryption material, user identifiers that are PII.
- **Strip / gate logs by build flavor.** Release firmware should compile with `LOG_LEVEL_WARN` minimum; debug builds open up to `TRACE`. Don't `#ifdef DEBUG` around individual `printf`s — let the logger filter.
- **No floating-point format specifiers (`%f`) on bare metal without verifying** the printf implementation supports them. Newlib-nano omits float by default — link with `-u _printf_float` if you need it.

## Memory and performance

- **Stack budget per task is sized and documented.** FreeRTOS task creation passes the stack size; that number is a constant in `constants.h`, not a literal scattered in `xTaskCreate` calls.
- **Static buffers over dynamic.** Acquisition buffers, BLE rings, SD-card sector buffers — all `static` or `std::array` with size known at compile time.
- **DMA buffers are aligned, in non-cached SRAM, and never on the stack.** Comment the alignment requirement.
- **Avoid `std::function` in hot paths** — type-erased lambdas allocate on capture and dispatch via virtual call. Use function pointers or templated callbacks instead.
- **Inline only when it matters.** Trust the compiler for everything else; `inline` on a 50-line method bloats flash for no win.

## Headers, includes, and dependencies

- **Forward-declare in headers** when a pointer/reference is all the header needs. Saves transitive `#include` weight.
- **Include order: own header → project headers → vendor headers → STL/C stdlib.** clang-format's `IncludeCategories` should enforce this — don't rearrange by hand.
- **No circular includes** between layers. If `manager/X.hpp` includes `features/Y.hpp`, the architecture is upside-down; refactor.
- **Vendor headers stay behind a thin wrapper.** `HalGpio`, `HalI2c`, `HalAdc` wrap STM32 HAL or ESP-IDF `gpio_set_level` / `i2c_master_write_to_device`. Application code never `#include <stm32l4xx_hal.h>` outside `hardware/utils/`.

## Build, format, lint

| Concern | Tool / preset |
|---|---|
| Build (STM32, generic CMake) | **CMake ≥ 3.22**, presets for Debug / Release / Test |
| Build (cross-target / multiple boards) | **PlatformIO** with `platformio.ini` environments |
| Build (ESP32) | **ESP-IDF** (`idf.py build`) — already CMake under the hood |
| Build (nRF / Zephyr) | **west** + Zephyr CMake |
| Format | **clang-format** — `.clang-format` checked into repo root, `BasedOnStyle: LLVM`, `IndentWidth: 4`, `ColumnLimit: 120` |
| Static analysis | **clang-tidy** (CI-only is fine), **cppcheck** for C-heavy repos, **MISRA-C** checks where regulatory scope demands |
| Lint | `make lint` runs `clang-tidy --warnings-as-errors=* -p build/`; CI re-runs |
| Coverage (host-side tests) | **gcov** + **lcov** or **gcovr** |
| Pre-commit | `clang-format --dry-run --Werror` + `commitlint` for conventional commits |

Run before pushing:

```
make format        # clang-format -i over src/, drivers wrappers, tests
make lint          # clang-tidy + cppcheck
make build         # default board / config
make build_tests   # host-side GoogleTest build (see firmware-testing)
make test          # ctest --output-on-failure
```

CI runs the same `make` targets. Warnings are errors (`-Werror -Wall -Wextra -Wpedantic -Wshadow -Wconversion`).

### CMake hygiene

- **`target_*` everything.** No directory-level `include_directories()` / `add_definitions()` — they leak to siblings.
- **One `CMakeLists.txt` per source folder.** `add_subdirectory(hardware)` from the top, each subfolder defines its own `add_library(... STATIC ...)`.
- **Two top-level executables**: production firmware (cross-compiled, MCU toolchain) and host-side tests (native toolchain, no HAL). Tests `#include` source files via globs and substitute mock HAL/driver headers via `include_directories` precedence — see `firmware-testing`.
- **No `file(GLOB ...)` for production sources** unless the build also re-runs CMake on file changes (`CONFIGURE_DEPENDS` helps but is fragile). Explicit `target_sources` is the rule for the firmware target; the tests target may use `GLOB_RECURSE` because the test list is intentionally inclusive.

## Compile-time configuration flags

- Feature flags go in `constants.h` or a CMake `target_compile_definitions` call. Never a global mutable variable.
- Document each flag at the top of `constants.h` with one line: name, effect, default, who owns it.
- Multi-board projects use **PlatformIO `[env:*]`** sections or **CMake presets** — never `#ifdef BOARD_X` scattered across the codebase.

## Versioning, releases, OTA

- **Semantic versioning** on the firmware binary: `MAJOR.MINOR.PATCH`. Major bumps when the BLE protocol or persisted memory layout changes.
- **Build embeds the git short SHA** into a string the device can report over BLE / serial. CI fails if the working tree is dirty for a release build.
- **OTA / FOTA images carry a CRC and version header.** The bootloader rejects a downgrade unless the manager explicitly allows it. Recovery path is documented in `bootloader/README.md`.

## Documentation

- `README.md` at the repo root — what the firmware does, supported boards, how to build, how to flash, where the linker scripts live.
- `docs/` for architecture notes (state machines, BLE service definitions, power profiles).
- `CHANGELOG.md` (keepachangelog format) — every release bumps it. Conventional commits feed `lerna`/`standard-version` if you want to automate.

## Target adapters

### STM32 (HAL or LL)

- CubeMX-generated code lives under `src/Core/` and `drivers/STM32xxx_HAL_Driver/`. **Treat it as vendor code** — regenerate via CubeMX, don't hand-edit, never commit auto-rewrites of `Core/Src/*.c` without re-running CubeMX.
- HAL access goes through `hardware/utils/HalGpio`, `HalI2c`, `HalAdc`, `HalSai`, `HalTimer` thin wrappers — virtual classes whose only job is to be mockable. Application code never `#include "stm32l4xx_hal.h"` outside those wrappers.
- Linker scripts (`*.ld`) live at the firmware root; bootloader projects add a second linker script for the application slot.
- ITM / SWO for printf debug, JTAG / SWD for flashing. STM32CubeIDE or CLion + OpenOCD as the dev environments.

### ESP32 (ESP-IDF)

- `main/` is the entry point; `components/` houses what STM32 calls `middlewares/`. Each component has its own `CMakeLists.txt` with `idf_component_register(... INCLUDE_DIRS ... REQUIRES ...)`.
- Configure via `idf.py menuconfig` — checked-in `sdkconfig.defaults`, not a hand-edited `sdkconfig`.
- FreeRTOS is built-in; use ESP-IDF's `xTaskCreatePinnedToCore` to bind tasks to cores when the workload is core-sensitive.
- Logging: `ESP_LOGI(TAG, "...")`. Component tag = component name in `UPPER_SNAKE`.

### ESP32 / AVR (Arduino core)

- `setup()` / `loop()` stay tiny — call `Main::startup()` and a single `manager.tick()`.
- The PlatformIO `framework = arduino` env handles board selection. `lib_deps` for external libraries — never copy a library's source into the repo.
- The drivers/handlers/managers/features split applies unchanged; Arduino code lives under `src/` exactly like the STM32 layout.

### nRF52 / nRF53 (Zephyr / nRF Connect)

- Module split via Zephyr's `west.yml` and per-module `CMakeLists.txt`. Devicetree overlays per board.
- `LOG_MODULE_REGISTER(<module>, CONFIG_<MODULE>_LOG_LEVEL)` per file; gate via Kconfig.
- The driver layer often disappears (Zephyr's `device.h` API replaces it) — keep handlers and managers; let drivers/ degenerate into a thin Zephyr-device adapter.

## Anti-patterns (always reject in review)

- A driver `#include`s a handler, manager, or feature header.
- A handler `#include`s `stm32l4xx_hal.h` (or any vendor header) directly.
- A manager flips a GPIO directly instead of going through a handler.
- A feature `Command` calls into the HAL or driver layer.
- A Singleton or global `instance` is added to bypass the `ServiceLocator` / explicit wiring.
- `new` / `malloc` in an acquisition loop or ISR.
- A blocking call inside an ISR.
- `printf` left in production code paths without a logger gate.
- Magic numbers from a datasheet inlined without a named constant + datasheet section reference.
- A feature flag introduced via `#ifdef` in five files instead of one CMake / `constants.h` switch.
- `using namespace` at file scope in headers.
- A vendor header copy-pasted into `libraries/` instead of pinned via a package manager / submodule with a version.

## Quick reference

| Aspect | Rule |
|---|---|
| Layered architecture | drivers → handlers → managers → features. Includes only flow downward. |
| Mock seam | Replace handlers + HAL utility classes; everything above runs unchanged on the host. |
| Dependency wiring | Constructor-injected via `ServiceLocator` in `main`; no Singletons or globals. |
| C++ standard | C++17 minimum, C++20 when toolchain allows. `-fno-exceptions -fno-rtti` on bare metal. |
| C standard | C11. Opaque struct handles. Module-prefixed public functions. |
| Dynamic allocation | Startup-only or behind a fixed pool; never in ISRs or acquisition loops. |
| Error model | Return codes / `std::optional` / `Result<T, E>` — never throw. Check every driver return. |
| Naming | `PascalCase` types, `camelCase` methods (C++); `snake_case_t` types, `module_action` functions (C). |
| Headers | One class/module per pair; forward-declare; include order via clang-format. |
| Build | CMake ≥ 3.22 with presets, or PlatformIO, or ESP-IDF. Two top targets: firmware + host-side tests. |
| Format | clang-format, LLVM base, indent 4, column 120. `make format` clean before push. |
| Lint | clang-tidy + cppcheck. Warnings are errors. |
| Logging | RTOS / project logger only; level-gated by build flavor; never log secrets. |
| ISRs | Short — capture and exit. No printf, no I²C, no delay. |
| Power | Drivers expose `activatePower/deactivatePower`; the manager decides when. |
| Vendor headers | Behind thin wrappers in `hardware/utils/` — never `#include "stm32..."` in app code. |
| Magic numbers | Always a named constant + datasheet section reference. |
| Testing | Host-side GoogleTest with handler-level mocks. See `firmware-testing`. |
| Sensor integration | Datasheet-first workflow. See `firmware-sensor-integration`. |
| Release builds | Embed git SHA; semver; CRC-protected OTA images with downgrade gating. |
