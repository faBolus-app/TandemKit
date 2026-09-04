#!/usr/bin/env python3
"""
port_message.py — scaffold a Swift TandemKit message from an upstream jwoglom/pumpX2 Java class.

WHY THIS IS SAFE TO AUTOMATE: TandemKit's `Bytes` helpers were deliberately mirrored 1:1 from the
Java library (readShort/readUint32/readUint64/readString/readFloat/toUint32/…), so the `parse()` and
`buildCargo()` bodies translate almost line-for-line. And every generated message is gated by a
byte-exact oracle-parity test (scripts/test.sh) — anything mistranslated fails loudly.

The generator does the mechanical 80%: it extracts @MessageProps (with the error-prone signed→
unsigned opcode conversion and characteristic mapping), infers Swift field types from the parse()
body, and emits a struct + a ResponseParser registration line + a test stub. Anything it can't
translate confidently is emitted as a `// TODO(port):` line for human review. It does NOT write into
the source tree — it prints to stdout so you review, paste, and oracle-verify.

Usage:
    python3 scripts/port_message.py <path-to-Response-or-Request.java>
    python3 scripts/port_message.py <dir>            # batch: every *.java under dir
"""
import re
import sys
import os

CHAR_MAP = {
    "CURRENT_STATUS": ".currentStatus",
    "CONTROL": ".control",
    "CONTROL_STREAM": ".controlStream",
    "HISTORY_LOG": ".historyLog",
    "AUTHORIZATION": ".authorization",
    "QUALIFYING_EVENTS": ".qualifyingEvents",
}


def unsigned_opcode(literal):
    """Java @MessageProps opcodes are signed bytes; convert to the 0-255 wire value."""
    v = int(literal)
    if v < 0:
        v += 256
    return v


def parse_history_props(text):
    """Parse a @HistoryLogProps annotation. opCode() is the record typeId; size defaults to 26."""
    m = re.search(r"@HistoryLogProps\s*\((.*?)\)", text, re.DOTALL)
    if not m:
        return None
    body = m.group(1)

    def field(name, default=None):
        mm = re.search(name + r"\s*=\s*([^,\)\s]+)", body)
        return mm.group(1).strip() if mm else default

    op = field("opCode")
    sz = field("size", "26")
    sm = re.match(r"(\d+)", sz)
    dn = re.search(r'displayName\s*=\s*"([^"]*)"', body)
    return {
        "kind": "history",
        "typeId": int(op) if op is not None else None,
        "size": sm.group(1) if sm else "26",
        "displayName": dn.group(1) if dn else "",
    }


def parse_props(text):
    m = re.search(r"@MessageProps\s*\((.*?)\)", text, re.DOTALL)
    if not m:
        return None
    body = m.group(1)

    def field(name, default=None):
        mm = re.search(name + r"\s*=\s*([^,\)\s]+)", body)
        return mm.group(1).strip() if mm else default

    op = field("opCode")
    props = {
        "opCode": unsigned_opcode(op) if op is not None else None,
        "opCode_raw": op,
        "size": field("size", "0"),
        "type": (field("type", "") or "").split(".")[-1],   # REQUEST / RESPONSE
        "characteristic": None,
        "signed": (field("signed", "false") == "true"),
        "modifiesInsulinDelivery": (field("modifiesInsulinDelivery", "false") == "true"),
        "variableSize": (field("variableSize", "false") == "true"),
        "response": field("response"),
        "request": field("request"),
    }
    ch = field("characteristic")
    if ch:
        props["characteristic"] = CHAR_MAP.get(ch.split(".")[-1], ".currentStatus")
    # size may carry an inline comment like "5 // 29 with signed" — keep only the leading int.
    sm = re.match(r"(\d+)", props["size"])
    props["size"] = sm.group(1) if sm else "0"
    return props


# --- parse() body translation -------------------------------------------------

