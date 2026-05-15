---
name: firmware-sensor-integration
description: Use whenever a firmware task adds, replaces, or significantly modifies the integration of a hardware peripheral — sensors (IMU, microphone, temperature, EMG, ADC front-ends), actuators (motors, buzzers, LEDs), radios (BLE, LoRa, Wi-Fi), power-management ICs, or memory devices (Flash, EEPROM, SD). Captures the datasheet-first workflow, register-map ingestion, driver / handler / mock split, bring-up checklist, and the reviewable artifacts every sensor integration must produce. Pair with `firmware-conventions` for the architectural layering and `firmware-testing` for the mock seam.
---

# Firmware Sensor Integration

A new peripheral does **not** start with code. It starts with the datasheet. Skipping that step is the most reliable way to ship a driver that works on the bench, fails in the field, and is unfixable without rewriting the whole stack.

This skill is the workflow to follow whenever a sensor (or any peripheral with its own datasheet) is added to a firmware project. It is target-agnostic and product-agnostic — the same workflow applies to STM32, ESP32, nRF, RP2040, or any host MCU, and to any product domain.

## The non-negotiable rule

**Read the datasheet before writing the driver.** Not the vendor's example code, not a blog post, not a GitHub library — the datasheet. The vendor example is a starting point; the datasheet is the contract.

If you cannot produce the artifacts in the [Bring-up package](#bring-up-package) section below, you have not read enough of the datasheet to start coding.

## Step 1 — Retrieve and pin the datasheet

1. **Download the latest revision of the datasheet** from the manufacturer's site (ST, TI, Analog Devices, Bosch, Nordic, …). Use the canonical part number; verify the revision number, marking code, and silicon stepping match the chip you have on the board.
2. **Save it under `docs/datasheets/`** in the repo, named `<vendor>_<partnumber>_<revision>.pdf` — e.g. `st_lis2dw12_rev6.pdf`. Datasheets are not generated; keep them in git or in an artifact store with a stable link. Never rely on the manufacturer's site staying up.
3. **Check the errata.** Many vendors ship a separate **errata sheet** (e.g. ST `ES####`). Save it next to the datasheet (`st_lis2dw12_errata_es0394.pdf`). The errata is part of the contract.
4. **Note the silicon revision your hardware uses.** Errata items frequently apply only to specific die revs. The hardware team should know which rev is on the PCB.
5. **Reference the datasheet in code.** Every magic constant pulled from the datasheet carries an inline pointer to section / page / table:
   ```cpp
   // LIS2DW12 datasheet §6.1.3 / Table 18 — WHO_AM_I register expected value.
   static constexpr uint8_t WHO_AM_I_VALUE = 0x44;
   ```

If you cannot find the datasheet, **stop** and escalate before writing a line of code. A driver written against guesswork is a future hardware regression.

## Step 2 — Read the datasheet, in this order

You do not need to read every page on first pass. You **do** need every item in this checklist to be answered, with section references, before you write the driver header.

1. **Block diagram** (usually §3 or §4) — what's actually inside the chip? Is the sensing element separate from a built-in FIFO / DSP? Does the part have multiple domains (analog supply vs digital supply)?
2. **Pin assignments and electrical characteristics** — supply voltage range, max ratings, I/O logic levels, level-shifter requirements, decoupling capacitor recommendations. Confirm against the schematic.
3. **Communication interface** — I²C / SPI / UART / I²S / SDIO. Address (7-bit vs 8-bit; SDO/SA0 strapping; alternate address). Maximum bus speed in fast / fast-plus / high-speed mode. Required pull-up values. CPOL/CPHA for SPI. Repeated start vs stop-then-start for I²C reads.
4. **Power-up sequence** — boot time, reset behavior, register defaults. Many parts require a `WHO_AM_I` read before any other access; some need a soft-reset bit asserted and a specific wait period before they accept further commands.
5. **Register map** (the bulk of the datasheet) — every register's address, reset value, R/W permissions, bit fields. This is what the driver layer is going to wrap.
6. **Operating modes** — low-power vs high-performance vs continuous; the state diagram showing legal transitions between modes. The handler is going to walk that diagram.
7. **Timing diagrams** — power-up time, reset time, mode-switch settling time, ODR (output data rate) settling, interrupt latency. Anything labeled "min", "typ", "max" with a unit of time is a `delay` or a `poll` in the driver.
8. **Interrupts / data-ready signals** — INT1 / INT2 pin wiring, polarity, latching behavior, threshold registers, FIFO watermark behavior.
9. **Calibration / temperature compensation** — does the part need a one-time calibration read at boot? Are there factory trim values in OTP that must be applied to raw readings?
10. **Errata that affect any of the above.** Re-read the errata after the datasheet. Common patterns: "WHO_AM_I returns 0 for the first read after reset", "I²C clock stretching exceeds spec — limit master clock", "FIFO depth is one less than advertised".

When this pass is done you should be able to answer (without re-opening the PDF): how do I initialize it, how do I read one sample, how do I read N samples, how do I put it to sleep, and how do I wake it up. Those four questions map 1:1 to the driver's public surface.

## Step 3 — Pick a starting point (without anchoring on it)

After the datasheet pass, **then** look at:

- The vendor's reference driver (ST's `xxx_reg.c` / `xxx_reg.h`, TI's `<part>_driver.c`, Bosch's `bmiXXX_defs.h`). These are often the cleanest abstraction over the register map.
- A Zephyr / Linux upstream driver if one exists. Worth reading for the corner cases — Linux drivers tend to encode every quirk the kernel community has hit.
- An Arduino / PlatformIO library — useful for sanity-checking your register access, **not** a substitute for understanding the registers.

