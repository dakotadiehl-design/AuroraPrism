# Aurora C4.5 Final C4 Closeout

## Project-Safe Imported Stage Media and Stock Asset Completeness

**Project:** Aurora Lighting Control\
**Target:** `Aurora_C4_GhostFixed`\
**Phase:** C4.5 final closeout\
**Status:** Required before C5\
**Purpose:** Close the two remaining C4 requirements found during final
code review after the C4.4 ghosting fix.

------------------------------------------------------------------------

# 1. Review Verdict

The C4.4 ghosting fix is architecturally sound and may be retained.

The current `StageCanvasView` now uses the intended **Approach B**:

-   committed Stage-object host remains stable as an invisible gesture
    proxy while an object is actively transformed,
-   committed artwork is suppressed for transient targets,
-   the active object is drawn in a separate transient world-space
    visual layer,
-   transient visuals do not accept hit testing,
-   `drawingGroup()` / transform compositing hacks were removed from the
    live Stage-object transform path,
-   selection/transform chrome follows the transient geometry,
-   multi-object transient eligibility is supported,
-   rotation/menu fixes remain intact.

The severe ghosting defect is therefore considered **closed**, subject
to the user's successful production-app observation.

Do **not** reopen C4.4 rendering architecture during this pass unless a
new regression is demonstrated.

Two C4 requirements remain incomplete:

1.  **Imported Stage images are not truly project-portable.**
2.  **The required stock Stage infrastructure set is missing at least a
    lighting stand and riser/platform asset.**

C5 should start only after these two items are closed.

------------------------------------------------------------------------

# 2. Required Fix A --- Imported Stage Images Must Live With the Project

## 2.1 Current implementation

`BuildWorkspaceHost.designImportImage()` currently copies imported
images to:

``` text
~/Library/Application Support/Aurora/stage-media/<UUID>.<ext>
```

and stores:

``` swift
StageLayoutObject.mediaRef = dest.path
```

`StageCanvasView.importedImageView` later resolves the image using:

``` swift
NSImage(contentsOfFile: path)
```

This means the `.aurora` project contains an **absolute machine-local
filesystem path**.

The implementation comment calls the App Support copy "project-safe,"
but it is not project-portable.

### Failure example

``` text
Mac A:
~/Library/Application Support/Aurora/stage-media/A1B2.png

Show.aurora stores that absolute path.

Copy Show.aurora to Mac B.

Mac B:
A1B2.png does not exist at Mac A's path.

Result:
Stage image is missing.
```

The same failure can occur after:

-   clearing Application Support,
-   moving data between user accounts,
-   restoring only the `.aurora` package from backup,
-   sending a show file to another operator,
-   long-term archival.

This violates the C4D roadmap requirement:

> Do not leave project documents dependent on arbitrary external
> absolute file paths that can disappear.

------------------------------------------------------------------------

# 3. Existing Project Infrastructure Already Supports the Correct Model

Aurora already has project-package binary/media infrastructure.

`ProjectPackage` explicitly supports:

``` text
Show.aurora/
    media/
```

and preserves `media/` across normal Save and Save As.

Aurora also already has:

``` swift
MediaAssetRef
```

whose documented purpose is:

> Path relative to the package root, e.g. `media/logo.png`.

Do not invent a second permanent media-storage architecture if the
existing package/media model can be extended cleanly.

------------------------------------------------------------------------

# 4. Desired Imported Stage Media Model

The durable project representation should be package-relative.

Conceptually:

``` text
Show.aurora/
    media/
        stage/
            1A2B3C4D.png
            5E6F7A8B.jpg
```

The Stage document should store a stable relative reference, not an
external absolute path.

Preferred conceptual model:

``` swift
StageLayoutObject
    mediaRef: "media/stage/1A2B3C4D.png"
```

or, preferably if clean with the existing model:

``` swift
StageLayoutObject
    mediaAssetID: UUID
```

with:

``` swift
ShowProject.mediaAssets
    ↓
MediaAssetRef(
    id: ...,
    name: ...,
    relativePath: "media/stage/1A2B3C4D.png"
)
```

Use whichever approach best fits the existing code with minimal
migration risk.

------------------------------------------------------------------------

# 5. Unsaved Project Handling

Aurora may allow Stage image import before the project has a package
URL.

Do not solve this by making App Support paths permanent project
references.

Use a staging strategy.

Recommended:

``` text
user imports image
    ↓
copy into Aurora temporary/staging media store
    ↓
Stage object refers to a managed pending-media identity
    ↓
when project saves:
    copy managed media into Show.aurora/media/stage/
    ↓
persist package-relative reference
```

