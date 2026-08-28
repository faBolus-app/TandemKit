import Foundation

/// TandemAuth — pump authentication: crypto primitives (`Crypto`), the legacy 16-char
/// pairing handshake (`PairingAuth`), and per-command signing support.
///
/// SAFETY-CRITICAL. The per-command signature authorizes insulin delivery (see
/// `TandemMessages.Packetize` for the HMAC-SHA1 signing applied to signed messages).
public enum TandemAuth {}
