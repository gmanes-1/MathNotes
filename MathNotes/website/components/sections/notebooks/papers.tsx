import type { ReactNode } from 'react'
import styles from './PaperDrawer.module.css'

export type PaperColour = {
  id: string
  name: string
  fill: string
  ink: 'cool' | 'kraft' | 'sage' | 'blush' | 'charcoal' | 'chalk'
}

export const colours: PaperColour[] = [
  { id: 'white', name: 'White', fill: '#ffffff', ink: 'cool' },
  { id: 'ivory', name: 'Ivory', fill: '#fdf9ec', ink: 'cool' },
  { id: 'legal', name: 'Legal pad', fill: '#fff8c3', ink: 'cool' },
  { id: 'kraft', name: 'Kraft', fill: '#d9c4a0', ink: 'kraft' },
  { id: 'sage', name: 'Sage', fill: '#dde5d7', ink: 'sage' },
  { id: 'blush', name: 'Blush', fill: '#f6e4e0', ink: 'blush' },
  { id: 'grey', name: 'Gray', fill: '#ecedef', ink: 'cool' },
  { id: 'charcoal', name: 'Charcoal', fill: '#2a2b2f', ink: 'charcoal' },
  { id: 'chalkboard', name: 'Chalkboard', fill: '#2b3e36', ink: 'chalk' },
]

/** A miniature sheet is drawn 96 wide and 124 tall, the shape of US Letter. */
export const sheet = { width: 96, height: 124 } as const

const W: number = sheet.width
const H: number = sheet.height

const fix = (value: number) => Math.round(value * 100) / 100
const steps = (from: number, to: number, by: number) => {
  const values: number[] = []
  for (let value = from; value <= to + 0.001; value += by) values.push(fix(value))
  return values
}
const across = (ys: number[], from = 0, to = W) => ys.map((y) => `M${fix(from)},${fix(y)}H${fix(to)}`).join('')
const down = (xs: number[], from = 0, to = H) => xs.map((x) => `M${fix(x)},${fix(from)}V${fix(to)}`).join('')

const penmanship = steps(15, 103, 22)
const checklist = steps(22, 118, 10.5)

const engineeringX = steps(6, 90, 4)
const engineeringY = steps(13, 117, 4)
const major = (index: number, values: number[]) => index % 5 === 0 || index === values.length - 1

const lean = (W * Math.tan(Math.PI / 6)).toFixed(2)
const isometric = Array.from({ length: 26 }, (_, index) => ((index - 6) * 8) / Math.cos(Math.PI / 6))
  .map((c) => `M0,${c.toFixed(2)}l${W},${lean}M0,${c.toFixed(2)}l${W},-${lean}`)
  .join('')

const hours = steps(18, 118, 100 / 15)
const tasks = steps(23, 56, 6.5)

const days = Array.from({ length: 8 }, (_, index) => ({ x: 5 + (index % 2) * 44.5, y: 5 + Math.floor(index / 2) * 29.25 }))

const staves = steps(12, 96, 28).flatMap((top) => [0, 1, 2, 3, 4].map((line) => top + line * 4))

const frames = Array.from({ length: 6 }, (_, index) => ({ x: 10 + (index % 2) * 44, y: fix(10.4 + Math.floor(index / 2) * 36.4) }))

export type Template = { name: string; art: ReactNode }
export type Family = { name: string; templates: Template[] }

