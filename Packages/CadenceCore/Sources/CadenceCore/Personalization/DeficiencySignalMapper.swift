/// Turns one logged session's salient facts into a `SessionObservation` the
/// detector consumes. Pure (no SwiftData / UI) so the mapping is unit-tested.
///
/// The "faded late?" marker is the soft signal for fade-based deficiencies. A
/// faded endurance block is taken as evidence for the profile's fade-driven
/// deficiencies — identified data-drivenly as ADD responses that increase an
/// endurance quality (e.g. 100m `late_race_deceleration`, 400m
/// `speed_endurance_deficiency`). The stress flag excludes the session exactly
/// like a low-readiness day.
public enum DeficiencySignalMapper {

    /// Names of the profile's fade-driven deficiencies (ADD responses whose
    /// increased quality is an endurance quality).
    public static func fadeDeficiencyNames(in profile: EventAdjustmentProfile) -> [String] {
        profile.deficiencies
            .filter { $0.response.usesAddRules && ($0.response.increase?.quality?.isEndurance ?? false) }
            .map { $0.name }
    }

    public static func observation(
        profile: EventAdjustmentProfile,
        phaseName: String,
        isLowReadiness: Bool,
        flaggedExternalStress: Bool,
        completedPrescribedReps: Bool,
        fadedEnduranceQualities: Set<Quality>
    ) -> SessionObservation {
        var patterns: Set<String> = []
        if fadedEnduranceQualities.contains(where: { $0.isEndurance }) {
            patterns.formUnion(fadeDeficiencyNames(in: profile))
        }
        return SessionObservation(
            phaseName: phaseName,
            isLowReadiness: isLowReadiness,
            isOutlier: false,
            isIllnessOrStress: flaggedExternalStress,   // confounder exclusion
            completedPrescribedReps: completedPrescribedReps,
            observedPatterns: patterns)
    }
}
