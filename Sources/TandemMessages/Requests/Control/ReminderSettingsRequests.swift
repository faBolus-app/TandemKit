import Foundation

/// Reminder / quick-bolus / sleep-schedule settings (A2). Signed CONTROL, non-insulin. Ports of the
/// `request/control/Set{BgReminder,SiteChangeReminder,MissedMealBolusReminder,PumpAlertSnooze,
/// QuickBolusSettings,SleepSchedule}Request` classes.

/// Sets a BG-check reminder (opcode 0xD8 → 0xD9). 9-byte cargo: reminderType + enabled +
/// LE uint16 threshold + uint32 minutes + bitmask.
public struct SetBgReminderRequest: Message {
    public static let props = MessageProps(opCode: 0xD8, size: 9, signed: true, type: .request, characteristic: .control, responseOpCode: 0xD9)
    public var cargo: [UInt8]
    public private(set) var reminderType = 0, reminderThreshold = 0, bitmask = 0
    public private(set) var enabledBGReminder = false
    public private(set) var reminderMinutes: UInt32 = 0
    public init() { cargo = [] }
    public init(reminderType: Int, enabledBGReminder: Bool, reminderThreshold: Int, reminderMinutes: UInt32, bitmask: Int) {
        self.reminderType = reminderType; self.enabledBGReminder = enabledBGReminder
        self.reminderThreshold = reminderThreshold; self.reminderMinutes = reminderMinutes; self.bitmask = bitmask
        self.cargo = Bytes.combine([UInt8(reminderType & 0xFF), enabledBGReminder ? 1 : 0],
                                   Bytes.firstTwoBytesLittleEndian(reminderThreshold),
                                   Bytes.toUint32(reminderMinutes), [UInt8(bitmask & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Sets the site-change reminder (opcode 0xDC → 0xDD). 7-byte cargo: enable + dayCount +
/// uint32 timeOfDayMinutes + bitmask.
public struct SetSiteChangeReminderRequest: Message {
    public static let props = MessageProps(opCode: 0xDC, size: 7, signed: true, type: .request, characteristic: .control, responseOpCode: 0xDD)
    public var cargo: [UInt8]
    public private(set) var enable = false
    public private(set) var dayCount = 0, bitmask = 0
    public private(set) var timeOfDayMinutes: UInt32 = 0
    public init() { cargo = [] }
    public init(enable: Bool, dayCount: Int, timeOfDayMinutes: UInt32, bitmask: Int) {
        self.enable = enable; self.dayCount = dayCount; self.timeOfDayMinutes = timeOfDayMinutes; self.bitmask = bitmask
        self.cargo = Bytes.combine([enable ? 1 : 0, UInt8(dayCount & 0xFF)],
                                   Bytes.toUint32(timeOfDayMinutes), [UInt8(bitmask & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Sets a missed-meal-bolus reminder window (opcode 0xDA → 0xDB). 8-byte cargo: reminderIndex +
/// enabled + LE uint16 startTime + LE uint16 endTime + selectedDays + bitmask.
public struct SetMissedMealBolusReminderRequest: Message {
    public static let props = MessageProps(opCode: 0xDA, size: 8, signed: true, type: .request, characteristic: .control, responseOpCode: 0xDB)
    public var cargo: [UInt8]
    public private(set) var reminderIndex = 0, startTime = 0, endTime = 0, selectedDays = 0, bitmask = 0
    public private(set) var enabledReminder = false
    public init() { cargo = [] }
    public init(reminderIndex: Int, enabledReminder: Bool, startTime: Int, endTime: Int, selectedDays: Int, bitmask: Int) {
        self.reminderIndex = reminderIndex; self.enabledReminder = enabledReminder
        self.startTime = startTime; self.endTime = endTime; self.selectedDays = selectedDays; self.bitmask = bitmask
        self.cargo = Bytes.combine([UInt8(reminderIndex & 0xFF), enabledReminder ? 1 : 0],
                                   Bytes.firstTwoBytesLittleEndian(startTime),
                                   Bytes.firstTwoBytesLittleEndian(endTime),
                                   [UInt8(selectedDays & 0xFF), UInt8(bitmask & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Sets the pump-alert snooze (opcode 0xD4 → 0xD5). 2-byte cargo: snoozeEnabled + snoozeDurationMins.
public struct SetPumpAlertSnoozeRequest: Message {
    public static let props = MessageProps(opCode: 0xD4, size: 2, signed: true, type: .request, characteristic: .control, responseOpCode: 0xD5)
    public var cargo: [UInt8]
    public private(set) var snoozeEnabled = false
    public private(set) var snoozeDurationMins = 0
    public init() { cargo = [] }
    public init(snoozeEnabled: Bool, snoozeDurationMins: Int) {
        self.snoozeEnabled = snoozeEnabled; self.snoozeDurationMins = snoozeDurationMins
        self.cargo = [snoozeEnabled ? 1 : 0, UInt8(snoozeDurationMins & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Sets quick-bolus settings (opcode 0xD2 → 0xD3). 7-byte cargo: enabled + modeRaw + 5-byte `magic`
/// (opaque, echoed from a prior read). Cargo-asserted directly (opaque byte array).
public struct SetQuickBolusSettingsRequest: Message {
    public static let props = MessageProps(opCode: 0xD2, size: 7, signed: true, type: .request, characteristic: .control, responseOpCode: 0xD3)
    public var cargo: [UInt8]
    public private(set) var enabled = false
    public private(set) var modeRaw = 0
    public private(set) var magic: [UInt8] = []
    public init() { cargo = [] }
    public init(enabled: Bool, modeRaw: Int, magic: [UInt8]) {
        precondition(magic.count == 5, "magic must be 5 bytes")
        self.enabled = enabled; self.modeRaw = modeRaw; self.magic = magic
        self.cargo = Bytes.combine([enabled ? 1 : 0, UInt8(modeRaw & 0xFF)], magic)
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Sets a sleep-schedule slot (opcode 0xCE → 0xCF). 8-byte cargo: slot + 6-byte schedule + flag.
public struct SetSleepScheduleRequest: Message {
    public static let props = MessageProps(opCode: 0xCE, size: 8, signed: true, type: .request, characteristic: .control, responseOpCode: 0xCF)
    public var cargo: [UInt8]
    public private(set) var slot = 0, flag = 0
    public private(set) var schedule: [UInt8] = []
    public init() { cargo = [] }
    public init(slot: Int, schedule: [UInt8], flag: Int) {
        precondition(schedule.count == 6, "schedule must be 6 bytes")
        self.slot = slot; self.schedule = schedule; self.flag = flag
        self.cargo = Bytes.combine([UInt8(slot & 0xFF)], schedule, [UInt8(flag & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}
