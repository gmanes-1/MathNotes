import type { Transition } from 'motion/react'

/** The curves of the app's launch splash (`Launch/SplashTimeline.swift`). */
export const ease = {
  glide: [0.16, 1, 0.3, 1],
  bounce: [0.34, 1.56, 0.64, 1],
  standard: [0, 0, 0.58, 1],
  inOut: [0.42, 0, 0.58, 1],
} as const satisfies Record<string, readonly [number, number, number, number]>

/** A tile landing: it passes its place and locks. */
export const landing: Transition = { type: 'spring', duration: 0.9, bounce: 0.4 }

/** Letters and cards coming up from under a line. */
export const rising: Transition = { type: 'spring', duration: 0.78, bounce: 0.34 }

/** The moon and the index cards. */
export const lively: Transition = { type: 'spring', duration: 0.85, bounce: 0.42 }

/** Content coming into view down the page. */
export const settle: Transition = { type: 'spring', duration: 0.7, bounce: 0.22 }

/** Hover and press. */
export const quick: Transition = { type: 'spring', duration: 0.32, bounce: 0.3 }
