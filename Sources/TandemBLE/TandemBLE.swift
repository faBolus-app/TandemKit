import Foundation

/// TandemBLE — Core Bluetooth central transport for the Tandem pump.
///
/// Platform-agnostic: imports CoreBluetooth only, never UIKit, so the same code runs on iOS
/// and watchOS. Entry point is `PumpBLEClient`; `PacketReassembler` handles inbound
/// multi-packet reassembly. Hardware-validated on real pumps — 6-digit JPAKE and legacy 16-char V1
/// pairing, read sweeps, and a signed bolus (see `PINNED.md` for the log). The connection flow
/// follows upstream `TandemBluetoothHandler`; the BLE path is exercised on hardware via the
/// `TandemBenchHarness` executable, not `swift test`.
public enum TandemBLE {}
