---
name: firmware-testing
description: Use when writing, reviewing, or scaffolding tests for any embedded firmware project — STM32, ESP32, nRF, RP2040, AVR, or any MCU target built with CMake / PlatformIO / ESP-IDF / west. Captures the host-side integration-test pattern (GoogleTest + gmock), the hardware-mock seam (driver / handler / HAL mocks), test layout mirroring src/, fixture-driven algorithm tests, requirement traceability, and the CI gate. Target-agnostic and product-agnostic. Pairs with `firmware-conventions` for the layered architecture this testing strategy assumes, and `firmware-sensor-integration` for the bring-up artifacts each peripheral test must cover.
---

# Firmware Testing

Firmware tests run on the **host machine** (your dev laptop and CI), not on the MCU. They compile the production source against a substituted HAL and a set of driver mocks, then exercise the handlers / managers / features through GoogleTest. The MCU is only involved during bring-up (`firmware-sensor-integration`) and during functional / on-device QA — never inside the unit-test loop.

This is intentional: every PR should be runnable through `make test` in under a minute on a dev machine, with no JTAG, no board, and no Docker. Tests that need real silicon do not belong in this tier.

## Test pyramid

| Tier | Where | Stack | What it covers |
|---|---|---|---|
| **Unit (algorithm)** | `tests/algorithms/`, `tests/common/` | GoogleTest, no mocks | Pure functions: DSP, filtering, parsers, value objects. Often fixture-driven from JSON. |
| **Integration (handler)** | `tests/hardware/<peripheral>/` | GoogleTest + gmock, **driver mock + HAL mock** | One handler with its driver + HAL collaborators substituted. The workhorse tier. |
| **Integration (manager / feature)** | `tests/manager/`, `tests/features/` | GoogleTest + gmock, **handler mocks** | Business logic against substituted handlers. State machines, Command execution, power policy. |
| **End-to-end (on-device QA)** | external | manual / scripted bench tests | Boots real firmware on real silicon; logged in bring-up notes. **Not** part of `make test`. |

Loading this skill means: every PR that touches firmware code adds or updates tests at the appropriate tier; the build fails if `make test` fails; the build fails if coverage on touched files drops.

## Hard rules (apply to every test, every project)

- **`TEST` not `TEST_F` unless you actually share fixtures.** Each test owns its mocks; copying setup is fine in a small file.
- **Every test method carries a `RecordProperty("Requirement", "SW-XXXX")`** when the project tracks requirements (regulated firmware — medical, automotive, aerospace, industrial). Same role as the .NET `[Trait(Traits.Requirement, ...)]`: this is the audit-trail link from test back to a tracker ticket (Jira / Azure DevOps / Linear / wherever requirements live).
- **Test file path mirrors the src file path.** `src/hardware/accelerometer/AccelerometerHandler.cpp` → `tests/hardware/accelerometer/AccelerometerHandlerTest.cpp`. Same rule for `src/manager/AcquisitionManagerState.cpp` → `tests/manager/AcquisitionManagerStateTest.cpp`.
- **Test class / suite name = `<Subject>Test`** (singular). Test method name = `Should<DoSomething>` or `Should<DoSomething>When<Condition>` (`ShouldStartAcquisition`, `ShouldReturnZeroSamplesWhenFifoEmpty`).
- **No real hardware, no real RTOS scheduler.** Tests link the production source against host-compiled mocks. If a test needs `vTaskDelay`, mock the time source — don't sleep.
- **No flaky tests.** A test that "sometimes passes" is a bug in the test or the code. Fix the race; don't `EXPECT_NEAR` your way out of it.
- **One logical assertion per test where practical.** Multiple `EXPECT_*` lines are fine if they verify the same outcome.

## Test project layout

