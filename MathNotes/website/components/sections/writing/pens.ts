export type Kind = 'pen' | 'fineliner' | 'fountain' | 'pencil' | 'highlighter' | 'crayon' | 'watercolour'

export type Pen = {
  id: string
  kind: Kind
  kindName: string
  color: string
  colorName: string
  breadth: number
  widthName: 'Fine' | 'Medium' | 'Broad'
  opacity: number
}

/** One pen of each kind, in the inks of the app's own palette. */
export const starters: Pen[] = [
  { id: 'pen', kind: 'pen', kindName: 'Pen', color: '#1B2230', colorName: 'Black', breadth: 0.3, widthName: 'Medium', opacity: 1 },
  { id: 'fineliner', kind: 'fineliner', kindName: 'Fineliner', color: '#2747B8', colorName: 'Blue', breadth: 0.08, widthName: 'Fine', opacity: 1 },
  { id: 'fountain', kind: 'fountain', kindName: 'Fountain pen', color: '#C9452F', colorName: 'Red', breadth: 0.48, widthName: 'Medium', opacity: 1 },
  { id: 'pencil', kind: 'pencil', kindName: 'Pencil', color: '#6E737C', colorName: 'Grey', breadth: 0.2, widthName: 'Fine', opacity: 1 },
  { id: 'highlighter', kind: 'highlighter', kindName: 'Highlighter', color: '#FFD426', colorName: 'Yellow', breadth: 0.95, widthName: 'Broad', opacity: 1 },
  { id: 'crayon', kind: 'crayon', kindName: 'Crayon', color: '#2F8F4E', colorName: 'Green', breadth: 0.62, widthName: 'Broad', opacity: 1 },
  { id: 'watercolour', kind: 'watercolour', kindName: 'Watercolour', color: '#3D8FD9', colorName: 'Sky blue', breadth: 0.8, widthName: 'Broad', opacity: 0.6 },
]

/** The tray holds eight pens at most. */
export const shelfLimit = 8

/** A new pen is like the one in hand, in another colour. */
export function another(pen: Pen): Pen {
  return { ...pen, id: 'another', color: '#E07A1F', colorName: 'Orange' }
}

const channels = (hex: string) => [1, 3, 5].map((at) => parseInt(hex.slice(at, at + 2), 16))

/** The ink at its opacity, for a blot on paper. */
export function onPaper(pen: Pen): string {
  const [red, green, blue] = channels(pen.color)
  return `rgb(${red} ${green} ${blue} / ${pen.opacity})`
}

/** The pale colour a faint ink has on a white page, for a blot on a dark well. */
export function onWell(pen: Pen): string {
  const [red, green, blue] = channels(pen.color).map((channel) => Math.round(channel * pen.opacity + 255 * (1 - pen.opacity)))
  return `rgb(${red} ${green} ${blue})`
}

/** The page of the sample, in its own units. */
export const sheet = { top: 16, width: 560, height: 286, rules: [100, 204], margin: 60 } as const

/** What is written on the sample page, each a single stroke, in the order the hand makes them. */
export const sample = {
  word:
    'M96,152 C112,148 134,130 132,116 C131,106 120,106 117,118 C112,140 114,178 106,194 C102,203 88,204 88,195 C88,186 104,188 118,196 C130,203 146,204 156,192 C161,184 165,164 166,150 C164,170 160,200 174,201 C188,202 196,172 198,150 C196,172 194,200 206,201 C214,201 220,190 224,178 C227,168 229,158 230,150 C230,167 229,187 228,201 C229,182 236,152 250,150 C264,149 262,172 261,188 C260,198 266,203 274,199 C282,195 288,182 292,172 C298,160 306,151 314,152 C304,146 292,162 292,180 C292,194 300,202 308,201 C318,200 322,174 323,152 C322,172 320,200 332,201 C342,202 352,190 360,176',
  moon: 'M474,112 C442,106 414,130 418,162 C422,192 454,206 480,188 C458,190 440,174 440,152 C440,134 452,118 474,112',
  star: 'M506,96 C507,106 510,109 520,110 C510,111 507,114 506,124 C505,114 502,111 492,110 C502,109 505,106 506,96',
  underline: 'M98,244 C150,232 190,254 240,242 C290,230 330,250 384,236',
  lasso: 'M90,152 C82,104 168,84 240,90 C312,95 392,108 386,162 C381,208 302,224 226,220 C150,217 96,206 90,152',
} as const

/** When each stroke starts and how long it takes, in seconds. */
export const beats = {
  word: { at: 0.05, takes: 0.95 },
  moon: { at: 1.08, takes: 0.42 },
  star: { at: 1.56, takes: 0.2 },
  underline: { at: 1.84, takes: 0.34 },
} as const
