// NotchMeow runs without a console window: the cat is the whole UI.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    notchmeow_lib::run()
}
