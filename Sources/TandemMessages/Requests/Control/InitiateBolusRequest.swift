import Foundation

/// The final command that initiates a bolus. Must follow a `BolusPermissionRequest` and use
/// the `bolusID` from its response. Signed + modifies insulin delivery — the most
/// safety-critical outgoing message. Port of `request/control/InitiateBolusRequest`
/// (opcode 0x9E / -98, size 37 + 24-byte HMAC).
///
/// Volumes are in **milliunits** (1000 = 1.0 u).
public struct InitiateBolusRequest: Message {
    public static let minBolusMilliunits: UInt32 = 50        // 0.05 u
    public static let minExtendedBolusMilliunits: UInt32 = 400 // 0.40 u

    /// Bolus-type bits (mirrors `BolusDeliveryHistoryLog.BolusType`).
    public static let bitFood1: Int = 1        // carb bolus
    public static let bitCorrection: Int = 2
    public static let bitExtended: Int = 4
    public static let bitFood2: Int = 8        // no-carb food bit
    /// Union of all known type bits — a mask with any other bit set is rejected (PX-07).
    public static let knownTypeBits: Int = 0x0F

    /// Derive the bolus-type bitmask from what the dose contains (PX-06). **FOOD1 when carbs are
    /// present, else FOOD2** — never both — matching the oracle (`BolusDeliveryHistoryLog.BolusType`:
    /// FOOD1 "used when there is carbs", FOOD2 "no carbs"). Adds CORRECTION / EXTENDED as applicable.
    /// This is the single source of truth for the mask, shared by the bench harness and production so
    /// they cannot diverge (the old harness OR-ed FOOD2 in for carb boluses — wrong).
    public static func typeBitmask(hasCarbs: Bool, hasCorrection: Bool, isExtended: Bool) -> Int {
        var mask = hasCarbs ? bitFood1 : bitFood2
        if hasCorrection { mask |= bitCorrection }
        if isExtended { mask |= bitExtended }
        return mask
    }

    /// Structured validation failure (PX-07). A malformed dose *throws* rather than silently truncating
    /// or trapping — the caller decides how to surface it, and no out-of-range value ever reaches the wire.
    public enum ValidationError: Error, Equatable {
        case doseTooSmall(totalMilliunits: UInt32, extendedMilliunits: UInt32)
        case invalidBolusID(Int)                 // must be 1...65535 (uint16 on the wire)
        case carbsOutOfRange(Int)                // 0...65535
        case bgOutOfRange(Int)                   // 0...65535
        case invalidTypeBitmask(Int)             // nonzero, only known bits
        case extendedIncoherent(String)          // EXTENDED bit vs extendedVolume/extendedSeconds mismatch
        case componentExceedsTotal(String)       // food+correction volume larger than the whole dose
        case foodBitIncoherent(String)           // not exactly one of FOOD1/FOOD2, or carbs>0 without FOOD1
        case correctionIncoherent(String)        // CORRECTION bit without a correction component
        case arithmeticOverflow(String)          // total+extended or food+correction overflows UInt32
    }

