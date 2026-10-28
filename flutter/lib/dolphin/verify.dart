/// Is the connecting peer the technician the portal authorized? (design 2026-10-27, section 3)
enum TechCheck { checking, verified, unverifiable, rejected }

class TechVerdict {
  final TechCheck state;
  final String name;
  const TechVerdict(this.state, [this.name = '']);
}

/// Owner decision D5 (WF-11): in click mode the customer's Accept needs the portal's word on who the technician is, so a
/// PC that cannot reach the portal ([TechCheck.unverifiable]) may not accept: it shows the message and the phone.
/// Code mode is unchanged: the code itself comes through the portal, so a code login does not depend on this check.
/// A mode not read yet ('') behaves as click. Deny and closing never depend on this.
bool acceptAllowed(TechVerdict verdict, String approveMode) => switch (verdict.state) {
      TechCheck.verified => true,
      TechCheck.unverifiable => approveMode == 'password',
      TechCheck.checking || TechCheck.rejected => false,
    };

/// Client options the portal pushes with the heartbeat (app/src/lib/engine/policy.ts).
const kDolphinTechIdOption = 'dolphin-tech-id';
const kDolphinTechNameOption = 'dolphin-tech-name';
const kDolphinTechUntilOption = 'dolphin-tech-until';

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
}) {
  if (techId.isEmpty) return const TechVerdict(TechCheck.unverifiable);
  if (techId != '-' && techId == peerId && nowSeconds < until) {
    return TechVerdict(TechCheck.verified, techName == '-' ? '' : techName);
  }
  if (waitedMs < kDolphinVerifyWaitMs) return const TechVerdict(TechCheck.checking);
  return const TechVerdict(TechCheck.rejected);
}
