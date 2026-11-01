'use client'

import { motion } from 'motion/react'
import { useEffect, useRef, type KeyboardEvent, type MouseEvent } from 'react'
import { settle } from '@/lib/motion'
import { Button } from '@/components/ui/Button'
import { sequence, source } from './shots'
import styles from './Viewer.module.css'

type Props = {
  /** The number of the screenshot on show, or null while the viewer is shut. */
  open: number | null
  onChange: (number: number | null) => void
}

const verdicts = { kept: 'Kept.', dropped: 'Dropped.' }

/** One screenshot at full size over the page, with its caption and the way to the next. */
export function Viewer({ open, onChange }: Props) {
  const dialog = useRef<HTMLDialogElement>(null)
  const last = useRef(open ?? 1)
  const shot = open === null ? null : sequence[open - 1]
  const direction = open !== null && open < last.current ? -1 : 1
  const shut = open === null

  useEffect(() => {
    if (open !== null) last.current = open
  }, [open])

  useEffect(() => {
    const element = dialog.current
    if (!element) return
    if (open !== null && !element.open) element.showModal()
    if (open === null && element.open) element.close()
  }, [open])

  useEffect(() => {
    if (shut) return
    const root = document.documentElement
    const before = root.style.overflow
    root.style.overflow = 'hidden'
    return () => {
      root.style.overflow = before
    }
  }, [shut])

  const step = (by: number) => {
    if (open === null) return
    onChange(((open - 1 + by + sequence.length) % sequence.length) + 1)
  }

  const onKey = (event: KeyboardEvent) => {
    if (event.key === 'ArrowRight') step(1)
    if (event.key === 'ArrowLeft') step(-1)
  }

  const onBackdrop = (event: MouseEvent) => {
    if (event.target === event.currentTarget) onChange(null)
  }

  return (
    <dialog
      ref={dialog}
      className={styles.viewer}
      aria-label={shot ? `Screenshot ${shot.number} of ${sequence.length}` : 'Screenshot'}
      onClose={() => onChange(null)}
      onKeyDown={onKey}
      onClick={onBackdrop}
    >
      {shot ? (
        <div className={styles.sheet}>
          <header className={styles.bar}>
            <p className={`meta ${styles.where}`}>
              <span className={styles.count}>
                No. {String(shot.number).padStart(2, '0')} of {sequence.length}
              </span>
              <span>{shot.entry.title}</span>
            </p>
            <Button size="compact" onClick={() => onChange(null)}>
              Close
            </Button>
          </header>

          <div className={styles.stage} onClick={onBackdrop}>
            <motion.img
              key={shot.name}
              className={[styles.image, shot.height / shot.width > 1.7 ? styles.tall : ''].join(' ')}
              src={source(shot, 'full')}
              width={shot.width}
              height={shot.height}
              alt={shot.alt}
              style={{ backgroundImage: `url(${source(shot, 'medium')})` }}
              initial={{ opacity: 0, x: 20 * direction }}
              animate={{ opacity: 1, x: 0 }}
              transition={settle}
            />
          </div>

          <footer className={styles.foot}>
            <p className={styles.caption} aria-live="polite">
              {shot.caption}
              {shot.verdict ? <strong className={styles[shot.verdict]}> {verdicts[shot.verdict]}</strong> : null}
            </p>
            <div className={styles.steps}>
              <Button size="compact" onClick={() => step(-1)} aria-label="The one before">
                <Arrow back />
              </Button>
              <Button size="compact" onClick={() => step(1)} aria-label="The next one">
                <Arrow />
              </Button>
            </div>
          </footer>
        </div>
      ) : null}
    </dialog>
  )
}

function Arrow({ back = false }: { back?: boolean }) {
  return (
    <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" style={back ? { transform: 'scaleX(-1)' } : undefined}>
      <path d="M2.5 8h10.5M9 4l4 4-4 4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
