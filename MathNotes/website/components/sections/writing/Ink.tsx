'use client'

import { motion } from 'motion/react'
import { ease } from '@/lib/motion'
import { sheet, type Kind } from './pens'

type Recipe = {
  alongNib: number[]
  width: number
  cap?: 'round' | 'butt'
  strength?: number
  grain?: 'fine' | 'coarse'
  multiplies?: boolean
  paleCore?: number
}

const nib = { x: 0.77, y: -0.64 }

const recipes: Record<Kind, Recipe> = {
  pen: { alongNib: [-0.75, 0, 0.75], width: 3.3 },
  fineliner: { alongNib: [0], width: 2 },
  fountain: { alongNib: [-3, -2, -1, 0, 1, 2, 3], width: 1.9 },
  pencil: { alongNib: [0], width: 2.7, grain: 'fine', strength: 0.94 },
  highlighter: { alongNib: [0], width: 15, cap: 'butt', strength: 0.78, multiplies: true },
  crayon: { alongNib: [0], width: 8.5, grain: 'coarse' },
  watercolour: { alongNib: [0], width: 14, paleCore: 10.5 },
}

const tile = 32

function flecks(seed: number, count: number, reach: number): string {
  let state = seed
  const next = () => {
    state = (state * 1664525 + 1013904223) % 4294967296
    return state / 4294967296
  }
  const tenth = (value: number) => Math.round(value * 10) / 10
  let d = ''
  for (let index = 0; index < count; index++) {
    const turn = next() * Math.PI * 2
    const length = next() * reach
    d += `M${tenth(next() * tile)} ${tenth(next() * tile)}l${tenth(Math.cos(turn) * length)} ${tenth(Math.sin(turn) * length)}`
  }
  return d
}

const grains = [
  { name: 'fine', d: flecks(7, 260, 1.6), weight: 0.9, bite: 0.8 },
  { name: 'coarse', d: flecks(19, 120, 2.6), weight: 1.25, bite: 0.86 },
] as const

const grainId = (name: string) => `writing-grain-${name}`

/** The tooth of the paper, for the pencil and the crayon to catch on. */
export function InkGrain() {
  return (
    <defs>
      {grains.map((grain) => (
        <pattern key={grain.name} id={`${grainId(grain.name)}-tile`} width={tile} height={tile} patternUnits="userSpaceOnUse">
          <rect width={tile} height={tile} fill="#fff" />
          <path d={grain.d} fill="none" stroke="#000" strokeWidth={grain.weight} strokeLinecap="round" strokeOpacity={grain.bite} />
        </pattern>
      ))}
      {grains.map((grain) => (
        <mask key={grain.name} id={grainId(grain.name)} maskUnits="userSpaceOnUse" x="0" y={sheet.top} width={sheet.width} height={sheet.height}>
          <rect y={sheet.top} width={sheet.width} height={sheet.height} fill={`url(#${grainId(grain.name)}-tile)`} />
        </mask>
      ))}
    </defs>
  )
}

type Props = {
  d: string
  kind: Kind
  color: string
  opacity?: number
  at: number
  takes: number
  play: boolean
  still?: boolean
}

const unwritten = { pathLength: 0, opacity: 0 }
const written = { pathLength: 1, opacity: 1 }

/** One stroke of a pen, written `at` seconds in over `takes` seconds. */
export function InkStroke({ d, kind, color, opacity = 1, at, takes, play, still = false }: Props) {
  const recipe = recipes[kind]
  const transition = still ? { duration: 0 } : { pathLength: { duration: takes, delay: at, ease: ease.inOut }, opacity: { duration: 0.01, delay: at } }
  const stroke = { d, fill: 'none', strokeLinecap: recipe.cap ?? 'round', strokeLinejoin: 'round' } as const
  const motionProps = { initial: still ? false : unwritten, animate: play || still ? written : unwritten, transition } as const
  return (
    <g
      data-ink
      opacity={(recipe.strength ?? 1) * opacity}
      mask={recipe.grain ? `url(#${grainId(recipe.grain)})` : undefined}
      style={recipe.multiplies ? { mixBlendMode: 'multiply' } : undefined}
    >
      {recipe.alongNib.map((along) => (
        <g key={along} transform={`translate(${nib.x * along} ${nib.y * along})`}>
          <motion.path {...stroke} stroke={color} strokeWidth={recipe.width} {...motionProps} />
        </g>
      ))}
      {recipe.paleCore ? <motion.path {...stroke} stroke="#fff" strokeOpacity="0.24" strokeWidth={recipe.paleCore} {...motionProps} /> : null}
    </g>
  )
}