```
tests/
├── CMakeLists.txt
├── main.cpp                    # GoogleTest entry; sets gmock policy, runs the suite
├── fixtures/                   # JSON / CSV golden data for algorithm tests
├── mocks/
│   ├── hal/                    # HalGpioMock, HalI2cMock, HalAdcMock, HalSaiMock, HalTimerMock
│   ├── drivers/                # BQ27421Mock, LIS2DW12Mock, flash_mock.h — one per driver class
│   ├── hardware/               # AccelerometerHandlerMock, BatteryHandlerMock, … (mocks of the handler virtuals)
│   ├── algorithms/             # mocks for pure-class collaborators when needed
│   ├── manager/                # ManagerStateControllerMock, PowerManagerMock
│   ├── headers/                # stub headers shadowing vendor headers (main.h, stm32xxxx_hal.h, …)
│   └── libraries/              # stubs for FatFs, BlueNRG-2, ESP-IDF subsystems
├── algorithms/                 # tests for `src/algorithms/`
├── common/                     # tests for `src/common/`
├── communication/              # tests for `src/communication/`
├── features/                   # tests for `src/features/`
├── hardware/                   # tests for `src/hardware/`
├── manager/                    # tests for `src/manager/`
└── libraries/                  # tests for project-side library wrappers
```

`tests/CMakeLists.txt` does four things:

