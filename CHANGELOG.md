# Changelog

All notable changes to ROM Splitter will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Validation and compatibility testing on real ArkOS/dArkOS handhelds.
- Improved handling and resolution of duplicate games across SD1 and SD2.
- Optional automatic discovery of new SD2 games during startup.

## [1.0.0-rc18] - 2026-09-21

Install directly over the last public candidate, **rc15**. rc16 and rc17 were not published; their changes are included here. No intermediate installation or uninstall is required.

### Added

- Keep the bind registry and SD2 card profiles outside the replaceable application directory. On upgrade from rc15, copy the existing state to the persistent location before replacing application files.
- In **Repair/rebuild bind mounts**, offer to back up empty orphan placeholders and rebuild their SD2 links after confirmation. Non-empty SD1 files and folders remain untouched and are reported as conflicts.

### Fixed

- Record bind ownership before creating a placeholder, so an interrupted mount can be cleaned up on the next activation.
- Report failed bind mounts as failures instead of counting them as successfully linked.
- Synchronize bind state when switching between older releases and rc18 through the ZIP installer.
- Avoid symbolic links and Unix permission-preserving copies under `/roms`, which is exFAT on the tested R36H.
- Keep the uninstall option available without local release ZIPs, disconnect only managed SD2 binds, and report removal failures accurately. SD1 and SD2 game files remain untouched.

### Validation

- rc18 opened and restored SD2 games on an R36H after the exFAT startup correction. Direct rc15-to-rc18 upgrade has automated local coverage but still needs real-device confirmation.
- Keep any `.rom-splitter-recovery.*` backup until the recovered games have been tested.

## [1.0.0-rc15] - 2026-09-13

### Added

- Add an "Uninstall ROM Splitter" option to the standalone installer's menu. It safely deactivates any active SD2 game links first (reusing the same routine as the in-app "Unmount SD2"), then removes only the Tools launchers, the boot service and the installed app copy. ROM/game files on SD1 and SD2 are never deleted, and the confirmation dialogs say so explicitly, with an extra warning when games are currently bound from SD2.

Uninstall menu orchestration and the SD2-bind detection logic passed local tests; handheld validation remains pending.

## [1.0.0-rc14] - 2026-09-13

### Added

- Let the standalone installer update to its bundled release or select a local ROM Splitter ZIP to reinstall or roll back.
- Validate the selected ZIP's version and contents, preserve the exact checksum check for the bundled release, and warn when another manually selected ZIP is not covered by that checksum.

Version selection, rollback choice and reinstall cancellation passed local tests; handheld validation remains pending.

## [1.0.0-rc13] - 2026-09-13

### Fixed

- Create unique temporary launcher and service files during installation instead of reusing fixed `/tmp` paths that may be owned by another user.
- Do not report an otherwise successful installation as failed solely because the progress dialog closed early; still report backend failures.

The R36H log identified the temporary-file permission error. The revised installer passed local checks and awaits real-device confirmation.

## [1.0.0-rc12] - 2026-09-13

### Changed

- Replace the quick text-only package installer with a self-contained dialog flow showing version comparison, reinstall confirmation, staged progress, dependency notices and a persistent success message.
- Add handheld button mapping to the installer and select the package by its embedded checksum instead of taking the first ZIP in the folder.
- Apply a two-point safety margin to the raw battery sensor because the R36H showed 19% in EmulationStation while the kernel reported 21%; show the sensor reading in Diagnostics.

Installer flow and battery cutoff passed local checks; real-device validation remains pending.

## [1.0.0-rc11] - 2026-09-13

### Added

- Block game moves, permanent deletion and SD2 formatting at 20% battery or lower, checking again between games in a batch. Warn but allow the operation when the battery level cannot be read.

Battery guard boundary and unavailable-reading cases passed local checks; real-device validation remains pending.

## [1.0.0-rc10] - 2026-09-13

### Added

- Show the installed version beside the ROM Splitter title in the main menu.
- Offer to restart EmulationStation after moving or deleting games or linking new SD2 games with option 9; offer again on Exit when changes remain pending.

### Fixed

- Correct an uninitialized path variable in permanent game deletion.

Restart prompts and permanent deletion passed local checks; hardware validation remains pending.

## [1.0.0-rc9] - 2026-09-13

### Fixed

- Route backend errors and command output to the log when SD2 is absent, without overwriting dialog screens.
- Show in-menu notices for missing SD2 during management, scanning and repair.
- Keep card-switch failures in the menu and avoid stale counters in failed scans.
- Preserve progress-only output in gauge pipes while logging technical scan details.

