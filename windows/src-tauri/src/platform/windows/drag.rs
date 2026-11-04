// The Windows drag source (sub-project G1): starts an OLE drag of real files from the island, the way Explorer does. The page cannot do this itself: with Tauri's drag-and-drop
// setting on (the island needs it, to receive files), WebView2 hands the page no HTML5 drag. So a press that moves on a shelf tile asks Rust, and Rust runs `DoDragDrop` with a
// shell data object that holds the files (CF_HDROP and the rest, built by the shell from their paths) and a drop source that follows the left button.
//
// `run` is modal: it returns when the button is released or Escape is pressed, so it is called on the main thread (the one OLE is initialised on, which is also where the window's own
// drop target lives) and never from an async worker. Only copying is allowed: an original is never moved or deleted by a drag.

use std::os::windows::ffi::OsStrExt;
use std::path::PathBuf;

use ::windows::core::{implement, BOOL, HRESULT, PCWSTR};
use ::windows::Win32::Foundation::{DRAGDROP_S_CANCEL, DRAGDROP_S_DROP, DRAGDROP_S_USEDEFAULTCURSORS, S_OK};
use ::windows::Win32::System::Com::{IBindCtx, IDataObject};
use ::windows::Win32::System::Ole::{DoDragDrop, IDropSource, IDropSource_Impl, DROPEFFECT, DROPEFFECT_COPY};
use ::windows::Win32::System::SystemServices::{MK_LBUTTON, MODIFIERKEYS_FLAGS};
use ::windows::Win32::UI::Shell::Common::ITEMIDLIST;
use ::windows::Win32::UI::Shell::{ILFree, SHCreateDataObject, SHParseDisplayName};

/// The drop source: the drag goes on while the left button is down, ends in a drop when it is released and is cancelled by Escape. The cursors are the system's.
#[implement(IDropSource)]
struct Source;

impl IDropSource_Impl for Source_Impl {
    fn QueryContinueDrag(&self, fescapepressed: BOOL, grfkeystate: MODIFIERKEYS_FLAGS) -> HRESULT {
        if fescapepressed.as_bool() {
            DRAGDROP_S_CANCEL
        } else if grfkeystate.0 & MK_LBUTTON.0 == 0 {
            DRAGDROP_S_DROP
        } else {
            S_OK
        }
    }

    fn GiveFeedback(&self, _effect: DROPEFFECT) -> HRESULT {
        DRAGDROP_S_USEDEFAULTCURSORS
    }
}

/// The shell's item ids for the paths, freed when this goes out of scope (the data object keeps its own copies).
struct Pidls(Vec<*mut ITEMIDLIST>);

impl Drop for Pidls {
    fn drop(&mut self) {
        for p in &self.0 {
            unsafe { ILFree(Some(*p as *const ITEMIDLIST)) };
        }
    }
}

/// Drags these files (they must exist) until the button is released. `Ok("copied")` when a target took a copy, `Ok("none")` when the drop landed nowhere that accepts files,
/// `Ok("cancelled")` for Escape, `Err` when the system could not even start.
pub fn run(paths: &[PathBuf]) -> Result<&'static str, String> {
    let mut pidls = Pidls(Vec::new());
    for p in paths {
        let wide: Vec<u16> = p.as_os_str().encode_wide().chain(Some(0)).collect();
        let mut pidl: *mut ITEMIDLIST = std::ptr::null_mut();
        unsafe { SHParseDisplayName(PCWSTR(wide.as_ptr()), None::<&IBindCtx>, &mut pidl, 0, None) }.map_err(|_| "cannot find the file".to_string())?;
        pidls.0.push(pidl);
    }
    let absolute: Vec<*const ITEMIDLIST> = pidls.0.iter().map(|p| *p as *const ITEMIDLIST).collect();
    let data: IDataObject = unsafe { SHCreateDataObject(None, Some(&absolute), None::<&IDataObject>) }.map_err(|e| format!("cannot make the data object: {e}"))?;
    let source: IDropSource = Source.into();
    let mut effect = DROPEFFECT(0);
    let hr = unsafe { DoDragDrop(&data, &source, DROPEFFECT_COPY, &mut effect) };
    if hr == DRAGDROP_S_DROP {
        Ok(if effect == DROPEFFECT_COPY { "copied" } else { "none" })
    } else if hr == DRAGDROP_S_CANCEL {
        Ok("cancelled")
    } else {
        Err(format!("DoDragDrop failed: {hr:?}"))
    }
}
