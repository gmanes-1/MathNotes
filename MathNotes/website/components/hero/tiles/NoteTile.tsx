'use client'

import { motion } from 'motion/react'
import { ease } from '@/lib/motion'
import { write } from '@/components/ui/hand'
import { inks, useScene } from '../scene'
import styles from '../BentoHero.module.css'

const words = ['Write', 'Sketch', 'Study'].map((word) => write(word))
const baseline = (row: number) => 31 + 36 * row
const wordStart = 35
const box = 'M4,13.5 L19.5,13 L20,29 L4.5,29.5 Z'
const tick = 'M6.5,20 L12,27 L24.5,7.5'
const shadows = [
  'M16,148.5 A13.5,13.5 0 0 0 16,175.5 A13.5,13.5 0 0 0 16,148.5 Z',
  'M58,148.5 A13.5,13.5 0 0 0 58,175.5 A6,13.5 0 0 0 58,148.5 Z',
  'M100,148.5 A13.5,13.5 0 0 0 100,175.5 Z',
  'M142,148.5 A13.5,13.5 0 0 0 142,175.5 A6,13.5 0 0 1 142,148.5 Z',
]
const pen = { fill: 'none', stroke: inks.ink, strokeLinecap: 'round', strokeLinejoin: 'round' } as const
const drawn = { duration: 0.3, ease: ease.inOut }

/** The note page: ruled paper filled in by hand with a checklist and moon phases. */
export function NoteTile() {
  const { beat, draw, still } = useScene()
  return (
    <div className={styles.note}>
      <motion.span className={styles.noteRules} {...beat({ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0% 0 0)' }, 640, { duration: still ? 0 : 0.75, ease: ease.glide })} />
      <motion.span className={styles.noteHeader} style={{ originX: 0 }} {...beat({ scaleX: 0 }, { scaleX: 1 }, 600, { duration: 0.52, ease: ease.glide })} />
      <motion.span className={styles.noteMargin} style={{ originY: 0 }} {...beat({ scaleY: 0 }, { scaleY: 1 }, 560, { duration: 0.52, ease: ease.glide })} />
      {[0, 1, 2].map((index) => (
        <motion.span
          key={index}
          className={`${styles.noteHole} ${styles[`noteHole${index}`]}`}
          {...beat({ scale: 0 }, { scale: 1 }, 620 + 70 * index, { duration: 0.42, ease: ease.bounce })}
        />
      ))}
      <motion.span className={`${styles.label} ${styles.noteLabelLead}`} {...beat({ opacity: 0, y: '90%' }, { opacity: 1, y: '0%' }, 680, { duration: 0.45, ease: ease.glide })}>
        Notes
      </motion.span>
      <motion.span className={`${styles.label} ${styles.noteLabelTrail}`} {...beat({ opacity: 0, y: '90%' }, { opacity: 1, y: '0%' }, 740, { duration: 0.45, ease: ease.glide })}>
        P. 12
      </motion.span>

      <svg className={styles.noteInk} viewBox="0 0 237.6 216" role="img" aria-label="A checklist: write, sketch, study">
        <motion.rect
          x={wordStart - 7.25}
          y={baseline(2) - 23}
          width={words[2].width + 14.5}
          height="27"
          rx="2"
          fill={inks.moon}
          style={{ transformBox: 'fill-box', originX: 0 }}
          {...beat({ scaleX: 0 }, { scaleX: 1 }, 1460, { duration: 0.24, ease: ease.glide })}
        />
        {shadows.map((d, index) => (
          <motion.path key={d} d={d} fill={inks.ink} {...beat({ opacity: 0 }, { opacity: 1 }, 1300 + 65 * index, { duration: 0.16 })} />
        ))}
        {[0, 1, 2].map((row) => (
          <g key={row} transform={`translate(0 ${36 * row})`}>
            <motion.path d={box} {...pen} strokeWidth="2.8" {...draw(760 + 70 * row, { duration: 0.26, ease: ease.glide })} />
          </g>
        ))}
        {words.map((word, row) => (
          <g key={row} transform={`translate(${wordStart} ${baseline(row) - 21})`}>
            {word.letters.map((letter, index) => (
              <g key={index} transform={letter.transform}>
                <motion.path d={letter.d} {...pen} strokeWidth="3.2" {...draw(840 + 180 * row + 42 * index, { duration: 0.22, ease: ease.inOut })} />
              </g>
            ))}
          </g>
        ))}
        {[0, 1].map((row) => (
          <g key={row} transform={`translate(0 ${36 * row})`}>
            <motion.path d={tick} {...pen} stroke={inks.tomato} strokeWidth="4" {...draw(1190 + 180 * row, { duration: 0.17, ease: ease.standard })} />
          </g>
        ))}
        <motion.path d="M200,21 L214.6,66 L176.3,38.2 L223.7,38.2 L185.4,66 Z" {...pen} stroke={inks.tomato} strokeWidth="3.6" {...draw(1330, { duration: 0.34, ease: ease.inOut })} />
        {[0, 1, 2, 3, 4].map((index) => (
          <motion.circle key={index} cx={16 + 42 * index} cy="162" r="13.5" {...pen} strokeWidth="2.8" {...draw(1120 + 65 * index, drawn)} />
        ))}
        <motion.path
          d="M4,207 q4.5,-9 9,0 t9,0 t9,0 t9,0 t9,0 m11,0 q4.5,-9 9,0 t9,0 t9,0 m11,0 q4.5,-9 9,0 t9,0 t9,0 t9,0"
          {...pen}
          strokeWidth="3.2"
          {...draw(1440, { duration: 0.24, ease: 'linear' })}
        />
      </svg>
    </div>
  )
}