Missing-card flows passed local checks; real-device confirmation remains pending.

## [1.0.0-rc8] - 2026-09-13

### Fixed

- Prevent technical mount output from leaking over the `Repair/rebuild bind mounts` dialog.
- Show per-item repair progress and a final success or failure message while retaining details in the log.

The repair flow passed local demo and failure-path checks; real-device validation remains pending.

## [1.0.0-rc7] - 2026-09-13

### Fixed

- Create GPT partitions using Parted's supported `fat32` type hint and `ROMS2` partition name, then format the partition with `mkfs.exfat`. Parted does not recognize `exfat` as a `mkpart` type.

Validated the Parted command on a temporary disk image; real-device formatting is still pending.

## [1.0.0-rc6] - 2026-09-13

### Changed

- During installation on Debian, attempt to install only missing optional formatting packages (`parted` and/or `exfatprogs`).
- Keep ROM Splitter installation successful when package installation is unavailable, including offline use, and warn that only SD2 formatting is disabled.
- Do not bundle architecture-specific `.deb` packages in the ZIP.

Installer fallback and simulated package installation passed local tests; real-device confirmation remains pending.

## [1.0.0-rc5] - 2026-09-13

### Fixed

- Check for `parted` and `mkfs.exfat` before asking to erase or disconnect an active SD2 card.
- Report missing formatting tools in the UI without changing mounts, bind links or card contents.
- Keep a second prerequisite check in the formatter for safety.

Verified locally with a missing-tool scenario; real-device validation remains pending.

## [1.0.0-rc4] - 2026-09-13

### Fixed

- Cancelling either active-SD2 or data-erasure confirmation now returns to the main menu instead of closing the app.
- Reduced the size of menus, checklists, messages, confirmations and gauges; long lists remain scrollable.
- Accounted for dialog line breaks when calculating message and confirmation height.

These interface changes passed local checks and still need real-device confirmation.

## [1.0.0-rc3] - 2026-09-13

### Changed

- When the selected card is the active SD2, show an explicit in-use warning and require confirmation before disconnecting its game binds and formatting it.
- Abort formatting if the card changes, bind deactivation fails, or any partition remains mounted. The formatter no longer attempts a silent unmount.
- Formatting recreates the partition table and exFAT filesystem; it does not perform zero-fill.

This workflow passed local safety checks and still needs real-device confirmation.

## [1.0.0-rc2] - 2026-09-13

### Fixed

- Added staged formatting progress and kept technical command output in the log instead of leaking into the interface.
- Cleared the previous card's manifest cache when mounting a newly formatted SD2, so its games can be discovered on the first scan.
- Strengthened device and partition validation before formatting proceeds.

These corrections passed local checks and still need real-device confirmation.

## [1.0.0-rc1] - 2026-08-15

First stable release candidate. No new functionality was added after 0.6.7-beta; this release promotes the tested beta code for final stabilization.

### Validated on real hardware

- ArkOS starts normally with SD2 absent.
- Inserting SD2 after startup is detected and its managed links are rebuilt.
- Games stored on SD2 launch successfully after link reconstruction.
- Interrupted transfers preserve the original source instead of deleting it.
- SD1 → SD2 and SD2 → SD1 transfers were exercised repeatedly.
- PortMaster games and directories containing many files were tested extensively across multiple beta versions.
- Permanent deletion, reboot restoration, installation updates, direct SD2 imports and controller navigation were exercised during development.

### Release policy

- The feature set is frozen for the 1.0 release.
- Only critical bug fixes, data-safety corrections, compatibility fixes and diagnostic improvements should enter another release candidate.
- If no critical regression is found during normal use, this code is intended to become 1.0.0.

### Known limitations

- Shared files referenced by multiple playlists are not tracked through a global dependency index.
- Existing SD1/SD2 path conflicts are preserved and reported but require manual resolution.
- Hardware validation outside the R36H/RG351MP-compatible ArkOS environment remains community-driven.

## [0.6.7-beta] - 2026-08-11

Release candidate for the first stable ROM Splitter version. This beta consolidates the complete dual-storage workflow and the fixes found during real-device testing.

### Highlights

