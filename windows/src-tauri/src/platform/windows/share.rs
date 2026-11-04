// The system's Share window for files (sub-project G1, Windows): `DataTransferManager`, reached through `IDataTransferManagerInterop` the way a desktop program that is not a packaged app
// has to. Two steps, because they live on different threads:
//   1. `prepare` (a worker thread): turns the paths into WinRT storage items. The WinRT `.get()` blocks, so it never runs on the main thread (the same rule as the OCR in ai/attachments.rs).
//   2. `show` (the main thread): asks for the Share window over the island's window and answers its `DataRequested` event with those items.
// Sending always starts with the user's click, and nothing here logs or returns a name, a path or a recipient: what the user picks in the Share window is the system's, and never ours.

use std::path::PathBuf;

use ::windows::core::{factory, AgileReference, Interface, HSTRING};
use ::windows::ApplicationModel::DataTransfer::{DataRequestedEventArgs, DataTransferManager};
use ::windows::Foundation::TypedEventHandler;
use ::windows::Storage::{IStorageItem, StorageFile, StorageFolder};
use ::windows::Win32::Foundation::HWND;
use ::windows::Win32::UI::Shell::IDataTransferManagerInterop;
use ::windows_collections::IIterable;

/// The one error `prepare` gives: it names no file, because it reaches the log.
const CANNOT_OPEN: &str = "cannot open a file to share";

/// The files and folders as storage items. Folders are shared as folders. Each item is held through an `AgileReference`, which is `Send`: the items are made on a worker thread and
/// used on the main thread, and a plain WinRT interface pointer is not promised to cross threads.
pub fn prepare(paths: &[PathBuf]) -> Result<Vec<AgileReference<IStorageItem>>, String> {
    let mut items = Vec::new();
    for p in paths {
        let path = HSTRING::from(p.as_os_str());
        let item: IStorageItem = if p.is_dir() {
            StorageFolder::GetFolderFromPathAsync(&path).and_then(|op| op.get()).and_then(|f| f.cast())
        } else {
            StorageFile::GetFileFromPathAsync(&path).and_then(|op| op.get()).and_then(|f| f.cast())
        }
        .map_err(|_| CANNOT_OPEN.to_string())?;
        items.push(AgileReference::new(&item).map_err(|_| CANNOT_OPEN.to_string())?);
    }
    Ok(items)
}

/// Shows the Share window over `window` and hands it `items` when it asks. Returns when the window has been asked for, not when it is closed.
pub fn show(window: HWND, items: Vec<AgileReference<IStorageItem>>) -> Result<(), String> {
    let interop = factory::<DataTransferManager, IDataTransferManagerInterop>().map_err(|e| e.to_string())?;
    let manager: DataTransferManager = unsafe { interop.GetForWindow(window) }.map_err(|e| e.to_string())?;
    let items = std::sync::Mutex::new(Some(items));
    // ponytail: on success the handler stays registered for the life of the window (one small closure per send, its items already taken); remove it from inside the handler if sends ever number in the thousands.
    let token = manager
        .DataRequested(&TypedEventHandler::<DataTransferManager, DataRequestedEventArgs>::new(move |_, args| {
            let Some(args) = args.as_ref() else { return Ok(()) };
            let data = args.Request()?.Data()?;
            data.Properties()?.SetTitle(&HSTRING::from("Files from NotchMeow"))?;
            if let Some(items) = items.lock().ok().and_then(|mut i| i.take()) {
                data.SetStorageItems(&IIterable::<IStorageItem>::from(items.iter().filter_map(|a| a.resolve().ok()).map(Some).collect::<Vec<_>>()), true)?;
            }
            Ok(())
        }))
        .map_err(|e| e.to_string())?;
    if let Err(e) = unsafe { interop.ShowShareUIForWindow(window) } {
        // The window never came up, so nothing will ask: do not leave a handler holding the files.
        let _ = manager.RemoveDataRequested(token);
        return Err(e.to_string());
    }
    Ok(())
}
