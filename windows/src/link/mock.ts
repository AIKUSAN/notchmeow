// A stand-in link for a plain browser (sub-project G2): `npm run dev` and the `?dev` page show the link's cards and Settings → Devices working with no app behind it, and the checks run it
// in plain Node. It keeps a snapshot, every call changes it as the real one would (a little), and `set` lets the `?dev` panel (devlink.ts) put it in any state. It records the calls.

import { LINK_EMPTY } from "./model.ts";
import type { LinkBackend, LinkSnapshot, ShownRef } from "./model.ts";

/** A name a card would accept, as Rust decides it: 1 to 63 bytes, no control or invisible character, no space at either end. The stand-in's copy of the rule is only for the `?dev` page. */
function nameOk(name: string): boolean {
  const bytes = new TextEncoder().encode(name).length;
  return bytes >= 1 && bytes <= 63 && name === name.trim() && !/[\p{Cc}\p{Cf}\u2028\u2029]/u.test(name);
}

/** A stand-in link: it keeps a snapshot, every call changes it as the real one would (a little), and `set` lets the `?dev` panel put it in any state. It records the calls for the checks. */
export function mockLinkBackend(seed: Partial<LinkSnapshot> = {}): LinkBackend & { snapshot: LinkSnapshot; calls: string[]; set(next: Partial<LinkSnapshot>): void } {
  const listeners = new Set<(s: LinkSnapshot) => void>();
  const self = {
    snapshot: { ...LINK_EMPTY, name: "Desk PC", folder: "C:\\Users\\Sam\\Downloads\\NotchMeow", ...seed } as LinkSnapshot,
    calls: [] as string[],
    set(next: Partial<LinkSnapshot>) {
      self.snapshot = { ...self.snapshot, ...next };
      for (const l of listeners) l(self.snapshot);
    },
    state: async () => self.snapshot,
    onSnapshot(cb: (s: LinkSnapshot) => void) {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    setVisible(on: boolean) {
      self.calls.push(`visible ${on}`);
      self.set({ visible: on, listening: on });
    },
    async setName(name: string) {
      self.calls.push(`name ${name}`);
      if (!nameOk(name)) return false;
      self.set({ name });
      return true;
    },
    setDevicesOpen: (open: boolean) => void self.calls.push(`devices ${open}`),
    setShelfOpen: (open: boolean) => void self.calls.push(`shelf ${open}`),
    pair: (id: string) => void self.calls.push(`pair ${id}`),
    answerPair: (yes: boolean, shown: ShownRef | null) => void self.calls.push(`answerPair ${yes} ${shown?.key ?? "-"}`),
    respondOffer: (accept: boolean, shown: ShownRef | null) => void self.calls.push(`respondOffer ${accept} ${shown?.key ?? "-"}`),
    cancelReceiving: (shown: ShownRef | null) => void self.calls.push(`cancelReceiving ${shown?.key ?? "-"}`),
    dismiss(shown: ShownRef | null) {
      self.calls.push(`dismiss ${shown?.key ?? "-"}`);
      if (self.snapshot.card?.kind === "result") self.set({ card: null });
    },
    forget(id: string) {
      self.calls.push(`forget ${id}`);
      self.set({ rows: self.snapshot.rows.filter((r) => r.id !== id) });
    },
    send: (ids: string[], to: string) => void self.calls.push(`send ${ids.join(",")} ${to}`),
    cancelSending: () => void self.calls.push("cancelSending"),
    revealResult: () => void self.calls.push("revealResult"),
    revealFolder: () => void self.calls.push("revealFolder"),
  };
  return self;
}
