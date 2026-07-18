<div align="center">

[![Release](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join-blue.svg?logo=apple)](https://testflight.apple.com/join/5RCKgnJ2)
![Platforms](https://img.shields.io/badge/iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Firmware](https://img.shields.io/badge/firmware-ESP32-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

# OUI-APEX

<img width="320" alt="OUI-SPY APEX" src="https://github.com/user-attachments/assets/5a201c27-558b-4409-9e49-82d6e0176a4c" />

**A phone-controlled ESP32 WiFi/BLE detector and wardriver.** Eight detection engines on one ESP32-S3 (or a dual-band ESP32-C5 for 2.4 + 5 GHz), driven from a Flutter app over BLE. Run a single board, or a mesh of boards with one coordinator.

</div>

> [!NOTE]
> Runs the [OUI-SPY ecosystem](https://github.com/colonelpanichacks) by colonelpanichacks. **Not affiliated with OUI-SPY.** Beta software — expect bugs.

---

## Table of Contents

1. [What is OUI-APEX?](#what-is-oui-apex) — what it does, and NODE vs MANAGER
2. [Supported boards](#supported-boards) — which board to buy / flash
3. [Quick start](#quick-start) — flash, install the app, connect
4. [The engines](#the-engines) — what it can detect
5. [Using the app](#using-the-app) — home, feed, wardrive, PCAP, settings
6. [Mesh — multiple boards](#mesh--multiple-boards) — manager + nodes
7. [Detection internals](#detection-internals) — how each engine works
8. [Flashing & hardware](#flashing--hardware) — web flasher, GPS wiring
9. [Build from source](#build-from-source) — PlatformIO + Flutter
10. [Dependencies & services](#dependencies--services)
11. [Ecosystem](#ecosystem) — standalone forks
12. [Acknowledgments](#acknowledgments)
13. [Disclaimer](#disclaimer)

---

## What is OUI-APEX?

OUI-APEX turns a cheap ESP32 board into a pocket **WiFi + BLE surveillance-hardware detector and wardriver**, fully driven from your phone over Bluetooth. Eight detection engines (trackers, Flock cameras, drones, and more) run on the board; a Flutter app on iOS / macOS / Android is the screen, map, and control panel. No SD card, no laptop — the board streams everything to the app over BLE.

Every board runs one of two firmwares:

- **NODE** — the scanner. Runs the detection engines on its own WiFi + BLE radios and talks to the phone app directly. **A single node is a complete, standalone OUI-APEX.** The web flasher defaults to it.
- **MANAGER** — only for a mesh of **2+ boards**. A coordinator: it links to the phone, splits work across nodes, and aggregates their detections. **It has no detection engines and does not scan itself** — a lone manager connects to the app but finds nothing. Flash a manager only when you have nodes for it to run.

**One board? Flash NODE and stop reading here.** Managers are covered in [Mesh](#mesh--multiple-boards).

---

## Supported boards

Several ESP32 variants work; the **XIAO ESP32-S3** is recommended. The [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) lists everything currently supported — request others via an issue.

| Board | Role | Bands | Web-flasher target | PlatformIO env |
|---|---|---|---|---|
| **XIAO ESP32-S3** ⭐ | NODE | 2.4 GHz | `node-xiao_s3` | `v3_app_controlled` |
| ESP32-S3 N16R8 DevKitC | NODE | 2.4 GHz | `node-s3_devkitc` | `v3_app_controlled_s3_devkitc` |
| **XIAO ESP32-C5** | NODE | **2.4 + 5 GHz** | `node-xiao_c5` | `v3_app_controlled_c5` |
| **XIAO ESP32-S3** ⭐ | MANAGER | — | `mgr-xiao_s3` | `v3_node_manager_s3` |
| ESP32-S3 N16R8 DevKitC | MANAGER | — | `mgr-s3_devkitc` | `v3_node_manager_s3_devkitc` |
| XIAO ESP32-C3 | MANAGER | — | `mgr-xiao_c3` | `v3_node_manager_xiao_c3` |
| ESP32 WROOM | MANAGER | — | `mgr-wroom` | `v3_node_manager_wroom` |

⭐ = recommended. The **ESP32-C5** is the only dual-band board — it adds 5 GHz (UNII-1 + UNII-3) scanning on top of 2.4 GHz; pick the band in *Settings → Config → WiFi band*.

| Your gear | Flash |
|---|---|
| **One board** | **NODE** (`node-xiao_s3`, or `node-xiao_c5` for 5 GHz) |
| **Several boards** | **NODE** on every board except the one you connect the app to; **MANAGER** on that one (`mgr-xiao_s3` — its PSRAM holds a deep buffer) |

---

## Quick start

1. **Flash** — open the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) in Chrome or Edge, plug in via USB-C, pick your [board target](#supported-boards) (default **NODE**), hit **Connect & Flash**. One time only; after that the app updates it over the air.
2. **Install the app** — [Android APK](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) · [iOS / macOS TestFlight](https://testflight.apple.com/join/5RCKgnJ2) · [macOS signed build](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest).
3. **Connect** — open the app, tap **CONNECT**, pick your board from the scan list.

> [!IMPORTANT]
> On Android, grant **Location → Allow all the time** — Android requires it to keep BLE scanning while the app is backgrounded or the screen is off.

Auto-connect is off by default (*Settings → Config → Connection → Auto-connect on launch*). Off: the app waits for you to pick a device. On: it reconnects to your last board by saved ID, including after you leave and return to BLE range.

<img width="610" alt="APEX overview" src="https://github.com/user-attachments/assets/0a798936-51f3-41d2-b103-cdec0e7d9134" />

---

## The engines

Eight engines, toggled from the home screen. They run together on whatever radios each needs.

| Engine | Radio | What it detects |
|---|---|---|
| **Detector** | WiFi + BLE | Your watchlist (MAC / OUI prefix / name / BLE service UUID) **plus** six toggleable signatures: Find My/AirTag trackers, Flipper Zero, WiFi deauth storms, directed probe-requests, Pwnagotchi, Meta smart glasses |
| **Flock BLE** | BLE | Flock Safety cameras + Raven gunshot sensors by BLE fingerprint |
| **Flock WiFi** | WiFi | Flock Safety cameras by 802.11 traffic |
| **Foxhunter** | WiFi + BLE | One chosen target — buzzer speeds up as you close in |
| **Sky Spy** | WiFi + BLE | FAA Remote ID drones (Open Drone ID) + operator position |
| **UniPwn** | BLE | Unitree robots — detect, connect, exploit actions |
| **Wardrive** | WiFi + BLE | Every AP + BLE device, WiGLE-style, GPS-stamped |
| **PCAP** | WiFi *or* BLE | Raw 802.11 or BLE link-layer frames to a `.pcap` |

How each engine works under the hood is in [Detection internals](#detection-internals).

---

## Using the app

Flutter app for iOS, macOS, and Android.

**Home** — one card per engine; tap to toggle or open its settings. Status bar shows connection, GPS fix, and node count.

**Live feed** — every detection from every engine in one stream. Filter by engine / preset / node, sort by time / RSSI / MAC, free-text search, and export the current view to WiGLE CSV. Tap a row to foxhunt or map it; long-press for the full detail sheet.

**Wardrive & map** — pick any mix of targets (WiGLE / Flock / Drone / Detector) and a radio (WiFi / BLE / Both), then **START**. Hits plot live, color-graded by density, with your route behind you. Drones plot at their broadcast Remote ID position (or an RSSI ring when they report no fix). Sessions save as WiGLE CSV and upload to **WiGLE** and/or **[WDGWars](https://wdgwars.pl)** with your API key — per-session upload buttons in the map bar and session log; saved sessions replay on the map, and you can import CSVs.

<img width="709" alt="App home" src="https://github.com/user-attachments/assets/62470061-c382-4724-8d86-72cb4dd4c1df" />
<img width="910" alt="Wardrive map" src="https://github.com/user-attachments/assets/cc0d4cc9-6524-41c7-bb04-9cd01dae58b8" />

**Geofences** — draw a zone; inside it everything goes silent (no feed, no log, no CSV, no beep, radios paused). Scanning resumes when you leave.

**PCAP** — no SD card; frames stream over BLE and the app writes a `.pcap` for Wireshark. WiFi 802.11 (radiotap) or BLE LL. **Auto-PCAP**: when an engine fires, the board can capture for 3–120 s (with cooldown + per-MAC rediscover), labeled by the engine and MAC that triggered it, then return to scanning. A PCAP library screen lists your captures.

<img width="910" alt="PCAP" src="https://github.com/user-attachments/assets/4b34e73d-1341-4222-8ec2-d17a179f6faa" />

**Offline scan** *(Settings → Config → Hardware → Offline Scan)* — keep the detection engines running after you close the app or walk out of BLE range; targeted detections buffer to flash and sync when you reconnect. The enabled engines + watchlist are saved to flash, so scanning **survives a reboot / power cycle** and resumes on boot with no phone.

**OTA updates** *(Settings → Updates)* — update over WiFi (give credentials once) or BLE (slower, works anywhere). In a mesh, nodes update one at a time.

**Wardrive accounts** — link **WiGLE** (API name + token) and **WDGWars** (64-char API key) at the top of *Settings → Config*. Each shows live stats — WiGLE rank / WiFi / BT counts; WDGWars networks, badges, gang, and your rolling 24 h new-AP quota — and a condensed strip on the home screen links back to the full view.

**Settings** — appearance, units, scan timing, channel range, WiFi band (2.4 / 5 GHz / both — 5 GHz on the dual-band ESP32-C5 node), the OUI vendor database (with WiGLE CSV import), WiGLE + WDGWars accounts, buzzer/LED, station-mode WiFi, watchlist, ignore list, factory reset, and database export/import for backing up captures.

<img width="1133" alt="Settings" src="https://github.com/user-attachments/assets/b8072937-67fb-4ae3-adc0-d1c748a26983" />

**iOS Dynamic Island** — on iPhone 14 Pro and newer (iOS 16.2+), live detection counts show on the Lock Screen and Dynamic Island during a session.

---

## Mesh — multiple boards

Flash the board you connect the app to as a **manager** (`mgr-xiao_s3` — its PSRAM holds a deep detection buffer) and every other board as a **node**. Power them on; nodes auto-join in ~10 s with no pairing. Connect the app to the manager.

- Detection runs across **all nodes**; every hit is tagged with the node that found it.
- The manager splits the WiFi channel range across nodes to cover the band faster.
- Manager settings (buzzer, LED, alert timing, ignore list, wardrive radio, WiFi band) push to every node and override their local copies.
- The manager does not scan — it coordinates and aggregates. All detection comes from nodes.
- With Offline Scan on, the manager persists its commanded engine set so a manager reboot restores it and re-commands the nodes.

---

## Detection internals

802.11 frames carry three MAC fields — **addr1** (receiver), **addr2** (transmitter), **addr3** (BSSID). Several engines check all three so a target is caught in any role.

**Detector** — your watchlist (full MACs, OUI prefixes, name patterns, 16-bit BLE service UUIDs), matched on BLE adverts and WiFi promiscuous frames. Alongside it, six built-in signatures — each toggled from the Signatures panel, off by default: Find My/AirTag offline-finding adverts (persistence-gated, ~3 s, anti-stalking), Flipper Zero (`Flipper` name), WiFi deauth/disassoc storms (rate-gated), directed probe-request SSIDs, the Pwnagotchi beacon, and Meta smart glasses (BLE mfg/service ID). Each is labeled in the feed by what it is; toggles sync to firmware and propagate to mesh nodes.

**Flock** — both engines share an OUI table (`flock_oui.h`). A field-tested **core set** is always on; an **extended set** (broad cellular/WiFi/control-chip vendor OUIs) is off by default because those prefixes appear on countless non-Flock devices — enable it under *Settings → Hardware → Flock Detection* when you want max coverage and will triage noise. Flock WiFi runs 802.11 promiscuous on channels 1/6/11, firing a wildcard probe on each hop, matching the OUI table on addr2/addr1/addr3 and decoding AP auth mode. Flock BLE matches on OUI, advertised name (`Penguin`, `Flock`, `FlockCam`, `FS-`, …), manufacturer ID `0x09C8` (XUNTONG), and Raven gunshot-detector GATT UUIDs.

**Foxhunter** — lock one target MAC; buzzer cadence speeds up as RSSI rises, across WiFi and BLE.

**Sky Spy** — FAA Remote ID: BLE scan for Open Drone ID adverts + WiFi promiscuous for NAN / beacon ODID frames. Decodes operator/UAV ID, position, altitude, speed, heading.

**UniPwn** — Unitree robots by BLE name prefix (`Go2_`, `G1_`, `H1_`, `B2_`, `X1_`): detect → connect → exploit actions.

**Wardrive** — logs every AP + BLE device (SSID, BSSID, channel, decoded auth mode), GPS-stamped, WiGLE-compatible. On the ESP32-C5 it sweeps 2.4 GHz **and** 5 GHz UNII channels.

---

## Flashing & hardware

Routine updates come from the app over OTA. The web flasher is for the **first flash on a bare board**, or recovery.

**Web flasher** — [lukeswitz.github.io/oui-spy-unified-blue](https://lukeswitz.github.io/oui-spy-unified-blue/), Chrome / Edge 89+ (Web Serial). Plug in via USB-C, pick the [target](#supported-boards) (NODE is the default), **Connect & Flash**. The flasher handles per-chip bootloader offsets automatically (e.g. the ESP32-C5 bootloader lives at `0x2000`), so you don't need to think about them.

**Optional on-board GPS** — a node normally gets location from the phone over BLE. Wire a serial GPS module (NEO-6M / NEO-8M, 9600 baud) and the node self-locates with no phone — useful for standalone / offline wardriving. When the module has a fix it takes priority over phone GPS; unplug it and the node falls back to the phone automatically (5 s timeout).

| GPS module | Board (XIAO ESP32-S3 default) |
|---|---|
| TX  | GPIO44 (`PIN_GPS_RX`) |
| RX  | GPIO43 (`PIN_GPS_TX`) |
| VCC | 3V3 |
| GND | GND |

Pins are per-board — override with `-DPIN_GPS_RX=` / `-DPIN_GPS_TX=` for other variants. Serial detections (`lat`/`lon`/`sats`) print on the module's first fix.

---

## Build from source

<details>
<summary><b>Firmware (PlatformIO)</b></summary>

```bash
pio run -e v3_app_controlled             # node (XIAO ESP32-S3)
pio run -e v3_app_controlled_s3_devkitc  # node (ESP32-S3 N16R8 DevKitC)
./build_c5.sh                            # node (XIAO ESP32-C5, dual-band 2.4+5GHz)
./build_c5.sh -t upload                  # flash the C5 node
pio run -e v3_node_manager_s3            # manager (XIAO ESP32-S3)
pio run -e v3_node_manager_s3_devkitc    # manager (ESP32-S3 N16R8 DevKitC)
pio run -e v3_node_manager_xiao_c3       # manager (XIAO ESP32-C3)
pio run -e v3_node_manager_wroom         # manager (ESP32 WROOM)
pio run -e v3_app_controlled -t upload   # flash node
pio device monitor                       # serial @ 115200
```
Dependency: `NimBLE-Arduino`.

The XIAO ESP32-C5 uses the pioarduino platform (Arduino 3.x / IDF 5.5, NimBLE 2.x). `build_c5.sh`
builds it in an isolated `PLATFORMIO_CORE_DIR` (`~/.platformio-c5`) so its framework/toolchain never
clobber the shared `~/.platformio` packages used by the standard-platform S3/C3/WROOM envs. CI builds
each env on a fresh runner with a per-env cache, so it is already isolated there.

</details>

<details>
<summary><b>App (Flutter 3.32+)</b></summary>

```bash
cd companion
flutter pub get
flutter run
flutter build apk --release
flutter build ipa --release
flutter build macos --release
```

</details>

---

## Dependencies & services

<details>
<summary><b>Libraries & services</b></summary>

**Firmware:** [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino), [Adafruit NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel), [ArduinoJson](https://github.com/bblanchon/ArduinoJson), [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus). ESP-IDF WiFi promiscuous + ESP-NOW + mbedTLS AES-GCM mesh.

**App:** flutter_blue_plus · flutter_map + latlong2 · drift + sqlite3 · geolocator · flutter_riverpod · go_router · flutter_local_notifications · dio · share_plus · flutter_secure_storage · wakelock_plus · permission_handler.

**Services:** [WiGLE](https://api.wigle.net) · [WDGWars](https://wdgwars.pl) · [CARTO](https://carto.com/basemaps/) / [OpenStreetMap](https://www.openstreetmap.org/) / [OpenTopoMap](https://opentopomap.org/) / [Stadia Maps](https://stadiamaps.com/) tiles · [Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database) vendor OUIs.

</details>

---

## Ecosystem

Standalone single-purpose forks that OUI-APEX unifies:

| Project | What |
|---|---|
| [OUI-SPY Detector](https://github.com/colonelpanichacks/ouispy-detector) | BLE/WiFi watchlist scanner |
| [OUI-SPY Foxhunter](https://github.com/colonelpanichacks/ouispy-foxhunter) | RSSI proximity tracker |
| [Flock You](https://github.com/colonelpanichacks/flock-you) | Flock Safety / Raven detector |
| [Sky-Spy](https://github.com/colonelpanichacks/Sky-Spy) | Drone Remote ID capture |
| [Remote-ID-Spoofer](https://github.com/colonelpanichacks/Remote-ID-Spoofer) | WiFi Remote ID spoofer + swarm |
| [OUI-SPY UniPwn](https://github.com/colonelpanichacks/Oui-Spy-UniPwn) | Unitree robot exploitation |

---

## Acknowledgments

- **Will Greenberg** ([@wgreenberg](https://github.com/wgreenberg)) — [flock-you](https://github.com/wgreenberg/flock-you): manufacturer ID `0x09C8` (XUNTONG) detection.
- **@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)) — original promiscuous Flock OUI set + the addr1 receiver-side technique.
- **Michael / DeFlockJoplin** ([DeflockJoplin](https://github.com/DeflockJoplin/flock-you)) — wildcard-probe signature.
- OUI superset also draws on [zmattmanz/flock-detection](https://github.com/zmattmanz), [dougborg/AirHound](https://github.com/dougborg), [VirtuallyScott/flock-you](https://github.com/VirtuallyScott).
- **OUI-SPY ecosystem author:** **colonelpanichacks**.

---

## Disclaimer

Security-research and privacy-auditing tool. Detecting surveillance hardware in public is legal in most jurisdictions; comply with local laws on wireless scanning and interception. GATT exploitation actions carry risk. Lawful use only — authors not responsible for misuse.