Alternative implementations are acceptable if they provide the same
guarantee.

Important invariant:

> Once a project is successfully saved, every imported Stage image
> required by that project must be recoverable from the project package
> itself.

------------------------------------------------------------------------

# 6. Save and Save As Requirements

## Normal Save

Imported Stage media already in the package must survive atomic package
replacement.

The existing `ProjectPackage.save(... preservingAssetsFrom:)` media-copy
behavior appears designed for this.

Verify it with Stage media specifically.

## Save As

When:

``` text
Original.aurora
→ Save As
→ TourCopy.aurora
```

all referenced Stage images must be present inside `TourCopy.aurora`.

Do not leave `TourCopy.aurora` referencing media only inside
`Original.aurora`.

## First Save

For an unsaved project with staged images:

``` text
Untitled project
+ imported floorplan.png
→ Save as MyShow.aurora
```

the first completed save must contain the image under `media/stage/`.

------------------------------------------------------------------------

# 7. Loading Imported Stage Images

Stop treating `mediaRef` as an arbitrary absolute path in production
rendering.

Current:

``` swift
NSImage(contentsOfFile: path)
```

Desired resolution:

``` text
project package URL
+
validated package-relative media path
→ image URL
```

or:

``` text
mediaAssetID
→ ShowProject.mediaAssets
→ relativePath
→ package URL
```

Do not allow package-relative paths to escape the package root through
`../` traversal.

Use the project's existing package-safety/path-validation conventions
where available.

------------------------------------------------------------------------

# 8. Legacy Migration

Current C4 projects may already contain absolute `mediaRef` paths into:

``` text
~/Library/Application Support/Aurora/stage-media/
```

Do not simply break those projects.

Implement a migration path.

Recommended behavior when loading/saving a legacy Stage image:

1.  Detect an absolute legacy `mediaRef`.
2.  If the referenced file still exists:
    -   import/copy it into managed package media on the next save,
    -   update the durable representation to
        package-relative/media-asset form.
3.  If it does not exist:
    -   retain a clear missing-media placeholder,
    -   do not crash,
    -   provide enough object/media identity for future relinking
        functionality.

Avoid silently deleting the Stage object.

------------------------------------------------------------------------

# 9. Media Cleanup

Do not aggressively delete media during routine object deletion unless
reference ownership is unquestionably safe.

For C4.5, it is acceptable for unused package media to remain orphaned.

Correctness and portability are more important than reclaiming a few
image files.

A later "Clean Project Media" function may garbage-collect unreferenced
files.

------------------------------------------------------------------------

# 10. Automated Tests for Imported Media

Add tests for at least:

## First-save embedding

``` text
unsaved/staged imported image
→ save project
→ image exists under package media/stage
→ Stage object resolves it
```

## Load portability

``` text
save package
→ copy package to new temporary directory
→ remove original staging/App Support source
→ load copied package
→ imported Stage image still resolves
```

This test is critical.

## Save As

``` text
source package contains Stage media
→ Save As destination
→ destination contains media
→ destination resolves Stage object
```

## Atomic re-save

``` text
save
→ modify project
→ save again
→ Stage media survives package replacement
```

## Legacy absolute-path migration

``` text
legacy object with absolute existing mediaRef
→ migration/save
→ durable package-relative reference
```

## Missing media

``` text
missing media file
→ load succeeds
→ Stage placeholder shown
→ no crash
```

------------------------------------------------------------------------

# 11. Manual Acceptance for Imported Media

Perform this in production Aurora:

-   [ ] Create new project.
-   [ ] Import a custom PNG floor plan into Stage.
-   [ ] Save as `MediaTest.aurora`.
-   [ ] Verify package contains the image in `media/stage/`.
-   [ ] Quit Aurora.
-   [ ] Copy the `.aurora` project to another directory.
-   [ ] Remove/rename the original imported source image.
-   [ ] If applicable, remove the old App Support staged copy.
-   [ ] Open the copied `.aurora` package.
-   [ ] Confirm the floor plan still renders.
-   [ ] Save As a second `.aurora` project.
-   [ ] Confirm the second package is independently complete.

This is the product-level acceptance test for C4D portability.

------------------------------------------------------------------------

# 12. Required Fix B --- Complete the Minimum Stock Infrastructure Set

The C4 roadmap requires these infrastructure assets at minimum:

-   crowd/audience,
-   mic stand,
-   speaker on stand,
-   **lighting stand**,
-   music stand,
-   **riser/platform**,
-   disco ball.

The current corrected stock catalog includes:

