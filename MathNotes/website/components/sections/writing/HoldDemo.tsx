'use client'

import { animate, motion, useInView, useMotionValue, useTransform, type AnimationPlaybackControls } from 'motion/react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { ease, quick } from '@/lib/motion'
import { Glyph } from './marks'
import { useStill } from '@/components/ui/useStill'
import styles from './Stage.module.css'

type Shape = 'line' | 'circle' | 'rectangle' | 'triangle'
type Phase = 'waiting' | 'drawing' | 'resting' | 'held' | 'undone'

const board = { width: 480, height: 270 } as const
const figure = /-?\d+(?:\.\d+)?/g

function paired(name: string, drawn: string, straight: string) {
  const from = (drawn.match(figure) ?? []).map(Number)
  const to = (straight.match(figure) ?? []).map(Number)
  const between = (amount: number) => {
    let index = 0
    return drawn.replace(figure, () => {
      const at = index++
      return (from[at] + (to[at] - from[at]) * amount).toFixed(1)
    })
  }
  return { name, drawn, between, start: { x: from[0], y: from[1] } }
}

const figures: Record<Shape, ReturnType<typeof paired>> = {
  line: paired(
    'Line',
    'M 94,212 C 148,172 196,170 242,138 C 284,108 338,106 388,58',
    'M 96,208 C 144,183.7 192,159.3 240,135 C 288,110.7 336,86.3 384,62',
  ),
  circle: paired(
    'Circle',
    'M 252,47 C 304,52 340,92 330,142 C 322,192 282,234 232,226 C 180,219 141,182 153,128 C 163,84 200,44 247,58',
    'M 240,43 C 290.8,43 332,84.2 332,135 C 332,185.8 290.8,227 240,227 C 189.2,227 148,185.8 148,135 C 148,84.2 189.2,43 240,43',
  ),
  rectangle: paired(
    'Rectangle',
    'M 126,58 C 196,47 284,61 362,50 C 353,104 366,160 356,223 C 282,213 198,229 118,216 C 127,162 113,108 128,45',
    'M 122,52 C 200.7,52 279.3,52 358,52 C 358,107.3 358,162.7 358,218 C 279.3,218 200.7,218 122,218 C 122,162.7 122,107.3 122,52',
  ),
  triangle: paired(
    'Triangle',
    'M 244,46 C 276,96 328,158 362,221 C 284,233 204,217 117,231 C 154,172 208,104 236,35',
    'M 240,40 C 279.3,102 318.7,164 358,226 C 279.3,226 200.7,226 122,226 C 161.3,164 200.7,102 240,40',
  ),
}

const order: Shape[] = ['line', 'circle', 'rectangle', 'triangle']

const says: Record<Phase, string> = {
  waiting: 'As drawn',
  drawing: 'Drawing',
  resting: 'Pen at rest',
  held: 'Straightened',
  undone: 'Your own stroke again',
}

const ink = '#1B2230'
const press = { rest: { y: 0, scale: 1 }, lift: { y: -2, scale: 1 }, press: { y: 0, scale: 0.92 } }

