'use client'

import { motion } from 'motion/react'
import { useRef, useState, useSyncExternalStore, type CSSProperties, type RefObject } from 'react'
import { useArrival } from '@/components/ui/useArrival'
import { landing } from '@/lib/motion'
import { Viewer } from './Viewer'
import { sequence, source, type Placed } from './shots'
import styles from './Pile.module.css'

type Spot = { x: number; y: number; w: number }

function dice(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0
    let mixed = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    mixed = (mixed + Math.imul(mixed ^ (mixed >>> 7), 61 | mixed)) ^ mixed
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4294967296
  }
}

const clamp = (value: number, least: number, most: number) => Math.min(Math.max(value, least), Math.max(least, most))

/**
 * Where each print lies on a desk `columns` cells across, in percent of the desk. Every print gets a cell of
 * its own, so none is buried, and about a cell's worth of area whatever its shape.
 */
function scatter(columns: number, seed: number): Spot[] {
  const roll = dice(seed)
  const rows = Math.ceil(sequence.length / columns)
  const cells = sequence.map((_, index) => index)
  for (let index = cells.length - 1; index > 0; index -= 1) {
    const other = Math.floor(roll() * (index + 1))
    ;[cells[index], cells[other]] = [cells[other], cells[index]]
  }
  const cell = 100 / columns
  return sequence.map((shot, index) => {
    const shape = shot.width / shot.height
    const w = Math.min(cell * Math.sqrt(shape), cell * 2.4)
    const h = (w / shape) * (columns / rows)
    const across = ((cells[index] % columns) + 0.5 + (roll() - 0.5) * 0.56) * cell
    const down = ((Math.floor(cells[index] / columns) + 0.5 + (roll() - 0.5) * 0.56) * 100) / rows
    return { x: clamp(across - w / 2, 1, 99 - w), y: clamp(down - h / 2, 1.5, 98.5 - h), w }
  })
}

const wide = scatter(8, 11)
const middling = scatter(6, 23)
const narrow = scatter(4, 5)
const turn = dice(41)
const lies = sequence.map((_, index) => ({ turn: Math.round((turn() - 0.5) * 150) / 10, layer: 1 + Math.floor(turn() * sequence.length), index }))

const percent = (value: number) => `${Math.round(value * 100) / 100}%`

const pointer = '(hover: hover) and (pointer: fine)'

function subscribe(changed: () => void) {
  const media = window.matchMedia(pointer)
  media.addEventListener('change', changed)
  return () => media.removeEventListener('change', changed)
}

/** Every screenshot loose on a desk: drag one aside with a mouse, select one to look at it closely. */
export function Pile() {
  const desk = useRef<HTMLDivElement>(null)
  const top = useRef(sequence.length + 1)
  const { arrived } = useArrival(desk, { amount: 0.15 })
  const [open, setOpen] = useState<number | null>(null)
  const fine = useSyncExternalStore(
    subscribe,
    () => window.matchMedia(pointer).matches,
    () => false,
  )

  return (
    <>
      <div ref={desk} className={styles.desk} aria-hidden="true">
        {sequence.map((shot, index) => (
          <Loose
            key={shot.name}
            shot={shot}
            index={index}
            desk={desk}
            dealt={arrived}
            draggable={fine}
            raise={() => (top.current += 1)}
            onOpen={setOpen}
          />
        ))}
      </div>
      <p className={styles.hint}>
        <span className={styles.byMouse}>Drag them about, or select one for a closer look.</span>
        <span className={styles.byTouch}>Tap one for a closer look.</span>
      </p>
      <Viewer open={open} onChange={setOpen} />
    </>
  )
}

type LooseProps = {
  shot: Placed
  index: number
  desk: RefObject<HTMLDivElement | null>
  dealt: boolean
  draggable: boolean
  raise: () => number
  onOpen: (number: number) => void
}

function Loose({ shot, index, desk, dealt, draggable, raise, onOpen }: LooseProps) {
  const lie = lies[index]
  const [layer, setLayer] = useState(lie.layer)
  const place = {
    '--x': percent(wide[index].x),
    '--y': percent(wide[index].y),
    '--w': percent(wide[index].w),
    '--mx': percent(middling[index].x),
    '--my': percent(middling[index].y),
    '--mw': percent(middling[index].w),
    '--nx': percent(narrow[index].x),
    '--ny': percent(narrow[index].y),
    '--nw': percent(narrow[index].w),
    zIndex: layer,
  } as CSSProperties

  return (
    <div className={styles.spot} style={place}>
      <motion.div
        initial={false}
        animate={dealt ? { opacity: 1, y: 0, scale: 1 } : { opacity: 0, y: -48, scale: 1.18 }}
        transition={dealt ? { ...landing, delay: 0.05 + index * 0.02 } : { duration: 0 }}
      >
        <motion.div
          className={`print ${styles.print}`}
          initial={false}
          animate={{ rotate: lie.turn }}
          drag={draggable}
          dragConstraints={desk}
          dragElastic={0.1}
          dragTransition={{ power: 0.12, timeConstant: 160 }}
          whileDrag={{ scale: 1.06, rotate: 0 }}
          tabIndex={-1}
          onPointerDown={() => setLayer(raise())}
          onTap={() => onOpen(shot.number)}
        >
          <img
            className={styles.image}
            src={source(shot, 'thumb')}
            width={shot.width}
            height={shot.height}
            alt=""
            draggable={false}
            loading="lazy"
            decoding="async"
          />
        </motion.div>
      </motion.div>
    </div>
  )
}