    /// Validates all bounds + cross-field invariants without constructing anything (PX-07).
    /// Called by `init(validating:)`; exposed so a caller/test can pre-check.
    public static func validate(
        totalVolume: UInt32, bolusID: Int, bolusTypeBitmask: Int,
        foodVolume: UInt32, correctionVolume: UInt32, bolusCarbs: Int, bolusBG: Int,
        extendedVolume: UInt32, extendedSeconds: UInt32
    ) throws {
        // Wire-width bounds (these fields are uint16 on the wire — reject before silent truncation).
        guard (1...0xFFFF).contains(bolusID) else { throw ValidationError.invalidBolusID(bolusID) }
        guard (0...0xFFFF).contains(bolusCarbs) else { throw ValidationError.carbsOutOfRange(bolusCarbs) }
        guard (0...0xFFFF).contains(bolusBG) else { throw ValidationError.bgOutOfRange(bolusBG) }
        // Type mask: nonzero and only known bits set.
        guard bolusTypeBitmask != 0, (bolusTypeBitmask & ~knownTypeBits) == 0 else {
            throw ValidationError.invalidTypeBitmask(bolusTypeBitmask)
        }
        // Exactly one food-type bit: FOOD1 (carbs) XOR FOOD2 (no carbs) — the reference always sets one,
        // never both and never neither.
        let hasFood1 = (bolusTypeBitmask & bitFood1) != 0
        let hasFood2 = (bolusTypeBitmask & bitFood2) != 0
        guard hasFood1 != hasFood2 else {
            throw ValidationError.foodBitIncoherent("exactly one of FOOD1/FOOD2 required (mask \(bolusTypeBitmask))")
        }
        // Recording carbs implies a FOOD1 (carb) bolus — FOOD2 means "no carbs", so carb metadata on a
        // FOOD2 bolus is incoherent.
        guard bolusCarbs <= 0 || hasFood1 else {
            throw ValidationError.foodBitIncoherent("bolusCarbs \(bolusCarbs) requires FOOD1, not FOOD2")
        }
        // A CORRECTION bit must carry a correction component.
        if (bolusTypeBitmask & bitCorrection) != 0 {
            guard correctionVolume > 0 else {
                throw ValidationError.correctionIncoherent("CORRECTION set but correctionVolume is 0")
            }
        }
        // Checked whole dose = total + extended (reject a silent UInt32 wrap).
        let (whole, wholeOverflow) = totalVolume.addingReportingOverflow(extendedVolume)
        guard !wholeOverflow else {
            throw ValidationError.arithmeticOverflow("totalVolume + extendedVolume overflows UInt32")
        }
        // Minimum dispensable dose (standard OR extended threshold).
        guard totalVolume >= minBolusMilliunits || whole >= minExtendedBolusMilliunits else {
            throw ValidationError.doseTooSmall(totalMilliunits: totalVolume, extendedMilliunits: extendedVolume)
        }
        // Extended coherence: the EXTENDED bit and the extended fields must agree.
        let extendedBitSet = (bolusTypeBitmask & bitExtended) != 0
        if extendedBitSet {
            guard extendedVolume > 0, extendedSeconds > 0 else {
                throw ValidationError.extendedIncoherent("EXTENDED set but extendedVolume/extendedSeconds is 0")
            }
        } else {
            guard extendedVolume == 0, extendedSeconds == 0 else {
                throw ValidationError.extendedIncoherent("extended fields set without the EXTENDED bit")
            }
        }
        // Component volumes summed can't exceed the whole dose (checked; subsumes each ≤ whole).
        let (componentSum, componentOverflow) = foodVolume.addingReportingOverflow(correctionVolume)
        guard !componentOverflow else {
            throw ValidationError.arithmeticOverflow("foodVolume + correctionVolume overflows UInt32")
        }
        guard componentSum <= whole else {
            throw ValidationError.componentExceedsTotal("food+correction \(componentSum) > total+extended \(whole)")
        }
    }

    /// Typed/throwing constructor (PX-07). Validates bounds + cross-field invariants, then builds. Prefer
    /// this over the trapping `init(totalVolume:…)` for any value derived from external/computed input.
    public init(
        validating totalVolume: UInt32,
        bolusID: Int,
        bolusTypeBitmask: Int,
        foodVolume: UInt32 = 0,
        correctionVolume: UInt32 = 0,
        bolusCarbs: Int = 0,
        bolusBG: Int = 0,
        bolusIOB: UInt32 = 0,
        extendedVolume: UInt32 = 0,
        extendedSeconds: UInt32 = 0,
        extended3: UInt32 = 0
    ) throws {
        try Self.validate(
            totalVolume: totalVolume, bolusID: bolusID, bolusTypeBitmask: bolusTypeBitmask,
            foodVolume: foodVolume, correctionVolume: correctionVolume, bolusCarbs: bolusCarbs,
            bolusBG: bolusBG, extendedVolume: extendedVolume, extendedSeconds: extendedSeconds)
        self.init(
            totalVolume: totalVolume, bolusID: bolusID, bolusTypeBitmask: bolusTypeBitmask,
            foodVolume: foodVolume, correctionVolume: correctionVolume, bolusCarbs: bolusCarbs,
            bolusBG: bolusBG, bolusIOB: bolusIOB, extendedVolume: extendedVolume,
            extendedSeconds: extendedSeconds, extended3: extended3)
    }

    public static let props = MessageProps(
        opCode: 0x9E,               // -98 as unsigned
        size: 37,
        signed: true,
        type: .request,
        characteristic: .control,
        modifiesInsulinDelivery: true,
        responseOpCode: 0x9F        // InitiateBolusResponse
    )

    public var cargo: [UInt8]

    public private(set) var totalVolume: UInt32 = 0
    public private(set) var bolusID: Int = 0
    public private(set) var bolusTypeBitmask: Int = 0
    public private(set) var foodVolume: UInt32 = 0
    public private(set) var correctionVolume: UInt32 = 0
    public private(set) var bolusCarbs: Int = 0
    public private(set) var bolusBG: Int = 0
    public private(set) var bolusIOB: UInt32 = 0
    public private(set) var extendedVolume: UInt32 = 0
    public private(set) var extendedSeconds: UInt32 = 0
    public private(set) var extended3: UInt32 = 0

