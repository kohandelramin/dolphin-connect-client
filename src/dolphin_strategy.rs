//! Dolphin Connect (DD-24): the heartbeat loop (`src/hbbs_http/sync.rs`) asks here before it applies the portal's
//! strategy. The rules and the canonical text are in `src/dolphin_strategy_core.rs`; this file makes the one Ed25519
//! call (libsodium through `hbb_common::sodiumoxide`, which upstream already uses for its own signatures) and keeps the
//! "last strategy refused" flag the next heartbeats report as `dolphin_sig: "bad"`.

use crate::dolphin_strategy_core as rules;
use hbb_common::log;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};

/// Set when a strategy is refused, cleared when one is applied. In memory only: after a restart the app reports its
/// old version, the portal sends the strategy again, and a bad one sets the flag again on that first answer.
static LAST_REFUSED: AtomicBool = AtomicBool::new(false);

/// Whether this strategy may be applied. `version` is the answer's `modified_at`, `id` the ID this heartbeat sent.
/// Logs a refusal with its reason, never the values or the signature.
pub fn accept(id: &str, version: Option<i64>, options: &HashMap<String, String>) -> bool {
    let applied = match rules::check(
        crate::dolphin::STRATEGY_PUBLIC_KEY,
        id,
        version,
        options.iter().map(|(k, v)| (k.as_str(), v.as_str())),
    ) {
        rules::Check::Unchecked => true,
        rules::Check::Refuse(why) => {
            log::warn!("strategy refused (DD-24): {why}; the previous settings stay");
            false
        }
        rules::Check::Verify { public_key, signature, message } => {
            if verify(&public_key, &signature, message.as_bytes()) {
                true
            } else {
                log::warn!("strategy refused (DD-24): the signature does not verify; the previous settings stay");
                false
            }
        }
    };
    let refused = rules::refused_after(LAST_REFUSED.load(Ordering::Relaxed), Some(applied));
    LAST_REFUSED.store(refused, Ordering::Relaxed);
    applied
}

fn verify(public_key: &[u8; 32], signature: &[u8; 64], message: &[u8]) -> bool {
    use hbb_common::sodiumoxide::crypto::sign;
    let Some(pk) = sign::PublicKey::from_slice(public_key) else {
        return false;
    };
    let Ok(sig) = sign::Signature::from_bytes(signature) else {
        return false;
    };
    sign::verify_detached(&sig, message, &pk)
}

/// The heartbeat's `dolphin_sig` field (`"bad"` while the last strategy was refused).
pub fn heartbeat_sig() -> Option<&'static str> {
    rules::heartbeat_sig(LAST_REFUSED.load(Ordering::Relaxed))
}

/// Whether to store the answer's `modified_at` (`None`: the answer had no strategy).
pub fn store_version(strategy_applied: Option<bool>) -> bool {
    rules::store_version(strategy_applied)
}
