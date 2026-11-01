import type { Kind } from './pens'

const line = { fill: 'none', stroke: 'currentColor', strokeLinecap: 'round', strokeLinejoin: 'round' } as const

const kinds: Record<Kind, string> = {
  pen: 'M3.2 1.6 H8.8 L7.9 6.2 L6 10.4 L4.1 6.2 Z M6 6.6 V10.4',
  fineliner: 'M8.4 1.4 L10.6 3.6 L5.2 9 L2.6 9.4 L3 6.8 Z M2 11.2 H10',
  fountain: 'M6 1.2 L9.4 5.8 L6 10.8 L2.6 5.8 Z M6 6.4 V10.8 M6 4.4 V4.6',
  pencil: 'M8.2 1.6 L10.4 3.8 L4.4 9.8 L1.6 10.4 L2.2 7.6 Z M6.9 2.9 L9.1 5.1',
  highlighter: 'M3.4 1.5 H8.6 V5.8 L7.4 7.8 H4.6 L3.4 5.8 Z M4.8 7.8 V10.5 L7.2 9.5 V7.8',
  crayon: 'M1.5 8.6 C2.9 3.8 4.4 2.6 5 5 C5.5 7.3 4 10 5.7 9.2 C7.4 8.4 7.7 4.1 8.7 5.2 C9.6 6.3 8.9 8.8 10.5 8',
  watercolour: 'M10.5 1.5 L6.4 5.6 M6.7 5.3 C7.7 6.2 7.7 7.2 6.9 8.2 C5.9 9.4 4.1 9.8 2.1 9.8 C3 8.9 2.7 7.8 3.5 6.6 C4.3 5.5 5.7 4.5 6.7 5.3 Z',
}

/** The mark of a pen's kind, for the corner of its label. */
export function KindMark({ kind, className }: { kind: Kind; className?: string }) {
  return (
    <svg className={className} viewBox="0 0 12 12" aria-hidden="true">
      <path d={kinds[kind]} {...line} strokeWidth="1.25" />
    </svg>
  )
}

const glyphs = {
  eraser: 'M11.6 3.4 L16.6 8.4 L9.2 15.8 H5.8 L3.4 13.4 Z M7.5 7.5 L12.5 12.5 M9 15.8 H17',
  lasso:
    'M10 3.6 C13.9 3.6 17 5.4 17 7.8 C17 10.2 13.9 12 10 12 C6.1 12 3 10.2 3 7.8 C3 5.4 6.1 3.6 10 3.6 Z M7.2 11.7 C5.7 12.7 5.9 14.6 7.4 14.6 C8.7 14.6 8.9 13 7.7 12.7 M7.5 14.6 C7.8 15.9 7.3 16.9 6.2 17.6',
  undo: 'M7.5 4.5 L3.5 8.5 L7.5 12.5 M3.5 8.5 H11.7 A4 4 0 0 1 11.7 16.5 H9.5',
  check: 'M4 10.5 L8.2 14.5 L16 5.5',
  plus: 'M10 4.5 V15.5 M4.5 10 H15.5',
  type: 'M4.5 7 V5 H15.5 V7 M10 5 V15.5 M7.6 15.5 H12.4',
  line: 'M4 16 L16 4',
  circle: 'M10 3.5 A6.5 6.5 0 1 0 10 16.5 A6.5 6.5 0 0 0 10 3.5 Z',
  rectangle: 'M3.5 5 H16.5 V15 H3.5 Z',
  triangle: 'M10 3.8 L16.8 15.5 H3.2 Z',
} as const

export type GlyphName = keyof typeof glyphs

/** A line drawing for a control of the tray or the bar. */
export function Glyph({ name, className, weight = 1.7 }: { name: GlyphName; className?: string; weight?: number }) {
  return (
    <svg className={className} viewBox="0 0 20 20" width="20" height="20" aria-hidden="true">
      <path d={glyphs[name]} {...line} strokeWidth={weight} />
    </svg>
  )
}
