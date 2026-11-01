'use client'

import { motion, useInView, useReducedMotion, useScroll, useTransform, type MotionValue } from 'motion/react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { landing } from '@/lib/motion'
import { site } from '@/lib/site'
import { Away, Button } from '../ui/Button'
import { PauseProvider, SceneProvider } from './scene'
import { NoteTile } from './tiles/NoteTile'
import { OwlTile } from './tiles/OwlTile'
import { CardsTile, MoonTile, TickerTile, VolumeTile, WordTile } from './tiles/SmallTiles'
import styles from './BentoHero.module.css'

type Spec = {
  name: 'owl' | 'pitch' | 'moon' | 'cards' | 'volume' | 'ticker' | 'word' | 'note'
  fill: 'moonFill' | 'boardFill' | 'inkFill' | 'tomatoFill'
  /** Where it comes from, in its own widths and heights, and the tilt it carries on the way. */
  enter: { x: number; y: number }
  /** Where it leaves to as the page scrolls, when that is not the way it came. */
  leave?: { x: number; y: number }
  tilt: number
  /** When it lands, on the splash's clock, and how hard it springs. */
  delay: number
  bounce: number
  /** Its turn to leave as the page scrolls. */
  order: number
}

const tiles: Spec[] = [
  { name: 'pitch', fill: 'boardFill', enter: { x: 0, y: -1.3 }, tilt: 3, delay: 120, bounce: 0.36, order: 3 },
  { name: 'ticker', fill: 'tomatoFill', enter: { x: 1.25, y: 0 }, tilt: 2, delay: 210, bounce: 0.38, order: 4 },
  { name: 'volume', fill: 'boardFill', enter: { x: 0, y: 0 }, tilt: -14, delay: 560, bounce: 0.5, order: 6 },
  { name: 'note', fill: 'boardFill', enter: { x: 1.25, y: 0 }, tilt: 4, delay: 150, bounce: 0.4, order: 2 },
  { name: 'cards', fill: 'moonFill', enter: { x: 1.35, y: 0 }, tilt: 7, delay: 265, bounce: 0.42, order: 5 },
  { name: 'moon', fill: 'inkFill', enter: { x: 0, y: -1.7 }, tilt: -8, delay: 320, bounce: 0.44, order: 7 },
  { name: 'owl', fill: 'moonFill', enter: { x: -1.25, y: 0 }, tilt: -5, delay: 30, bounce: 0.38, order: 1 },
  { name: 'word', fill: 'inkFill', enter: { x: 0, y: 1.35 }, leave: { x: -1.1, y: 0 }, tilt: 1.5, delay: 90, bounce: 0.36, order: 0 },
]

/** How long the stylesheet waits for scripts before it shows the hero still, in milliseconds. */
const patience = 3000

/** The stylesheet's stacked arrangement, where the tiles stay put. */
const stackedLayout = '(max-width: 900px), (max-aspect-ratio: 1 / 1)'

const scenes: Record<Spec['name'], () => ReactNode> = {
  owl: () => <OwlTile />,
  pitch: () => <Pitch />,
  moon: () => <MoonTile />,
  cards: () => <CardsTile />,
  volume: () => <VolumeTile />,
  ticker: () => <TickerTile />,
  word: () => <WordTile />,
  note: () => <NoteTile />,
}

/** The app's launch splash as the page's opening. */
export function BentoHero() {
  const stage = useRef<HTMLDivElement>(null)
  const { scrollYProgress } = useScroll({ target: stage, offset: ['start start', 'end start'] })
  const reduced = useReducedMotion()
  const [stacked, setStacked] = useState(false)
  const [paused, setPaused] = useState(false)
  const [ready, setReady] = useState<'no' | 'yes' | 'late'>('no')

  useEffect(() => setReady(performance.now() > patience ? 'late' : 'yes'), [])

  useEffect(() => {
    document.documentElement.toggleAttribute('data-still', paused)
    return () => document.documentElement.removeAttribute('data-still')
  }, [paused])

  useEffect(() => {
    const query = window.matchMedia(stackedLayout)
    const update = () => setStacked(query.matches)
    update()
    query.addEventListener('change', update)
    return () => query.removeEventListener('change', update)
  }, [])

  return (
    <section className={styles.stage} ref={stage} aria-label="OwlLuna" data-ready={ready === 'no' ? undefined : ''}>
      <noscript>
        <style>{`[data-tile],[data-tile] [style]{transform:none!important;opacity:1!important;stroke-dasharray:none!important;clip-path:none!important}`}</style>
      </noscript>
      <PauseProvider value={{ paused, toggle: () => setPaused((value) => !value) }}>
        <div className={styles.board}>
          {tiles.map((spec) => (
            <Tile key={spec.name} spec={spec} progress={scrollYProgress} peels={!reduced && !stacked} paused={paused} late={ready === 'late'}>
              {scenes[spec.name]()}
            </Tile>
          ))}
        </div>
      </PauseProvider>
    </section>
  )
}