export const families: Family[] = [
  {
    name: 'Writing',
    templates: [
      { name: 'Blank', art: null },
      {
        name: 'Narrow ruled',
        art: (
          <>
            <path className={styles.rule} d={across(steps(19, 119, 6))} />
            <path className={styles.margin} d={down([13])} />
          </>
        ),
      },
      {
        name: 'Wide ruled',
        art: (
          <>
            <path className={styles.rule} d={across(steps(21, 119, 9))} />
            <path className={styles.margin} d={down([13])} />
          </>
        ),
      },
      {
        name: 'Penmanship',
        art: (
          <>
            <path className={styles.rule} d={across(penmanship)} />
            <path className={styles.ruleDash} d={across(penmanship.map((y) => y + 5))} />
            <path className={styles.ruleFirm} d={across(penmanship.map((y) => y + 10))} />
            <path className={styles.ruleFaint} d={across(penmanship.map((y) => y + 15))} />
            <path className={styles.margin} d={down([9])} />
          </>
        ),
      },
      {
        name: 'Checklist',
        art: (
          <>
            <path className={styles.rule} d={across(checklist)} />
            {checklist.map((y) => (
              <rect key={y} className={styles.firm} x="4" y={y - 7} width="5" height="5" />
            ))}
            <path className={styles.margin} d={down([13])} />
          </>
        ),
      },
    ],
  },
  {
    name: 'Grids',
    templates: [
      { name: 'Grid', art: <path className={styles.mesh} d={down(steps(8, 95, 8)) + across(steps(8, 123, 8))} /> },
      {
        name: 'Engineering',
        art: (
          <>
            <path
              className={styles.meshFaint}
              d={down(engineeringX.filter((_, index) => !major(index, engineeringX)), 13, 117) + across(engineeringY.filter((_, index) => !major(index, engineeringY)), 6, 90)}
            />
            <path
              className={styles.rule}
              d={down(engineeringX.filter((_, index) => major(index, engineeringX)), 13, 117) + across(engineeringY.filter((_, index) => major(index, engineeringY)), 6, 90)}
            />
            <path className={styles.marginFirm} d="M6,8.5H90" />
          </>
        ),
      },
      { name: 'Dotted', art: <path className={styles.dots} d={across(steps(8, 120, 8), 8, 88.1)} /> },
      { name: 'Isometric', art: <path className={`${styles.mesh} ${styles.slanted}`} d={down(steps(8, 88, 8)) + isometric} /> },
    ],
  },
  {
    name: 'Planning',
    templates: [
      {
        name: 'Cornell',
        art: (
          <>
            <path className={styles.rule} d={across(steps(19.5, 95, 6.5), 29, W)} />
            <path className={styles.marginFirm} d={`M0,13H${W}M29,13V99M0,99H${W}`} />
          </>
        ),
      },
      {
        name: 'Day planner',
        art: (
          <>
            <path className={styles.rule} d={across(hours, 14, 63) + down([67], 13, 118) + across(tasks, 71, 92) + across(steps(66.5, 118.5, 6.5), 71, 92)} />
            <path className={styles.firm} d={hours.slice(0, -1).map((y) => `M5,${(y + 3.4).toFixed(2)}H10`).join('')} />
            {tasks.map((y) => (
              <rect key={y} className={styles.firm} x="71" y={y - 4.4} width="3.2" height="3.2" />
            ))}
            <path className={styles.marginFirm} d={`M0,13H${W}`} />
          </>
        ),
      },
      {
        name: 'Week planner',
        art: (
          <>
            <path className={styles.wash} d={days.map((day) => `M${day.x},${day.y}h41.5v5h-41.5z`).join('')} />
            <path className={styles.ruleFaint} d={days.map((day) => across(steps(day.y + 10, day.y + 24, 5), day.x + 2, day.x + 39.5)).join('')} />
            <path className={styles.rule} d={days.map((day) => `M${day.x},${day.y}h41.5v26.25h-41.5zM${day.x},${fix(day.y + 5)}h41.5`).join('')} />
          </>
        ),
      },
    ],
  },
  {
    name: 'Creative',
    templates: [
      { name: 'Music staff', art: <path className={styles.firm} d={across(staves, 8, 88)} /> },
      {
        name: 'Storyboard',
        art: (
          <>
            <path className={styles.rule} d={frames.map((frame) => across([frame.y + 25.9, frame.y + 30.4], frame.x, frame.x + 38)).join('')} />
            <path className={styles.firm} d={frames.map((frame) => `M${frame.x},${frame.y}h38v21.4h-38z`).join('')} />
          </>
        ),
      },
    ],
  },
]
