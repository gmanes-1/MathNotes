'use client'

import { useInView, useIsomorphicLayoutEffect, type UseInViewOptions } from 'motion/react'
import { useState, type RefObject } from 'react'

type View = Pick<UseInViewOptions, 'amount' | 'margin'>

/** Whether an element has scrolled into view. What is on screen at load has arrived already. */
export function useArrival(ref: RefObject<Element | null>, view: View = {}) {
  const [waited, setWaited] = useState(false)
  const inView = useInView(ref, { once: true, ...view })

  useIsomorphicLayoutEffect(() => {
    const element = ref.current
    if (element && element.getBoundingClientRect().top > window.innerHeight * 0.92) setWaited(true)
  }, [ref])

  return { arrived: !waited || inView, waited }
}
