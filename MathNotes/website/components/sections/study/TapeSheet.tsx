'use client'

import { motion, useInView } from 'motion/react'
import { useEffect, useRef, useState } from 'react'
import { useStill } from '@/components/ui/useStill'
import { landing, quick } from '@/lib/motion'
import { Tape } from '../../ui/Tape'
import { Drawn, pen, useDrawn } from './Ink'
import { Sheet } from './Sheet'
import { capHeight, write } from '@/components/ui/hand'
import styles from './TapeSheet.module.css'

const heading = write('The Moon')
const underline = `M-1,4.2 Q${heading.width * 0.26},0.8 ${heading.width * 0.54},3.5 T${heading.width + 2},2.6`
const underlineSize = { width: `${(heading.width + 10) / capHeight}em`, height: `${7 / capHeight}em` }

const notes = [
  { prompt: write('Orbit =', 2), answer: write('27 days', 9), color: 'mustard' },
  { prompt: write('Pulls the', 5), answer: write('tides', 1), color: 'rose' },
  { prompt: write('We see', 8), answer: write('one side', 3), color: 'sage' },
  { prompt: write('Light =', 4), answer: write('sunlight', 10), color: 'sky' },
] as const

const phases = [0, 1, 2, 3, 4].map((index) => {
  const x = 11 + index * 30
  const top = `M${x},1 A10,10 0 0 0 ${x},21`
  const shadows = [`${top} A10,10 0 0 0 ${x},1 Z`, `${top} A4.4,10 0 0 0 ${x},1 Z`, `${top} Z`, `${top} A4.4,10 0 0 1 ${x},1 Z`, '']
  return { x, shadow: shadows[index] }
})

const beats = { heading: 0.1, rule: 0.46, doodle: 0.6, notes: 0.7, row: 0.3, phases: 1.95, tape: 2.25, lift: 3.5 }
const away = { opacity: 0, y: '-90%', rotate: -7, scale: 1.12 }
const down = { opacity: 1, y: '0%', rotate: 0, scale: 1 }
const up = { opacity: 0, y: '-72%', rotate: -5, scale: 1 }

/** A page of notes with four strips of study tape over the answers. */
export function TapeSheet() {
  const figure = useRef<HTMLElement>(null)
  const touched = useRef(false)
  const play = useInView(figure, { once: true, amount: 0.4 })
  const still = useStill()
  const drawn = useDrawn()
  const placed = play || still
  const [landed, setLanded] = useState(false)
  const [lifted, setLifted] = useState<boolean[]>(() => notes.map(() => false))
  const [said, setSaid] = useState('')

  useEffect(() => {
    if (!play) return
    const land = window.setTimeout(() => setLanded(true), (beats.tape + 0.9) * 1000)
    const show = window.setTimeout(() => {
      if (!touched.current) setLifted((current) => current.map((value, index) => (index === 1 ? true : value)))
    }, beats.lift * 1000)
    return () => {
      window.clearTimeout(land)
      window.clearTimeout(show)
    }
  }, [play])

  const toggle = (row: number) => {
    touched.current = true
    setLanded(true)
    setSaid(lifted[row] ? 'The tape is back in place.' : `Under the tape: ${notes[row].answer.text}.`)
    setLifted((current) => current.map((value, index) => (index === row ? !value : value)))
  }

  return (
    <figure ref={figure} className={styles.figure}>
      <Sheet lead="Astronomy" trail="P. 12">
        <div className={styles.title}>
          <span className={styles.heading}>
            <Drawn line={heading} play={play} delay={beats.heading} />
            <svg className={styles.underline} style={underlineSize} viewBox={`-4 0 ${heading.width + 10} 7`} overflow="visible" aria-hidden="true">
              <motion.path d={underline} {...pen} strokeWidth="2.5" {...drawn(play, beats.rule, 0.3)} />
            </svg>
          </span>
        </div>

        <svg className={styles.doodle} viewBox="0 0 70 50" overflow="visible" aria-hidden="true">
          <motion.path d="M30,5 Q8,8 9,27 Q10,45 31,46 Q17,38 17,25 Q17,12 30,5 Z" {...pen} strokeWidth="2.3" {...drawn(play, beats.doodle, 0.4)} />
          <motion.path className={styles.star} d="M57,6.2 L62.3,22.4 L48.5,12.4 L65.5,12.4 L51.7,22.4 Z" {...pen} strokeWidth="2.3" {...drawn(play, beats.doodle + 0.3, 0.34)} />
        </svg>

        {notes.map((note, row) => {
          const start = beats.notes + row * beats.row
          const isLifted = lifted[row]
          return (
            <div key={note.color} className={styles.row}>
              <Drawn line={note.prompt} play={play} delay={start} />
              <span className={styles.cover}>
                <Drawn line={note.answer} play={play} delay={start + note.prompt.letters.length * 0.04} />
                <button
                  type="button"
                  className={styles.strip}
                  aria-pressed={isLifted}
                  aria-label={`Lift the tape after “${note.prompt.text}”`}
                  onClick={() => toggle(row)}
                >
                  <span className={styles.band}>
                    <motion.span className={styles.layer} initial={false} animate={{ opacity: isLifted ? 1 : 0 }} transition={{ duration: 0.16 }}>
                      <Tape color={note.color} lifted className={styles.fill} />
                    </motion.span>
                    <motion.span
                      data-study-art
                      className={styles.layer}
                      initial={away}
                      animate={!placed ? away : isLifted ? up : down}
                      whileHover={isLifted ? undefined : { y: '-9%', rotate: -1.4 }}
                      transition={
                        landed || still
                          ? isLifted
                            ? { ...quick, opacity: { duration: 0.16 } }
                            : { type: 'spring', duration: 0.46, bounce: 0.46, opacity: { duration: 0.08 } }
                          : { ...landing, duration: 0.6, delay: beats.tape + row * 0.13, opacity: { duration: 0.1, delay: beats.tape + row * 0.13 } }
                      }
                    >
                      <Tape color={note.color} className={styles.fill} />
                    </motion.span>
                  </span>
                </button>
              </span>
            </div>
          )
        })}

        <div className={styles.row}>
          <svg className={styles.phases} viewBox="0 0 142 22" overflow="visible" aria-hidden="true">
            {phases.map((phase, index) => {
              const wait = beats.phases + index * 0.07
              return (
                <g key={phase.x}>
                  {phase.shadow ? (
                    <motion.path data-study-art d={phase.shadow} fill="currentColor" initial={{ opacity: 0 }} animate={{ opacity: placed ? 1 : 0 }} transition={still ? { duration: 0 } : { duration: 0.16, delay: wait + 0.2 }} />
                  ) : null}
                  <motion.circle cx={phase.x} cy="11" r="10" {...pen} strokeWidth="2.4" {...drawn(play, wait, 0.3)} />
                </g>
              )
            })}
          </svg>
        </div>
      </Sheet>
      <figcaption className={`meta ${styles.caption}`}>Tap a strip to lift it. Tap again to put it back.</figcaption>
      <p className="visually-hidden" role="status">
        {said}
      </p>
    </figure>
  )
}
