import Foundation
import os.log

/// The safety NOTICE this driver carries with it wherever it is reused.
///
/// PumpX2Kit's saline / NO-GO bench posture is a property of the *faBolus app*, not of a generic
/// exported driver — so this library states its own limits explicitly, in the header, the README,
/// and a one-time runtime log line on manager init (`TandemPumpManager.logNoticeOnce()`).
public enum PumpX2LoopKitNotice {

    /// The verbatim notice. Mirrors PumpX2Kit's own top-of-file disclaimer.
    public static let text = """
    PumpX2LoopKit — UNVERIFIED. This is a reverse-engineered Tandem pump protocol driver. It is \
    NOT FDA-cleared, NOT affiliated with or endorsed by Tandem Diabetes Care or Dexcom, and NOT \
    for use with real insulin. For research and simulation with saline only. The pump — not this \
    library — is the sole authority on how much insulin was actually delivered; every delivered \
    amount reported here comes from the pump's own record.
    """

    private static let log = Logger(subsystem: "PumpX2LoopKit", category: "notice")
    private static let didLog = OSAllocatedUnfairLock(initialState: false)

    /// Emit the notice to the unified log exactly once per process.
    public static func logOnce() {
        didLog.withLock { already in
            guard !already else { return }
            already = true
            log.notice("\(text, privacy: .public)")
        }
    }
}
