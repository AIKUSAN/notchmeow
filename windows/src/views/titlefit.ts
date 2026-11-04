// The active session row's title (the Mac's ProjectsTitleFit rule): the tool
// label ("Claude Code", "n8n") is drawn whole beside the name, or not at all.
// The name gives way first: when it is cut short with the label beside it, the
// label is dropped, never drawn as a fragment. Pure, so the rule is tested
// without a DOM; views.ts measures the two widths after layout.

/** Half a pixel of slack for the rounding of layout widths. */
const SLACK = 0.5;

/** True when the name, drawn with the label beside it, is cut short: nameNatural is its full width, nameShown the width it gets. */
export function labelGivesWay(nameNatural: number, nameShown: number): boolean {
  return nameNatural > nameShown + SLACK;
}