-   audience assets,
-   mic stands,
-   speaker on pole,
-   music stand,
-   truss,
-   disco ball,

but does not include dedicated stable stock entries for:

-   lighting stand,
-   riser/platform.

Using a generic Stage Area shape is useful, but it does not satisfy the
original stock-object-library requirement for a recognizable
riser/platform object.

Add original Aurora assets for both.

------------------------------------------------------------------------

# 13. New Stable Asset Keys

Recommended keys:

``` text
stage.equipment.lighting_stand
stage.equipment.riser_platform
```

Display names:

``` text
Lighting Stand
Riser / Platform
```

Do not reuse or rename existing stable asset keys.

Add these to:

-   source silhouette kit,
-   bundled Aurora Stage asset resources,
-   `Catalog.json`,
-   palette category metadata,
-   contact sheet/documentation as appropriate.

------------------------------------------------------------------------

# 14. Asset Requirements

Match the corrected Aurora silhouette kit:

-   isolated asset only,
-   no text baked into art,
-   transparent background,
-   tight bounds,
-   vector master,
-   suitable runtime tinting,
-   stable aspect ratio,
-   sensible default Stage size.

## Lighting stand

A recognizable tripod/T-bar or compact stage-lighting stand silhouette.

Do not make it visually indistinguishable from the speaker stand.

## Riser/platform

A low rectangular stage riser/platform rendered in a way that reads
clearly from the Stage Designer's top/diagram-oriented presentation.

It should be useful for:

-   drum riser,
-   keyboard riser,
-   general raised platform.

------------------------------------------------------------------------

# 15. Stock Catalog Tests

Add/adjust tests to verify:

``` text
stage.equipment.lighting_stand exists
stage.equipment.riser_platform exists
```

Verify:

-   stable key lookup,
-   no missing artwork,
-   aspect/default size metadata,
-   palette placement,
-   selection/resize/rotation behavior.

------------------------------------------------------------------------

# 16. C4.4 Regression Checks

Do not modify the ghosting renderer merely while completing these fixes.

Before approving C4:

-   [ ] rapid performer drag remains ghost-free,
-   [ ] multi-object drag remains ghost-free,
-   [ ] resize remains live,
-   [ ] rotation slider remains live,
-   [ ] direct rotation remains live,
-   [ ] beam aim remains live,
-   [ ] exactly one View menu remains,
-   [ ] Workspace menu remains present.

------------------------------------------------------------------------

# 17. Known C4 Deferrals That Do NOT Block C5

The following may remain deferred.

## Personality-defined Pan/Tilt physical range

`StageBeamDirectionResolver` correctly isolates the current fallback
mapping and contains a TODO for real fixture personality ranges.

This does **not** block C5 because:

-   static fixture Stage aim is correct,
-   moving-beam approximation is isolated behind a resolver,
-   no ad-hoc universal Pan math is embedded in `StageCanvasView`.

Retain the TODO for later fixture-definition enhancement.

## SVG-native Stage rendering

The corrected kit includes SVG masters, while current production
`StageStockGlyphView` uses PNG/`NSImage`.

This is not a C5 blocker if the current assets look acceptable at
expected Stage zoom ranges.

Keep vector-native rendering as a quality/performance future
enhancement.

## Line/truss endpoint handles

Four-corner transform handling is sufficient for the current C4
acceptance gate.

Dedicated endpoint handles may remain future UX refinement.

## Media garbage collection

Unused package Stage media may remain in the package.

Safe cleanup can come later.

------------------------------------------------------------------------

# 18. C4 Final Completion Criteria

C4 may be marked **complete** when:

-   C4.4 ghosting remains fixed in production,
-   Stage object movement/resizing/rotation works,
-   direct beam aim works,
-   static and moving beams remain usable,
-   object palette remains responsive,
-   corrected silhouette assets contain no raster-sheet text,
-   required minimum stock Stage object set is complete,
-   imported custom Stage images are embedded/managed with the `.aurora`
    project,
-   copied `.aurora` projects remain visually complete without the
    original source/App Support image,
-   Save As preserves Stage media,
-   native Xcode build succeeds,
-   relevant tests pass,
-   production portability test passes.

------------------------------------------------------------------------

# 19. STOP / HANDOFF

After C4.5:

> **STOP and produce a final C4 acceptance note.**

If all criteria above pass:

> **C4 is CLOSED. Proceed to C5 Multi-Monitor / Undockable Workspace.**

Do not add new C4 visual features during this closeout unless they are
required to fix a regression.

C4.5 should be small, boring, portable, and final.
