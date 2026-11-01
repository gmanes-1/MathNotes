'use client'

import { motion, useTransform, type MotionValue } from 'motion/react'
import type { CSSProperties, ReactNode } from 'react'
import { useStill } from '@/components/ui/useStill'
import { ease } from '@/lib/motion'
import { capHeight, type HandLetter, type Handwriting } from '@/components/ui/hand'

export const pen = { fill: 'none', stroke: 'currentColor', strokeLinecap: 'round', strokeLinejoin: 'round' } as const
const weight = 2.7
const step = 0.04
const dry = { pathLength: 0, opacity: 0 }
const inked = { pathLength: 1, opacity: 1 }

/** A pen stroke drawn once `play` is set. Under Reduce Motion the ink is simply there. */
export function useDrawn() {
  const still = useStill()
  return (play: boolean, wait: number, duration = 0.22) => ({
    'data-study-art': true,
    initial: still ? false : dry,
    animate: play || still ? inked : dry,
    transition: still ? { duration: 0 } : { duration, ease: ease.inOut, delay: wait, opacity: { duration: 0.01, delay: wait } },
  })
}

type FrameProps = { line: Handwriting; className?: string; children: ReactNode }

function Frame({ line, className, children }: FrameProps) {
  const size: CSSProperties = { width: `${(line.width + 10) / capHeight}em`, height: `${31 / capHeight}em` }
  return (
    <svg className={className} style={size} viewBox={`-4 -5 ${line.width + 10} 31`} overflow="visible" aria-hidden="true">
      {children}
    </svg>
  )
}

/** A line of handwriting as it lies on the paper, one cap-height to the em. */
export function Written({ line, className }: { line: Handwriting; className?: string }) {
  return (
    <Frame line={line} className={className}>
      {line.letters.map((letter, index) => (
        <g key={index} transform={letter.transform}>
          <path d={letter.d} {...pen} strokeWidth={weight} />
        </g>
      ))}
    </Frame>
  )
}

type DrawnProps = { line: Handwriting; play: boolean; delay?: number }

/** A line that writes itself, letter by letter, once `play` is set. */
export function Drawn({ line, play, delay = 0 }: DrawnProps) {
  const drawn = useDrawn()
  return (
    <Frame line={line}>
      {line.letters.map((letter, index) => (
        <g key={index} transform={letter.transform}>
          <motion.path d={letter.d} {...pen} strokeWidth={weight} {...drawn(play, delay + index * step)} />
        </g>
      ))}
    </Frame>
  )
}

type ReplayedProps = { line: Handwriting; clock: MotionValue<number>; at: number; step: number }

/** A line written during a recording: each letter is faint until the clock reaches the moment it was written. */
export function Replayed({ line, clock, at, step }: ReplayedProps) {
  return (
    <Frame line={line}>
      {line.letters.map((letter, index) => (
        <Stroke key={index} letter={letter} clock={clock} at={at + index * step} />
      ))}
    </Frame>
  )
}

/** The opacity of ink written at `at`: 16% while it is still to come, as in the app's replay. */
export function useInk(clock: MotionValue<number>, at: number) {
  return useTransform(clock, [at, at + 0.14], [0.16, 1])
}

function Stroke({ letter, clock, at }: { letter: HandLetter; clock: MotionValue<number>; at: number }) {
  const opacity = useInk(clock, at)
  return (
    <g transform={letter.transform}>
      <motion.path d={letter.d} {...pen} strokeWidth={weight} style={{ opacity }} />
    </g>
  )
}
