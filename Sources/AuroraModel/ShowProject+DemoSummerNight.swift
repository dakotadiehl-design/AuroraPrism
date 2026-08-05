import Foundation

public extension ShowProject {
    /// Deterministic populated demo for UI-02A visual validation (Summer Night Show).
    /// Real model objects only — load via normal document path.
    static func demoSummerNight() -> ShowProject {
        // Fixed IDs for stable screenshots / reload.
        let u1 = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
        let dimDef = UUID(uuidString: "A1000000-0000-4000-8000-000000000010")!
        let rgbDef = UUID(uuidString: "A1000000-0000-4000-8000-000000000011")!
        let mhDef = UUID(uuidString: "A1000000-0000-4000-8000-000000000012")!
        let listID = UUID(uuidString: "A1000000-0000-4000-8000-000000000020")!
        let songID = UUID(uuidString: "A1000000-0000-4000-8000-000000000030")!
        let created = Date(timeIntervalSince1970: 1_725_200_000)

        let dimmerDef = FixtureDefinition(
            id: dimDef,
            manufacturer: "Generic",
            model: "Dimmer",
            modeName: "1ch",
            channels: [
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000101")!, offset: 1, name: "Intensity", attribute: "intensity", defaultValue: 0, highlightValue: 255)
            ],
            colorModel: nil,
            hasPanTilt: false
        )
        let rgbDefinition = FixtureDefinition(
            id: rgbDef,
            manufacturer: "Generic",
            model: "RGB Wash",
            modeName: "3ch",
            channels: [
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000111")!, offset: 1, name: "Red", attribute: "colorR", defaultValue: 0, highlightValue: 255),
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000112")!, offset: 2, name: "Green", attribute: "colorG", defaultValue: 0, highlightValue: 255),
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000113")!, offset: 3, name: "Blue", attribute: "colorB", defaultValue: 0, highlightValue: 255),
            ],
            colorModel: .rgb,
            hasPanTilt: false
        )
        let mhDefinition = FixtureDefinition(
            id: mhDef,
            manufacturer: "Generic",
            model: "Moving Head",
            modeName: "basic",
            channels: [
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000121")!, offset: 1, name: "Pan", attribute: "pan", defaultValue: 128, highlightValue: 128),
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000122")!, offset: 2, name: "Tilt", attribute: "tilt", defaultValue: 128, highlightValue: 128),
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000123")!, offset: 3, name: "Intensity", attribute: "intensity", defaultValue: 0, highlightValue: 255),
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000124")!, offset: 4, name: "Red", attribute: "colorR", defaultValue: 0, highlightValue: 255),
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000125")!, offset: 5, name: "Green", attribute: "colorG", defaultValue: 0, highlightValue: 255),
                ChannelDef(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000126")!, offset: 6, name: "Blue", attribute: "colorB", defaultValue: 0, highlightValue: 255),
            ],
            colorModel: .rgb,
            hasPanTilt: true
        )

        // UI-02 C2: demo must not surprise-route Art-Net; operator enables network output explicitly.
        let universe = Universe(id: u1, number: 1, name: "Main Stage", channelCount: 512, protocolHint: .none)

        // Fixtures
        var fixtures: [PatchedFixture] = []
        var addr: UInt16 = 1
        func add(_ name: String, def: UUID, ch: UInt16, idSuffix: String) -> UUID {
            let id = UUID(uuidString: "A1000000-0000-4000-8000-0000000002\(idSuffix)")!
            fixtures.append(PatchedFixture(id: id, name: name, definitionId: def, universeId: u1, address: addr))
            addr += ch
            return id
        }

        let front1 = add("Front Wash 1", def: rgbDef, ch: 3, idSuffix: "01")
        let front2 = add("Front Wash 2", def: rgbDef, ch: 3, idSuffix: "02")
        let front3 = add("Front Wash 3", def: rgbDef, ch: 3, idSuffix: "03")
        let front4 = add("Front Wash 4", def: rgbDef, ch: 3, idSuffix: "04")
        let back1 = add("Back Wash 1", def: rgbDef, ch: 3, idSuffix: "05")
        let back2 = add("Back Wash 2", def: rgbDef, ch: 3, idSuffix: "06")
        let back3 = add("Back Wash 3", def: rgbDef, ch: 3, idSuffix: "07")
        let back4 = add("Back Wash 4", def: rgbDef, ch: 3, idSuffix: "08")
        let spot1 = add("Spot 1", def: mhDef, ch: 6, idSuffix: "09")
        let spot2 = add("Spot 2", def: mhDef, ch: 6, idSuffix: "0A")
        let spot3 = add("Spot 3", def: mhDef, ch: 6, idSuffix: "0B")
        let spot4 = add("Spot 4", def: mhDef, ch: 6, idSuffix: "0C")
        let aud1 = add("Audience L", def: dimDef, ch: 1, idSuffix: "0D")
        let aud2 = add("Audience R", def: dimDef, ch: 1, idSuffix: "0E")
        let house = add("House", def: dimDef, ch: 1, idSuffix: "0F")

        let gFront = UUID(uuidString: "A1000000-0000-4000-8000-000000000301")!
        let gBack = UUID(uuidString: "A1000000-0000-4000-8000-000000000302")!
        let gMovers = UUID(uuidString: "A1000000-0000-4000-8000-000000000303")!
        let gAudience = UUID(uuidString: "A1000000-0000-4000-8000-000000000304")!

        let groups = [
            Group(id: gFront, name: "Front Wash", fixtureIds: [front1, front2, front3, front4]),
            Group(id: gBack, name: "Back Wash", fixtureIds: [back1, back2, back3, back4]),
            Group(id: gMovers, name: "Movers", fixtureIds: [spot1, spot2, spot3, spot4]),
            Group(id: gAudience, name: "Audience", fixtureIds: [aud1, aud2, house]),
        ]

        // Update group membership on fixtures
        for i in fixtures.indices {
            var f = fixtures[i]
            var gids: [UUID] = []
            if [front1, front2, front3, front4].contains(f.id) { gids.append(gFront) }
            if [back1, back2, back3, back4].contains(f.id) { gids.append(gBack) }
            if [spot1, spot2, spot3, spot4].contains(f.id) { gids.append(gMovers) }
            if [aud1, aud2, house].contains(f.id) { gids.append(gAudience) }
            f.groupIds = gids
            fixtures[i] = f
        }

        let palettes: [Palette] = [
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000401")!, name: "Warm Amber", type: .color, values: ["colorR": 1, "colorG": 0.55, "colorB": 0.15]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000402")!, name: "Deep Blue", type: .color, values: ["colorR": 0.1, "colorG": 0.2, "colorB": 0.9]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000403")!, name: "Open White", type: .color, values: ["colorR": 1, "colorG": 0.95, "colorB": 0.9]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000404")!, name: "Magenta", type: .color, values: ["colorR": 0.9, "colorG": 0.15, "colorB": 0.55]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000405")!, name: "Center", type: .position, values: ["pan": 0.5, "tilt": 0.45]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000406")!, name: "Drummer", type: .position, values: ["pan": 0.35, "tilt": 0.55]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000407")!, name: "Audience", type: .position, values: ["pan": 0.5, "tilt": 0.75]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000408")!, name: "Wide", type: .beam, values: ["intensity": 1]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000409")!, name: "Full", type: .intensity, values: ["intensity": 1]),
            Palette(id: UUID(uuidString: "A1000000-0000-4000-8000-00000000040A")!, name: "Half", type: .intensity, values: ["intensity": 0.5]),
        ]

        // UI-04: Looks carry real multi-fixture levels so apply is demonstrable.
        let warmRGB: [String: Double] = ["colorR": 1, "colorG": 0.55, "colorB": 0.15, "intensity": 0.85]
        let coolRGB: [String: Double] = ["colorR": 0.1, "colorG": 0.25, "colorB": 0.9, "intensity": 0.7]
        let fullRGB: [String: Double] = ["colorR": 1, "colorG": 0.95, "colorB": 0.9, "intensity": 1]
        func lookLevels(_ ids: [UUID], attrs: [String: Double], panTilt: (Double, Double)? = nil) -> CueLevelData {
            CueLevelData(fixtures: ids.map { id in
                var a = attrs
                if let panTilt {
                    a["pan"] = panTilt.0
                    a["tilt"] = panTilt.1
                }
                return FixtureCueLevels(fixtureId: id, attributes: a)
            })
        }
        let allWashes = [front1, front2, front3, front4, back1, back2, back3, back4]
        let movers = [spot1, spot2, spot3, spot4]
        let presets: [Preset] = [
            Preset(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000501")!,
                name: "Warm Concert",
                levels: lookLevels(allWashes, attrs: warmRGB),
                notes: "I+C look"
            ),
            Preset(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000502")!,
                name: "Cool Theater",
                levels: lookLevels(allWashes, attrs: coolRGB),
                notes: "I+C look"
            ),
            Preset(
                id: UUID(uuidString: "A1000000-0000-4000-8000-000000000503")!,
                name: "Full Stage",
                levels: lookLevels(allWashes + movers, attrs: fullRGB, panTilt: (0.5, 0.45)),
                notes: "I+C+P"
            ),
        ]

        // UI-02 C7: fixed cue UUIDs for deterministic demo / tests / screenshots.
        func cueID(_ suffix: String) -> UUID {
            UUID(uuidString: "A1000000-0000-4000-8000-0000000006\(suffix)")!
        }

        func cue(_ id: UUID, _ n: String, _ name: String, fade: Double, levels: [UUID: Double] = [:]) -> Cue {
            let attrs: [FixtureCueLevels] = levels.map { fid, intensity in
                FixtureCueLevels(fixtureId: fid, attributes: ["intensity": intensity])
            }
            return Cue(
                id: id,
                number: Decimal(string: n) ?? 0,
                name: name,
                fadeIn: fade,
                fadeOut: 0,
                delay: 0,
                follow: .none,
                tracking: .track,
                levels: CueLevelData(fixtures: attrs)
            )
        }

        func map(_ ids: [UUID], _ v: Double) -> [UUID: Double] {
            Dictionary(uniqueKeysWithValues: ids.map { ($0, v) })
        }

        var levels = map(allWashes, 0.3)
        levels.merge(map([house], 0.5)) { _, n in n }

        let cues: [Cue] = [
            cue(cueID("01"), "1.0", "House Down", fade: 3, levels: map([house], 0.3)),
            cue(cueID("02"), "2.0", "Intro Look", fade: 2, levels: map(allWashes, 0.4)),
            cue(cueID("03"), "3.0", "Verse 1", fade: 1, levels: map(allWashes, 0.7).merging(map(movers, 0.5)) { _, n in n }),
            cue(cueID("04"), "4.0", "Chorus 1", fade: 1.5, levels: map(allWashes, 1).merging(map(movers, 0.9)) { _, n in n }),
            cue(cueID("05"), "5.0", "Move 1", fade: 1, levels: map(movers, 1)),
            cue(cueID("06"), "6.0", "Verse 2", fade: 1, levels: map(allWashes, 0.6)),
            cue(cueID("07"), "7.0", "Chorus 2", fade: 1.5, levels: map(allWashes, 1).merging(map(movers, 1)) { _, n in n }),
            cue(cueID("08"), "8.0", "Solo Spot", fade: 0.5, levels: map([spot2], 1)),
            cue(cueID("09"), "9.0", "Band Look", fade: 2, levels: map(allWashes, 0.8).merging(map(movers, 0.7)) { _, n in n }),
            cue(cueID("0A"), "10.0", "Audience Sweep", fade: 2, levels: map([aud1, aud2], 0.6)),
            cue(cueID("0B"), "11.0", "Bridge", fade: 3, levels: map(allWashes, 0.35)),
            cue(cueID("0C"), "12.0", "Build", fade: 2, levels: map(allWashes, 0.75).merging(map(movers, 0.6)) { _, n in n }),
            cue(cueID("0D"), "13.0", "Peak Chorus", fade: 1, levels: map(allWashes + movers, 1)),
            cue(cueID("0E"), "14.0", "Outro Wash", fade: 4, levels: map(allWashes, 0.5)),
            cue(cueID("0F"), "15.0", "Soft Exit", fade: 5, levels: map(allWashes, 0.2).merging(map([house], 0.15)) { _, n in n }),
            cue(cueID("10"), "16.0", "Blackout", fade: 1, levels: [:]),
            cue(cueID("11"), "17.0", "Encore Hit", fade: 0.3, levels: map(allWashes + movers, 1)),
            cue(cueID("12"), "18.0", "Final Bow", fade: 3, levels: map(allWashes, 0.4).merging(map([aud1, aud2], 0.5)) { _, n in n }),
        ]

        let cueList = CueList(id: listID, name: "Opening", cues: cues)

        let song = Song(
            id: songID,
            title: "Summer Night",
            artist: "Aurora Demo",
            entries: [
                SongEntry(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000031")!, target: .cue(listId: listID, cueId: cues[0].id), label: "Intro"),
                SongEntry(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000032")!, target: .cue(listId: listID, cueId: cues[2].id), label: "Verse"),
                SongEntry(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000033")!, target: .cue(listId: listID, cueId: cues[3].id), label: "Chorus"),
                SongEntry(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000034")!, target: .cue(listId: listID, cueId: cues[7].id), label: "Solo"),
                SongEntry(id: UUID(uuidString: "A1000000-0000-4000-8000-000000000035")!, target: .cue(listId: listID, cueId: cues[15].id), label: "Blackout"),
            ]
        )

        return ShowProject(
            metadata: ProjectMetadata(
                name: "Summer Night Show",
                author: "Aurora",
                notes: "UI-02A visual demo — deterministic populated project",
                createdAt: created,
                modifiedAt: created
            ),
            preferences: ProjectPreferences(
                defaultFadeIn: 2,
                defaultFadeOut: 2,
                defaultTracking: .track,
                preferredFrameRateHz: 40
            ),
            fixtureDefinitions: [dimmerDef, rgbDefinition, mhDefinition],
            universes: [universe],
            fixtures: fixtures,
            groups: groups,
            palettes: palettes,
            presets: presets,
            cueLists: [cueList],
            songs: [song]
        )
    }
}
