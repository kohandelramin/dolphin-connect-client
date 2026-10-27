// Dolphin Connect (TB-4): Windows version resource numbers, shared by build.rs and libs/portable/build.rs through
// include!. Standard library only and no inner doc comments (include! takes items only), so CI tests it alone:
// rustc --edition 2021 --test dolphin/version_resource.rs

// "2.0.0.412" -> the 64-bit FILEVERSION/PRODUCTVERSION value Windows shows as 2.0.0.412. None unless four numbers
// of at most 65535 (build_plan.py guarantees that for the workflow's DOLPHIN_FILE_VERSION).
#[allow(dead_code)]
pub fn pack_file_version(v: &str) -> Option<u64> {
    let parts = v
        .split('.')
        .map(|p| if p.bytes().all(|b| b.is_ascii_digit()) { p.parse::<u16>().ok().map(u64::from) } else { None })
        .collect::<Option<Vec<u64>>>()?;
    if parts.len() != 4 {
        return None;
    }
    Some((parts[0] << 48) | (parts[1] << 32) | (parts[2] << 16) | parts[3])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packs_four_numbers_into_the_fixed_file_version() {
        assert_eq!(pack_file_version("2.0.0.412"), Some((2u64 << 48) | 412));
        assert_eq!(pack_file_version("1.2.3.4"), Some((1u64 << 48) | (2u64 << 32) | (3u64 << 16) | 4));
        assert_eq!(pack_file_version("65535.0.0.65535"), Some((65535u64 << 48) | 65535));
    }

    #[test]
    fn refuses_anything_else() {
        for bad in ["2.0.0", "2.0.0.65536", "2.0.0.x", "", "2.0.0.1.1", "2.0.0-rc.1"] {
            assert_eq!(pack_file_version(bad), None, "{bad:?}");
        }
    }
}