/** Draw and hold: a pen draws a rough figure and rests, the figure straightens, and Undo gives the rough one back. */
export function HoldDemo() {
  const stage = useRef<HTMLDivElement>(null)
  const measure = useRef<SVGPathElement>(null)
  const moving = useRef<AnimationPlaybackControls | null>(null)
  const resting = useRef(0)
  const touched = useRef(false)
  const inView = useInView(stage, { once: true, amount: 0.45 })
  const still = useStill()

  const [shape, setShape] = useState<Shape>('circle')
  const [phase, setPhase] = useState<Phase>('waiting')

  const chosen = figures[shape]
  const held = phase === 'held'
  const progress = useMotionValue(0)
  const trueness = useMotionValue(0)
  const d = useTransform(trueness, (amount) => chosen.between(amount))
  const inked = useTransform(progress, (value) => (value > 0.002 ? 1 : 0))

  const tip = (value: number) => {
    const path = measure.current
    if (!path || value <= 0) return chosen.start
    return path.getPointAtLength(path.getTotalLength() * Math.min(1, value))
  }
  const tipX = useTransform(progress, (value) => tip(value).x)
  const tipY = useTransform(progress, (value) => tip(value).y)

  const halt = useCallback(() => {
    moving.current?.stop()
    window.clearTimeout(resting.current)
  }, [])

  const straighten = useCallback(
    (truly: boolean) => {
      halt()
      setPhase(truly ? 'held' : 'undone')
      if (still) trueness.set(truly ? 1 : 0)
      else moving.current = animate(trueness, truly ? 1 : 0, truly ? { duration: 0.5, ease: ease.bounce } : { duration: 0.34, ease: ease.glide })
    },
    [halt, still, trueness],
  )

  const draw = useCallback(
    (next: Shape) => {
      halt()
      setShape(next)
      trueness.set(0)
      const rest = () => {
        setPhase('resting')
        resting.current = window.setTimeout(() => straighten(true), 640)
      }
      if (still) {
        progress.set(1)
        rest()
        return
      }
      progress.set(0)
      setPhase('drawing')
      moving.current = animate(progress, 1, { duration: 0.95, ease: ease.inOut, onComplete: rest })
    },
    [halt, progress, still, straighten, trueness],
  )

  useEffect(() => {
    if (inView) draw('circle')
  }, [inView, draw])

  useEffect(() => halt, [halt])

  const penDown = phase === 'drawing' || phase === 'resting'
  const lifted = phase === 'waiting' ? { opacity: 0, x: 0, y: 0 } : { opacity: 0, x: 22, y: 14 }

  return (
    <div className={`print ${styles.stage} ${styles.moon}`} ref={stage}>
      <noscript>
        <style>{`g[data-ink] path{stroke-dasharray:none!important;opacity:1!important}`}</style>
      </noscript>
      <div className={styles.desk}>
        <div className={styles.sheet}>
          <svg
            className={styles.page}
            viewBox={`0 0 ${board.width} ${board.height}`}
            role="img"
            aria-label={`A dotted page with a ${chosen.name.toLowerCase()} drawn by hand${held ? ' and straightened' : ''}`}
          >
            <defs>
              <pattern id="writing-dots" width="20" height="20" y="5" patternUnits="userSpaceOnUse">
                <circle cx="10" cy="10" r="1.3" fill="#CFC7B4" />
              </pattern>
            </defs>
            <rect width={board.width} height={board.height} fill="url(#writing-dots)" />
            <path ref={measure} d={chosen.drawn} fill="none" stroke="none" />
            <g data-ink>
              <motion.path
                d={d}
                fill="none"
                stroke={ink}
                strokeWidth="4.2"
                strokeLinecap="round"
                strokeLinejoin="round"
                style={{ pathLength: progress, opacity: inked }}
              />
            </g>
            {still ? null : (
              <motion.g style={{ x: tipX, y: tipY }}>
                <motion.g
                  initial={false}
                  animate={penDown ? { opacity: 1, x: 0, y: 0 } : lifted}
                  transition={penDown ? { duration: 0.12 } : { duration: 0.3, ease: ease.glide }}
                >
                  {phase === 'resting' ? (
                    <motion.circle
                      r="12"
                      fill="none"
                      stroke="#C9452F"
                      strokeWidth="2.6"
                      strokeLinecap="round"
                      transform="rotate(-90)"
                      initial={{ pathLength: 0, opacity: 0 }}
                      animate={{ pathLength: 1, opacity: 1 }}
                      transition={{ pathLength: { duration: 0.56, ease: 'linear' }, opacity: { duration: 0.01 } }}
                    />
                  ) : null}
                  <g transform="rotate(128)">
                    <path d="M-7,-19 L-7,-104 Q-7,-111 0,-111 Q7,-111 7,-104 L7,-19 Z" fill="#FFFDF6" stroke={ink} strokeWidth="2.4" strokeLinejoin="round" />
                    <path d="M-7,-19 L0,-1 L7,-19 Z" fill="#FFFDF6" stroke={ink} strokeWidth="2.4" strokeLinejoin="round" />
                    <path d="M-2.6,-7.5 L0,-1 L2.6,-7.5 Z" fill={ink} stroke={ink} strokeWidth="1.6" strokeLinejoin="round" />
                    <path d="M-7,-90 H7" stroke={ink} strokeWidth="2.2" />
                  </g>
                </motion.g>
              </motion.g>
            )}
          </svg>
        </div>

        <div className={styles.tray} role="group" aria-label="Draw and hold">
          <div className={styles.shapes} role="group" aria-label="Shape">
            {order.map((name) => (
              <motion.button
                key={name}
                type="button"
                className={styles.slot}
                aria-pressed={shape === name}
                aria-label={figures[name].name}
                onClick={() => {
                  touched.current = true
                  draw(name)
                }}
                initial={false}
                animate="rest"
                whileHover="lift"
                whileTap="press"
              >
                <motion.span className={`${styles.icon} ${shape === name ? styles.on : ''}`} variants={press} transition={quick}>
                  <Glyph name={name} />
                </motion.span>
              </motion.button>
            ))}
          </div>
          <span className={styles.rule} aria-hidden="true" />
          <motion.button
            type="button"
            className={styles.action}
            aria-disabled={!held}
            onClick={() => {
              if (!held) return
              touched.current = true
              straighten(false)
            }}
            initial={false}
            animate="rest"
            whileTap={held ? 'press' : undefined}
          >
            <motion.span className={styles.plate} variants={press} transition={quick}>
              <Glyph name="undo" />
              Undo
            </motion.span>
          </motion.button>
        </div>
      </div>

      <dl className={`${styles.band} ${styles.pair}`}>
        <div className={styles.fact}>
          <dt className="meta">Shape</dt>
          <dd className={styles.value}>{chosen.name}</dd>
        </div>
        <div className={styles.fact}>
          <dt className="meta">Stroke</dt>
          <dd className={styles.value}>
            {held ? <Glyph name="check" className={styles.mark} weight={2.2} /> : null}
            {phase === 'undone' ? <Glyph name="undo" className={styles.mark} weight={2} /> : null}
            {says[phase]}
          </dd>
        </div>
      </dl>
      <p className="visually-hidden" role="status">
        {touched.current && (phase === 'held' || phase === 'undone') ? says[phase] : ''}
      </p>
    </div>
  )
}