1. Pulls in **GoogleTest** (and **nlohmann_json** if the project uses JSON fixtures) via `FetchContent`. Pin to a known good tag (`v1.14.0` or later); do **not** track `main`.
2. Adds the **mocks/** subdirectories to the include path **before** the vendor include paths, so a test compilation unit picks up `main.h` from `tests/mocks/headers/` instead of the CubeMX-generated one.
3. Builds **one test executable** per build configuration (the project's `Debug`/`Release`/`Test` config). Coverage flags (`--coverage -O0`) on the test config.
4. Calls `gtest_discover_tests(...)` so CTest picks up every `TEST(...)` automatically.

Example:

```cmake
project(<project-name>-test C CXX ASM)

include(FetchContent)
FetchContent_Declare(googletest    GIT_REPOSITORY https://github.com/google/googletest.git  GIT_TAG v1.14.0)
FetchContent_Declare(nlohmann_json GIT_REPOSITORY https://github.com/nlohmann/json.git      GIT_TAG v3.11.3)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest nlohmann_json)

include_directories(
    ${FIRMWARE_SOURCE_DIR}/tests/algorithms
    ${FIRMWARE_SOURCE_DIR}/tests/libraries
    ${FIRMWARE_SOURCE_DIR}/tests/features
    ${FIRMWARE_SOURCE_DIR}/tests/mocks/headers     # shadows main.h, vendor headers
    ${FIRMWARE_SOURCE_DIR}/tests/mocks/hal
    ${FIRMWARE_SOURCE_DIR}/tests/mocks/drivers
    ${FIRMWARE_SOURCE_DIR}/tests/mocks/hardware
    ${FIRMWARE_SOURCE_DIR}/tests/mocks/manager
    ${FIRMWARE_SOURCE_DIR}/tests/mocks/algorithms
    ${FIRMWARE_SOURCE_DIR}/tests/mocks/libraries/FATFS
    ${FIRMWARE_SOURCE_DIR}/tests/mocks/libraries/BlueNRG-2
)

file(GLOB_RECURSE EXECUTABLE_TESTS_SOURCES "*.cpp" "*.hpp")

add_compile_options(--coverage -O0)
add_link_options(--coverage)

add_executable(${CMAKE_BUILD_TYPE} ${SOURCES} ${EXECUTABLE_TESTS_SOURCES} ${LINKER_SCRIPT})

# Pass fixture paths through compile defs so tests can locate goldens.
target_compile_definitions(${CMAKE_BUILD_TYPE} PRIVATE
    FIXTURES_DIR="${FIRMWARE_SOURCE_DIR}/tests/fixtures")

target_link_libraries(${CMAKE_BUILD_TYPE} GTest::gtest_main GTest::gmock_main nlohmann_json::nlohmann_json)

enable_testing()
include(GoogleTest)
gtest_discover_tests(${CMAKE_BUILD_TYPE})
```

The top-level `CMakeLists.txt` selects between firmware build and test build via the active configuration / preset. Two binaries, two toolchains, one source tree.

## The mock seam — how it actually works

Production code lives at three vertical positions in the dependency stack (`firmware-conventions` describes the architecture). The seam where tests inject mocks depends on what's under test:

| Under test | Replace | Leave real |
|---|---|---|
| **Handler** (`AccelerometerHandler`) | Driver class (`Accelerometer` → `AccelerometerMock`), HAL utilities (`HalGpio` → `HalGpioMock`) | The handler itself, `common/` value objects |
| **Manager** (`AcquisitionManagerState`) | All handlers (`AccelerometerHandler` → `AccelerometerHandlerMock`), `ServiceLocator` | The manager itself, `Command` base, value objects |
| **Feature command** (`StartAcquisitionCommand`) | The relevant handler mocks and `ManagerStateController` mock | The command itself |
| **Algorithm** (`SignalQualityAssessor`) | Nothing — algorithms are pure functions on buffers | Everything |

This works because **every handler inherits from a virtual base** (`HardwareHandler` and its own public-virtual methods), and **every driver wraps the vendor's register library in a virtual class**. The mocks are gmock `MOCK_METHOD` subclasses; the real implementation lives in `src/`.

### Driver mock (`tests/mocks/drivers/`)

```cpp
#ifndef BQ27421MOCK_HPP
#define BQ27421MOCK_HPP
#include "BQ27421.hpp"
#include "gmock/gmock.h"

class BQ27421Mock : public BQ27421 {
public:
    MOCK_METHOD(bool,     setCapacity,     (uint16_t capacity),         (override));
    MOCK_METHOD(uint16_t, getVoltage,      (),                          (override));
    MOCK_METHOD(int16_t,  getCurrent,      (current_measure type),      (override));
    MOCK_METHOD(uint16_t, getDeviceType,   (),                          (override));
    MOCK_METHOD(uint16_t, getStateOfCharge,(soc_measure type),          (override));
    MOCK_METHOD(uint8_t,  getStateOfHealth,(soh_measure type),          (override));
    MOCK_METHOD(uint16_t, flags,           (),                          (override));
    MOCK_METHOD(bool,     isBattery435VEnabled, (),                     (override));
    MOCK_METHOD(uint16_t, getCapacity,     (capacity_measure type),     (override));
};
#endif
```

One `MOCK_METHOD` line per virtual function on the driver. If the driver class adds a method, the mock must add a line — or the test won't compile, which is exactly the behavior we want.

### HAL mock (`tests/mocks/hal/`)

```cpp
#ifndef HALGPIOMOCK_HPP
#define HALGPIOMOCK_HPP
#include "HalGpio.hpp"
#include "gmock/gmock.h"

class HalGpioMock : public Cmo::Hardware::Utils::HalGpio {
public:
    MOCK_METHOD(void, WritePin,
                (GPIO_TypeDef *GPIOx, uint16_t GPIO_Pin, GPIO_PinState PinState),
                (override));
};
#endif
```

The HAL wrappers are thin (`firmware-conventions` keeps them that way precisely so the mocks are trivial).

### Vendor-header shadow (`tests/mocks/headers/`)

The handler's `.cpp` `#include`s `main.h` (CubeMX-generated pin / port macros) and indirectly pulls in `stm32l4xx_hal.h`. The test target can't compile against the real CubeMX headers on the host. Solution: a stub `tests/mocks/headers/main.h` that defines only the symbols the tests need (`ACC_ON_GPIO_Port`, `ACC_ON_Pin`, the `GPIO_TypeDef *` typedef, the `GPIO_PinState` enum). Include paths put `tests/mocks/headers/` **before** `drivers/STM32xxxx_HAL_Driver/Inc/`, and the host build picks up the stub.

ESP-IDF analogue: stub headers for `driver/gpio.h`, `driver/i2c.h`, `esp_err.h`, `freertos/FreeRTOS.h`, with just enough typedefs and macros to compile.

## Pattern — handler test

The bread and butter. Each test instantiates the handler with mocks, sets `EXPECT_CALL` expectations matching what the datasheet says should happen, then calls the public method.

```cpp
#include "AccelerometerHandler.hpp"
#include "AccelerometerMock.hpp"
#include "HalGpioMock.hpp"
#include "Timer.hpp"
#include "main.h"

#include <gtest/gtest.h>

using Cmo::Hardware::Accelerometer::AccelerometerHandler;
using testing::_;
using testing::DoAll;
using testing::Return;
using testing::SetArgPointee;
using testing::SetArrayArgument;

TEST(AccelerometerHandlerTest, ShouldActivatePowerOnStartup) {
    RecordProperty("Requirement", "SW-1534");
    HalGpioMock         halMock;
    AccelerometerMock   accelerometerMock;

    EXPECT_CALL(halMock,          WritePin(ACC_ON_GPIO_Port, ACC_ON_Pin, GPIO_PIN_SET));
    EXPECT_CALL(accelerometerMock, getDeviceId(_, _))
        .WillOnce(DoAll(SetArgPointee<1>(LIS2DW12_ID), Return(0)));
    EXPECT_CALL(accelerometerMock, setReset(_, PROPERTY_ENABLE));
    EXPECT_CALL(accelerometerMock, getReset(_, _))
        .WillOnce(DoAll(SetArgPointee<1>(0), Return(0)));
    EXPECT_CALL(accelerometerMock, setAutoIncrement(_, PROPERTY_ENABLE));
    EXPECT_CALL(accelerometerMock, setUpdateDataBlock(_, PROPERTY_ENABLE));

    AccelerometerHandler handler(&halMock, &accelerometerMock);

    handler.startup();
}
```

Test reads like a contract: "on startup we set this GPIO, verify WHO_AM_I, soft-reset, then poll the reset bit, then enable auto-increment and block-data-update". If the datasheet says to do something else, the handler and this test both change.

## Pattern — buffer / FIFO test

When the handler reads samples from a FIFO, the test seeds the mock with a known byte pattern and asserts on the converted output.

```cpp
TEST(AccelerometerHandlerTest, ShouldGetAccelerometerData) {
    RecordProperty("Requirement", "SW-241");
    HalGpioMock        halMock;
    AccelerometerMock  accelerometerMock;

    constexpr uint16_t numberOfSamples = 2;
    constexpr uint8_t  accData01[6] = {1, 0, 2, 0, 3, 0};
    constexpr uint8_t  accData02[6] = {7, 0, 8, 0, 9, 0};

    EXPECT_CALL(accelerometerMock, getFifoDataLevel(_, _))
        .WillOnce(DoAll(SetArgPointee<1>(numberOfSamples), Return(0)));
    EXPECT_CALL(accelerometerMock, getAccelerationRaw(_, _))
        .WillOnce(DoAll(SetArrayArgument<1>(accData01, accData01 + 6), Return(0)))
        .WillOnce(DoAll(SetArrayArgument<1>(accData02, accData02 + 6), Return(0)));
    EXPECT_CALL(accelerometerMock, fromFs2ToMg(_))
        .WillRepeatedly([](int16_t v) { return v * 10; });

    AccelerometerHandler handler(&halMock, &accelerometerMock);
    const auto data = handler.getAccelerometerData();

    EXPECT_EQ(data.size(), 10u);
    EXPECT_EQ(data[4], 10);
    EXPECT_EQ(data[9], 90);
}
```

Note: the test asserts both the converted samples **and** the embedded timestamp / size metadata. Anything the datasheet says about the FIFO becomes a `WillOnce` shape; anything the handler does with the bytes becomes an `EXPECT_EQ`.

## Pattern — manager test with handler mocks

State-machine tests mock the handlers, not the drivers. The seam is one layer up.

```cpp
TEST(AcquisitionManagerStateTest, ShouldStartAccelerometerAndMicrophoneOnEnter) {
    RecordProperty("Requirement", "SW-241");

    AccelerometerHandlerMock acc;
    MicrophoneHandlerMock    mic;
    MemoryHandlerMock        mem;
    ServiceLocator           locator;
    locator.registerInstance<AccelerometerHandlerMock>(&acc);
    locator.registerInstance<MicrophoneHandlerMock>(&mic);
    locator.registerInstance<MemoryHandlerMock>(&mem);

    EXPECT_CALL(acc, activatePower());
    EXPECT_CALL(acc, startAcquisition());
    EXPECT_CALL(mic, activatePower());
    EXPECT_CALL(mic, startAcquisition());

    AcquisitionManagerState state(&locator);
    EXPECT_TRUE(state.enter());
}
```

This is why every handler exposes a virtual public surface: it lets the manager run against substitutes without inventing parallel abstractions.

## Pattern — algorithm / pure-function test with JSON fixtures

DSP, ML inference, parsers — anything that's a pure function of input bytes. Stash golden inputs and expected outputs as JSON under `tests/fixtures/`, parse with `nlohmann::json`, run the function, compare.

```cpp
TEST(SignalQualityAssessorTest, ShouldClassifyArtifactSamples) {
    nlohmann::json fixture;
    std::ifstream(std::string(FIXTURES_DIR) + "/siqa-pm_pm_ON-ART_003_cpp_io.json") >> fixture;

    std::vector<float> input  = fixture["input"];
    std::vector<int>   expect = fixture["expected"];

    SignalQualityAssessor sut;
    auto actual = sut.classify(input);

    EXPECT_EQ(actual, expect);
}
```

Fixture files are committed and reviewed alongside the code. When the algorithm changes, the diff in the fixture is the change — that's the whole point.

## Requirement traceability

For regulated firmware, every `TEST(...)` carries a `RecordProperty("Requirement", "SW-XXXX")` where `SW-XXXX` is a Jira ticket. GoogleTest writes this into the JUnit XML output, which the CI pipeline ships to the audit-trail tooling.

Rules:

- Use the **same key** (`"Requirement"`) everywhere — don't invent `"REQ"`, `"Ticket"`, `"req-id"` variants.
- One requirement per test. If a test verifies behavior shared across multiple tickets, list them as a comma-separated string (`"SW-1534,SW-241"`) — or, better, split the test.
- Tests that exist for CI / dev hygiene (route sanity, log-leak detection) use a sentinel like `"SW-INFRA"`.

## Time, randomness, and other non-determinism

- **Time** — handlers that depend on wall clock take a `Timer` (or RTOS tick) injection point. The test provides a fake that returns whatever the test wants.
- **Random** — same pattern. Inject the source.
- **FreeRTOS** — link against a stub `freertos.h` that defines `vTaskDelay` as a no-op (or as a hook the test can verify was called). The production scheduler does not run inside the test process.
- **ISRs** — call the ISR function directly from the test, with the data the ISR would have seen on real hardware.

## CI gate

| Workflow step | What it runs |
|---|---|
| `make format` (`--dry-run --Werror`) | Reject unformatted source. |
| `make lint` | clang-tidy + cppcheck. |
| `make build` | Cross-compiled firmware build (default board / configuration). |
| `make build_tests` | Host-side test build. |
| `make test` | `ctest --output-on-failure --no-tests=error` on the test binary. |
| Coverage report | gcov + lcov / gcovr. Coverage on touched files must not drop. |
| JUnit XML upload | The `RecordProperty` traces feed the audit trail. |

Every PR runs every step. A failing step is a blocker; flaky steps are bugs, not "retry-able".

## Anti-patterns (always reject in review)

- A handler test that talks to real hardware (e.g. `#include "stm32l4xx_hal.h"` directly).
- A test that calls `usleep` / `std::this_thread::sleep_for` to "wait for the device".
- A `MOCK_METHOD` line missing from a mock after the driver added a new virtual — the test compiles but silently misses coverage.
- A manager test that mocks drivers instead of handlers. The seam is one level too low; refactor.
- `EXPECT_CALL(...).Times(testing::AnyNumber())` used to silence "uninteresting call" warnings. Either the call should happen or it shouldn't — be explicit.
- Tests without `RecordProperty("Requirement", ...)` in a regulated firmware project.
- A test that depends on the order it runs in (relies on static state set by an earlier `TEST`).
- `file(GLOB ...)` over production source while the firmware build uses explicit `target_sources` — test discovery silently drifts from what the firmware actually builds.
- A "smoke test" that just instantiates the handler and asserts nothing. Either assert on behavior or delete it.

## Quick reference

| Aspect | Rule |
|---|---|
| Where tests run | Host machine and CI. Never on the MCU. |
| Test framework | GoogleTest + gmock. nlohmann_json for fixture-driven algorithm tests. |
| File layout | `tests/` mirrors `src/`; mocks under `tests/mocks/{hal,drivers,hardware,manager,headers,libraries}/`. |
| Mock seam — handler test | Mock the driver class + HAL utilities. |
| Mock seam — manager / feature test | Mock the handlers. |
| Mock seam — algorithm test | Mock nothing — algorithms are pure. |
| Naming | `<Subject>Test` suite; `Should<DoSomething>[When<Condition>]` methods. |
| Traceability | `RecordProperty("Requirement", "SW-XXXX")` on every test in regulated firmware. |
| Vendor headers in tests | Shadowed by stubs in `tests/mocks/headers/`. |
| Time / random / ISR | Injected and faked — never real wall-clock waits. |
| Build | One test executable per configuration; coverage flags on the test config; `gtest_discover_tests` for CTest. |
| CI | `format → lint → build → build_tests → test → coverage → JUnit upload`. Warnings are errors. |
