'use client'

import { useRef, type CSSProperties } from 'react'
import { Drawn } from '@/components/sections/study/Ink'
import { write } from '@/components/ui/hand'
import { Reveal } from '@/components/ui/Reveal'
import { Tape } from '@/components/ui/Tape'
import { useArrival } from '@/components/ui/useArrival'
import { source, type Placed, type Verdict } from './shots'
import styles from './Print.module.css'

const turns = [-1.1, 0.7, -0.5, 1.2, 0.4, -0.9, 1, -0.3]
const tapes = ['mustard', 'sage', 'rose', 'sky'] as const
const words = { kept: write('Kept'), dropped: write('Dropped', 3) }
const said = { kept: 'Kept', dropped: 'Dropped' }

type Props = {
  shot: Placed
  onOpen: (number: number) => void
  /** Seconds after it comes into view. */
  delay?: number
}

/** A screenshot as a print taped to the board, with its number and caption under it. */
export function Print({ shot, onOpen, delay = 0 }: Props) {
  const shape = shot.width / shot.height
  const style = { '--turn': `${turns[shot.number % turns.length]}deg`, '--order': shot.number } as CSSProperties
  return (
    <figure className={[styles.print, shape >= 1.25 ? styles.wide : ''].join(' ')} style={style}>
      <Reveal delay={delay} tilt={shot.number % 2 ? 2 : -2}>
        <button type="button" className={`print ${styles.frame}`} onClick={() => onOpen(shot.number)}>
          {shape < 3.5 ? <Tape color={tapes[shot.number % tapes.length]} className={styles.tape} /> : null}
          <img
            className={styles.image}
            src={source(shot, 'medium')}
            width={shot.width}
            height={shot.height}
            alt={shot.alt}
            loading="lazy"
            decoding="async"
          />
          {shot.verdict ? <Tag verdict={shot.verdict} /> : null}
          <span className="visually-hidden">
            {shot.verdict ? ` ${said[shot.verdict]}.` : ''} Open it larger.
          </span>
        </button>
        <figcaption className={styles.caption}>
          <span className={`meta ${styles.number}`}>No. {String(shot.number).padStart(2, '0')}</span>
          {shot.caption}
        </figcaption>
      </Reveal>
    </figure>
  )
}

/** A paper label on a print's corner saying whether the idea stayed, written on as it comes into view. */
export function Tag({ verdict, className }: { verdict: Verdict; className?: string }) {
  const ref = useRef<HTMLSpanElement>(null)
  const { arrived } = useArrival(ref, { amount: 1 })
  return (
    <span ref={ref} className={[styles.tag, styles[verdict], className].filter(Boolean).join(' ')} aria-hidden="true">
      <Drawn line={words[verdict]} play={arrived} delay={0.25} />
    </span>
  )
}
