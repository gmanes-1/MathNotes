'use client'

import { useSyncExternalStore } from 'react'

const query = '(prefers-reduced-motion: reduce)'

function subscribe(changed: () => void) {
  const media = window.matchMedia(query)
  media.addEventListener('change', changed)
  return () => media.removeEventListener('change', changed)
}

/** Whether Reduce Motion is on. It reads as off while the page hydrates. */
export function useStill(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(query).matches,
    () => false,
  )
}