- Moves individual games or batches between SD1 and SD2 while preserving the paths expected by EmulationStation.
- Restores games from SD2 to SD1 and supports permanent deletion from either storage after explicit confirmation.
- Browses all games normally or through the filtered SD1/SD2 → system → games workflow.
- Groups CUE/BIN, M3U multidisc sets and PortMaster launchers/data directories as logical games.
- Detects games copied directly to SD2 and rebuilds their links with progressive scan feedback.
- Supports switching between multiple UUID-identified SD2 cards with independent manifests and conflict protection.
- Provides controller navigation on the R36H/RG351MP through the firmware's `gptokeyb`.
- Displays separate progress for discovery, copying, file verification and transfer finalization.

### Fixed

- Fixed gauge protocol lines such as `XXX`, percentages and scan messages appearing as systems in the SD1/SD2 browser.
- Corrected file-descriptor redirection order so system names go only to the menu cache and progress events go only to the gauge.
- Fixed application exits caused by short adaptive dialogs returning a false arithmetic status under Bash `set -e`.
- Fixed application exits after new-game scans and completed transfers.
- Fixed SD1 system discovery `Broken pipe` errors on large libraries.
- Fixed duplicated directory nesting during PortMaster transfers.
- Fixed B-button navigation, empty-selection handling and checklist selection using X.

### Performance and interface

- Caches a prepared game list while the user remains inside the same system.
- Defers recursive PortMaster size calculation until selection.
- Uses progressive system discovery for the storage-specific browser.
- Sizes menus, messages, confirmations, checklists and gauges according to their content.
- Keeps pagination for long system and game lists.

### Safety

- Verifies copied content with SHA-256 before removing the source.
- Preserves the original and rolls back completed members when a grouped transfer fails.
- Never overwrites a real SD1 file when activating, importing or switching SD2 cards.
- Records managed bind placeholders separately so only ROM Splitter-owned paths are removed.
- Protects detected system and ROM devices from SD2 formatting.

### Validation

- Tested interactively on an R36H running an ArkOS image that identifies the device as `RG351MP`.
- Locally tested SD1 → SD2 → SD1 round trips, PortMaster directory transfers, deletion, multidisc grouping, multiple-card switching and conflict preservation.
- Release scripts pass Bash syntax validation and the generated ZIP passes integrity verification.

### Remaining beta limitations

- Broader compatibility testing is still needed across the other supported ArkOS/dArkOS handheld models.
- Shared files referenced by multiple playlists are not tracked through a global dependency index.
- Existing SD1/SD2 path conflicts are reported and preserved but require manual resolution.
- Formatting should continue to be tested with expendable media until the stable release.

## [0.6.6-beta] - 2026-08-11

### Fixed

- Fixed the application closing before showing the empty game-selection warning.
- Fixed the application closing after a completed copy instead of showing its result dialog.
- The adaptive dialog-size helper now always returns success and cannot trigger Bash `set -e` for short text.

## [0.6.5-beta] - 2026-08-11

### Fixed

- Fixed the application closing after the new-game scan finishes.
- The scan gauge now stays below 100% until its producer exits, avoiding a dialog/SIGPIPE race, and the result screen explicitly returns control to the main menu.
- Conflict items now update the live scan counter instead of skipping their progress event.

### Added

- Added a progressive system-discovery gauge after selecting SD1 or SD2 in the storage browser.
- SD1 discovery displays the current system and processed/total count; SD2 reports manifest processing.
- The discovered system list is reused by the following menu instead of being calculated a second time.

## [0.6.4-beta] - 2026-08-11

### Changed

- Applied content-based sizing to message, confirmation and information dialogs.
- Checklist height now follows its visible item count, with pagination retained for long game lists.
- Scanning, copying and verification gauges now use a more compact 9×68 layout.
- Short dialogs use a 60-column width and expand only when their content requires additional space.

## [0.6.3-beta] - 2026-08-11

### Fixed

- Fixed the remaining SD1 `Broken pipe`: the storage detector no longer stops consuming a system's sorted item stream after finding its first SD1 game.

### Changed

- Short menus now use a compact one-line navigation hint, 60-column width and content-based height.
- The SD1/SD2 selector is reduced to 9 rows, while detailed X/L1/R1 help remains available where it is relevant in game checklists.

## [0.6.2-beta] - 2026-08-11

### Fixed

- Fixed repeated `sort: write failed: Broken pipe` errors when opening the storage-specific browser.
- Replaced the early-closing `grep -q` pipeline with a complete system-list capture compatible with `pipefail`.

### Changed

- Dialog menu height now adapts to the number of options, reducing unused gray space in short menus such as the SD1/SD2 selector.
- Long system and main-menu lists retain their previous maximum dimensions and pagination.

