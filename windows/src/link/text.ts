// The words of the link's cards and of Settings → Devices, as small pure functions (sub-project G2). The Mac's twin is `LinkText` in LinkViews.swift.

export { sizeLabel } from "../shelf/store.ts";

/** "483 291": the six digits in two groups, to read out and compare across a desk. */
export function spaced(code: string): string {
  return /^\d{6}$/.test(code) ? `${code.slice(0, 3)} ${code.slice(3)}` : code;
}

/** Whole percent of a transfer, 0 to 100. An empty file is done. */
export function percent(done: number, total: number): number {
  if (!(total > 0)) return 100;
  return Math.max(0, Math.min(100, Math.floor((done * 100) / total)));
}

/** What Settings → Devices says of a machine. */
export function stateWords(state: "pairedOnline" | "pairedOffline" | "available"): string {
  return state === "pairedOnline" ? "Paired" : state === "pairedOffline" ? "Paired, not seen" : "Available";
}

/** The screen reader's reading of the code: "4 8 3 2 9 1". */
export function readCode(code: string): string {
  return code.split("").join(" ");
}

/** The help under the machines list, by system: the firewall on Windows, mDNS on Linux. */
export function permissionHelp(platform: "windows" | "linux" | "other"): string {
  if (platform === "windows") return "If the list stays empty, check that Windows Defender Firewall allows NotchMeow on private networks (Windows asks the first time Visible turns on).";
  if (platform === "linux") return "If the list stays empty, check that your firewall allows UDP 5353 (mDNS) and NotchMeow's incoming connections on the local network.";
  return "If the list stays empty, check that your firewall allows NotchMeow on the local network.";
}
