import Foundation

/// TandemBLE: runs the pump link over CoreBluetooth.
///
/// `PumpConnection` drives TandemLink's state machine (`LinkReducer`) and performs its effects through a
/// `LinkTransport`; `CoreBluetoothTransport` is the real one. Platform-agnostic: imports CoreBluetooth
/// only, never UIKit, so the same code runs on iOS and watchOS. The connection flow follows upstream
/// pumpx2's `TandemBluetoothHandler`. A macOS test host can't use Bluetooth (no usage description), so
/// the transport runs on hardware through the bench harness (`Bench/`), and the tests drive
/// `PumpConnection` through a scripted transport.
public enum TandemBLE {}
