import { asset, site } from '@/lib/site'

export type Verdict = 'kept' | 'dropped'

export type Shot = {
  /** The file in `public/prototypes`, without its size or extension. */
  name: string
  /** Pixels of the largest file. */
  width: number
  height: number
  alt: string
  caption: string
  verdict?: Verdict
}

/** One column of a band: its share of the width, and the screenshots stacked in it. */
export type Column = [share: number, ...names: string[]]

export type Entry = {
  id: string
  title: string
  note: string
  /** Someone to thank under the note: the words that lead up to the name, and where the name links. */
  credit?: { lead: string; name: string; url: string }
  shots: Shot[]
  /** How the entry is laid out on a wide screen: bands down the page, columns across each. */
  bands: Column[][]
}

export const entries: Entry[] = [
  {
    id: 'stock',
    title: 'Taking stock',
    note: 'A review pass. Nine screens went onto one sheet, in light and dark, and whatever looked wrong got a before and an after.',
    shots: [
      {
        name: 'first-pass',
        width: 1864,
        height: 1813,
        alt: 'A sheet of nine iPad screenshots: the library, the editor toolbar, Find in Notebook, New Notebook, Add a Link and Settings by day, then the library, Select Ink and Handwriting as Text at night.',
        caption: 'Nine screens on one sheet. The status bar still carries the app’s working title; the owl came later.',
      },
      {
        name: 'page-navigator',
        width: 1220,
        height: 3135,
        alt: 'The page navigator four times: before, after, after with a page number typed in, and after at night.',
        caption: 'The page navigator, before and after: a field that looks like one, and a Done you can find.',
      },
    ],
    bands: [[[8, 'first-pass'], [4, 'page-navigator']]],
  },
  {
    id: 'inks',
    title: 'Eight kinds of ink',
    note: 'Each pen needed a sample of how it writes. PencilKit draws the line and the app keeps only its shape, so one drawing takes any colour.',
    shots: [
      {
        name: 'ink-shapes',
        width: 2000,
        height: 800,
        alt: 'A grid of wavy strokes in white on cream: eight kinds of ink, each at six widths from a hairline to very broad, shown twice.',
        caption: 'Each ink at six widths, saved as a bare shape. Not much to look at until it is given a colour.',
      },
      {
        name: 'ink-samples',
        width: 1056,
        height: 1536,
        alt: 'Eight wavy strokes in each of four colours: navy, cobalt, yellow and tomato.',
        caption: 'Given four. Pen, fineliner, fountain pen and calligraphy pen; then pencil, highlighter, crayon and brush.',
      },
      {
        name: 'ink-swatches',
        width: 1150,
        height: 1010,
        alt: 'A pen’s options: the pencil in green, eight stroke samples in a grid with one outlined, a palette of sixteen colours with a colour well, and a width strip.',
        caption: 'Their first home: a grid in the pen’s options. The pen roll replaced it.',
        verdict: 'dropped',
      },
    ],
    bands: [[[7, 'ink-shapes', 'ink-swatches'], [5, 'ink-samples']]],
  },
  {
    id: 'tray',
    title: 'Where the pens go',
    note: 'The app keeps its own pens, each with its ink and its width, and they need somewhere to stand. Three places were tried.',
    shots: [
      {
        name: 'tray-side',
        width: 517,
        height: 756,
        alt: 'A whiteboard page with four pens in a column down its left edge and the system’s tool picker along the bottom.',
        caption: 'First place: the app’s own pens down the side of a whiteboard, with the system’s tool picker still along the foot.',
        verdict: 'dropped',
      },
      {
        name: 'tray-top',
        width: 834,
        height: 1210,
        alt: 'The same whiteboard with the four pens moved into the top bar, beside undo and redo.',
        caption: 'Second place: up in the top bar, beside undo and redo.',
        verdict: 'dropped',
      },
      {
        name: 'stock-picker',
        width: 550,
        height: 133,
        alt: 'A close crop of the system’s tool picker: undo, redo, six drawing tools, a ruler and six colours.',
        caption: 'The system’s picker, close up. Nothing of it is left in the app but the colour well.',
        verdict: 'dropped',
      },
      {
        name: 'whiteboard-bar',
        width: 300,
        height: 37,
        alt: 'A small bar with three buttons, Show Everything, Actual Size and Pages, and a help button.',
        caption: 'The whiteboard’s own bar, cropped out to be looked at by itself.',
      },
      {
        name: 'tray-foot',
        width: 1340,
        height: 800,
        alt: 'A tray at the foot of a dotted page holding four pens, an eraser, a lasso, a picture, a text box and settings. A pen’s options are open above it, and the system’s colour picker is open over those.',
        caption: 'Third place: the foot of the page, on one board. Here the system’s colour picker has opened on top of the pen’s own options.',
        verdict: 'kept',
      },
      {
        name: 'tray-frames',
        width: 1944,
        height: 1342,
        alt: 'Four screenshots of a ruled page with the tray at its foot. In the fourth, a menu titled Shortcuts in the Tray is set so large that its words break across lines.',
        caption: 'Four frames of the tray at the foot of a page. In the last, the shortcuts menu has outgrown its popover.',
      },
      {
        name: 'tray-shortcuts',
        width: 1168,
        height: 720,
        alt: 'The Shortcuts in the Tray menu at night: Picture and Text Box ticked in mustard, then Sticker, Link, Study Tape, Ruler and Zoom Window.',
        caption: 'The same menu once it fitted. What stands in the tray is ticked in mustard.',
      },
    ],
    bands: [
      [[3, 'tray-side'], [4, 'tray-top'], [5, 'stock-picker', 'whiteboard-bar', 'tray-foot']],
      [[7, 'tray-frames'], [5, 'tray-shortcuts']],
    ],
  },
  {
    id: 'roll',
    title: 'The pen roll',
    note: 'The kinds of pen are drawn, not named: eight tools standing in a cloth pocket, the one in use pulled up. Names would not have fitted under them at large text sizes, or in German.',
    shots: [
      {
        name: 'pen-roll-stitched',
        width: 991,
        height: 2000,
        alt: 'Six drawings of the pen roll: eight tools standing in a blue pocket with dashed stitching, in black, blue, yellow, red and green, and once on a dark ground.',
        caption: 'First drawings: a stitched pocket, and the chosen tool standing taller than the rest. The stitching went.',
      },
      {
        name: 'pen-roll-piped',
        width: 1344,
        height: 2520,
        alt: 'Six more drawings of the pen roll with deeper pockets. The last three have a mustard line along the pocket’s top edge.',
        caption: 'Second round: pockets that swell between their seams, then mustard piping along the top. The last three are how it stayed.',
        verdict: 'kept',
      },
      {
        name: 'pen-roll-close',
        width: 1360,
        height: 840,
        alt: 'A close view of the pen roll at night, the fountain pen standing out of its pocket over a check mark.',
        caption: 'Close enough to check the nibs.',
      },
      {
        name: 'pen-options',
        width: 1260,
        height: 1140,
        alt: 'A pen’s options at night: the fountain pen’s own line, the pen roll, sixteen colours and a colour well, a width strip, and buttons to move the pen along or take it off.',
        caption: 'In place: the pen’s own line at the top, the roll, the colours, and a width strip that swells as the stroke does.',
      },
      {
        name: 'split-view',
        width: 2400,
        height: 1155,
        alt: 'Three screenshots of two notebooks open side by side, with a pen’s options opened from the left notebook and then from the right.',
        caption: 'Two notebooks side by side, and the options opened from each half.',
      },
      {
        name: 'chalkboard',
        width: 2400,
        height: 954,
        alt: 'A pen’s options over a dark green chalkboard page, for a black fountain pen and for a blue pen. The black ink is drawn pale.',
        caption: 'On a chalkboard page, black ink is shown as pale as it writes there.',
      },
    ],
    bands: [
      [[3, 'pen-roll-stitched'], [4, 'pen-roll-piped'], [5, 'pen-roll-close', 'pen-options']],
      [[6, 'split-view'], [6, 'chalkboard']],
    ],
  },
  {
    id: 'dish',
    title: 'A dish for the Pencil',
    note: 'A squeeze of the Pencil brings the tools to its tip.',
    shots: [
      {
        name: 'ink-dish',
        width: 1452,
        height: 750,
        alt: 'A round dish by day and at night: eight wells of ink round its rim, one of them checked, with an eraser, a lasso, undo and redo in the middle.',
        caption: 'The ink dish: a well for each pen round the rim, and the eraser, the lasso, undo and redo in the middle.',
        verdict: 'kept',
      },
      {
        name: 'pen-opacity',
        width: 1512,
        height: 1258,
        alt: 'A pen’s options by day and at night with a second strip under the width, set to 45%, and the red pen’s line drawn faint.',
        caption: 'Opacity joins width. A pen set faint shows it on its own label.',
      },
      {
        name: 'tray-full',
        width: 2400,
        height: 143,
        alt: 'The tray by day and at night with eight pens, an eraser, a lasso, a picture, a text box and settings.',
        caption: 'Eight pens in the tray, to see how it holds up when it is full.',
      },
    ],
    bands: [[[7, 'ink-dish'], [5, 'pen-opacity']], [[12, 'tray-full']]],
  },
  {
    id: 'owl',
    title: 'A name and an owl',
    note: 'Here the app became OwlLuna and got its owl: brown, in round glasses, on a crescent moon, with a pad under one wing and a pencil in the other.',
    credit: { lead: 'The owl was designed by', ...site.logoDesigner },
    shots: [
      {
        name: 'owl-drawings',
        width: 2000,
        height: 742,
        alt: 'The owl four times: a hand-painted sketch, then drawn cleanly on violet, on black and on dotted cream. Smaller copies are lined up below.',
        caption: 'From a painted sketch to the icon. The clean ones are drawn in code, so the icon, its alternates and the mark in Settings come from one source.',
      },
      {
        name: 'icon-sheet',
        width: 1594,
        height: 1876,
        alt: 'A sheet titled OwlLuna app icon: Cobalt, Tomato, Moss, Oxblood, Mustard and Print, each in light, dark and tinted, and at five Home Screen sizes.',
        caption: 'The review sheet. Six skies, each in light, dark and tinted, and down to 40 pixels, where the glasses still have to read.',
      },
      {
        name: 'cold-launch',
        width: 2280,
        height: 1100,
        alt: 'Twelve frames of the app starting at night: the Home Screen, three empty frames, the owl icon alone, then the empty library saying Your shelf is ready.',
        caption: 'A launch, frame by frame: three empty ones before the owl turns up.',
      },
    ],
    bands: [[[12, 'owl-drawings']], [[5, 'icon-sheet'], [7, 'cold-launch']]],
  },
  {
    id: 'tabs',
    title: 'Tabs',
    note: 'Open notebooks sit in a row of tabs over the editor. Two details of how they behave.',
    shots: [
      {
        name: 'tab-drag',
        width: 1640,
        height: 520,
        alt: 'A row of three notebook tabs with one, Recipes 4, lifted and being dragged along the row.',
        caption: 'A tab picked up and carried along the row.',
      },
      {
        name: 'tab-menu',
        width: 1640,
        height: 520,
        alt: 'A tab’s menu: Open Beside, Move Left, Close Other Tabs and Close Tab.',
        caption: 'A tab’s menu. Open Beside puts two notebooks side by side.',
      },
    ],
    bands: [[[6, 'tab-drag'], [6, 'tab-menu']]],
  },
  {
    id: 'corners',
    title: 'Square corners',
    note: 'Up to here, bars, buttons and fields were capsules. Then they were redrawn as flat rectangles with small corners, and stayed that way.',
    shots: [
      {
        name: 'controls-sheet',
        width: 1800,
        height: 1713,
        alt: 'A sheet of redrawn controls: the page navigator’s bar, the library toolbar, the editor bar, a New Notebook sheet with fields, tabs, buttons and switches, and a floating find bar.',
        caption: 'Every kind of control on one sheet, each on the ground it sits on: desk, paper, surface, and over a page.',
      },
      {
        name: 'library-dark',
        width: 1379,
        height: 2000,
        alt: 'The library at night: the sidebar with its shelves, and a grid of notebook covers in cloth and print.',
        caption: 'The library, its bar still a capsule. It followed.',
      },
      {
        name: 'card-menu',
        width: 1500,
        height: 2000,
        alt: 'The editor at night with its More menu open as a flat card under a cobalt band, and a Draw With card beside it offering System Setting, Apple Pencil Only and Pencil and Finger.',
        caption: 'Menus became cards: a cloth band for the name, ruled rows, and a second card for Draw With.',
      },
    ],
    bands: [[[6, 'controls-sheet'], [3, 'library-dark'], [3, 'card-menu']]],
  },
  {
    id: 'launch',
    title: 'The first two seconds',
    note: 'Three goes at what the app shows while it starts, each storyboarded with a clock in the corner of every frame.',
    shots: [
      {
        name: 'splash-wordmark',
        width: 1600,
        height: 1200,
        alt: 'Nine storyboard frames timed from 0 to 2,200 milliseconds: a violet sheet rises over the library, the word OwlLuna comes up in yellow, and the sheet drops away.',
        caption: 'First go: a violet curtain and the name, over in 2.2 seconds.',
        verdict: 'dropped',
      },
      {
        name: 'splash-blocks',
        width: 1612,
        height: 908,
        alt: 'Twelve storyboard frames: plain coloured blocks fly in to fill the screen like a bento box, hold, then leave to show the library.',
        caption: 'Second go, in plain blocks: tiles land from the edges, hold, and peel away to the library.',
      },
      {
        name: 'splash-bento',
        width: 1468,
        height: 2000,
        alt: 'Two frames of the finished splash: tiles holding the owl writing on a pad, a ruled note page, a crescent moon, index cards under a STUDY stamp and the wordmark, whole and then as they begin to leave.',
        caption: 'The blocks filled in. This is what the app opens with.',
        verdict: 'kept',
      },
    ],
    bands: [[[7, 'splash-wordmark', 'splash-blocks'], [5, 'splash-bento']]],
  },
  {
    id: 'row',
    title: 'The row you are on',
    note: 'How the sidebar shows which shelf is open: four options, each by day and at night, and then the one that went in. Last in the pile, the app in German.',
    shots: [
      {
        name: 'row-wash',
        width: 748,
        height: 143,
        alt: 'Three sidebar rows by day and at night. The selected one, Favourites, has a pale fill.',
        caption: 'Option A for the selected row: a wash.',
        verdict: 'dropped',
      },
      {
        name: 'row-outline',
        width: 750,
        height: 153,
        alt: 'The same rows with the selected one outlined.',
        caption: 'Option B: an outline.',
        verdict: 'dropped',
      },
      {
        name: 'row-bar',
        width: 754,
        height: 138,
        alt: 'The same rows with a pale fill on the selected one and a blue bar down its leading edge.',
        caption: 'Option C: a wash with a bar down its leading edge.',
        verdict: 'dropped',
      },
      {
        name: 'row-cobalt',
        width: 754,
        height: 139,
        alt: 'The same rows with the selected one filled in cobalt.',
        caption: 'Option D: solid cobalt.',
        verdict: 'kept',
      },
      {
        name: 'row-debug',
        width: 660,
        height: 520,
        alt: 'A close view of the sidebar with a focus ring round the Favourites row and, under it, a test row reading p=std f=0 plain.',
        caption: 'A test row printing its own state, left in while the system’s focus ring was being dealt with.',
      },
      {
        name: 'sidebar-light',
        width: 660,
        height: 1100,
        alt: 'The sidebar by day with the Journal shelf selected on a woven cobalt plate.',
        caption: 'What went in: D, with the weave of the cloth covers.',
      },
      {
        name: 'sidebar-dark',
        width: 660,
        height: 1100,
        alt: 'The same sidebar at night.',
        caption: 'And at night.',
      },
      {
        name: 'library-german',
        width: 965,
        height: 1400,
        alt: 'The library in German, with a notice asking whether to keep a copy of the notebooks in iCloud and two buttons: Jetzt nicht and Mit iCloud synchronisieren.',
        caption: 'In German, one of the app’s four languages. iCloud sync asks before it copies anything.',
      },
    ],
    bands: [
      [[6, 'row-wash', 'row-outline', 'row-bar', 'row-cobalt'], [6, 'row-debug']],
      [[3, 'sidebar-light'], [3, 'sidebar-dark'], [5, 'library-german']],
    ],
  },
]

export type Placed = Shot & { number: number; entry: Entry }

/** Every screenshot in the order it is told, numbered from 1. */
export const sequence: Placed[] = entries.flatMap((entry) => entry.shots.map((shot) => ({ ...shot, entry }))).map((shot, index) => ({ ...shot, number: index + 1 }))

export type Size = 'full' | 'medium' | 'thumb'

const suffix: Record<Size, string> = { full: '', medium: '-m', thumb: '-t' }

export function source(shot: Shot, size: Size): string {
  return asset(`/prototypes/${shot.name}${suffix[size]}.webp`)
}
