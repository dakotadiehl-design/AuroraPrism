import Foundation

/// Root show document: pure data, no hardware dependencies.
public struct ShowProject: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var metadata: ProjectMetadata
    public var preferences: ProjectPreferences
    public var fixtureDefinitions: [FixtureDefinition]
    public var universes: [Universe]
    public var fixtures: [PatchedFixture]
    public var groups: [Group]
    public var palettes: [Palette]
    public var presets: [Preset]
    public var cueLists: [CueList]
    public var songs: [Song]
    public var mediaAssets: [MediaAssetRef]
    public var midiMappings: [MIDIMapping]
    /// Advanced MIDI rules (P0-J). Simple mappings remain primary for basic learn.
    public var midiRules: [MIDIRule]
    /// Reusable MIDI behaviors with envelopes (P0-J).
    public var midiBehaviors: [MIDIBehaviorDefinition]
    /// Electronic drum / device note maps.
    public var drumProfiles: [DrumDeviceProfile]
    /// Outbound MIDI feedback profiles.
    public var midiFeedbackProfiles: [MIDIFeedbackProfile]
    /// Durable effect definitions (P1-4); order field defines apply stack.
    public var effects: [EffectDefinition]
    public var workspaceLayoutId: UUID?
    /// 2D Stage Designer layout (P0-A). Visual only — does not affect patch.
    public var stageLayout: StageLayout
    /// Advanced MIDI Engine + Musical Engine project document (schema v4+).
    public var ame: AMEProjectDocument

    public init(
        schemaVersion: Int = ProjectPackage.currentSchemaVersion,
        metadata: ProjectMetadata,
        preferences: ProjectPreferences = .default,
        fixtureDefinitions: [FixtureDefinition] = [],
        universes: [Universe] = [],
        fixtures: [PatchedFixture] = [],
        groups: [Group] = [],
        palettes: [Palette] = [],
        presets: [Preset] = [],
        cueLists: [CueList] = [],
        songs: [Song] = [],
        mediaAssets: [MediaAssetRef] = [],
        midiMappings: [MIDIMapping] = [],
        midiRules: [MIDIRule] = [],
        midiBehaviors: [MIDIBehaviorDefinition] = [],
        drumProfiles: [DrumDeviceProfile] = [],
        midiFeedbackProfiles: [MIDIFeedbackProfile] = [],
        effects: [EffectDefinition] = [],
        workspaceLayoutId: UUID? = nil,
        stageLayout: StageLayout = .empty,
        ame: AMEProjectDocument = .empty
    ) {
        self.schemaVersion = schemaVersion
        self.metadata = metadata
        self.preferences = preferences
        self.fixtureDefinitions = fixtureDefinitions
        self.universes = universes
        self.fixtures = fixtures
        self.groups = groups
        self.palettes = palettes
        self.presets = presets
        self.cueLists = cueLists
        self.songs = songs
        self.mediaAssets = mediaAssets
        self.midiMappings = midiMappings
        self.midiRules = midiRules
        self.midiBehaviors = midiBehaviors
        self.drumProfiles = drumProfiles
        self.midiFeedbackProfiles = midiFeedbackProfiles
        self.effects = effects
        self.workspaceLayoutId = workspaceLayoutId
        self.stageLayout = stageLayout
        self.ame = ame
    }

    /// Empty project suitable for offline editing with no drivers attached.
    public static func empty(name: String = "Untitled Show") -> ShowProject {
        ShowProject(metadata: ProjectMetadata(name: name))
    }

    /// Deterministic sample used by tests and optional UI smoke hooks.
    public static func sample() -> ShowProject {
        // Fixed UUIDs (valid 8-4-4-4-12 hex) for golden tests.
        let universeID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let definitionID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let fixtureID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        let cueListID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
        let cueID = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
        let groupID = UUID(uuidString: "00000000-0000-4000-8000-000000000006")!
        let channelID = UUID(uuidString: "00000000-0000-4000-8000-000000000007")!
        let songID = UUID(uuidString: "00000000-0000-4000-8000-000000000008")!
        let songEntryID = UUID(uuidString: "00000000-0000-4000-8000-000000000009")!
        let paletteID = UUID(uuidString: "00000000-0000-4000-8000-00000000000a")!
        let mappingID = UUID(uuidString: "00000000-0000-4000-8000-00000000000b")!
        let created = Date(timeIntervalSince1970: 1_725_000_000)

        let dimmer = FixtureDefinition(
            id: definitionID,
            manufacturer: "Generic",
            model: "Dimmer",
            modeName: "1-channel",
            channels: [
                ChannelDef(
                    id: channelID,
                    offset: 1,
                    name: "Intensity",
                    attribute: "intensity",
                    defaultValue: 0,
                    highlightValue: 255
                )
            ],
            colorModel: nil,
            hasPanTilt: false
        )

        let universe = Universe(
            id: universeID,
            number: 1,
            name: "Main",
            channelCount: 512,
            protocolHint: .local
        )

        let fixture = PatchedFixture(
            id: fixtureID,
            name: "SL Dim 1",
            definitionId: definitionID,
            universeId: universeID,
            address: 1,
            groupIds: [groupID]
        )

        let group = Group(id: groupID, name: "Stage Left", fixtureIds: [fixtureID])

        let cue = Cue(
            id: cueID,
            number: Decimal(string: "1.0")!,
            name: "House to half",
            fadeIn: 3,
            fadeOut: 0,
            delay: 0,
            follow: .none,
            tracking: .track,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.5])
            ])
        )

        let cueList = CueList(id: cueListID, name: "Main", cues: [cue])

        let song = Song(
            id: songID,
            title: "Opening",
            artist: "",
            entries: [
                SongEntry(
                    id: songEntryID,
                    target: .cueList(cueListID),
                    label: "Main list"
                )
            ]
        )

        return ShowProject(
            schemaVersion: ProjectPackage.currentSchemaVersion,
            metadata: ProjectMetadata(
                name: "Sample Show",
                author: "Aurora",
                notes: "PR2 golden fixture project",
                createdAt: created,
                modifiedAt: created
            ),
            preferences: ProjectPreferences(
                defaultFadeIn: 2,
                defaultFadeOut: 2,
                defaultTracking: .track,
                preferredFrameRateHz: 40
            ),
            fixtureDefinitions: [dimmer],
            universes: [universe],
            fixtures: [fixture],
            groups: [group],
            palettes: [
                Palette(
                    id: paletteID,
                    name: "Half",
                    type: .intensity,
                    values: ["intensity": 0.5]
                )
            ],
            presets: [],
            cueLists: [cueList],
            songs: [song],
            mediaAssets: [],
            midiMappings: [
                MIDIMapping(
                    id: mappingID,
                    name: "Go",
                    channel: 1,
                    messageType: "noteOn",
                    data1: 36,
                    action: "go"
                )
            ],
            workspaceLayoutId: nil
        )
    }
}