type TileProps = {
  spec: Spec
  progress: MotionValue<number>
  peels: boolean
  paused: boolean
  /** Scripts arrived after the still was shown, so the tile stays where it is and its scene plays at once. */
  late: boolean
  children: ReactNode
}

function Tile({ spec, progress, peels, paused, late, children }: TileProps) {
  const cell = useRef<HTMLDivElement>(null)
  const born = useRef(0)
  const inView = useInView(cell, { once: true, amount: 0.15 })
  const live = useInView(cell)
  const [scene, setScene] = useState({ play: false, shift: 0 })

  useEffect(() => {
    born.current = performance.now()
  }, [])

  useEffect(() => {
    if (!inView) return
    const shift = late ? Infinity : performance.now() - born.current > 500 ? spec.delay : 0
    setScene((current) => (current.play ? current : { play: true, shift }))
  }, [inView, late, spec.delay])

  const start = 0.05 + spec.order * 0.035
  const reach = peels ? 46 : 0
  const leave = spec.leave ?? spec.enter
  const x = useTransform(progress, [start, start + 0.6], ['0%', `${leave.x * reach}%`])
  const y = useTransform(progress, [start, start + 0.6], ['0%', `${leave.y * reach}%`])
  const rotate = useTransform(progress, [start, start + 0.6], [0, peels ? spec.tilt : 0])

  const sticker = spec.name === 'volume'
  const away = { x: `${spec.enter.x * 100}%`, y: `${spec.enter.y * 100}%`, rotate: spec.tilt, scale: sticker ? 0 : 1 }
  const rest = { x: '0%', y: '0%', rotate: 0, scale: 1 }

  return (
    <div ref={cell} className={`${styles.cell} ${styles[`${spec.name}Cell`]}`}>
      <motion.div className={styles.peel} style={{ x, y, rotate }}>
        <motion.div
          data-tile
          className={`print ${styles.tile} ${styles[spec.fill]} ${spec.name === 'pitch' ? styles.pitchTile : ''}`}
          initial={away}
          animate={scene.play ? rest : away}
          transition={late ? { duration: 0 } : { ...landing, bounce: spec.bounce, duration: sticker ? 0.7 : 0.9, delay: Math.max(0, spec.delay - scene.shift) / 1000 }}
        >
          <SceneProvider value={{ ...scene, loop: scene.play && live && !paused }}>{children}</SceneProvider>
        </motion.div>
      </motion.div>
    </div>
  )
}

function Pitch() {
  return (
    <div className={styles.pitch}>
      <div className={styles.pitchLabels}>
        <span className={styles.pitchLabel}>For iPad and Apple Pencil</span>
        <span className={styles.pitchLabel}>Free · MIT License</span>
      </div>
      <div className={styles.pitchWords}>
        <h1 className={`display ${styles.pitchTitle}`}>Handwritten notes for iPad. Free, for good.</h1>
        <p className={styles.pitchLede}>
          No subscription, no ads, no account and no tracking. OwlLuna is open source, and your notes stay on your
          iPad, and in your own iCloud if you turn sync on.
        </p>
      </div>
      <div className={styles.pitchActions}>
        {site.appStoreUrl ? (
          <Button href={site.appStoreUrl} variant="cloth">
            Download on the App Store
            <Away />
          </Button>
        ) : (
          <Button href="#features" variant="cloth">
            See what it does
          </Button>
        )}
        <Button href={site.repo}>
          Source on GitHub
          <Away />
        </Button>
        {site.appStoreUrl ? null : <span className={styles.pitchSoon}>Coming soon to the App Store</span>}
      </div>
    </div>
  )
}
