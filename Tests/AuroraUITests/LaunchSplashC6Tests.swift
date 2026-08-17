import AuroraUI
import XCTest

/// C6 splash + C5 close policy tests against **production** library types.
final class LaunchSplashC6Tests: XCTestCase {

    func testTimingConstantsComeFromProductionPolicy() {
        XCTAssertEqual(LaunchSplashPolicy.minimumVisibleSeconds, 2.85, accuracy: 0.001)
        XCTAssertEqual(LaunchSplashPolicy.maximumVisibleSeconds, 12.0, accuracy: 0.001)
        XCTAssertGreaterThan(LaunchSplashPolicy.minimumVisibleSeconds, 2.0)
        XCTAssertLessThan(LaunchSplashPolicy.minimumVisibleSeconds, 4.0)
        XCTAssertGreaterThan(
            LaunchSplashPolicy.maximumVisibleSeconds,
            LaunchSplashPolicy.minimumVisibleSeconds
        )
    }

    func testRemainingMinimumHold() {
        XCTAssertEqual(
            LaunchSplashPolicy.remainingMinimumHold(elapsed: 0),
            LaunchSplashPolicy.minimumVisibleSeconds,
            accuracy: 0.001
        )
        XCTAssertEqual(LaunchSplashPolicy.remainingMinimumHold(elapsed: 10), 0, accuracy: 0.001)
        let mid = LaunchSplashPolicy.minimumVisibleSeconds / 2
        XCTAssertEqual(
            LaunchSplashPolicy.remainingMinimumHold(elapsed: mid),
            mid,
            accuracy: 0.05
        )
    }

    func testAutoDismissRequiresReadyAndIntro() {
        XCTAssertTrue(LaunchSplashPolicy.allowsAutoDismiss(
            bootstrapFailed: false, bootstrapReady: true, introComplete: true
        ))
        XCTAssertFalse(LaunchSplashPolicy.allowsAutoDismiss(
            bootstrapFailed: true, bootstrapReady: true, introComplete: true
        ))
        XCTAssertFalse(LaunchSplashPolicy.allowsAutoDismiss(
            bootstrapFailed: false, bootstrapReady: false, introComplete: true
        ))
        XCTAssertFalse(LaunchSplashPolicy.allowsAutoDismiss(
            bootstrapFailed: false, bootstrapReady: true, introComplete: false
        ))
    }

    func testMaxHoldWatchdogSkipsFailedBootstrap() {
        XCTAssertTrue(LaunchSplashPolicy.shouldForceExitAfterMaxHold(
            bootstrapFailed: false, alreadyDismissed: false
        ))
        XCTAssertFalse(LaunchSplashPolicy.shouldForceExitAfterMaxHold(
            bootstrapFailed: true, alreadyDismissed: false
        ))
        XCTAssertFalse(LaunchSplashPolicy.shouldForceExitAfterMaxHold(
            bootstrapFailed: false, alreadyDismissed: true
        ))
    }

    func testFloatClosePolicyUserVsQuit() {
        XCTAssertEqual(
            FloatWindowClosePolicy.decide(isTerminating: false, surfaceStillFloating: true),
            .redock
        )
        XCTAssertEqual(
            FloatWindowClosePolicy.decide(isTerminating: true, surfaceStillFloating: true),
            .preserveFloating
        )
        XCTAssertEqual(
            FloatWindowClosePolicy.decide(isTerminating: false, surfaceStillFloating: false),
            .ignore
        )
    }
}
