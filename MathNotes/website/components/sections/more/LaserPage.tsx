'use client'

import { useRef, type CSSProperties } from 'react'
import { useArrival } from '@/components/ui/useArrival'
import { write } from '@/components/ui/hand'
import styles from './art.module.css'

const heading = write('tides')
const tide = 'M38,154 C60,154 77,110 99,110 C121,110 138,154 160,154 C182,154 199,110 221,110 C243,110 260,154 282,154'
const lap = 'M258,118 C259,133 243,145 222,144 C202,143 185,133 186,118 C187,103 203,92 223,93 C243,94 257,104 258,118 Z'
const tail = [
  { length: 34, width: 2.2, opacity: 0.2 },
  { length: 25, width: 3, opacity: 0.26 },
  { length: 16, width: 3.8, opacity: 0.36 },
  { length: 8, width: 4.6, opacity: 0.6 },
]
const along = (length: number) => ({ '--len': length }) as CSSProperties

/** A page shown whole on a dark screen, with the laser pointer circling part of it. */
export function LaserPage() {
  const ref = useRef<SVGSVGElement>(null)
  const { arrived } = useArrival(ref, { amount: 0.6 })
  return (
    <svg
      ref={ref}
      className={styles.svg}
      data-waiting={arrived ? undefined : ''}
      viewBox="0 0 320 200"
      role="img"
      aria-label="A page shown whole on a dark screen. A red laser dot circles one crest of a tide chart, leaving a short fading tail."
    >
      <text className={`${styles.label} ${styles.labelPaper}`} x="20" y="28">
        Second screen
      </text>
      <rect className={styles.page} x="20" y="44" width="280" height="140" />
      <g transform="translate(38 58) scale(0.62)">
        {heading.letters.map((letter, index) => (
          <g key={index} transform={letter.transform}>
            <path className={styles.hand} d={letter.d} />
          </g>
        ))}
      </g>
      <path className={styles.pen} d="M38,86 q4,-7 8,0 t8,0 t8,0 t8,0 t8,0 m9,0 q4,-7 8,0 t8,0 t8,0" />
      <path className={styles.axis} d="M38,132 H282" />
      <path className={styles.curve} d={tide} />
      {tail.map((layer) => (
        <path
          key={layer.length}
          className={styles.laser}
          d={lap}
          pathLength={100}
          strokeWidth={layer.width}
          opacity={layer.opacity}
          style={along(layer.length)}
        />
      ))}
      <path className={styles.laser} d={lap} pathLength={100} strokeWidth="9" style={along(0)} />
      <path className={`${styles.laser} ${styles.laserCore}`} d={lap} pathLength={100} strokeWidth="3.4" style={along(0)} />
    </svg>
  )
}
