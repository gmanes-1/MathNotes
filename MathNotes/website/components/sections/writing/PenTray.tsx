'use client'

import { AnimatePresence, animate, motion, useInView, useMotionValue, useTransform, type AnimationPlaybackControls } from 'motion/react'
import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import { ease, lively, quick } from '@/lib/motion'
import { InkGrain, InkStroke } from './Ink'
import { Glyph, KindMark } from './marks'
import { another, beats, onPaper, onWell, sample, sheet, shelfLimit, starters } from './pens'
import { useStill } from '@/components/ui/useStill'
import styles from './Stage.module.css'

type Tool = 'pen' | 'eraser' | 'lasso'

const helpers = {
  eraser: { name: 'Eraser', does: 'Takes off whole strokes, or part of one.' },
  lasso: { name: 'Lasso', does: 'Moves, copies or deletes the ink it catches.' },
} as const

const [, baseline] = sheet.rules
const bottom = sheet.top + sheet.height
const slant = `translate(0 ${baseline}) skewX(-9) translate(0 ${-baseline})`
const rub = { from: 82, to: 404, along: 241 } as const
const press = { rest: { y: 0, scale: 1 }, lift: { y: -2, scale: 1 }, press: { y: 0, scale: 0.92 } }
const unwritten = { pathLength: 0, opacity: 0 }
const written = { pathLength: 1, opacity: 1 }

