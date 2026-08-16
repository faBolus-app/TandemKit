# Booked bench session — saline, one sitting

**Status:** BOOKED (not yet run). **Trigger:** the next time a pump + saline cartridge + a signing/dev
Mac are all in the same place. **Disposition unchanged by this doc: NO-GO for real insulin delivery —
saline only, on the bench, never on a body.**

This session exists because three separate open items all require the *same* hardware setup and are
cheapest to answer in one sitting. Booking them together is the point — do not run them piecemeal, and
do not "discover" them at a later audit (master-plan P7). Each objective below is independently
pass/fail and independently loggable back into `PINNED.md`'s Validation log.

## Preconditions (all three objectives)

- Tandem pump on the **pinned firmware** (`PINNED.md` — Control-IQ+ 7.10.2); if firmware differs, record
  it and treat parity results as firmware-specific.
- Cartridge filled with **saline**. Confirm on the pump's own screens / t:connect after every step —
  the pump is the source of truth, not the app.
- `swift run TandemBenchHarness` with `PUMPX2_DELIVER_SALINE=1` (the only flag that unblocks writes; it
  is off in every CI job — see WIP register item 9).
- Byte-parity to the cliparser oracle is expected to hold throughout; a divergence is itself a finding.

---

## Objective 1 — Cancel *mid*-delivery → partial-delivery reporting (WIP item 5; defect group B)

The indeterminate case group B is built around: a cancel issued **while a dose is still completing**. The
0.10 u delivery already validated (`PINNED.md` 2026-07-18) completes too fast to race, so this needs an
**extended or large** bolus whose delivery window is long enough to interrupt.

**Procedure**
1. Program an extended/combo or a large units bolus (e.g. 2.0 u extended over the shortest allowed
   duration, or the largest saline-safe immediate dose) so the delivery window is measurable.
2. Partway through delivery, issue a signed `CancelBolus`.
3. Read `LastBolusStatusV2` and `CurrentBolusStatus`; compare the **delivered** amount to the pump
   screen and t:connect.

**Pass/fail (DoD)**
- The app reports the **actual partial amount** the pump recorded — never the requested amount, never a
  fabricated "delivered", never a stuck "delivering" (FB-02 / R3-B).
- If the cancel *races* completion (dose finishes before the cancel lands), the outcome is reported as
  **indeterminate** and reconciled against pump history on the next read — not asserted as either
  full-delivery or cancelled.
- Feeds `faBolus/docs/RELEASE-GATES.md` §1 "Cancel mid-delivery" and the group-B §14 matrix.

---

## Objective 2 — Does the pump ECHO the request txId? (WIP item 12; R3-D)

R3-D closed the cross-resolve hazard (two identical in-flight opcodes) with **delivery-class
serialization** because the transaction coordinator correlates by `(characteristic, opCode)` FIFO, and
it is **not established** whether a Tandem response echoes the request's transaction id in `frame[1]`.
Matching on a txId the pump does *not* echo would fail every correlation and break all pump comms — so
this must be a measured hardware fact before the code changes.

**Procedure**
1. With the harness logging raw frames, send several requests of **distinct** opcodes and a couple of
   the **same** opcode back-to-back (a status poll burst is ideal).
2. For each, record `request.frame[1]` (the txId byte the client set) and the matching
   `response.frame[1]`.

**Pass/fail (DoD)**
- **Echoed** (`response.frame[1] == request.frame[1]` reliably, including for same-opcode bursts): then
  the follow-up is safe — add `&& frame[1] == entry.txId` to `PumpTransactionCoordinator.ingest()` and
  drop the `serialized` gate, letting two identical in-flight opcodes coexist. Retest Objective 1 after.
- **Not echoed / unreliable:** record it; **keep** delivery-class serialization exactly as shipped. This
  is the safe default and requires no code change.
- Either way, update WIP register item 12 with the captured pairs.

---

## Objective 4 — Confirm the `CurrentActiveIdpValuesResponse` byte-4 targetBg decode live (09.8-04; D-07)

09.8-04 corrected `CurrentActiveIdpValuesResponse.currentTargetBg` from `Int(raw[5])` (which decoded
the real capture as 0) to `Bytes.readShort(raw, 4)` — the real hardware capture `7017000073002c012800`
(cited in `gh pr diff 102 --repo jwoglom/pumpx2`; see WIP-REGISTER "ADOPTION CANDIDATE #1") decodes to
`currentTargetBg == 115` only at byte 4. This fix landed **capture-backed but NOT oracle-backed** — the
pinned cliparser oracle is itself defective for this field (its `buildCargo` writes targetBg at byte 5,
padding at byte 4; the OPPOSITE of the real wire), so no OracleRunner vector can confirm the offset by
construction. The byte-4 offset is confirmed only on the primary pinned pump; it must be confirmed live.

**Procedure**
1. Set a distinctive, known IDP target BG on the pump (e.g. 115 mg/dL), then read
   `CurrentActiveIdpValuesResponse` with the harness logging the raw cargo bytes.
2. Capture the raw cargo on **BOTH pump families** — `t:slim X2` AND `Mobi` — AND across **more than one
   t:slim software version** (the layout may be version-dependent, not only family-dependent; the older
   `[t:slim X2 · API 2.5 · V1/16-char]` bench pump is a second version to capture). Tag every capture with
   its `[pump family · firmware/SW version · pairing]` per PINNED.md's tagging rule.
3. For each capture, confirm byte 4 (not byte 5) carries the set target BG, and confirm no capture shows a
   genuine byte-5 layout.

**Pass/fail (DoD)**
- The app's decoded `currentTargetBg` equals the target set on the pump screen, on every (pump family,
  firmware version) captured, decoding from byte 4.
- If ANY capture shows targetBg at byte 5 (a genuine variant), the decode MUST become variant-aware keyed
  on `(pump family, firmware version)` — a flat single-offset read is then wrong for some version. Record
  the variant capture and open the variant-aware fix as its own reviewed PR.
- Until this objective passes on all captured families/versions, `currentTargetBg` stays experimental-only
  and gated (see `faBolus/docs/UNVERIFIED-GUESSES.md` entry 7) — NOT trusted for any real-insulin dosing
  decision. Feeds that faBolus entry's "Verify" step.

---

## Objective 3 — Mass/accuracy at a larger dose (WIP item 5, first half)

The only delivery validated to date is 0.10 u. Confirm accuracy does not drift at a clinically
meaningful magnitude.

**Procedure**
1. Deliver a larger saline dose (e.g. 1.0–2.0 u immediate).
2. Compare requested vs `LastBolusStatusV2` delivered vs the pump screen.

**Pass/fail (DoD)**
- Requested == delivered == pump-screen, within the pump's own rounding increment (the increment is
  already oracle-locked in `InitiateBolusRequest`; this confirms the *physical* result matches).

---

## After the session

- Append each objective's result to `PINNED.md` Validation log (dated), the same way 2026-07-18 was
  logged.
- Update WIP register items 5 and 12 with outcomes.
- If Objective 2 passed, open the txId-match change as its own reviewed PR (it touches the delivery
  correlation path — not a drive-by edit).