def translate_expr(expr):
    """Translate a Java RHS expression to Swift + infer the Swift field type."""
    e = expr.strip()
    # bool: raw[N] != 0  or  raw[N] & 0xFF != 0
    m = re.fullmatch(r"raw\[(\d+)\]\s*!=\s*0", e)
    if m:
        return f"raw[{m.group(1)}] != 0", "Bool", "false"
    m = re.fullmatch(r"\(?raw\[(\d+)\]\s*&\s*0x[0-9A-Fa-f]+\)?\s*!=\s*0", e)
    if m:
        return f"raw[{m.group(1)}] != 0", "Bool", "false"
    # int: raw[N] & 0xFF   or   raw[N]
    m = re.fullmatch(r"raw\[(\d+)\]\s*&\s*0x[0-9A-Fa-f]+", e)
    if m:
        return f"Int(raw[{m.group(1)}])", "Int", "0"
    m = re.fullmatch(r"raw\[(\d+)\]", e)
    if m:
        return f"Int(raw[{m.group(1)}])", "Int", "0"
    # Bytes.readShort(raw, N)
    m = re.fullmatch(r"Bytes\.readShort\(raw,\s*(\d+)\)", e)
    if m:
        return f"Bytes.readShort(raw, {m.group(1)})", "Int", "0"
    # Bytes.readUint32(raw, N) -> store as Int
    m = re.fullmatch(r"Bytes\.readUint32\(raw,\s*(\d+)\)", e)
    if m:
        return f"Int(Bytes.readUint32(raw, {m.group(1)}))", "Int", "0"
    # Bytes.readUint64(raw, N) -> UInt64
    m = re.fullmatch(r"Bytes\.readUint64\(raw,\s*(\d+)\)", e)
    if m:
        return f"Bytes.readUint64(raw, {m.group(1)})", "UInt64", "0"
    # Bytes.readString(raw, N, L)
    m = re.fullmatch(r"Bytes\.readString\(raw,\s*(\d+),\s*(\d+)\)", e)
    if m:
        return f"Bytes.readString(raw, {m.group(1)}, {m.group(2)})", "String", '""'
    # Bytes.readFloat(raw, N)
    m = re.fullmatch(r"Bytes\.readFloat\(raw,\s*(\d+)\)", e)
    if m:
        return f"Bytes.readFloat(raw, {m.group(1)})", "Float", "0"
    return None, None, None  # unrecognized


def parse_body_translate(text):
    """Return (assignments, fields) where fields is an ordered dict name->(type,default)."""
    m = re.search(r"public void parse\(byte\[\] raw\)\s*\{(.*?)\n\s*\}", text, re.DOTALL)
    assignments, fields, todos = [], {}, []
    if not m:
        return assignments, fields, todos
    for line in m.group(1).splitlines():
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        s = re.sub(r"\s*//.*$", "", s).strip()   # drop trailing inline comments
        if not s:
            continue
        if any(k in s for k in ("removeSignedRequestHmacBytes", "Validate", "this.cargo = raw",
                                 "parseBase(raw)", "new MinsTime", "getIdpStatus",
                                 "getBgSource", "= getBgSource")):
            continue
        am = re.fullmatch(r"this\.(\w+)\s*=\s*(.+);", s)
        if not am:
            todos.append(s)
            continue
        name, rhs = am.group(1), am.group(2)
        swift_rhs, ftype, default = translate_expr(rhs)
        if swift_rhs is None:
            todos.append(f"{name} = {rhs}   (unrecognized RHS)")
            continue
        assignments.append(f"{name} = {swift_rhs}")
        fields[name] = (ftype, default)
    return assignments, fields, todos


def emit(props, cls, assignments, fields, todos):
    is_response = props["type"] == "RESPONSE"
    base = "ResponseMessage" if is_response else "Message"
    parts = [f"opCode: {props['opCode']}", f"size: {props['size']}"]
    if props["variableSize"]:
        parts.append("variableSize: true")
    if props["signed"]:
        parts.append("signed: true")
    parts.append(f"type: .{'response' if is_response else 'request'}")
    parts.append(f"characteristic: {props['characteristic'] or '.currentStatus'}")
    if props["modifiesInsulinDelivery"]:
        parts.append("modifiesInsulinDelivery: true")
    propsline = "MessageProps(" + ", ".join(parts) + ")"

    out = []
    note = f" (opcode raw {props['opCode_raw']})" if props["opCode_raw"] and int(props["opCode_raw"]) < 0 else ""
    out.append(f"/// TODO(port): docstring. Ported from {cls}.java{note}.")
    out.append(f"public struct {cls}: {base} {{")
    out.append(f"    public static let props = {propsline}")
    out.append("    public var cargo: [UInt8]")
    for name, (ftype, default) in fields.items():
        out.append(f"    public private(set) var {name}: {ftype} = {default}")
    out.append("    public init() { cargo = [] }")
    if is_response:
        out.append("    public init(cargo raw: [UInt8]) {")
        out.append("        cargo = raw")
        # Fail CLOSED on a short buffer: when the struct has a `status` field, a bare `return`
        # here would leave it at its default 0 (== accepted) — decoding a truncated/empty frame
        # as an accepted ack. Set status to a non-zero (rejected) value before returning.
        if "status" in fields:
            out.append(f"        guard raw.count >= {props['size']} else {{")
            out.append("            status = 1")
            out.append("            return")
            out.append("        }")
        else:
            out.append(f"        guard raw.count >= {props['size']} else {{ return }}")
        for a in assignments:
            out.append(f"        {a}")
        for t in todos:
            out.append(f"        // TODO(port): {t}")
        out.append("    }")
        out.append(f"    public mutating func parse(_ raw: [UInt8]) {{ self = {cls}(cargo: raw) }}")
    else:
        out.append("    public mutating func parse(_ raw: [UInt8]) {")
        out.append("        let body = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3)")
        out.append("        cargo = body")
        for a in assignments:
            out.append(f"        {a.replace('raw[', 'body[').replace('raw,', 'body,')}")
        for t in todos:
            out.append(f"        // TODO(port): {t}")
        out.append("    }")
    out.append("}")
    reg = f"        add({cls}.self)" if is_response else None
    return "\n".join(out), reg