**Never copy-paste a vendor reference driver verbatim into the repo.** Either pin it as a vendored dependency in `drivers/<part>/` (with the upstream version and tag recorded in a `README.md`) or rewrite it against the project's driver-class pattern (see `firmware-conventions`). Mixing the two — partial copy with hand-edits — strands the codebase from upstream fixes.

## Step 4 — Decide the integration shape

Two layers, every time (cross-reference `firmware-conventions` for the architecture rules):

### Driver (chip-specific, register-level)

- One folder under `drivers/<PART_NUMBER>/` for the vendor register-access library (often pulled in unchanged from the vendor), and one virtual class under `src/hardware/<peripheral>/<PartName>.{hpp,cpp}` that wraps it.
- The virtual class exposes **one method per register-level operation** the handler needs. Same name and shape as the underlying vendor function (`setReset`, `getDeviceId`, `setDataRate`, `setFifoMode`).
- Each method has a Doxygen comment that names the register and bit field it touches — copy the description straight from the datasheet.
- This class exists **only** so a `<PartName>Mock : public <PartName>` can substitute it under GoogleTest. If your codebase will never have host-side tests (rare; reconsider), the virtual layer is still cheap insurance.

### Handler (peripheral abstraction, business-facing)

- Owns the device state machine — `startup()`, `activatePower()`, `deactivatePower()`, `startAcquisition()`, `stopAcquisition()`, `getXxxData()`.
- Holds the driver pointer and any HAL utility pointers (`HalGpio` for power-enable pins, `HalI2c` for the bus). Constructor-injected — never `new`'d inside.
- Encapsulates timing requirements from the datasheet: post-reset waits, FIFO drain loops, sample-rate conversions, raw-to-engineering-unit math.
- Translates errors from the driver into the handler's public error model (return code, `std::optional`, etc.).
- Methods are virtual so a `<Peripheral>HandlerMock : public <Peripheral>Handler` can stand in for higher-layer (manager / feature) tests.

