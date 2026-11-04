// The Linux drag source (sub-project G1): starts a GTK drag of real files from the island's window. The data is a `text/uri-list` of `file://` URIs, which file managers, mail clients and
// browsers all take. Only copying is offered. GTK runs this on the main thread; `begin` returns at once and `done` is called from the drag's end.
//
// Wayland is the risk the spike exists to measure: a compositor may refuse a drag that does not come from the press that started it (GTK then returns no drag context, and `done` gets
// that error). X11 and XWayland do not mind. See dragout.rs for the fallback.

use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use gtk::gdk;
use gtk::glib::SignalHandlerId;
use gtk::prelude::*;

use crate::dragout::file_uri;
use crate::platform::DragDone;

pub fn begin(window: &gtk::ApplicationWindow, paths: &[PathBuf], done: DragDone) {
    let uris: Vec<String> = paths.iter().map(|p| file_uri(p)).collect();
    let source: gtk::Widget = window.clone().upcast();
    let done = Rc::new(RefCell::new(Some(done)));
    let handlers: Rc<RefCell<Vec<SignalHandlerId>>> = Rc::new(RefCell::new(Vec::new()));

    // Both handlers are taken off the window again when the drag is over, so a second drag starts clean.
    let finish = {
        let (source, handlers, done) = (source.clone(), handlers.clone(), done.clone());
        Rc::new(move |result: Result<&'static str, String>| {
            for id in handlers.borrow_mut().drain(..) {
                source.disconnect(id);
            }
            if let Some(d) = done.borrow_mut().take() {
                d(result);
            }
        })
    };

    let get = source.connect_drag_data_get(move |_, _, data, _, _| {
        let refs: Vec<&str> = uris.iter().map(String::as_str).collect();
        data.set_uris(&refs);
    });
    let end = {
        let finish = finish.clone();
        source.connect_drag_end(move |_, ctx| finish(Ok(if ctx.selected_action() == gdk::DragAction::COPY { "copied" } else { "cancelled" })))
    };
    handlers.borrow_mut().extend([get, end]);

    let targets = gtk::TargetList::new(&[gtk::TargetEntry::new("text/uri-list", gtk::TargetFlags::OTHER_APP, 0)]);
    if source.drag_begin_with_coordinates(&targets, gdk::DragAction::COPY, 1, None, -1, -1).is_none() {
        finish(Err("The system would not start the drag (on Wayland it needs the press that began it).".into()));
    }
}
