'use client'

import type { TargetAndTransition, Transition } from 'motion/react'
import { createContext, useContext } from 'react'
import { useStill } from '../ui/useStill'

type Scene = {
  /** The tile is on screen, so its scene may run. */
  play: boolean
  /** Milliseconds taken off every beat, for a tile that came into view late. */
  shift: number
  /** The endless parts may run: the tile is in view and nothing has paused them. */
  loop: boolean
}

const SceneContext = createContext<Scene>({ play: true, shift: 0, loop: true })

export const SceneProvider = SceneContext.Provider

/** The clock of the app's launch splash: beats are given in its milliseconds. */
export function useScene() {
  const scene = useContext(SceneContext)
  const still = useStill()
  const at = (ms: number) => Math.max(0, ms - scene.shift) / 1000
  const beat = (from: TargetAndTransition, to: TargetAndTransition, ms: number, transition: Transition = {}) => ({
    initial: from,
    animate: scene.play ? to : from,
    transition: { ...transition, delay: at(ms) },
  })
  /** A pen stroke drawn from its start; it has no ink at all until its beat. */
  const draw = (ms: number, transition: Transition = {}) => ({
    initial: { pathLength: 0, opacity: 0 },
    animate: scene.play ? { pathLength: 1, opacity: 1 } : { pathLength: 0, opacity: 0 },
    transition: still ? { duration: 0 } : { ...transition, delay: at(ms), opacity: { duration: 0.01, delay: at(ms) } },
  })
  return { play: scene.play, loop: scene.loop && !still, still, at, beat, draw }
}

/** The fixed inks of the splash's tiles, which do not change at night. */
export const inks = {
  ink: '#1B2230',
  paper: '#F1EDE4',
  white: '#FFFDF6',
  rule: '#D6CFBE',
  moon: '#F4DE3C',
  moonLight: '#FBF07A',
  tomato: '#C9452F',
} as const

/** A point in an SVG drawing's own coordinates for a group to turn or grow about. */
export const about = (x: number, y: number) => ({ transformBox: 'view-box', originX: `${x}px`, originY: `${y}px` }) as const

type Pause = { paused: boolean; toggle: () => void }

const PauseContext = createContext<Pause>({ paused: false, toggle: () => {} })

export const PauseProvider = PauseContext.Provider

export const usePause = () => useContext(PauseContext)
