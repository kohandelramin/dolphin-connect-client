//! Dolphin Connect: settings compiled into this build (see dolphin/README.md).
//!
//! Replaces RustDesk's custom-client loader, so neither a `custom.txt` beside the exe nor the exe's
//! file name can point the client at another server.
use hbb_common::config;
use std::{collections::HashMap, sync::RwLock};

include!("dolphin_generated.rs");

fn fill(map: &RwLock<HashMap<String, String>>, entries: &[(&str, &str)]) {
    let mut map = map.write().unwrap();
    for (k, v) in entries {
        map.insert((*k).to_owned(), (*v).to_owned());
    }
}

pub fn apply() {
    *config::APP_NAME.write().unwrap() = APP_NAME.to_owned();
    *config::PROD_RENDEZVOUS_SERVER.write().unwrap() = RENDEZVOUS_SERVER.to_owned();
    fill(&config::OVERWRITE_SETTINGS, OVERRIDE_SETTINGS);
    fill(&config::DEFAULT_SETTINGS, DEFAULT_SETTINGS);
    fill(&config::OVERWRITE_LOCAL_SETTINGS, OVERRIDE_LOCAL_SETTINGS);
    fill(&config::DEFAULT_LOCAL_SETTINGS, DEFAULT_LOCAL_SETTINGS);
    fill(&config::BUILTIN_SETTINGS, BUILTIN_SETTINGS);
    fill(&config::HARD_SETTINGS, HARD_SETTINGS);
    hbb_common::log::info!("Dolphin Connect settings applied (profile {})", PROFILE);
}
