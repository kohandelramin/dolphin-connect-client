//! Dolphin Connect, Plan 19 C3: «کادر رنگی دور صفحه», the rules of the coloured frame around the customer's screen
//! during a session (src/dolphin_frame.rs draws it). Pure, so they are tested alone:
//! `rustc --edition 2021 --test src/dolphin_frame_core.rs`.

/// How thick each edge is, in physical pixels: enough to see at a glance, thin enough to cover nothing useful.
pub const FRAME_THICKNESS: i32 = 5;

/// `main_set_common("dolphin-frame", ...)`: "#rrggbb" shows the frame in that colour, anything else removes it.
pub fn parse_colour(value: &str) -> Option<(u8, u8, u8)> {
    let hex = value.trim().strip_prefix('#')?;
    if hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let byte = |i: usize| u8::from_str_radix(&hex[i..i + 2], 16).ok();
    Some((byte(0)?, byte(2)?, byte(4)?))
}

/// Windows' COLORREF: 0x00bbggrr.
pub fn colorref((r, g, b): (u8, u8, u8)) -> u32 {
    (r as u32) | ((g as u32) << 8) | ((b as u32) << 16)
}

/// A screen rectangle in physical pixels, right and bottom exclusive (as Windows' RECT).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

impl Rect {
    pub fn width(&self) -> i32 {
        self.right - self.left
    }
    pub fn height(&self) -> i32 {
        self.bottom - self.top
    }
}

/// The four strips along one monitor's edges, inside it: top and bottom across the whole width, left and right
/// between them (no overlap, so the corners are drawn once). None for a monitor too small to frame.
pub fn edge_rects(m: Rect, t: i32) -> Vec<Rect> {
    if t <= 0 || m.width() <= 2 * t || m.height() <= 2 * t {
        return vec![];
    }
    vec![
        Rect { left: m.left, top: m.top, right: m.right, bottom: m.top + t },
        Rect { left: m.left, top: m.bottom - t, right: m.right, bottom: m.bottom },
        Rect { left: m.left, top: m.top + t, right: m.left + t, bottom: m.bottom - t },
        Rect { left: m.right - t, top: m.top + t, right: m.right, bottom: m.bottom - t },
    ]
}

/// What a new command asks the drawing thread to do, given what it shows now.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameChange {
    /// Nothing to do: the same colour, or still nothing.
    Keep,
    /// Show the frame (start the thread).
    Show,
    /// Remove the frame (end the thread).
    Hide,
    /// Another colour: end the thread and start it again.
    Recolour,
}

pub fn frame_change(current: Option<(u8, u8, u8)>, wanted: Option<(u8, u8, u8)>) -> FrameChange {
    match (current, wanted) {
        (None, None) => FrameChange::Keep,
        (None, Some(_)) => FrameChange::Show,
        (Some(_), None) => FrameChange::Hide,
        (Some(a), Some(b)) if a == b => FrameChange::Keep,
        (Some(_), Some(_)) => FrameChange::Recolour,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn colours() {
        assert_eq!(parse_colour("#E11D48"), Some((0xE1, 0x1D, 0x48)));
        assert_eq!(parse_colour(" #0d9488 "), Some((0x0D, 0x94, 0x88)));
        for bad in ["", "-", "E11D48", "#E11D4", "#E11D480", "#GG0000", "red"] {
            assert_eq!(parse_colour(bad), None, "{bad}");
        }
        assert_eq!(colorref((0x12, 0x34, 0x56)), 0x0056_3412);
    }

    #[test]
    fn four_edges_inside_the_monitor_without_overlap() {
        let m = Rect { left: 0, top: 0, right: 1920, bottom: 1080 };
        let e = edge_rects(m, 5);
        assert_eq!(e.len(), 4);
        let area: i64 = e.iter().map(|r| r.width() as i64 * r.height() as i64).sum();
        // The frame's area exactly: the whole minus the inside.
        assert_eq!(area, 1920 * 1080 - (1920 - 10) * (1080 - 10));
        for r in &e {
            assert!(r.left >= m.left && r.top >= m.top && r.right <= m.right && r.bottom <= m.bottom);
            assert!(r.width() > 0 && r.height() > 0);
        }
        // A second monitor left of the primary: negative coordinates work the same.
        let left = Rect { left: -1280, top: 0, right: 0, bottom: 1024 };
        assert_eq!(edge_rects(left, 5)[3], Rect { left: -5, top: 5, right: 0, bottom: 1019 });
        assert!(edge_rects(Rect { left: 0, top: 0, right: 8, bottom: 8 }, 5).is_empty());
        assert!(edge_rects(m, 0).is_empty());
    }

    #[test]
    fn changes() {
        let red = Some((1, 2, 3));
        let blue = Some((3, 2, 1));
        assert_eq!(frame_change(None, None), FrameChange::Keep);
        assert_eq!(frame_change(None, red), FrameChange::Show);
        assert_eq!(frame_change(red, None), FrameChange::Hide);
        assert_eq!(frame_change(red, red), FrameChange::Keep);
        assert_eq!(frame_change(red, blue), FrameChange::Recolour);
    }
}