// MARK: - Patch invariants

public struct PatchOverlap: Equatable, Sendable, Hashable {
    public var first: UUID
    public var second: UUID
    public var universeId: UUID
}

public extension ShowProject {
    /// Returns pairs of fixtures whose DMX ranges overlap within the same universe.
    /// Uses each fixture's personality `channelCount` when the definition is present; otherwise 1.
    func overlappingPatchRanges() -> [PatchOverlap] {
        var definitionChannels: [UUID: UInt16] = [:]
        for definition in fixtureDefinitions {
            definitionChannels[definition.id] = definition.channelCount
        }

        var overlaps: [PatchOverlap] = []
        let byUniverse = Dictionary(grouping: fixtures.filter(\.isPatched), by: \.universeId)

        for (universeId, patched) in byUniverse {
            let sorted = patched.sorted { $0.address < $1.address }
            for i in 0..<sorted.count {
                let a = sorted[i]
                let aCount = definitionChannels[a.definitionId] ?? 1
                let aEnd = a.endAddress(channelCount: aCount)
                for j in (i + 1)..<sorted.count {
                    let b = sorted[j]
                    if b.address > aEnd { break }
                    let bCount = definitionChannels[b.definitionId] ?? 1
                    let bEnd = b.endAddress(channelCount: bCount)
                    if b.address <= aEnd && a.address <= bEnd {
                        overlaps.append(PatchOverlap(first: a.id, second: b.id, universeId: universeId))
                    }
                }
            }
        }
        return overlaps
    }
}