Illustrative example for an accelerometer with a vendor register library (e.g. ST's `lis2dw12_reg.c`): a virtual `Accelerometer` driver class wraps the vendor register functions, and an `AccelerometerHandler` turns "start acquisition" into a sequence of `setFullScale`, `setDataRate`, `setFifoMode`, `setPowerMode` calls, exposing `getAccelerometerData()` that polls FIFO depth and converts raw counts to engineering units. The same split applies to any other part — the names track the part and its operating modes, the shape does not.

## Step 5 — Bring-up package

Before merging the integration, the following artifacts must exist in the PR (or be linkable from it):

| Artifact | Location | What goes in it |
|---|---|---|
| **Datasheet PDF** | `docs/datasheets/<vendor>_<part>_<rev>.pdf` | Pinned revision. |
| **Errata PDF (if any)** | `docs/datasheets/<vendor>_<part>_errata_<id>.pdf` | Same. |
| **Integration note** | `docs/peripherals/<part>.md` | One-page markdown: pin map, bus speed, address, power-up sequence, ODR table you're using, FIFO / DMA strategy, INT line wiring, any errata that affected the driver, links to the datasheet section numbers. |
| **Driver class** | `src/hardware/<peripheral>/<Part>.{hpp,cpp}` | Virtual class wrapping the vendor register library. |
| **Handler class** | `src/hardware/<peripheral>/<Peripheral>Handler.{hpp,cpp}` | State machine + domain API. Inherits `HardwareHandler`. |
| **Driver mock** | `tests/mocks/drivers/<Part>Mock.{hpp,cpp}` | gmock `MOCK_METHOD` for every virtual on the driver class. |
| **Handler mock** | `tests/mocks/hardware/<Peripheral>HandlerMock.hpp` | gmock `MOCK_METHOD` for every virtual on the handler. |
| **Handler tests** | `tests/hardware/<peripheral>/<Peripheral>HandlerTest.cpp` | One `TEST(...)` per public method + edge cases (FIFO empty, FIFO overflow, mode-switch failure, post-reset timing). Each test carries `RecordProperty("Requirement", "SW-XXXX")` if the project uses requirement traceability. |
| **Bring-up log** | PR description or `docs/peripherals/<part>-bringup.md` | What you measured on the bench: scope captures of I²C startup, current draw in each power mode, FIFO depth vs sample-rate validation, first/last-sample timestamps. The reviewer relies on this — don't leave it implicit. |

## Step 6 — Bench validation (don't skip)

Code that compiles is not a driver. Verify on real hardware before opening the PR:

1. **Logic analyzer on the bus.** Capture the init sequence; compare register writes against the datasheet's recommended startup. Any unexpected NACK, repeated-start, or unusual byte means the driver disagrees with the part.
2. **Confirm `WHO_AM_I` returns the expected value.** If it doesn't, every line of code after that is fiction.
3. **Sweep the modes** the project uses. For each mode, validate ODR (output data rate) by counting samples over 10 s, validate full-scale by tipping the board against gravity (for IMUs) / shorting the input (for ADCs) / sealing the cavity (for mics).
4. **Validate the FIFO / interrupt path.** If the handler relies on FIFO watermark / data-ready interrupts, scope the INT line under load.
5. **Power measurement.** Verify the off-state current matches the datasheet's "power-down" spec. A handler that thinks it powered down a sensor but actually left it in standby is a battery-life regression.
6. **Sanity-check raw-to-engineering-unit conversion** against a known reference. For an accelerometer at rest, ±1 g on the gravity axis. For a thermometer, a calibrated reference at two temperatures. For a battery gauge, a multimeter on the cell.

The bring-up log in step 5's table is the artifact that proves you did this. A PR without it is incomplete.

## Step 7 — Test (host-side, no hardware in the loop)

Once the bench-validation is done, the unit / integration tests for the handler **do not need real hardware** — that's the entire point of the driver-class abstraction. See `firmware-testing` for the GoogleTest patterns. The minimum coverage:

- Startup sequence — `EXPECT_CALL` on every register write the datasheet mandates, in order.
- Each public handler method — happy path + at least one failure path (driver returns error, FIFO empty, timeout).
- Mode transitions — start → stop → start, sleep → wake, etc. Confirm no stale state.
- Edge cases pulled from the datasheet — overflow, underrange, calibration-not-ready.

If a behavior is too coupled to wall-clock time to mock, refactor the handler to take a `Timer` (or equivalent) abstraction so tests can advance time deterministically.

## Step 8 — Wire it into the manager / features

- Register the new handler in `main` via the `ServiceLocator`.
- Add `activatePower()` / `deactivatePower()` to the `PowerManager`'s policy for each device state.
- If the peripheral surfaces over BLE / UART, add `features/<area>/<Verb><Peripheral>Command.{hpp,cpp}` for each external request — `Start<X>Command`, `Stop<X>Command`, `Get<X>DataCommand`.
- Tests for those commands belong under `tests/features/<area>/` and use the **handler mock**, not the driver mock — that's the whole reason both mocks exist.

## Anti-patterns (always reject in review)

- Driver was written from a blog post / Arduino library without the datasheet being in `docs/datasheets/`.
- No errata sheet linked when the part has a published errata.
- Register addresses or bit values inlined as magic numbers without a datasheet section reference.
- Handler `#include`s the vendor register library directly instead of going through the virtual driver class.
- No mock for the driver (`<Part>Mock`) — means the handler isn't testable on the host.
- Bring-up log absent or hand-waved ("works on my bench").
- `delay_ms(100)` sprinkled through the driver without a comment naming the timing parameter from the datasheet.
- `WHO_AM_I` not checked at startup, or its expected value hardcoded as a literal instead of a named `WHO_AM_I_VALUE` constant.
- Power-down path untested — the handler advertises `deactivatePower()` but no test confirms the power-enable GPIO actually goes low.

## Quick reference

| Step | Output |
|---|---|
| 1. Pin the datasheet | `docs/datasheets/<vendor>_<part>_<rev>.pdf` (+ errata) |
| 2. Read it in the prescribed order | You can answer init / read-one / read-N / sleep / wake without re-opening the PDF |
| 3. Pick a starting point | Vendor `*_reg.c` pinned under `drivers/<PART>/`; never copy-paste-and-edit |
| 4. Decide the shape | Virtual driver class + handler class, both mockable |
| 5. Bring-up package | Datasheet, integration note, driver, handler, mocks, tests, bring-up log |
| 6. Bench-validate | Logic analyzer, WHO_AM_I, ODR sweep, FIFO/INT, power measurement, unit conversion |
| 7. Host-side tests | Cover startup, each public method, mode transitions, datasheet edge cases |
| 8. Wire it in | `main` registers the handler; PowerManager owns power policy; features expose BLE/UART commands |
