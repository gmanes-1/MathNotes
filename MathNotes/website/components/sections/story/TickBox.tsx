'use client'

import { motion, useReducedMotion } from 'motion/react'
import { useRef } from 'react'
import { ease } from '@/lib/motion'
import { useArrival } from '@/components/ui/useArrival'

const box = 'M4,13.5 L19.5,13 L20,29 L4.5,29.5 Z'
const tick = 'M6.5,20 L12,27 L24.5,7.5'
const pen = { fill: 'none', strokeLinecap: 'round', strokeLinejoin: 'round' } as const
const dry = { pathLength: 0, opacity: 0 }
const inked = { pathLength: 1, opacity: 1 }

type Props = { ticked?: boolean; delay?: number; className?: string }

/** The hand-drawn checkbox of the splash's note page. */
export function TickBox({ ticked = true, delay = 0, className }: Props) {
  const ref = useRef<SVGSVGElement>(null)
  const { arrived } = useArrival(ref, { amount: 1 })
  const still = useReducedMotion()
  const stroke = (duration: number, after: number) => {
    if (!arrived) return { duration: 0 }
    if (still) return { duration: 0, opacity: { duration: 0.3 } }
    return { duration, ease: ease.inOut, delay: delay + after, opacity: { duration: 0.01, delay: delay + after } }
  }

  return (
    <svg ref={ref} className={className} viewBox="1 5 26 27" aria-hidden="true">
      <motion.path
        d={box}
        {...pen}
        strokeWidth="2.4"
        style={{ stroke: 'var(--ink)' }}
        initial={false}
        animate={ticked || arrived ? inked : dry}
        transition={ticked ? { duration: 0 } : stroke(0.34, 0)}
      />
      {ticked ? (
        <motion.path
          d={tick}
          {...pen}
          strokeWidth="3.2"
          style={{ stroke: 'var(--tomato)' }}
          initial={false}
          animate={arrived ? inked : dry}
          transition={stroke(0.2, 0.1)}
        />
      ) : null}
    </svg>
  )
}