    public init() { self.cargo = [] }

    /// Standard (non-extended) bolus.
    public init(
        totalVolume: UInt32,
        bolusID: Int,
        bolusTypeBitmask: Int,
        foodVolume: UInt32 = 0,
        correctionVolume: UInt32 = 0,
        bolusCarbs: Int = 0,
        bolusBG: Int = 0,
        bolusIOB: UInt32 = 0
    ) {
        self.init(
            totalVolume: totalVolume, bolusID: bolusID, bolusTypeBitmask: bolusTypeBitmask,
            foodVolume: foodVolume, correctionVolume: correctionVolume, bolusCarbs: bolusCarbs,
            bolusBG: bolusBG, bolusIOB: bolusIOB, extendedVolume: 0, extendedSeconds: 0, extended3: 0
        )
    }

    /// Full form, including extended-bolus fields.
    public init(
        totalVolume: UInt32,
        bolusID: Int,
        bolusTypeBitmask: Int,
        foodVolume: UInt32,
        correctionVolume: UInt32,
        bolusCarbs: Int,
        bolusBG: Int,
        bolusIOB: UInt32,
        extendedVolume: UInt32,
        extendedSeconds: UInt32,
        extended3: UInt32
    ) {
        precondition(totalVolume >= Self.minBolusMilliunits
            || (totalVolume + extendedVolume) >= Self.minExtendedBolusMilliunits)
        precondition(bolusID > 0)
        self.cargo = Self.buildCargo(
            totalVolume: totalVolume, bolusID: bolusID, bolusTypeId: bolusTypeBitmask,
            foodVolume: foodVolume, correctionVolume: correctionVolume, bolusCarbs: bolusCarbs,
            bolusBG: bolusBG, bolusIOB: bolusIOB, extendedVolume: extendedVolume,
            extendedSeconds: extendedSeconds, extended3: extended3)
        self.totalVolume = totalVolume
        self.bolusID = bolusID
        self.bolusTypeBitmask = bolusTypeBitmask
        self.foodVolume = foodVolume
        self.correctionVolume = correctionVolume
        self.bolusCarbs = bolusCarbs
        self.bolusBG = bolusBG
        self.bolusIOB = bolusIOB
        self.extendedVolume = extendedVolume
        self.extendedSeconds = extendedSeconds
        self.extended3 = extended3
    }

    public mutating func parse(_ raw: [UInt8]) {
        let raw = removeSignedRequestHmacBytes(raw)
        precondition(raw.count == Self.props.size)
        self.cargo = raw
        self.totalVolume = Bytes.readUint32(raw, 0)
        self.bolusID = Bytes.readShort(raw, 4)
        self.bolusTypeBitmask = Int(raw[8])
        self.foodVolume = Bytes.readUint32(raw, 9)
        self.correctionVolume = Bytes.readUint32(raw, 13)
        self.bolusCarbs = Bytes.readShort(raw, 17)
        self.bolusBG = Bytes.readShort(raw, 19)
        self.bolusIOB = Bytes.readUint32(raw, 21)
        self.extendedVolume = Bytes.readUint32(raw, 25)
        self.extendedSeconds = Bytes.readUint32(raw, 29)
        self.extended3 = Bytes.readUint32(raw, 33)
    }

    public static func buildCargo(
        totalVolume: UInt32, bolusID: Int, bolusTypeId: Int, foodVolume: UInt32,
        correctionVolume: UInt32, bolusCarbs: Int, bolusBG: Int, bolusIOB: UInt32,
        extendedVolume: UInt32, extendedSeconds: UInt32, extended3: UInt32
    ) -> [UInt8] {
        Bytes.combine(
            Bytes.toUint32(totalVolume),
            Bytes.firstTwoBytesLittleEndian(bolusID),
            [0, 0],
            [UInt8(truncatingIfNeeded: bolusTypeId)],
            Bytes.toUint32(foodVolume),
            Bytes.toUint32(correctionVolume),
            Bytes.firstTwoBytesLittleEndian(bolusCarbs),
            Bytes.firstTwoBytesLittleEndian(bolusBG),
            Bytes.toUint32(bolusIOB),
            Bytes.toUint32(extendedVolume),
            Bytes.toUint32(extendedSeconds),
            Bytes.toUint32(extended3)
        )
    }
}
