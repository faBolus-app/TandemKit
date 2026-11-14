import Foundation
import Testing
import TandemMessages
@testable import TandemLink

/// One test per phase and the inputs that move it, in the order a connection goes through them.
@Suite struct LinkTransitionTests {
    let target = PumpTarget(
        peripheralID: LinkHarness.pumpID, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode))

    // MARK: idle and waiting for Bluetooth

    @Test func idleWithoutTargetStaysIdleWhenBluetoothComesOn() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        #expect(h.phase == .idle)
        #expect(h.commands.isEmpty)
    }

    @Test func connectWithBluetoothOffWaitsThenIssuesPendingConnect() {
        var h = LinkHarness()
        h.apply(.connect(target, SupportMatrix()))
        #expect(h.phase == .waitingForBluetooth)
        #expect(h.commands.isEmpty)
        h.apply(.power(.poweredOn))
        #expect(h.phase == .connecting)
        #expect(h.commands == [.connect(LinkHarness.pumpID)])
    }

    @Test func connectToAMobiFailsWithoutTouchingBluetooth() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: LinkHarness.pumpID, model: .mobi, credentials: .jpake(code: "123456")),
                SupportMatrix()))
        #expect(h.phase == .failed(.unsupportedModel(.mobi)))
        #expect(!h.allCommands.contains(.connect(LinkHarness.pumpID)))
    }

    // MARK: scanning

    @Test func pairingScanReportsPumpsWithTheirModelAndTimesOut() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.scanForPairing)
        #expect(h.phase == .scanning(forPairing: true))
        #expect(h.commands == [.scan(repeats: true)])
        h.apply(.discovered(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693", rssi: -60))
        #expect(
            h.events == [
                .discovered(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693", model: .tslim, rssi: -60)
            ])
        h.advance(by: 119)
        #expect(h.phase == .scanning(forPairing: true), "a pump found that isn't taking a pairing doesn't stop it")
        h.advance(by: 1)
        #expect(h.phase == .failed(.pumpNotFound))
        #expect(h.allCommands.last == .stopScan)
    }

    @Test func pairingScanListsOnlyPumpsStrongerThanTheFloor() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.scanForPairing)
        h.apply(.discovered(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693", rssi: -75))
        #expect(h.events.isEmpty)
        h.apply(.discovered(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693", rssi: -74))
        #expect(h.events.count == 1)
        h.apply(.discovered(peripheralID: UUID(), name: "tslim X2 ***694", rssi: 127))
        #expect(h.events.count == 1, "signal unknown passes")
    }

    @Test func aListedPumpIsReportedAgainOnlyWhenItsSignalMoves() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.scanForPairing)
        h.clearLog()
        for rssi in [-60, -62, -58, -61, -64] {
            h.apply(.discovered(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693", rssi: rssi))
        }
        #expect(h.allEvents.count == 1)
        h.apply(.discovered(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693", rssi: -65))
        #expect(h.allEvents.count == 2)
    }

    /// Tandem's manufacturer data, CoreBluetooth-style: company ID 0x059D little-endian, format 0, the
    /// authentication method, then type and state nibbles.
    static func advertised(_ state: UInt8) -> [UInt8] { [0x9D, 0x05, 0x00, 0x01, 0x10 | state] }

    @Test func pairingScanTimerStopsWhenTheStrongestPumpTakesAPairing() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.scanForPairing)
        let near = UUID()
        h.apply(
            .discovered(peripheralID: near, name: "Tandem Mobi 1", rssi: -40, manufacturerData: Self.advertised(2)))
        h.apply(
            .discovered(
                peripheralID: LinkHarness.pumpID, name: "Tandem Mobi 2", rssi: -60,
                manufacturerData: Self.advertised(1)))
        #expect(h.timers[.scan] != nil, "the strongest is already paired elsewhere")
        h.apply(
            .discovered(
                peripheralID: LinkHarness.pumpID, name: "Tandem Mobi 2", rssi: -30,
                manufacturerData: Self.advertised(1)))
        #expect(h.timers[.scan] == nil)
        h.advance(by: 600)
        #expect(h.phase == .scanning(forPairing: true), "the scan runs until a pump is picked")
    }

    @Test func registrationStateNeedsTandemsFormat() {
        #expect(PumpRegistrationState(manufacturerData: Self.advertised(1)) == .acceptingConnections)
        #expect(PumpRegistrationState(manufacturerData: Self.advertised(7)) == .readyToPair)
        #expect(PumpRegistrationState(manufacturerData: nil) == nil)
        #expect(PumpRegistrationState(manufacturerData: [0x4C, 0x00, 0x00, 0x01, 0x11]) == nil, "another company")
        #expect(PumpRegistrationState(manufacturerData: [0x9D, 0x05, 0x01, 0x01, 0x11]) == nil, "another format")
        #expect(PumpRegistrationState(manufacturerData: [0x9D, 0x05, 0x00, 0x01]) == nil, "short")
        #expect(PumpRegistrationState(manufacturerData: Self.advertised(3)) == nil, "no such state")
    }

    @Test func pairingScanWaitsForBluetoothAndResumes() {
        var h = LinkHarness()
        h.apply(.scanForPairing)
        #expect(h.phase == .waitingForBluetooth)
        h.apply(.power(.poweredOn))
        #expect(h.phase == .scanning(forPairing: true))
    }

    @Test func unresolvableTargetScansAndConnectsWhenSeen() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.peripheralUnavailable(LinkHarness.pumpID))
        #expect(h.phase == .scanning(forPairing: false))
        #expect(h.commands == [.scan(repeats: false)])
        h.apply(.discovered(peripheralID: UUID(), name: "tslim X2 other", rssi: -50))
        #expect(h.phase == .scanning(forPairing: false))
        h.apply(.discovered(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693", rssi: -50))
        #expect(h.commands == [.stopScan, .connect(LinkHarness.pumpID)])
        #expect(h.phase == .connecting)
    }

    @Test func knownPumpScanTimeoutIsAFlap() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.peripheralUnavailable(LinkHarness.pumpID))
        h.advance(by: 30)
        #expect(h.state.ladder.flaps == 1)
        #expect(h.phase == .backingOff)
    }

    // MARK: connecting → discovering → authenticating → handshaking → ready

    @Test func connectionSetsUpAuthenticatesAndHandshakes() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693"))
        #expect(h.phase == .discovering)
        #expect(h.commands == [.discover(LinkHarness.pumpID), .readDeviceInformation])
        #expect(h.timers[.establishment] == 30)

        h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
        #expect(h.commands.count == ServiceUUID.notificationCharacteristics.count)
        h.apply(.subscription(.currentStatus, isNotifying: true, failed: false))
        #expect(h.phase == .discovering)
        h.apply(.subscription(.authorization, isNotifying: true, failed: false))
        #expect(h.phase == .authenticating)
        #expect(h.last.contains(.startAuthentication(.legacy(code: LinkHarness.legacyCode))))

        // The handshake's requests go out on AUTHORIZATION with the connection's txIds.
        h.apply(
            .authenticationRequest(
                CentralChallengeRequest(appInstanceId: 0, centralChallenge: [UInt8](repeating: 0, count: 8))))
        #expect(h.lastWrite?.characteristic == .authorization)
        #expect(h.lastWrite?.txId == 0)
        // AUTHORIZATION frames go to the handshake, not to the request queue.
        h.notify(CentralChallengeResponse(cargo: [UInt8](repeating: 0, count: 30)), txId: 0)
        #expect(h.last.contains { if case .authenticationFrame = $0 { return true } else { return false } })

        h.apply(.authenticated(key: LinkHarness.key, derivedSecret: nil))
        #expect(h.phase == .handshaking)
        #expect(h.lastWrite?.opCode == ApiVersionRequest.props.opCode)
        h.answerHandshake()
        #expect(h.phase == .ready)
        // Exactly ApiVersion, PumpVersion, TimeSinceReset after authenticating, nothing else.
        #expect(h.writes.map(\.opCode) == [16, 32, 84, 54])
        #expect(h.state.connection?.identity.apiVersion == .v2_5)
        #expect(h.state.connection?.identity.unit == LinkHarness.p1Unit)
        #expect(h.state.connection?.clock?.pumpTime == 586_961_779)
        #expect(h.timers[.establishment] == nil)
        #expect(h.timers[.hold] != nil)
        #expect(h.allEvents.contains(.ready(h.state.connection!.identity)))
    }

    @Test func missingOptionalCharacteristicsAreNotWaitedFor() {
        // Older firmware lacks CONTROL and CONTROL_STREAM.
        var h = LinkHarness()
        h.makeReady(present: [.authorization, .currentStatus, .historyLog, .qualifyingEvents])
        #expect(h.phase == .ready)
        let id = h.submit(DismissNotificationRequest(kind: .alert, notificationId: 1), allowing: .benign)
        #expect(h.results[id] == .notSent(.characteristicUnavailable))
    }

    @Test func optionalSubscriptionFailureIsNotWaitedFor() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693"))
        h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
        h.apply(.subscription(.controlStream, isNotifying: false, failed: true))
        h.apply(.subscription(.currentStatus, isNotifying: true, failed: false))
        h.apply(.subscription(.authorization, isNotifying: true, failed: false))
        #expect(h.phase == .authenticating)
    }

    @Test func missingRequiredCharacteristicFailsSetupAsAFlap() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693"))
        h.apply(.characteristicsDiscovered([.currentStatus]))
        #expect(h.commands.contains(.cancelConnection(LinkHarness.pumpID)))
        #expect(
            h.allEvents.contains { if case .disconnected(.setupFailed, _) = $0 { return true } else { return false } })
        #expect(h.phase == .backingOff)
    }

    @Test func requiredSubscriptionFailureFailsSetup() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693"))
        h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
        h.apply(.subscription(.authorization, isNotifying: false, failed: true))
        #expect(h.state.connection == nil)
        #expect(h.phase == .backingOff)
    }

    @Test func establishmentTimeoutCancelsAndFlaps() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693"))
        h.advance(by: 30)
        #expect(h.allCommands.contains(.cancelConnection(LinkHarness.pumpID)))
        #expect(
            h.allEvents.contains {
                if case .disconnected(.establishmentTimedOut, _) = $0 { return true } else { return false }
            })
        #expect(h.state.ladder.flaps == 1)
    }

    @Test func pendingConnectHasNoTimeout() {
        // The pending connect waits for the pump as long as it takes.
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.advance(by: 3600)
        #expect(h.phase == .connecting)
        #expect(h.timers.isEmpty)
    }

    @Test func handshakeErrorFailsTheConnectionNotReadyWithClearedIdentity() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.connectAndAuthenticate()
        h.replyError(code: 6, request: ApiVersionRequest.props.opCode)
        #expect(h.phase == .backingOff)
        #expect(h.state.connection == nil)
        #expect(
            h.allEvents.contains {
                if case .disconnected(.handshakeFailed, _) = $0 { return true } else { return false }
            })
        #expect(!h.allEvents.contains { if case .ready = $0 { return true } else { return false } })
    }

    // MARK: authentication outcomes

    @Test func rejectedCodeFailsForGood() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693"))
        h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
        h.apply(.subscription(.currentStatus, isNotifying: true, failed: false))
        h.apply(.subscription(.authorization, isNotifying: true, failed: false))
        h.apply(.authenticationFailed(rejected: true))
        #expect(h.phase == .failed(.authenticationRejected))
        #expect(h.last.contains(.endAuthentication))
        #expect(h.commands.contains(.cancelConnection(LinkHarness.pumpID)))
        h.advance(by: 600)
        #expect(!h.allCommands.dropFirst().contains(.connect(LinkHarness.pumpID)))
    }

    @Test func authenticationGlitchIsAFlap() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693"))
        h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
        h.apply(.subscription(.currentStatus, isNotifying: true, failed: false))
        h.apply(.subscription(.authorization, isNotifying: true, failed: false))
        h.apply(.authenticationFailed(rejected: false))
        #expect(h.phase == .backingOff)
        #expect(h.state.ladder.flaps == 1)
    }

    @Test func firstJpakePairingReportsTheDerivedSecretAndReconnectsWithIt() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: LinkHarness.pumpID, model: .tslim, credentials: .jpake(code: "123456")),
                SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 1234"))
        h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
        h.apply(.subscription(.currentStatus, isNotifying: true, failed: false))
        h.apply(.subscription(.authorization, isNotifying: true, failed: false))
        h.apply(.authenticated(key: [1, 2, 3], derivedSecret: [9, 9]))
        #expect(h.events.contains(.paired(.jpakeResume(derivedSecret: [9, 9]))))
        #expect(h.state.target?.credentials == .jpakeResume(derivedSecret: [9, 9]))
    }

    /// On a first JPAKE pairing, the pump answering a wrong code by dropping the link (as Mobi reads it): one
    /// drop is retried, a second ends the pairing, and nothing reconnects after it.
    @Test func aFirstJpakePairingThatDropsTwiceEndsAsPairingDropped() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: LinkHarness.pumpID, model: .tslim, credentials: .jpake(code: "123456")),
                SupportMatrix()))
        func authenticateAndDrop() {
            h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 1234"))
            h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
            h.apply(.subscription(.currentStatus, isNotifying: true, failed: false))
            h.apply(.subscription(.authorization, isNotifying: true, failed: false))
            h.apply(.disconnected(peripheralID: LinkHarness.pumpID, nil))
        }
        authenticateAndDrop()
        #expect(h.phase == .backingOff)
        h.advance(by: 60)
        authenticateAndDrop()
        #expect(h.phase == .failed(.pairingDropped))
        let connects = h.allCommands.filter { $0 == .connect(LinkHarness.pumpID) }.count
        h.advance(by: 600)
        #expect(h.allCommands.filter { $0 == .connect(LinkHarness.pumpID) }.count == connects)
    }

    /// A reconnect from the stored secret keeps the ordinary flap rule: a drop there isn't the code.
    @Test func aResumeThatDropsDuringAuthenticationIsAFlap() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(
                    peripheralID: LinkHarness.pumpID, model: .tslim, credentials: .jpakeResume(derivedSecret: [9])),
                SupportMatrix()))
        for _ in 0..<3 {
            h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 1234"))
            h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
            h.apply(.subscription(.currentStatus, isNotifying: true, failed: false))
            h.apply(.subscription(.authorization, isNotifying: true, failed: false))
            h.apply(.disconnected(peripheralID: LinkHarness.pumpID, nil))
            #expect(h.phase == .backingOff)
            h.advance(by: 60)
        }
        #expect(h.state.ladder.pairingDrops == 0)
    }

    // MARK: identity

    @Test func nameContradictingTheStoredModelIsRejected() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "Tandem Mobi 123"))
        #expect(h.phase == .failed(.identityMismatch(stored: .tslim, seen: .mobi)))
        #expect(h.state.telemetry.connects == 1 && h.state.telemetry.disconnects == 1)
    }

    @Test func storedModelIsUsedWhenTheNameSaysNothing() {
        // A retrieved or restored reconnect may have no advertised name: the stored model stands.
        var h = LinkHarness()
        h.makeReady(name: nil)
        #expect(h.state.connection?.identity.model == .tslim)
    }

    @Test func modelNeverComesFromTheApiVersion() {
        // P2 is a t:slim at API 4.0. With no name and no stored model, the model stays unknown.
        var h = LinkHarness()
        h.makeReady(model: nil, name: nil, api: (4, 0), unit: LinkHarness.p2Unit)
        #expect(h.state.connection?.identity.model == nil)
        #expect(h.state.connection?.identity.apiVersion == ApiVersion(major: 4, minor: 0))
    }

    // MARK: ready → held, stop

    @Test func holdWindowMarksTheLinkHeld() {
        var h = LinkHarness()
        h.makeReady()
        #expect(h.state.connection?.heldAt == nil)
        h.advance(by: 10)
        #expect(h.state.connection?.heldAt != nil)
    }

    @Test func stopClosesTheLinkAndNeverReconnects() {
        var h = LinkHarness()
        h.makeReady()
        h.apply(.stop)
        #expect(h.phase == .idle)
        #expect(h.commands == [.cancelConnection(LinkHarness.pumpID)])
        #expect(h.events.contains { if case .disconnected(.requested, _) = $0 { return true } else { return false } })
        h.apply(.disconnected(peripheralID: LinkHarness.pumpID, nil))
        h.advance(by: 600)
        #expect(h.phase == .idle)
        #expect(h.allCommands.filter { $0 == .connect(LinkHarness.pumpID) }.count == 1)
    }

    @Test func lateConnectAfterStopIsCancelled() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.stop)
        h.apply(.connected(peripheralID: LinkHarness.pumpID, name: "tslim X2 ***693"))
        #expect(h.commands == [.cancelConnection(LinkHarness.pumpID)])
        #expect(h.state.connection == nil)
    }

    @Test func strayPeripheralIsCancelled() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        let other = UUID()
        h.apply(.connected(peripheralID: other, name: "tslim X2 other"))
        #expect(h.commands == [.cancelConnection(other)])
        #expect(h.phase == .connecting)
    }

    @Test func reconnectingTheSameTargetKeepsTheLink() {
        var h = LinkHarness()
        h.makeReady()
        h.apply(.connect(target, SupportMatrix()))
        #expect(h.phase == .ready)
        #expect(h.commands.isEmpty)
    }
}