## [0.6.1-beta] - 2026-08-11

### Added

- Added a progressive gauge to `Scan SD2 for new games`.
- The scan displays the current system/item, processed/total count, linked items, conflicts and failures.
- The existing result dialog remains available after the progress gauge closes.

## [0.6.0-beta] - 2026-08-10

### Added

- Added `Manage games by storage` to browse through SD1/SD2 → system → games.
- Added fast storage-aware system discovery using physical SD1 entries and the active SD2 manifest.
- Reuses the existing checklist, batching, move and permanent-delete operations in filtered storage views.
- Storage filters apply to complete logical groups, including CUE/M3U sets and PortMaster launcher/data directories.

### Changed

- Moving or deleting games invalidates the current filtered view so systems and locations remain accurate.
- Empty selections and cancelled dialogs continue to reuse the prepared in-system cache without rescanning.

## [0.5.0-beta] - 2026-08-09

### Added

- Added safe switching between multiple SD2 cards through `Activate/switch SD2 card`.
- Added a local manifest profile for each card UUID while retaining the portable manifest stored on each SD2.
- Added an active-bind registry so only placeholders created by ROM Splitter are removed during card deactivation.
- Added switch results showing the active UUID, links created, conflicts skipped and missing manifest items.
- Diagnostics now displays the active card profile and number of known card profiles.

### Changed

- Boot restoration now deactivates stale recorded binds before mounting and activating the inserted card profile.
- Safe unmount removes managed empty placeholders after their bind mounts are detached.
- A newly inserted card is detected by its saved UUID or the `ROMS2` filesystem label and becomes the preferred card.

### Security

- Existing non-managed SD1 files and non-empty directories block activation instead of being overwritten or hidden by a bind mount.
- Legacy installations migrate only mounted targets or safe empty placeholders from the previous local manifest into the bind registry.

## [0.4.4-beta] - 2026-08-09

### Performance

- Keeps the prepared game list cached while the user remains inside the same system.
- Pressing A without a selection, dismissing its warning, or cancelling an action no longer rescans the system.
- Invalidates and rebuilds the list only after switching systems or completing an operation that may change game locations or membership.

## [0.4.3-beta] - 2026-08-09

### Added

- Added a separate copy-verification gauge after transfer progress reaches 100%.
- Directory verification displays the current relative file and a checked/total file counter.
- Added a finalization status screen while bind mounts, source cleanup and manifest updates are performed.

### Changed

- Transfer feedback now clearly separates copying, integrity verification and finalization so the application no longer appears frozen at 100%.

## [0.4.2-beta] - 2026-08-09

First public beta candidate tested on an R36H running an ArkOS image that identifies the device as `RG351MP`.

### Highlights

- Manage individual games or batches across SD1 and SD2 without changing the paths expected by EmulationStation.
- Move games in both directions, permanently delete selected games, and discover games copied directly to SD2.
- Treat CUE/BIN sets, M3U multidisc games and PortMaster launchers/data directories as logical groups.
- Operate the complete `dialog` interface using handheld controls, including hierarchical B-button navigation.
- Show progressive feedback while scanning systems and copying directories, including current-file and copied/total counters.

### Fixed

- Fixed `PIPESTATUS[1]: unbound variable` after the game scanning gauge reached 100%.
- Captures the complete scan pipeline status before inspecting individual commands, preserving compatibility with Bash `set -u`.

### Beta notes

- Transfer, restoration, PortMaster grouping, controller navigation and scanning have been exercised on real R36H hardware.
- Formatting and transfers should still be tested with expendable media before using important cards.
- Existing conflicts where the same path contains different games on SD1 and SD2 are reported and skipped for manual resolution.
- Shared files referenced by multiple playlists are not yet tracked through a global dependency index.

## [0.4.1] - 2026-08-09

### Added

- Added a progressive scanning gauge whenever a system game list is opened or refreshed.
- The gauge reports storage scanning, logical group resolution and menu preparation progress with processed/total item counts.

## [0.4.0] - 2026-08-09

### Added

- Added permanent deletion of selected games from either SD1 or SD2.
- Deletion handles complete logical groups, including PortMaster launchers/data directories and CUE/M3U members.
- Added an action menu after game selection to choose between moving and deleting.

### Fixed

- Pressing B in the game checklist now returns to the system list instead of leaving the manager flow.
- Pressing A without marking a game now displays a selection-required message and returns to the game list.
- Game and system screens now use nested navigation loops so each B press returns exactly one screen.

## [0.3.1] - 2026-08-09

