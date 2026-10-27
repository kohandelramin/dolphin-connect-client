include!("../../dolphin/version_resource.rs");

fn main() {
    #[cfg(windows)]
    {
        use std::io::Write;
        let mut res = winres::WindowsResource::new();
        res.set_icon("../../res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("../../res/manifest.xml");
        // Dolphin Connect (TB-4): the outer exe is what customers see in Explorer, so it carries our name and version.
        println!("cargo:rerun-if-env-changed=DOLPHIN_VERSION");
        println!("cargo:rerun-if-env-changed=DOLPHIN_FILE_VERSION");
        if let (Ok(version), Ok(file_version)) = (std::env::var("DOLPHIN_VERSION"), std::env::var("DOLPHIN_FILE_VERSION")) {
            let packed = pack_file_version(&file_version).expect("DOLPHIN_FILE_VERSION must be four numbers up to 65535");
            res.set("ProductName", "Dolphin Connect")
                .set("FileDescription", "Dolphin Connect")
                .set("CompanyName", "Dolphin")
                .set("LegalCopyright", "\u{a9} Dolphin \u{b7} portions \u{a9} Purslane Tech Pte. Ltd. \u{b7} AGPL-3.0")
                .set("FileVersion", &file_version)
                .set("ProductVersion", &version)
                .set_version_info(winres::VersionInfo::FILEVERSION, packed)
                .set_version_info(winres::VersionInfo::PRODUCTVERSION, packed);
        }
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
