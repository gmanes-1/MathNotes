'use client'

import { motion } from 'motion/react'
import { useRef, useSyncExternalStore } from 'react'
import { ease, rising } from '@/lib/motion'
import { words } from './covers'
import { useArrival } from '@/components/ui/useArrival'
import { useStill } from '@/components/ui/useStill'
import styles from './JournalPage.module.css'

const sample = '2026-10-11'
const subscribe = () => () => {}
const two = (value: number) => String(value).padStart(2, '0')

function today() {
  const now = new Date()
  return `${now.getFullYear()}-${two(now.getMonth() + 1)}-${two(now.getDate())}`
}

function masthead(key: string) {
  const [year, month, day] = key.split('-').map(Number)
  const date = new Date(Date.UTC(year, month - 1, day))
  const format = (options: Intl.DateTimeFormatOptions) => date.toLocaleDateString('en-GB', { ...options, timeZone: 'UTC' })
  return {
    weekday: format({ weekday: 'long' }),
    date: format({ day: 'numeric', month: 'long', year: 'numeric' }),
    count: `Day ${Math.round((date.getTime() - Date.UTC(year, 0, 0)) / 86_400_000)}`,
  }
}

const hump = 5.4
const pace = 0.024
const lines = [
  [5, 8, 4, 7],
  [7, 3, 9, 6],
  [4, 6, 8],
  [6, 5, 3, 8],
  [9, 4],
]

type Stroke = { d: string; duration: number; delay: number }

const strokes = lines
  .flatMap((line, row) => words(0, 12 + row * 26, line, hump).map((d, index) => ({ d, duration: line[index] * pace })))
  .reduce<Stroke[]>((written, stroke) => {
    const last = written[written.length - 1]
    return [...written, { ...stroke, delay: last ? last.delay + last.duration + 0.06 : 0.7 }]
  }, [])

/** Today's journal page: dotted ivory paper printed with the weekday, the date and the day of the year. */
export function JournalPage() {
  const page = useRef<HTMLDivElement>(null)
  const { arrived: play } = useArrival(page, { amount: 0.4 })
  const still = useStill()
  const key = useSyncExternalStore(subscribe, today, () => sample)
  const head = masthead(key)
  const at = (delay: number, transition: object = {}) => (play ? { ...transition, delay } : { duration: 0 })

  return (
    <div ref={page} className={styles.page} role="img" aria-label={`Today's page of a journal, printed ${head.weekday}, ${head.date}`}>
      <div className={`print ${styles.paper}`}>
        <div className={styles.masthead}>
          <div className={styles.first}>
            <motion.span className={styles.weekday} initial={false} animate={{ opacity: play ? 1 : 0 }} transition={at(0.1, { duration: 0.3 })}>
              {head.weekday}
            </motion.span>
            <motion.span className={styles.rule} style={{ originX: 0 }} initial={false} animate={{ scaleX: play ? 1 : 0 }} transition={at(0.2, { duration: 0.6, ease: ease.glide })} />
            <motion.span className={styles.count} initial={false} animate={{ opacity: play ? 1 : 0 }} transition={at(0.45, { duration: 0.3 })}>
              {head.count}
            </motion.span>
          </div>
          <span className={styles.riser}>
            <motion.span key={head.date} className={styles.date} initial={false} animate={{ y: play ? '0%' : '112%' }} transition={at(0.28, rising)}>
              {head.date}
            </motion.span>
          </span>
        </div>
        <svg className={styles.ink} viewBox="0 0 190 124" aria-hidden="true">
          {strokes.map((stroke) => (
            <motion.path
              key={stroke.d}
              d={stroke.d}
              initial={false}
              animate={play ? { pathLength: 1, opacity: 1 } : { pathLength: 0, opacity: 0 }}
              transition={
                play && !still
                  ? { duration: stroke.duration, ease: 'linear', delay: stroke.delay, opacity: { duration: 0.01, delay: stroke.delay } }
                  : { duration: 0 }
              }
            />
          ))}
        </svg>
      </div>
    </div>
  )
}
