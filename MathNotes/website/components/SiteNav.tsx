'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useRef, useState } from 'react'
import { asset, site } from '@/lib/site'
import { quick } from '@/lib/motion'
import { Away, Button } from './ui/Button'
import styles from './SiteNav.module.css'

const links = [
  { href: '/#features', label: 'Features' },
  { href: '/#story', label: 'Story' },
  { href: '/prototypes/', label: 'Prototypes' },
  { href: '/privacy/', label: 'Privacy' },
  { href: '/support/', label: 'Support' },
]

export function SiteNav() {
  const pathname = usePathname()
  const [open, setOpen] = useState(false)
  const menu = useRef<HTMLDivElement>(null)
  const button = useRef<HTMLButtonElement>(null)

  useEffect(() => setOpen(false), [pathname])

  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      setOpen(false)
      button.current?.focus()
    }
    const onPointer = (event: PointerEvent) => {
      if (menu.current && !menu.current.contains(event.target as Node)) setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    window.addEventListener('pointerdown', onPointer)
    return () => {
      window.removeEventListener('keydown', onKey)
      window.removeEventListener('pointerdown', onPointer)
    }
  }, [open])

  const current = (href: string) => !href.includes('#') && pathname.replace(/\/$/, '') === href.replace(/\/$/, '')

  return (
    <header className={styles.bar}>
      <div className={`wrap ${styles.inner}`}>
        <Link href="/" className={styles.brand} aria-label="OwlLuna, home">
          <img src={asset('/owlluna-icon.png')} alt="" width={32} height={32} className={styles.icon} />
          <span className={styles.name}>OwlLuna</span>
        </Link>

        <nav className={styles.links} aria-label="Site">
          <ul className={styles.group}>
            {links.map((link) => (
              <li key={link.href}>
                <Link href={link.href} className={styles.link} aria-current={current(link.href) ? 'page' : undefined}>
                  {link.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>

        <div className={styles.actions}>
          <Button href={site.appStoreUrl || site.repo} variant="cloth" size="compact">
            {site.appStoreUrl ? 'Get the app' : 'GitHub'}
            <Away />
          </Button>
          <noscript>
            <style>{`.${styles.menu}{display:none!important}`}</style>
          </noscript>
          <div
            className={styles.menu}
            ref={menu}
            onBlur={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget)) setOpen(false)
            }}
          >
            <button
              ref={button}
              type="button"
              className={styles.menuButton}
              aria-expanded={open}
              aria-controls="site-menu"
              onClick={() => setOpen((value) => !value)}
            >
              Menu
            </button>
            <AnimatePresence>
              {open ? (
                <motion.div
                  id="site-menu"
                  className={styles.card}
                  initial={{ opacity: 0, y: -8, scale: 0.97 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -6, scale: 0.98 }}
                  transition={quick}
                >
                  <div className={`cloth ${styles.cardBand}`}>Menu</div>
                  <nav aria-label="Site">
                    <ul>
                      {links.map((link) => (
                        <li key={link.href}>
                          <Link
                            href={link.href}
                            className={styles.cardRow}
                            aria-current={current(link.href) ? 'page' : undefined}
                            onClick={() => setOpen(false)}
                          >
                            {link.label}
                          </Link>
                        </li>
                      ))}
                    </ul>
                  </nav>
                </motion.div>
              ) : null}
            </AnimatePresence>
          </div>
        </div>
      </div>
    </header>
  )
}
