'use client'

import { useEffect } from 'react'

/** Opens the question an address points at, so a link ending in its id lands on the answer. */
export function OpenFromLink() {
  useEffect(() => {
    const open = () => {
      const id = window.location.hash.slice(1)
      const target = id ? document.getElementById(id) : null
      if (target instanceof HTMLDetailsElement) target.open = true
    }
    open()
    window.addEventListener('hashchange', open)
    return () => window.removeEventListener('hashchange', open)
  }, [])

  return null
}