### Fixed

- Fixed directory transfers creating `game/game/files` instead of `game/files`.
- Directory copies now use trailing-slash rsync semantics and an equivalent safe `cp` fallback.
- Fixed PortMaster transfer verification failures caused by the duplicated directory level.
- Deduplicated SD1/SD2 directory candidates and uses launcher references to resolve otherwise ambiguous normalized names.
- Prevented PortMaster resolver warnings from being printed over the dialog interface while building the list.

### Added

- Directory transfer progress now displays the current relative file and a copied/total file counter such as `30/100`.
- Non-progress rsync output and errors are recorded in the ROM Splitter log for diagnosis.

### Performance

- PortMaster directory candidates are scanned once and cached for all launchers.
- Launcher path-related lines are parsed once instead of once per candidate directory.
- Recursive PortMaster directory size calculation is deferred until games are selected, avoiding a full scan of every installed port before displaying the list.

## [0.3.0] - 2026-08-09

### Added

- PortMaster launcher inspection for games whose `.sh` launcher and data directory use different names.
- Safe parsing of common `GAMEDIR`, `GAME_DIR`, `PORTDIR`, `PORT_DIR`, base/install directory assignments and `cd` commands.
- The parser never sources or executes PortMaster launchers while resolving their dependencies.

### Changed

- Only top-level `.sh` launchers are shown for recognized PortMaster games; their large data directories are hidden and transferred automatically with the launcher.
- Name-based matching remains the fast first choice, while launcher inspection is used as a fallback.
- Multiple possible directory references are treated as an ambiguity and blocked instead of guessed.

## [0.2.6] - 2026-08-09

### Performance

- Added a per-system inventory cache for game sizes and SD1/SD2 locations.
- Replaced repeated per-game `stat`, `awk` and manifest lookups with a single directory scan.
- Reuses cached dependency sizes when calculating CUE, M3U and PortMaster logical groups.
- Limits recursive size calculations to directory-based games, substantially reducing list loading time for systems containing many file-based ROMs.

## [0.2.5] - 2026-08-09

### Fixed

- Removed the duplicate `b = repeat` mapping that could override or interfere with `b = esc` on the R36H `gptokeyb` implementation.
- B now emits only Escape, providing reliable previous-screen navigation in `dialog` menus.

## [0.2.4] - 2026-08-09

### Fixed

- Fixed `Broken pipe` errors caused by the progress dialog receiving 100% before rsync finished writing its final output.
- Disabled progress-parser buffering so percentages reach the gauge as they are produced.
- Replaced the non-portable three-argument `awk match()` expression with a parser compatible with the awk implementations commonly shipped by ArkOS/dArkOS.
- Suppressed duplicate percentage updates and emits the final 100% only after the rsync output stream closes.

## [0.2.3] - 2026-08-09

### Fixed

- Added a dedicated `gptokeyb` profile for ROM Splitter instead of using the firmware's generic dialog mapping.
- Mapped B to Escape so it returns to the previous screen.
- Mapped X to Space so checklist items can be marked and unmarked.
- Mapped START to Escape and retained A as Enter.
- Kept the firmware's original `/opt/inttools/keys.gptk` unchanged.

## [0.2.2] - 2026-08-09

### Fixed

- Added native R36H/RG351MP controller support through `/opt/inttools/gptokeyb` and the firmware-provided `/opt/inttools/keys.gptk` mapping.
- Added `/opt/system/Tools/PortMaster/gptokeyb` as a compatible fallback location.
- Added `/opt/quitter/oga_controls` and `/opt/system/Tools/PortMaster/oga_controls` to the mapper search paths.
- Prevented a second mapper from starting when either `gptokeyb` or `oga_controls` is already active.
- Ensured a mapper started by ROM Splitter is stopped when the application exits.

## [0.2.1] - 2026-08-09

### Fixed

- Fixed a black screen when ROM Splitter was launched by EmulationStation without a controlling terminal.
- Added virtual-console launch handling through `openvt`, with an automatic return to the EmulationStation console after exit.
- Preserved direct interactive execution through SSH or a local terminal.

### Diagnostics

- Confirmed from an R36H trace that the application and `dialog` menu initialize correctly when a TTY is available.
- Confirmed that this R36H image identifies itself as `RG351MP` and does not provide `oga_controls` in the standard searched locations.

## [0.2.0] - 2026-08-08

### Added

