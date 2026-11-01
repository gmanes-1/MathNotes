'use client'

import { motion } from 'motion/react'
import { ease, lively, rising } from '@/lib/motion'
import { about, inks, usePause, useScene } from '../scene'
import styles from '../BentoHero.module.css'

/** Coming to rest when a loop stops. */
const rest = { duration: 0.4, ease: ease.inOut }

const stars = [
  { x: 186, y: 36, d: 'M0,-14 Q2,-2 14,0 Q2,2 0,14 Q-2,2 -14,0 Q-2,-2 0,-14 Z' },
  { x: 44, y: 30, d: 'M0,-9 Q1.4,-1.4 9,0 Q1.4,1.4 0,9 Q-1.4,1.4 -9,0 Q-1.4,-1.4 0,-9 Z' },
  { x: 206, y: 86, d: 'M0,-7 Q1.2,-1.2 7,0 Q1.2,1.2 0,7 Q-1.2,1.2 -7,0 Q-1.2,-1.2 0,-7 Z' },
  { x: 60, y: 88, d: 'M0,-6 Q1,-1 6,0 Q1,1 0,6 Q-1,1 -6,0 Q-1,-1 0,-6 Z' },
]

/** The moon tile: a crescent rises on a spring and rocks, while four stars pop in and twinkle. */
export function MoonTile() {
  const { loop, at, beat } = useScene()
  return (
    <svg className={styles.art} viewBox="0 0 240 112" role="img" aria-label="A crescent moon among stars">
      <motion.g {...beat({ y: 135, opacity: 0 }, { y: 0, opacity: 1 }, 620, { ...lively, opacity: { duration: 0.12, delay: at(620) } })}>
        <motion.g
          style={about(112.1, 57.7)}
          initial={{ rotate: -9 }}
          animate={loop ? { rotate: 9 } : { rotate: -9 }}
          transition={loop ? { duration: 1.5, ease: ease.inOut, repeat: Infinity, repeatType: 'reverse' } : rest}
        >
          <circle cx="112" cy="58" r="36" fill={inks.moon} />
          <circle cx="128" cy="45" r="30" fill={inks.ink} />
        </motion.g>
      </motion.g>
      {stars.map((star, index) => (
        <g key={star.d} transform={`translate(${star.x} ${star.y})`}>
          <motion.g style={about(0, 0)} {...beat({ scale: 0, rotate: -90 }, { scale: 1, rotate: 0 }, 1000 + index * 110, { duration: 0.52, ease: ease.bounce })}>
            <motion.path
              d={star.d}
              fill={inks.moonLight}
              style={about(0, 0)}
              animate={loop ? { scale: [1, 0.62] } : { scale: 1 }}
              transition={loop ? { duration: 0.7, ease: ease.inOut, repeat: Infinity, repeatType: 'reverse', delay: at(1600) + index * 0.23 } : rest}
            />
          </motion.g>
        </g>
      ))}
    </svg>
  )
}

const tilts = [-8, 7, -1]
const hinge = about(120, 186.4)
const stamp = about(150, 116)

