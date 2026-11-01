'use client'

import { motion } from 'motion/react'
import { ease, landing, lively } from '@/lib/motion'
import { useStill } from '@/components/ui/useStill'
import styles from './art.module.css'

const grip = { originX: 0, originY: 1 }
const lands = (tilt: number) => ({ away: { y: 26, rotate: tilt, opacity: 0 }, placed: { y: 0, rotate: 0, opacity: 1 } })
const after = (delay: number) => ({ ...landing, delay, opacity: { duration: 0.12, delay } })

/** Two Home Screen widgets as plates: Today's Page, a tear-off calendar leaf, and Quick Note. */
export function WidgetPlates() {
  const still = useStill()
  return (
    <motion.svg
      className={styles.svg}
      viewBox="0 0 320 200"
      role="img"
      aria-label="Two Home Screen widgets. Today’s Page is a calendar leaf for Thursday 12 March, marked as written. Quick Note is a pencil on a square over its name."
      initial="away"
      whileInView="placed"
      viewport={{ once: true, amount: 0.4 }}
    >
      <text className={`${styles.label} ${styles.labelOnTomato}`} x="20" y="28">
        Home Screen
      </text>

      <motion.g data-drawn variants={lands(-5)} transition={after(0.1)}>
        <rect className={styles.widget} x="40" y="50" width="112" height="112" rx="4" />
        <path className={styles.leafHead} d="M40,72 V54 a4,4 0 0 1 4,-4 H148 a4,4 0 0 1 4,4 V72 Z" />
        <text className={styles.leafWeekday} x="96" y="64.5" textAnchor="middle">
          Thursday
        </text>
        <text className={styles.leafDay} x="96" y="118" textAnchor="middle">
          12
        </text>
        <text className={styles.leafMonth} x="96" y="134" textAnchor="middle">
          March
        </text>
        <motion.path
          data-drawn
          className={styles.tick}
          d="M70,147.5 l4,4.5 l8,-10"
          variants={{ away: { pathLength: 0, opacity: 0 }, placed: { pathLength: 1, opacity: 1 } }}
          transition={still ? { duration: 0 } : { duration: 0.22, ease: ease.standard, delay: 0.9, opacity: { duration: 0.01, delay: 0.9 } }}
        />
        <text className={styles.leafDone} x="88" y="152">
          Written
        </text>
      </motion.g>

      <motion.g data-drawn variants={lands(5)} transition={after(0.18)}>
        <rect className={styles.widget} x="168" y="50" width="112" height="112" rx="4" />
        <path className={styles.glyph} d="M226,78 H212 a5,5 0 0 0 -5,5 V112 a5,5 0 0 0 5,5 H241 a5,5 0 0 0 5,-5 V98" />
        <motion.path
          data-drawn
          className={`${styles.glyph} ${styles.glyphPencil}`}
          d="M222,102 l3,-9.5 l20,-20 l6.5,6.5 l-20,20 Z"
          style={grip}
          variants={{ away: { rotate: -24 }, placed: { rotate: 0 } }}
          transition={{ ...lively, delay: 0.75 }}
        />
        <text className={styles.widgetName} x="224" y="143" textAnchor="middle">
          Quick Note
        </text>
      </motion.g>
    </motion.svg>
  )
}