- Automatic detection of candidate secondary storage devices.
- Protection against formatting devices containing `/`, `/boot`, or `/roms`.
- SD2 preparation using GPT, exFAT and the `ROMS2` label.
- UUID-based SD2 identification and mounting at `/roms2`.
- Game listing by EmulationStation system with size and storage location.
- Individual and batch transfers between SD1 and SD2.
- Free-space checks and SHA-256 copy verification before source removal.
- Bind mounts that preserve the original `/roms` paths used by EmulationStation.
- Persistent SD2 manifest and systemd boot service for bind restoration.
- Safe cancellation and rollback behavior for failed transfers.
- CUE/BIN grouping based on references declared inside CUE files.
- M3U multidisc grouping, including nested CUE dependencies.
- PortMaster launcher and game-directory grouping.
- Manual scanning for games copied directly to SD2 by computer or network.
- Conflict protection when the same logical path already exists on SD1.
- Storage diagnostics, bind repair and safe SD2 unmount operations.
- `dialog`/`whiptail` interface with terminal fallback.
- Built-in handheld controls through `oga_controls`.
- Automatic controller profiles for Anbernic RG351/RG353/RG503, R35S, R36S, R36H, RGB10, RK2020, OGA, OGS and GameForce devices.
- Hierarchical B-button navigation without accidentally exiting from the main menu.
- Safe desktop demo mode using `--demo`.
- Portable ZIP release builder and standalone installer for `/roms/tools`.
- Embedded SHA-256 package verification in the release installer.
- Preservation of existing SD2 configuration during package updates.
- English installation, usage, recovery and troubleshooting documentation.

### Changed

- Games are represented as logical groups instead of independent files when dependencies are detected.
- The Tools system is excluded from game management to protect the installed application and launchers.
- Copy verification now checks content rather than relying only on file size.
- SD2 placeholders remain identifiable after the card is unmounted.
- The boot restoration service retries when SD2 is not immediately available.

### Security

- Rejects absolute paths, parent-directory traversal, tabs and line breaks in managed paths.
- Refuses ambiguous PortMaster directory matches instead of selecting one automatically.
- Preserves the original source until copying, verification and bind creation complete successfully.

### Known limitations

- Version 0.6.7-beta has automated local coverage and R36H validation, but broader handheld compatibility testing is still required.
- Shared files referenced by multiple playlists are not yet tracked through a global dependency index.
- Existing SD1/SD2 conflicts are reported but require manual resolution.

[Unreleased]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc16...HEAD
[1.0.0-rc16]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc15...v1.0.0-rc16
[1.0.0-rc15]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc14...v1.0.0-rc15
[1.0.0-rc14]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc13...v1.0.0-rc14
[1.0.0-rc13]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc12...v1.0.0-rc13
[1.0.0-rc12]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc11...v1.0.0-rc12
[1.0.0-rc11]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc10...v1.0.0-rc11
[1.0.0-rc10]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc9...v1.0.0-rc10
[1.0.0-rc9]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc8...v1.0.0-rc9
[1.0.0-rc8]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc7...v1.0.0-rc8
[1.0.0-rc7]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc6...v1.0.0-rc7
[1.0.0-rc6]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc5...v1.0.0-rc6
[1.0.0-rc5]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc4...v1.0.0-rc5
[1.0.0-rc4]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc3...v1.0.0-rc4
[1.0.0-rc3]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc2...v1.0.0-rc3
[1.0.0-rc2]: https://github.com/FerreiraTechLab/ArkOS-SD2-Manager/compare/v1.0.0-rc1...v1.0.0-rc2
[1.0.0-rc1]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.6.7-beta...v1.0.0-rc1
[0.6.7-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.6.6-beta...v0.6.7-beta
[0.6.6-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.6.5-beta...v0.6.6-beta
[0.6.5-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.6.4-beta...v0.6.5-beta
[0.6.4-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.6.3-beta...v0.6.4-beta
[0.6.3-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.6.2-beta...v0.6.3-beta
[0.6.2-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.6.1-beta...v0.6.2-beta
[0.6.1-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.6.0-beta...v0.6.1-beta
[0.6.0-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.5.0-beta...v0.6.0-beta
[0.5.0-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.4.4-beta...v0.5.0-beta
[0.4.4-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.4.3-beta...v0.4.4-beta
[0.4.3-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.4.2-beta...v0.4.3-beta
[0.4.2-beta]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.4.1...v0.4.2-beta
[0.4.1]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.2.6...v0.3.0
[0.2.6]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/wesleiferreira98/ArkOS-SD2-Manager/releases/tag/v0.2.0