/** The flashcard tile: three index cards fan up from below, then the stamp lands on them and wobbles. */
export function CardsTile() {
  const { loop, at, beat } = useScene()
  return (
    <svg className={styles.art} viewBox="0 0 240 176" role="img" aria-label="Three index cards under a stamp that says Study">
      {tilts.map((tilt, index) => (
        <motion.g
          key={tilt}
          style={hinge}
          {...beat({ y: 162, rotate: 0, opacity: 0 }, { y: 0, rotate: tilt, opacity: 1 }, 800 + index * 80, { ...lively, opacity: { duration: 0.1, delay: at(800 + index * 80) } })}
        >
          <rect x="46" y="36" width="148" height="94" rx="4" fill={inks.white} stroke={inks.ink} strokeWidth="3.6" />
          {index === tilts.length - 1 ? (
            <>
              <path d="M46,58 H194" stroke={inks.tomato} strokeWidth="3" />
              <path d="M58,74 H182 M58,89 H182 M58,104 H128" stroke={inks.rule} strokeWidth="2.4" strokeLinecap="round" />
            </>
          ) : null}
        </motion.g>
      ))}
      <motion.g style={stamp} {...beat({ scale: 2, opacity: 0 }, { scale: [2, 0.92, 1], opacity: [0, 1, 1] }, 1340, { duration: 0.3, times: [0, 0.55, 1], ease: ['easeIn', 'easeOut'] })}>
        <motion.g
          style={stamp}
          initial={{ rotate: -11.5 }}
          animate={loop ? { rotate: -6.5 } : { rotate: -11.5 }}
          transition={loop ? { duration: 0.95, ease: ease.inOut, repeat: Infinity, repeatType: 'reverse' } : rest}
        >
          <rect x="94" y="95" width="112" height="42" rx="3" fill={inks.white} stroke={inks.tomato} strokeWidth="4" />
          <text x="150" y="127.6" textAnchor="middle" textLength="84" lengthAdjust="spacingAndGlyphs" className={styles.stampWord} fill={inks.tomato}>
            STUDY
          </text>
        </motion.g>
      </motion.g>
    </svg>
  )
}

/** The volume label: VOL. fades up in one corner and the digits rise in the opposite one. */
export function VolumeTile() {
  const { beat } = useScene()
  return (
    <div className={styles.volume}>
      <motion.span aria-hidden="true" className={`${styles.label} ${styles.volumeLabel}`} {...beat({ opacity: 0, y: '90%' }, { opacity: 1, y: '0%' }, 800, { duration: 0.45, ease: ease.glide })}>
        Vol.
      </motion.span>
      <span className={styles.volumeDigits} aria-hidden="true">
        {['0', '1'].map((digit, index) => (
          <span key={digit} className={styles.riser}>
            <motion.span {...beat({ y: '112%' }, { y: '0%' }, 840 + index * 80, rising)}>{digit}</motion.span>
          </span>
        ))}
      </span>
      <span className="visually-hidden">Volume 1</span>
    </div>
  )
}

const verbs = ['Write', 'Sketch', 'Study']

/** The ticker: the three things the app is for, running leftwards. */
export function TickerTile() {
  const { paused, toggle } = usePause()
  return (
    <div className={styles.ticker}>
      <span className="visually-hidden">Write, sketch, study.</span>
      <button type="button" className={styles.pause} aria-pressed={paused} onClick={toggle}>
        <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
          {paused ? <path d="M4.5 2.5v11l9-5.5z" /> : <path d="M3.5 2.5h3v11h-3z M9.5 2.5h3v11h-3z" />}
        </svg>
        <span className="visually-hidden">Pause the animations</span>
      </button>
      <div className={styles.tickerBand} aria-hidden="true">
        {[0, 1, 2, 3].map((turn) => (
          <span key={turn} className={styles.tickerTurn}>
            {verbs.map((verb) => (
              <span key={verb} className={styles.tickerWord}>
                {verb}
                <i className={styles.diamond} />
              </span>
            ))}
          </span>
        ))}
      </div>
    </div>
  )
}

const wordmark = [...'OWLLUNA']

/** The wordmark slab: OWLLUNA rises letter by letter over a rule that grows from the left. */
export function WordTile() {
  const { beat } = useScene()
  return (
    <div className={styles.word}>
      <div className={styles.wordColumn}>
        <span className={styles.wordLine} aria-hidden="true">
          {wordmark.map((letter, index) => (
            <span key={index} className={styles.riser}>
              <motion.span style={{ color: index < 3 ? inks.paper : inks.moon }} {...beat({ y: '112%' }, { y: '0%' }, 590 + index * 55, rising)}>
                {letter}
              </motion.span>
            </span>
          ))}
        </span>
        <motion.span className={styles.wordRule} style={{ originX: 0 }} {...beat({ scaleX: 0 }, { scaleX: 1 }, 470, { duration: 0.7, ease: ease.glide })} />
      </div>
      <span className="visually-hidden">OwlLuna</span>
    </div>
  )
}
