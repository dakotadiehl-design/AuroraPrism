/// Musical Engine foundation: authoritative musical time, transport, scheduling.
///
/// Does **not** own CoreMIDI or AME mapping logic. Continuous timing sources and
/// consumers (AME, future Effects Engine) depend on this module.
public enum AuroraMusicalModule {
    public static let name = "AuroraMusical"
    public static let version = "0.3.0-phase-c"
}
