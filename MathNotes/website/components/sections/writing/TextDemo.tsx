'use client'

import { motion, useInView } from 'motion/react'
import { useRef, useState } from 'react'
import { ease, quick, rising } from '@/lib/motion'
import { InkStroke } from './Ink'
import { Glyph } from './marks'
import { sample, sheet } from './pens'
import { useStill } from '@/components/ui/useStill'
import styles from './Stage.module.css'

const view = { x: 40, y: 84, width: 356, height: 150 } as const
const [, baseline] = sheet.rules
const caught = { x: 77, y: 93, width: 298, height: 124 } as const
const slant = `translate(0 ${baseline}) skewX(-9) translate(0 ${-baseline})`
const ink = '#1B2230'
const press = { rest: { y: 0, scale: 1 }, lift: { y: -2, scale: 1 }, press: { y: 0, scale: 0.92 } }

/** Handwriting to text: a selected word gives way to type in its place, and Undo brings the handwriting back. */
export function TextDemo() {
  const stage = useRef<HTMLDivElement>(null)
  const inView = useInView(stage, { once: true, amount: 0.5 })
  const still = useStill()
  const [typed, setTyped] = useState(false)
  const shown = inView || still

  return (
    <div className={`print ${styles.stage} ${styles.tomato}`} ref={stage}>
      <noscript>
        <style>{`rect[data-caught]{opacity:1!important}rect[data-caught=line]{stroke-dasharray:none!important}`}</style>
      </noscript>
      <div className={styles.desk}>
        <div className={styles.sheet}>
          <svg
            className={styles.page}
            viewBox={`${view.x} ${view.y} ${view.width} ${view.height}`}
            role="img"
            aria-label={typed ? 'The word Luna in type, where the handwriting was' : 'The word Luna in handwriting, selected'}
          >
            <clipPath id="writing-over-the-line">
              <rect x={view.x} y={view.y} width={view.width} height={baseline + 1.5 - view.y} />
            </clipPath>
            <path d={sheet.rules.map((y) => `M0,${y} H${sheet.width}`).join(' ')} stroke="#D6CFBE" strokeWidth="1.6" />
            <path d={`M${sheet.margin},0 V${sheet.top + sheet.height}`} stroke="#C9452F" strokeWidth="1.6" opacity="0.8" />
            <motion.g initial={false} animate={{ opacity: typed ? 0 : 1 }} transition={{ duration: 0.16, ease: ease.standard }}>
              <g transform={slant}>
                <InkStroke d={sample.word} kind="pen" color={ink} at={0.1} takes={0.95} play={inView} still={still} />
              </g>
            </motion.g>
            <motion.rect
              {...caught}
              data-caught="line"
              rx="3"
              fill="none"
              stroke={ink}
              strokeWidth="2.4"
              initial={still ? false : { pathLength: 0, opacity: 0 }}
              animate={shown ? { pathLength: 1, opacity: 1 } : { pathLength: 0, opacity: 0 }}
              transition={still ? { duration: 0 } : { pathLength: { duration: 0.55, delay: 1.15, ease: ease.inOut }, opacity: { duration: 0.01, delay: 1.15 } }}
            />
            <motion.rect
              {...caught}
              data-caught="dashes"
              rx="3"
              fill="none"
              stroke="#E8B023"
              strokeWidth="2.4"
              strokeDasharray="7 7"
              initial={still ? false : { opacity: 0 }}
              animate={{ opacity: shown ? 1 : 0 }}
              transition={still ? { duration: 0 } : { duration: 0.14, delay: 1.66 }}
            />
            <g clipPath="url(#writing-over-the-line)">
              <motion.g
                initial={false}
                animate={typed ? { y: 0, opacity: 1 } : { y: 92, opacity: 0 }}
                transition={typed ? { y: rising, opacity: { duration: 0.01 } } : { duration: 0.14 }}
              >
                <text x="94" y={baseline - 1.5} className={styles.type} fill={ink}>
                  Luna
                </text>
              </motion.g>
            </g>
          </svg>
        </div>

        <div className={styles.tray} role="group" aria-label="Handwriting to text">
          <motion.button
            type="button"
            className={styles.action}
            aria-pressed={typed}
            onClick={() => setTyped((now) => !now)}
            initial={false}
            animate="rest"
            whileTap="press"
          >
            <motion.span className={styles.plate} variants={press} transition={quick}>
              <Glyph name="type" />
              Turn into Text
            </motion.span>
          </motion.button>
          <motion.button
            type="button"
            className={styles.action}
            aria-disabled={!typed}
            onClick={() => setTyped(false)}
            initial={false}
            animate="rest"
            whileTap={typed ? 'press' : undefined}
          >
            <motion.span className={styles.plate} variants={press} transition={quick}>
              <Glyph name="undo" />
              Undo
            </motion.span>
          </motion.button>
        </div>
      </div>
      <p className="visually-hidden" role="status">
        {typed ? 'Turned into text' : 'Handwriting'}
      </p>
    </div>
  )
}