/** A sheet of paper over the app's tool tray: taking up a pen writes the sample again in that pen's ink. */
export function PenTray() {
  const stage = useRef<HTMLDivElement>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const newest = useRef<HTMLButtonElement>(null)
  const rubbing = useRef<AnimationPlaybackControls | null>(null)
  const touched = useRef(false)
  const inView = useInView(stage, { once: true, amount: 0.3 })
  const still = useStill()

  const [shelf, setShelf] = useState(starters)
  const [penId, setPenId] = useState(starters[0].id)
  const [tool, setTool] = useState<Tool>('pen')
  const [turn, setTurn] = useState(0)
  const [ready, setReady] = useState(false)
  const [more, setMore] = useState({ before: false, after: false })

  const rubbed = useMotionValue(0)
  const edge = useTransform(rubbed, (amount) => rub.from + (rub.to - rub.from) * amount)
  const bob = useTransform(rubbed, (amount) => rub.along + Math.sin(amount * Math.PI * 7) * 4)
  const eraserShown = useTransform(rubbed, (amount) => (amount > 0 && amount < 1 ? 1 : 0))

  const pen = shelf.find((each) => each.id === penId) ?? shelf[0]
  const full = shelf.length >= shelfLimit

  useEffect(() => setReady(true), [])

  useEffect(() => () => rubbing.current?.stop(), [])

  useEffect(() => {
    const element = scroller.current
    if (!element) return
    const update = () => {
      const end = element.scrollWidth - element.clientWidth
      setMore({ before: element.scrollLeft > 1, after: element.scrollLeft < end - 1 })
    }
    update()
    element.addEventListener('scroll', update, { passive: true })
    const observer = new ResizeObserver(update)
    observer.observe(element)
    return () => {
      element.removeEventListener('scroll', update)
      observer.disconnect()
    }
  }, [shelf.length])

  useEffect(() => {
    if (full) newest.current?.focus()
  }, [full])

  const take = (id: string) => {
    touched.current = true
    rubbing.current?.stop()
    rubbed.set(0)
    setPenId(id)
    setTool('pen')
    setTurn((count) => count + 1)
  }

  const add = () => {
    const fresh = another(pen)
    setShelf((pens) => (pens.length < shelfLimit ? [...pens, fresh] : pens))
    take(fresh.id)
  }

  const erase = () => {
    touched.current = true
    setTool('eraser')
    if (rubbed.get() >= 1) return
    rubbing.current?.stop()
    if (still) rubbed.set(1)
    else rubbing.current = animate(rubbed, 1, { duration: 0.8, ease: ease.inOut })
  }

  const lasso = () => {
    touched.current = true
    setTool('lasso')
  }

  const ink = { kind: pen.kind, color: pen.color, opacity: pen.opacity, play: inView, still }
  const strength = `${Math.round(pen.opacity * 100)}%`
  const said = tool === 'pen' ? `${pen.widthName} width, ${strength} opacity` : helpers[tool].does

  return (
    <div className={styles.stage} ref={stage}>
      <noscript>
        <style>{`g[data-ink] path{stroke-dasharray:none!important;opacity:1!important}`}</style>
      </noscript>
      <div className={styles.desk}>
        <div className={`print ${styles.sheet}`}>
          <svg
            className={styles.page}
            viewBox={`0 ${sheet.top} ${sheet.width} ${sheet.height}`}
            role="img"
            aria-label="A ruled page with the word Luna, a crescent moon and a star, written with the pen in hand"
          >
            <InkGrain />
            <clipPath id="writing-unrubbed">
              <motion.rect x={edge} y={sheet.top} width={sheet.width} height={sheet.height} />
            </clipPath>
            <path d={sheet.rules.map((y) => `M0,${y} H${sheet.width}`).join(' ')} stroke="#D6CFBE" strokeWidth="1.6" />
            <path d={`M${sheet.margin},${sheet.top} V${bottom}`} stroke="#C9452F" strokeWidth="1.6" opacity="0.8" />
            <g key={`${pen.id}-${turn}`}>
              <g transform={slant}>
                <InkStroke d={sample.word} {...ink} {...beats.word} />
              </g>
              <InkStroke d={sample.moon} {...ink} {...beats.moon} />
              <InkStroke d={sample.star} {...ink} {...beats.star} />
              <g clipPath="url(#writing-unrubbed)">
                <InkStroke d={sample.underline} {...ink} {...beats.underline} />
              </g>
            </g>
            <motion.g style={{ x: edge, y: bob, opacity: eraserShown }}>
              <g transform="rotate(-24)">
                <rect x="-19" y="-11" width="38" height="22" rx="3" fill="#E3A6A1" stroke="#1B2230" strokeWidth="2.4" />
                <path d="M-5,-11 V11 H19 V-11 Z" fill="#F7F1E3" stroke="#1B2230" strokeWidth="2.4" strokeLinejoin="round" />
              </g>
            </motion.g>
            <AnimatePresence>
              {tool === 'lasso' ? (
                <motion.g key="lasso" exit={{ opacity: 0 }} transition={{ duration: 0.14 }}>
                  <motion.path
                    d={sample.lasso}
                    fill="none"
                    stroke="#1B2230"
                    strokeWidth="2.6"
                    strokeLinecap="round"
                    initial={still ? false : unwritten}
                    animate={written}
                    transition={{ pathLength: { duration: 0.7, ease: ease.inOut }, opacity: { duration: 0.01 } }}
                  />
                  <motion.path
                    d={sample.lasso}
                    fill="none"
                    stroke="#E8B023"
                    strokeWidth="2.6"
                    strokeDasharray="7 7"
                    initial={still ? false : { opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ duration: 0.14, delay: 0.66 }}
                  />
                </motion.g>
              ) : null}
            </AnimatePresence>
          </svg>
        </div>

        <div className={styles.tray} role="group" aria-label="Tools">
          <div className={styles.pens} ref={scroller} data-before={more.before || undefined} data-after={more.after || undefined}>
            {shelf.map((each, index) => {
              const inHand = tool === 'pen' && each.id === pen.id
              const blot = {
                '--size': `calc(var(--label) * ${((9 + 11 * each.breadth) / 32).toFixed(3)})`,
                '--day': onPaper(each),
                '--night': onWell(each),
              } as CSSProperties
              return (
                <motion.button
                  key={each.id}
                  ref={index === shelfLimit - 1 ? newest : undefined}
                  type="button"
                  className={styles.slot}
                  aria-pressed={inHand}
                  aria-label={`${each.kindName}, ${each.colorName.toLowerCase()}`}
                  onClick={() => take(each.id)}
                  initial={false}
                  animate="rest"
                  whileHover="lift"
                  whileTap="press"
                >
                  <motion.span className={`${styles.label} ${inHand ? styles.inHand : ''}`} variants={press} transition={quick}>
                    <KindMark kind={each.kind} className={styles.kind} />
                    <span className={styles.blot} style={blot} />
                    {inHand ? (
                      <motion.span className={`cloth ${styles.check}`} initial={ready ? { scale: 0 } : false} animate={{ scale: 1 }} transition={lively}>
                        <Glyph name="check" weight={2.8} />
                      </motion.span>
                    ) : null}
                  </motion.span>
                </motion.button>
              )
            })}
            {full ? null : (
              <motion.button type="button" className={styles.slot} aria-label="New pen" onClick={add} initial={false} animate="rest" whileHover="lift" whileTap="press">
                <motion.span className={`${styles.label} ${styles.empty}`} variants={press} transition={quick}>
                  <Glyph name="plus" weight={1.9} />
                </motion.span>
              </motion.button>
            )}
          </div>
          <span className={styles.rule} aria-hidden="true" />
          {(['eraser', 'lasso'] as const).map((name) => (
            <motion.button
              key={name}
              type="button"
              className={styles.slot}
              aria-pressed={tool === name}
              aria-label={helpers[name].name}
              onClick={name === 'eraser' ? erase : lasso}
              initial={false}
              animate="rest"
              whileHover="lift"
              whileTap="press"
            >
              <motion.span className={`${styles.icon} ${tool === name ? styles.on : ''}`} variants={press} transition={quick}>
                <Glyph name={name} />
              </motion.span>
            </motion.button>
          ))}
        </div>
      </div>

      <dl className={styles.band}>
        {tool === 'pen' ? (
          <>
            <Fact term="Kind">{pen.kindName}</Fact>
            <Fact term="Colour">
              <span className={styles.swatch} style={{ background: pen.color }} />
              {pen.colorName}
            </Fact>
            <Fact term="Width">
              <svg className={styles.breadth} viewBox="0 0 30 14" aria-hidden="true">
                <path d="M3,8.5 C8,3 13,12 18,7 C21,4 25,5 27,6" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth={1.2 + pen.breadth * 6} />
              </svg>
              {pen.widthName}
            </Fact>
            <Fact term="Opacity">{strength}</Fact>
          </>
        ) : (
          <div className={`${styles.fact} ${styles.wide}`}>
            <dt className="meta">{helpers[tool].name}</dt>
            <dd className={styles.does}>{helpers[tool].does}</dd>
          </div>
        )}
      </dl>
      <p className="visually-hidden" role="status">
        {touched.current ? said : ''}
      </p>
    </div>
  )
}

function Fact({ term, children }: { term: string; children: ReactNode }) {
  return (
    <div className={styles.fact}>
      <dt className="meta">{term}</dt>
      <dd className={styles.value}>{children}</dd>
    </div>
  )
}
