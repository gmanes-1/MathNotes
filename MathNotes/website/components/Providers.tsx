'use client'

import { MotionConfig } from 'motion/react'
import type { ReactNode } from 'react'

/** With Reduce Motion nothing moves or turns; what is left cross-fades, as in the app. */
export function Providers({ children }: { children: ReactNode }) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>
}