def emit_history(props, cls, assignments, fields, todos):
    """Emit a HistoryLogEvent struct. Base fields (pumpTimeSec/sequenceNum) come from parseBase;
    the event-specific reads start at offset 10 in the 26-byte record."""
    out = []
    dn = props["displayName"]
    out.append(f'/// {dn or cls} — history-log event (typeId {props["typeId"]}). Ported from {cls}.java.')
    out.append(f"public struct {cls}: HistoryLogEvent {{")
    out.append(f"    public static let typeId = {props['typeId']}")
    out.append("    public var cargo: [UInt8]")
    out.append("    public private(set) var pumpTimeSec: UInt32 = 0")
    out.append("    public private(set) var sequenceNum: UInt32 = 0")
    for name, (ftype, default) in fields.items():
        out.append(f"    public private(set) var {name}: {ftype} = {default}")
    out.append("    public init() { cargo = [] }")
    out.append("    public init(cargo raw: [UInt8]) {")
    out.append("        cargo = raw")
    # Fail CLOSED on a short buffer: when the struct has a `status` field, a bare `return`
    # here would leave it at its default 0 (== accepted) — decoding a truncated/empty record
    # as an accepted ack. Set status to a non-zero (rejected) value before returning.
    if "status" in fields:
        out.append(f"        guard raw.count >= {props['size']} else {{")
        out.append("            status = 1")
        out.append("            return")
        out.append("        }")
    else:
        out.append(f"        guard raw.count >= {props['size']} else {{ return }}")
    out.append("        pumpTimeSec = Bytes.readUint32(raw, 2)")
    out.append("        sequenceNum = Bytes.readUint32(raw, 6)")
    for a in assignments:
        out.append(f"        {a}")
    for t in todos:
        out.append(f"        // TODO(port): {t}")
    out.append("    }")
    out.append("}")
    reg = f"        add({cls}.self)"
    return "\n".join(out), reg


def process(path):
    text = open(path).read()
    cls = os.path.splitext(os.path.basename(path))[0]

    hist = parse_history_props(text)
    if hist and hist["typeId"] is not None:
        assignments, fields, todos = parse_body_translate(text)
        swift, reg = emit_history(hist, cls, assignments, fields, todos)
        print(swift + "\n")
        print(f"// HistoryLogParser registration:\n//{reg}\n")
        if todos:
            print(f"// ⚠️  {len(todos)} line(s) need manual review\n", file=sys.stderr)
        return

    props = parse_props(text)
    if not props or props["opCode"] is None:
        print(f"// SKIP {cls}: no @MessageProps/@HistoryLogProps opCode found", file=sys.stderr)
        return
    assignments, fields, todos = parse_body_translate(text)
    swift, reg = emit(props, cls, assignments, fields, todos)
    print(swift)
    print()
    if reg:
        print(f"// ResponseParser registration:\n//{reg}\n")
    if todos:
        print(f"// ⚠️  {len(todos)} line(s) need manual review (see TODO(port) above)\n", file=sys.stderr)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    target = sys.argv[1]
    if os.path.isdir(target):
        for root, _, files in os.walk(target):
            for f in sorted(files):
                if f.endswith(".java"):
                    print(f"\n// ===== {f} =====")
                    process(os.path.join(root, f))
    else:
        process(target)


if __name__ == "__main__":
    main()
