/// Is the connecting peer the technician the portal authorized? (design 2026-10-27, section 3)
enum TechCheck { checking, verified, unverifiable, rejected }

class TechVerdict {
  final TechCheck state;
  final String name;
  const TechVerdict(this.state, [this.name = '']);
}

/// Owner decision D5 (WF-11): the customer's Accept needs the portal's word on who the technician is, so only
/// [TechCheck.verified] may accept, in every approve mode. A PC that cannot reach the portal shows the message and the
/// phone instead. Code mode stays usable: a valid one-time code is authorised in Rust before any prompt
/// (src/server/connection.rs), so a code login never reaches this check; the prompt serves only a peer with no code or
/// a wrong one. Deny and closing never depend on this.
bool acceptAllowed(TechVerdict verdict) => verdict.state == TechCheck.verified;

/// Client options the portal pushes with the heartbeat (app/src/lib/engine/policy.ts).
const kDolphinTechIdOption = 'dolphin-tech-id';
const kDolphinTechNameOption = 'dolphin-tech-name';
const kDolphinTechUntilOption = 'dolphin-tech-until';

/// "Y" while the client's heartbeat to the portal is failing (src/dolphin_portal.rs, written by src/hbbs_http/sync.rs).
const kDolphinPortalDownOption = 'dolphin-portal-down';

/// TB-9 (B9): the end time comes from the portal's clock and is compared with this PC's, which can be wrong. The portal
/// re-sends who may connect at least every 5 minutes and cuts expired sessions itself, so the prompt allows a PC clock
/// up to this far ahead instead of refusing a technician who is still authorized.
const kDolphinClockSkewSeconds = 600;

/// How long the prompt waits for the next heartbeat (every 3 s while a connection is open).
const kDolphinVerifyWaitMs = 6000;

/// [techId] empty means the portal never sent it (a PC that cannot reach the portal): we cannot check ([acceptAllowed] decides what
/// that means). "-" means the portal says nobody may connect now.
TechVerdict verifyTechnician({
  required String peerId,
  required String techId,
  required String techName,
  required int until,
  required int nowSeconds,
  required int waitedMs,
  bool portalDown = false,
}) {
  if (techId.isEmpty) return const TechVerdict(TechCheck.unverifiable);
  if (techId != '-' && techId == peerId && nowSeconds < until + kDolphinClockSkewSeconds) {
    return TechVerdict(TechCheck.verified, techName == '-' ? '' : techName);
  }
  // The wait comes first: a new prompt shows "checking" before the outage text (neither state accepts).
  if (waitedMs < kDolphinVerifyWaitMs) return const TechVerdict(TechCheck.checking);
  if (portalDown) return const TechVerdict(TechCheck.unverifiable);
  return const TechVerdict(TechCheck.rejected);
}
