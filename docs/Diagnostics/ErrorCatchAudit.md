# Prism Error Catch Audit

Current inventory: **151** `catch` sites under `Sources/`.

Each site is classified with a disposition. Status `migrated` means the site uses structured reporting, a typed log, rethrow-without-duplicate-log, or an explicit documented ignore.

Code `none` means the catch is control-flow only and must not emit a second operator event.

| File | Line | Classification | Category | Code | Status | Notes |
| --- | ---: | --- | --- | --- | --- | --- |
| `Sources/Aurora/AMEEngineWindowRoot.swift` | 193 | blocking popup | project.document | project.command.failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/AppModel.swift` | 392 | blocking popup | project.document | project.document.import_failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/AppModel.swift` | 445 | blocking popup | project.document | project.document.open_failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/AppModel.swift` | 607 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/AppModel.swift` | 629 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/AppModel.swift` | 697 | blocking popup | project.document | project.document.save_failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/AppModel.swift` | 712 | expected control flow | project.document | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/Aurora/AppModel.swift` | 721 | expected control flow | project.document | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/Aurora/AppModel.swift` | 756 | blocking popup | project.document | project.command.failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/AppModel.swift` | 846 | blocking popup | project.document | project.command.failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/AppModel.swift` | 865 | blocking popup | project.document | project.command.failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/AppModel.swift` | 956 | operational log | engine.show | engine.show.start_failed | migrated | Typed PrismLog event at this site. |
| `Sources/Aurora/ControlActionRouter.swift` | 641 | expected control flow | app.lifecycle | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/Aurora/Controllers/AppSettingsStore.swift` | 106 | inline status | app.settings | app.settings.config_fallback | migrated | Corrupt logging JSON; warning is emitted after logger bootstrap. |
| `Sources/Aurora/Controllers/InputController.swift` | 121 | inline status | control.midi | none | migrated | Human status only; the domain emitter already logged or no extra log is required. |
| `Sources/Aurora/Controllers/InputController.swift` | 195 | inline status | control.midi | none | migrated | Human status only; the domain emitter already logged or no extra log is required. |
| `Sources/Aurora/Controllers/InputController.swift` | 236 | inline status | control.midi | control.midi.learned | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Controllers/OutputController.swift` | 209 | inline status | output.routing | none | migrated | Human status only; the domain emitter already logged or no extra log is required. |
| `Sources/Aurora/Controllers/OutputController.swift` | 248 | inline status | output.routing | none | migrated | Human status only; the domain emitter already logged or no extra log is required. |
| `Sources/Aurora/Controllers/OutputController.swift` | 363 | intentionally ignored | output.artnet | output.artnet.failed | migrated | Driver start already emits the protocol failed event; catch avoids dual-write. |
| `Sources/Aurora/Controllers/OutputController.swift` | 380 | intentionally ignored | output.artnet | output.artnet.failed | migrated | Driver start already emits the protocol failed event; catch avoids dual-write. |
| `Sources/Aurora/Controllers/ProjectController.swift` | 86 | operational log | fixture.library | fixture.library.load_failed | migrated | Typed log at this site; userFacingMessage does not re-log. |
| `Sources/Aurora/Controllers/ProjectController.swift` | 99 | operational log | fixture.library | fixture.library.load_failed | migrated | Typed log at this site; userFacingMessage does not re-log. |
| `Sources/Aurora/Controllers/ProjectController.swift` | 312 | operational log | project.autosave | project.autosave.failed | migrated | Typed PrismLog event at this site. |
| `Sources/Aurora/Controllers/RemoteController.swift` | 114 | inline status | remote.host | none | migrated | Human status only; the domain emitter already logged or no extra log is required. |
| `Sources/Aurora/Controllers/ShowControlController.swift` | 157 | operational log | engine.show | engine.show.start_failed | migrated | Typed PrismLog event at this site. |
| `Sources/Aurora/LightKeyFixtureImporterWindow.swift` | 96 | expected control flow | fixture.lightkey | fixture.lightkey.import_failed | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/Aurora/LightKeyFixtureImporterWindow.swift` | 141 | expected control flow | fixture.lightkey | fixture.lightkey.import_failed | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/Aurora/Settings/AuroraSettingsRoot.swift` | 92 | blocking popup | fixture.library | fixture.library.load_failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/Settings/AuroraSettingsRoot.swift` | 127 | blocking popup | fixture.library | fixture.library.failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/Settings/AuroraSettingsRoot.swift` | 283 | inline status | control.midi | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Settings/AuroraSettingsRoot.swift` | 509 | inline status | output.routing | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Shell/DesignStageSurface.swift` | 402 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Shell/DesignStageSurface.swift` | 491 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Shell/DesignStageSurface.swift` | 502 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Shell/DesignStageSurface.swift` | 595 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Shell/DesignStageSurface.swift` | 815 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Shell/DesignStageSurface.swift` | 826 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Shell/DesignStageSurface.swift` | 907 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/Aurora/Tools/CheckpointBScreenshotExporter.swift` | 31 | operational log | ui.presentation | ui.presentation.export_failed | migrated | Screenshot export failure logged as ui.presentation.export_failed. |
| `Sources/Aurora/Tools/CheckpointBScreenshotExporter.swift` | 43 | operational log | ui.presentation | ui.presentation.export_failed | migrated | Screenshot export failure logged as ui.presentation.export_failed. |
| `Sources/Aurora/Tools/CheckpointC1ScreenshotExporter.swift` | 31 | operational log | ui.presentation | ui.presentation.export_failed | migrated | Screenshot export failure logged as ui.presentation.export_failed. |
| `Sources/Aurora/Tools/CheckpointC1ScreenshotExporter.swift` | 46 | operational log | ui.presentation | ui.presentation.export_failed | migrated | Screenshot export failure logged as ui.presentation.export_failed. |
| `Sources/Aurora/Tools/CheckpointC2ScreenshotExporter.swift` | 33 | operational log | ui.presentation | ui.presentation.export_failed | migrated | Screenshot export failure logged as ui.presentation.export_failed. |
| `Sources/Aurora/Tools/CheckpointC3ScreenshotExporter.swift` | 31 | operational log | ui.presentation | ui.presentation.export_failed | migrated | Screenshot export failure logged as ui.presentation.export_failed. |
| `Sources/Aurora/UserFixtureLibraryWindow.swift` | 164 | blocking popup | fixture.library | fixture.library.failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/Aurora/UserFixtureLibraryWindow.swift` | 183 | blocking popup | fixture.library | fixture.library.failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/AuroraCore/DocumentSession+PatchBatch.swift` | 45 | expected control flow | project.document | project.command.rolled_back | migrated | Apply/undo rollback; debug log project.command.rolled_back when rollback runs. |
| `Sources/AuroraCore/DocumentSession.swift` | 123 | operational log | project.document | project.command.rolled_back | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraCore/DocumentSession.swift` | 176 | operational log | project.document | project.command.rolled_back | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraCore/DocumentSession.swift` | 205 | operational log | project.document | project.command.rolled_back | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraFixtureLib/FixtureImporter.swift` | 64 | expected control flow | fixture.import | fixture.import.failed | migrated | Format probe / parse fallback; importer emits fixture.import.failed on terminal failure. |
| `Sources/AuroraFixtureLib/FixtureImporter.swift` | 66 | expected control flow | fixture.import | fixture.import.failed | migrated | Format probe / parse fallback; importer emits fixture.import.failed on terminal failure. |
| `Sources/AuroraFixtureLib/FixtureImporter.swift` | 68 | expected control flow | fixture.import | fixture.import.failed | migrated | Format probe / parse fallback; importer emits fixture.import.failed on terminal failure. |
| `Sources/AuroraFixtureLib/FixtureImporter.swift` | 422 | expected control flow | fixture.import | fixture.import.failed | migrated | Format probe / parse fallback; importer emits fixture.import.failed on terminal failure. |
| `Sources/AuroraFixtureLib/FixtureLibrary.swift` | 39 | expected control flow | fixture.library | none | migrated | Maps or rethrows; caller or later typed event owns operator presentation. |
| `Sources/AuroraFixtureLib/FixtureLibrary.swift` | 46 | expected control flow | fixture.library | none | migrated | Maps or rethrows; caller or later typed event owns operator presentation. |
| `Sources/AuroraFixtureLib/FixtureLibrary.swift` | 68 | operational log | fixture.library | none | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraFixtureLib/FixtureLibrary.swift` | 75 | operational log | fixture.library | fixture.library.loaded | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraFixtureLib/LightKey/LightKeyFixtureImporter.swift` | 375 | expected control flow | fixture.import | fixture.import.failed | migrated | Format probe / parse fallback; importer emits fixture.import.failed on terminal failure. |
| `Sources/AuroraModel/AuroraLibraryPackage.swift` | 146 | expected control flow | fixture.library | fixture.library.load_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraModel/AuroraLibraryPackage.swift` | 155 | expected control flow | fixture.library | fixture.library.load_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraModel/AuroraLibraryPackage.swift` | 158 | expected control flow | fixture.library | fixture.library.load_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraModel/AuroraLibraryPackage.swift` | 229 | expected control flow | fixture.library | fixture.library.not_a_package | migrated | Maps or rethrows; caller or later typed event owns operator presentation. |
| `Sources/AuroraModel/AuroraLibraryPackage.swift` | 231 | expected control flow | fixture.library | fixture.library.not_a_package | migrated | Maps or rethrows; caller or later typed event owns operator presentation. |
| `Sources/AuroraModel/ProjectPackage.swift` | 222 | operational log | project.document | project.document.saved | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraModel/ProjectPackage.swift` | 230 | operational log | project.document | project.document.saved | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraModel/ProjectPackage.swift` | 241 | expected control flow | project.document | project.document.saved | migrated | Maps or rethrows; caller or later typed event owns operator presentation. |
| `Sources/AuroraModel/ProjectPackage.swift` | 243 | expected control flow | project.document | project.document.saved | migrated | Maps or rethrows; caller or later typed event owns operator presentation. |
| `Sources/AuroraModel/ProjectPackage.swift` | 277 | expected control flow | project.document | project.document.open_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraModel/ProjectPackage.swift` | 289 | expected control flow | project.document | project.document.open_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraModel/ProjectPackage.swift` | 570 | expected control flow | project.document | project.document.open_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraModel/ProjectPackage.swift` | 572 | expected control flow | project.document | project.document.open_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraModel/ProjectPackage.swift` | 596 | expected control flow | project.document | project.document.open_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraModel/ProjectPackage.swift` | 598 | expected control flow | project.document | project.document.open_failed | migrated | Decode/migration fallback; package APIs emit open/save/migrate events at the boundary. |
| `Sources/AuroraMusical/MusicalTypes.swift` | 130 | expected control flow | music.song | none | migrated | Parse fallback for musical meter text; no operator popup. |
| `Sources/AuroraOutput/ArtNetOutputDriver.swift` | 75 | operational log | output.artnet | output.artnet.failed | migrated | Typed log at this site; userFacingMessage does not re-log. |
| `Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift` | 448 | operational log | output.localDMX | none | migrated | Typed log at this site; userFacingMessage does not re-log. |
| `Sources/AuroraOutput/ENTTECUSBDMXProDriver.swift` | 544 | operational log | output.localDMX | none | migrated | Typed log at this site; userFacingMessage does not re-log. |
| `Sources/AuroraOutput/OutputManager.swift` | 56 | operational log | output.routing | output.routing.changed | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraOutput/SACNOutputDriver.swift` | 77 | operational log | output.sacn | output.sacn.failed | migrated | Typed log at this site; userFacingMessage does not re-log. |
| `Sources/AuroraRemote/RemoteMessages.swift` | 157 | operational log | remote.codec | remote.codec.invalid | migrated | Typed PrismLog event at this site. |
| `Sources/AuroraUI/Panels/CueBlocksPanel.swift` | 834 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueBlocksPanel.swift` | 880 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueBlocksPanel.swift` | 897 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueBlocksPanel.swift` | 942 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueBlocksPanel.swift` | 1120 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueBlocksPanel.swift` | 1134 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueBlocksPanel.swift` | 1151 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueBlocksPanel.swift` | 1164 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 336 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 349 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 371 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 396 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 417 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 434 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 450 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 639 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 680 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 694 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 708 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 733 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/CueListPanel.swift` | 745 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/FixtureBrowserPanel.swift` | 206 | blocking popup | ui.patch | ui.patch.command_failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/AuroraUI/Panels/FixtureBrowserPanel.swift` | 281 | blocking popup | ui.patch | ui.patch.command_failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/AuroraUI/Panels/FixtureProfileEditorPanel.swift` | 369 | inline status | fixture.library | fixture.library.save_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/FixtureProfileEditorPanel.swift` | 408 | inline status | fixture.library | fixture.library.save_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/FixtureProfileEditorPanel.swift` | 427 | inline status | fixture.library | fixture.library.save_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/FixtureProfileEditorPanel.swift` | 469 | inline status | fixture.library | fixture.library.save_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/InspectorPanel.swift` | 217 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/InspectorPanel.swift` | 277 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/InspectorPanel.swift` | 303 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/InspectorPanel.swift` | 327 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/InspectorPanel.swift` | 351 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PalettesPanel.swift` | 277 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PalettesPanel.swift` | 297 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PalettesPanel.swift` | 432 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PalettesPanel.swift` | 484 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PalettesPanel.swift` | 497 | inline status | project.document | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 502 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 514 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 534 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 544 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 565 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 598 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 619 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 645 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchPanel.swift` | 657 | expected control flow | ui.patch | none | migrated | Control-flow catch; no operator-facing popup. |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 689 | inline status | ui.patch | fixture.library.save_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 1222 | blocking popup | ui.patch | ui.patch.command_failed | migrated | Presents PrismErrorReport after a single report(). |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 1256 | inline status | ui.patch | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 1281 | inline status | ui.patch | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 1325 | inline status | ui.patch | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 1533 | inline status | ui.patch | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 1546 | inline status | ui.patch | fixture.library.save_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 1641 | inline status | ui.patch | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/PatchWorkspaceView.swift` | 1652 | inline status | ui.patch | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/SongPanel.swift` | 253 | inline status | music.song | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/SongPanel.swift` | 265 | inline status | music.song | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/SongPanel.swift` | 322 | inline status | music.song | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/StagePanel.swift` | 380 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/StagePanel.swift` | 391 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Panels/StagePanel.swift` | 439 | inline status | ui.stage | ui.stage.layout_commit_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Stage/StageCanvasView.swift` | 1535 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Stage/StageCanvasView.swift` | 1553 | inline status | ui.stage | project.command.failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Stage/StageCanvasView.swift` | 1578 | inline status | ui.stage | ui.stage.layout_commit_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Stage/StageStockCatalog.swift` | 119 | inline status | ui.stage | ui.stage.media_failed | migrated | Logs once via report(); panel shows human status text. |
| `Sources/AuroraUI/Workspace/FloatSurfaceID.swift` | 343 | intentionally ignored + debug | ui.workspace | ui.workspace.float_persist_failed | migrated | Persistence failure logged; UI continues with defaults. |
| `Sources/AuroraUI/Workspace/FloatSurfaceID.swift` | 358 | intentionally ignored + debug | ui.workspace | ui.workspace.float_persist_failed | migrated | Persistence failure logged; UI continues with defaults. |
| `Sources/AuroraUI/Workspace/WorkspaceLayoutStore.swift` | 30 | intentionally ignored + debug | ui.workspace | ui.workspace.layout_load_failed | migrated | Persistence failure logged; UI continues with defaults. |
| `Sources/AuroraUI/Workspace/WorkspaceLayoutStore.swift` | 48 | intentionally ignored + debug | ui.workspace | ui.workspace.layout_save_failed | migrated | Persistence failure logged; UI continues with defaults. |

Total sites: 151

