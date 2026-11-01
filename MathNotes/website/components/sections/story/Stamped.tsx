'use client'

import { motion } from 'motion/react'
import { useRef, type ReactNode } from 'react'
import { useArrival } from '@/components/ui/useArrival'
import styles from '../Story.module.css'

const slam = 0.45

/** Brings a rubber stamp down on the foot of whatever it holds, hard enough to jolt it. */
export function Stamped({ word, children }: { word: string; children: ReactNode }) {
  const ref = useRef<HTMLSpanElement>(null)
  const { arrived, waited } = useArrival(ref, { amount: 1 })
  const landing = waited && arrived

  return (
    <div className={styles.stamped}>
      <motion.div
        initial={false}
        animate={landing ? { y: [0, 4, 0] } : { y: 0 }}
        transition={landing ? { duration: 0.24, delay: slam + 0.15, ease: 'easeOut' } : { duration: 0 }}
      >
        {children}
      </motion.div>
      <span ref={ref} className={styles.stampSpot} aria-hidden="true">
        <motion.span
          className={styles.stamp}
          style={{ rotate: -9 }}
          initial={false}
          animate={landing ? { scale: [2, 0.92, 1], opacity: [0, 1, 1] } : arrived ? { scale: 1, opacity: 1 } : { scale: 2, opacity: 0 }}
          transition={landing ? { duration: 0.3, times: [0, 0.55, 1], ease: ['easeIn', 'easeOut'], delay: slam } : { duration: 0 }}
        >
          {word}
        </motion.span>
      </span>
    </div>
  )
}
