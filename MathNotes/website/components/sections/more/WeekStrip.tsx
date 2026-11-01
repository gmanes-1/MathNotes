'use client'

import { motion } from 'motion/react'
import { ease, landing } from '@/lib/motion'
import { useStill } from '@/components/ui/useStill'
import styles from './art.module.css'

const days = [
  { name: 'Monday', initial: 'M', lines: [4, 4, 2], tilt: -7 },
  { name: 'Tuesday', initial: 'T', lines: [4, 3], tilt: 5 },
  { name: 'Wednesday', initial: 'W', lines: [], tilt: -4 },
  { name: 'Thursday', initial: 'T', lines: [4, 4, 4, 2], tilt: 6 },
  { name: 'Friday', initial: 'F', lines: [3, 4], tilt: -5, today: true },
  { name: 'Saturday', initial: 'S', lines: [], tilt: 4 },
  { name: 'Sunday', initial: 'S', lines: [], tilt: -6 },
]

const sheet = { width: 36, height: 48, gap: 6, left: 16, top: 78 }
const foot = { originX: 0.5, originY: 1 }
const wave = (turns: number, y: number) => `M7.6,${y} q2.6,-5 5.2,0${' t5.2,0'.repeat(turns - 1)}`

/** The This-week strip: seven small sheets land in a row, and the days that were written fill with ink. */
export function WeekStrip() {
  const still = useStill()
  return (
    <motion.svg
      className={styles.svg}
      viewBox="0 0 320 200"
      role="img"
      aria-label="The This-week strip: seven small sheets, Monday to Sunday, with ink on Monday, Tuesday, Thursday and Friday."
      initial="away"
      whileInView="placed"
      viewport={{ once: true, amount: 0.4 }}
    >
      <text className={styles.label} x="20" y="28">
        This week
      </text>
      <path className={styles.ledge} d="M0,131.5 H320" />
      {days.map((day, index) => (
        <g key={day.name} transform={`translate(${sheet.left + index * (sheet.width + sheet.gap)} ${sheet.top})`}>
          <motion.g
            data-drawn
            style={foot}
            variants={{ away: { y: 30, rotate: day.tilt, opacity: 0 }, placed: { y: 0, rotate: 0, opacity: 1 } }}
            transition={{ ...landing, delay: 0.1 + index * 0.06, opacity: { duration: 0.12, delay: 0.1 + index * 0.06 } }}
          >
            <rect className={styles.sheet} width={sheet.width} height={sheet.height} rx="3" />
            {day.lines.map((turns, row) => {
              const delay = 0.75 + index * 0.09 + row * 0.07
              return (
                <motion.path
                  key={row}
                  data-drawn
                  className={styles.pen}
                  d={wave(turns, 14 + row * 9)}
                  variants={{ away: { pathLength: 0, opacity: 0 }, placed: { pathLength: 1, opacity: 1 } }}
                  transition={still ? { duration: 0 } : { duration: 0.28, ease: ease.inOut, delay, opacity: { duration: 0.01, delay } }}
                />
              )
            })}
          </motion.g>
          <text className={`${styles.day} ${day.today ? styles.today : ''}`} x={sheet.width / 2} y={sheet.height + 27} textAnchor="middle">
            {day.initial}
          </text>
          {day.today ? <rect className={styles.todayRule} x={sheet.width / 2 - 7} y={sheet.height + 32.5} width="14" height="2.5" /> : null}
        </g>
      ))}
    </motion.svg>
  )
}
