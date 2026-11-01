'use client'

import { motion } from 'motion/react'
import { useRef, type ReactNode } from 'react'
import { settle } from '@/lib/motion'
import { useArrival } from './useArrival'

type Props = {
  children: ReactNode
  /** Seconds after it comes into view. */
  delay?: number
  /** How far below its place it starts, in pixels. */
  rise?: number
  /** Degrees it starts turned by, like a tile of the splash. */
  tilt?: number
  className?: string
}

/** Brings content up as it scrolls into view. It is only ever hidden below the window. */
export function Reveal({ children, delay = 0, rise = 28, tilt = 0, className }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const { arrived } = useArrival(ref, { margin: '0px 0px -10% 0px' })
  return (
    <motion.div
      ref={ref}
      className={className}
      initial={false}
      animate={arrived ? { opacity: 1, y: 0, rotate: 0 } : { opacity: 0, y: rise, rotate: tilt }}
      transition={arrived ? { ...settle, delay } : { duration: 0 }}
    >
      {children}
    </motion.div>
  )
}
