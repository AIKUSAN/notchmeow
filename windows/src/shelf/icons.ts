// The shelf's few icons: stroke paths on a 24x24 grid, drawn with svg(path, size, { stroke }). Own file so no shipping icon list changes.

export const SHELF_ICONS = {
  // an open tray
  tray: "M22 12h-6l-2 3h-4l-2-3H2M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z",
  // a sheet with a folded corner
  file: "M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8zM14 3v5h5",
  // a folder
  folder: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
  // a paper plane
  send: "M21 3 10 14M21 3l-7 18-4-7-7-4z",
  // a folder with an arrow out
  reveal: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM12 15v-5M9.5 12.5 12 10l2.5 2.5",
  // a speech bubble
  ask: "M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z",
  // a cross
  remove: "M6 6l12 12M18 6 6 18",
  // a tick
  check: "M5 12.5 10 17.5 19 7",
  // a laptop (To a device, sub-project G2)
  device: "M5 6h14v9H5zM2 19h20",
} as const;
