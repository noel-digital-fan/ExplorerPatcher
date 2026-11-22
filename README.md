<!-- Explorer Patcher Plus: modified by noel-digital-fan on 2026-11-19. -->
<!-- Modified 2026-11-21: document source validation independent of binary publication. -->
# Explorer Patcher Plus

Explorer Patcher Plus is a free, unofficial fork of [ExplorerPatcher](https://github.com/valinet/ExplorerPatcher), maintained by [noel-digital-fan](https://github.com/noel-digital-fan). It combines ExplorerPatcher's Windows customization features with additional work on the Windows 10 taskbar search experience on Windows 11.

ExplorerPatcher is the foundation of this project. Its original authors and contributors deserve credit for the core program and the upstream fixes brought into this fork. This fork is independently maintained and is not an official ExplorerPatcher release.

## What Plus adds

The custom search changes apply when using the **Windows 10 (ExplorerPatcher) taskbar on Windows 11**:

- Keep the taskbar search box visible while Search is open.
- Display typed text, selection, and the caret inside that taskbar search box, while Windows Search keeps keyboard focus and input handling.
- Attach the search-results panel above the taskbar and align it with the search box after the Start button.
- Remove the floating panel's rounded corners and shadow for a more Windows 10-like appearance.
- Reapply positioning when Search opens, resizes, or lays out its content, and refresh positioning when search-box or taskbar icon-size settings change.

The fork also adds stable-release synchronization, update endpoints belonging to this repository, and the Explorer Patcher Plus display name. Internal filenames, settings keys, and installation paths retain `ExplorerPatcher` for upgrade compatibility.

Windows updates can affect shell behavior. A successful build does not establish that every Windows version or taskbar layout works; the custom search behavior still needs testing on the Windows builds you use.

## Authorship and AI assistance

- **Upstream work:** ExplorerPatcher, its original features, and imported upstream commits belong to the original authors and contributors. These commits are preserved with their history and are not claimed as our work.
- **Custom search work:** the fork's maintainer developed the additional taskbar search behavior with AI assistance. **Claude assisted with the main implementation**, as reported by the maintainer. The original custom commits are [`c0e3338`](https://github.com/noel-digital-fan/ExplorerPatcher/commit/c0e3338), [`14ee81f`](https://github.com/noel-digital-fan/ExplorerPatcher/commit/14ee81f), and [`cd6509d`](https://github.com/noel-digital-fan/ExplorerPatcher/commit/cd6509d).
- **Fork maintenance:** Codex assisted with the release-sync workflow, fork update routing, branding, documentation, and validation added on November 19, 2026.

AI assistance is disclosed for the fork-specific work; it does not describe the authorship of the upstream project. Maintainers remain responsible for reviewing and testing changes.

## Distribution status and license

The ExplorerPatcher source is distributed under the **GNU General Public License, version 2**, preserved in [LICENSE](LICENSE). The source of this fork follows the same terms. Original copyright notices, license notices, and author history are retained. Fork-specific modifications are identified in the affected files and in this README.

This project is intended to be shared free of charge, with no profit sought by its maintainer. That policy does not restrict recipients' rights under the GPL. The GPL's source, notice, and redistribution requirements apply even when a copy is given away for free. The software comes without warranty under the license.

**Binary publication is currently disabled.** The inherited build bundles third-party components whose redistribution terms need separate verification:

- `ep_taskbar` DLLs from [ExplorerPatcher/ep_taskbar_releases](https://github.com/ExplorerPatcher/ep_taskbar_releases), which has no published license in its repository. See the [maintainer's discussion of its closed-source status](https://github.com/valinet/ExplorerPatcher/discussions/5124).
- Microsoft Windows components downloaded by the inherited installer build, including `pnidui.dll`, `StartUI.dll`, and `JumpViewUI.dll`.

The GPL license for the main source does not establish permission to redistribute those separate binaries. Until the relevant permissions and source obligations are resolved, this fork publishes neither installers nor downloadable CI binary artifacts. Source changes and build checks can continue.

## Building and using the fork

Clone this repository with its submodules:

```powershell
git clone --recurse-submodules https://github.com/noel-digital-fan/ExplorerPatcher.git
cd ExplorerPatcher
```

The [Build workflow](.github/workflows/build.yml) records the toolchain, dependencies, and commands used by this fork. It builds x64 and ARM64 installers and validates their embedded update metadata. See the upstream [compilation guide](https://github.com/valinet/ExplorerPatcher/wiki/Compiling) for background. Building for your own use does not establish permission to redistribute all bundled components.

If you have a locally built installer, use `ep_setup.exe` for Intel/AMD x64 or `ep_setup_arm64.exe` for ARM64. Installation requests administrator access and restarts File Explorer. Right-click the taskbar and select **Properties** to configure the program. Some features depend on your Windows version.

For a personal x64 installation, the repository owner can prepare an unpublished draft with a `personal-install-` tag targeting an exact source commit, then run the Build workflow with that commit and the draft's numeric `personal_release_id`. This stages an installer in the existing draft for authenticated download; it does not publish the draft or enable public releases or CI binary artifacts. Delete the temporary draft after downloading. Drafts are visible to repository users with write access, so check repository access before using this route.

To uninstall, use **Properties → Uninstall**, Windows **Installed apps**, or run the locally built installer with `/uninstall`. This fork upgrades the existing ExplorerPatcher installation rather than installing alongside it.

## Updates from this repository

Both built-in update channels default to **noel-digital-fan/ExplorerPatcher**. An explicitly saved URL pointing at the official ExplorerPatcher repository is treated as the fork's corresponding URL, so an old setting cannot replace your custom build with an official installer. The inherited `ep_make` update option, which builds the official repository, is removed from this fork; an old `UpdateUseLocal` setting is ignored. Other explicitly configured custom servers remain supported.

Once binary distribution is permitted and a fork release exists, **Properties → Updates** offers the existing choices to notify, prompt to install updates automatically, or check manually. Windows may still require administrator approval to install. For existing installations, install a newly built Plus version once to receive these defaults. With publication disabled, there are no fork installers for the updater to download.

## Following official releases

The [Sync official stable release workflow](.github/workflows/sync-upstream.yml) checks hourly, at minute 23. GitHub may delay scheduled runs and disables schedules in public repositories after 60 days without activity; check Actions if syncing stops. It can also be run manually from Actions.

The workflow fetches the latest **published stable release tag** from `valinet/ExplorerPatcher` and merges that exact commit into this fork's default branch. It does not follow every new commit or prerelease. Your custom commits are retained, including any newer upstream commits intentionally merged earlier. If a conflict or concurrent push occurs, the job fails without force-pushing; resolve the conflict and rerun it.

When a sync changes this fork's source, the workflow runs the Windows build and automation checks even while binary publication is disabled. Scheduled checks with no source changes do not rebuild the same unpublished version every hour. Run the sync workflow manually to retry validation of the current source. These checks do not publish installers or downloadable binary artifacts while the redistribution setting remains disabled.

The future installer-release path is prepared behind the repository variable `BINARY_REDISTRIBUTION_APPROVED`. It remains disabled unless that variable is exactly `true`. Do not enable it until the bundled-component permissions and source obligations have been resolved. When enabled, the workflow calls the build directly with the exact fork commit, stages both installers and a source archive, and publishes a `fork-<official-tag>` release only after all assets are present. Failed builds and incomplete draft releases are retried. Existing release tags keep their original source commit.

The source archive includes the fork's tracked source, checked-out submodule source, build scripts, retained notices, and any dependency-source patches applied by the build. It does not supply source or licensing permission for the separately obtained proprietary components listed above.

Run the release-sync checks locally with PowerShell:

```powershell
pwsh -File .github/scripts/Test-SyncUpstreamRelease.ps1
```

## Upstream project

Read the original [ExplorerPatcher documentation](https://github.com/valinet/ExplorerPatcher/wiki) for inherited settings and features, and [support the upstream developers](https://github.com/valinet/ExplorerPatcher?sponsor) if you find their work useful. Report fork-specific search, update, and branding problems in [this repository](https://github.com/noel-digital-fan/ExplorerPatcher/issues).
