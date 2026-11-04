// Which system this is, for the one rule that differs: when the app gives up on a permission request (Windows and Linux at 110 s, the Mac at 115 s). The Windows and Linux
// app is never the Mac. Pure: the user agent is a parameter, so the plain-Node checks can say what they like.

import type { Platform } from "./core.ts";

export function platformName(userAgent: string = typeof navigator === "undefined" ? "" : navigator.userAgent): Exclude<Platform, "mac"> {
  return /windows/i.test(userAgent) ? "windows" : "linux";
}
