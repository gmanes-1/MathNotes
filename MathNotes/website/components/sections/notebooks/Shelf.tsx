'use client'

import { AnimatePresence, motion, useReducedMotion } from 'motion/react'
import { useRef, useState, type ReactNode } from 'react'
import { landing, quick } from '@/lib/motion'
import { ClothCover } from '../../ui/ClothCover'
import { FirstPageCover, PrintCover } from './covers'
import { useArrival } from '@/components/ui/useArrival'
import styles from './Shelf.module.css'

type Book = {
  title: string
  kind: 'Cloth' | 'Print' | 'First page'
  cover: ReactNode
  tilt: number
}

const books: Book[] = [
  { title: 'Field Notes', kind: 'Cloth', cover: <ClothCover title="Field Notes" meta="Mar 2026" color="moss" />, tilt: -5 },
  { title: 'Life Drawing', kind: 'Print', cover: <PrintCover title="Life Drawing" />, tilt: 4 },
  { title: 'Cello', kind: 'Cloth', cover: <ClothCover title="Cello" meta="Sep 2026" color="oxblood" />, tilt: -3 },
  { title: 'Organic Chemistry', kind: 'First page', cover: <FirstPageCover color="navy" />, tilt: 5 },
  { title: 'Planner', kind: 'Cloth', cover: <ClothCover title="Planner" meta="Jan 2026" color="mustard" />, tilt: -4 },
  { title: 'Recipes', kind: 'Cloth', cover: <ClothCover title="Recipes" meta="Kitchen" color="slate" />, tilt: 3 },
]

const drop = { type: 'spring', duration: 0.55, bounce: 0.5 } as const

/** A shelf of notebooks in the three cover styles, standing on a ledge. */
export function Shelf() {
  const row = useRef<HTMLUListElement>(null)
  const { arrived: play } = useArrival(row, { amount: 0.3 })
  const reduced = useReducedMotion()
  const [favourites, setFavourites] = useState<readonly string[]>(['Field Notes'])

  const toggle = (title: string) =>
    setFavourites((current) => (current.includes(title) ? current.filter((name) => name !== title) : [...current, title]))

  return (
    <figure className={styles.shelf}>
      <figcaption className={styles.top}>
        <span className="meta">This week</span>
        <span className={styles.line} aria-hidden="true" />
        <span className={styles.hint}>
          <svg viewBox="0 0 10 20" width="10" height="20" aria-hidden="true">
            <path d="M0,0H10V20L5,16L0,20Z" />
          </svg>
          <span className="meta">Try it: tap a cover for its favourite ribbon</span>
        </span>
      </figcaption>
      <ul className={styles.row} ref={row}>
        {books.map((book, index) => {
          const favourite = favourites.includes(book.title)
          return (
            <li key={book.title} className={styles.slot}>
              <motion.div
                className={styles.stand}
                initial={false}
                animate={play ? { y: 0, rotate: 0, opacity: 1 } : { y: 56, rotate: book.tilt, opacity: 0 }}
                transition={play ? { ...landing, delay: 0.08 + index * 0.07, opacity: { duration: 0.2, delay: 0.08 + index * 0.07 } } : { duration: 0 }}
              >
                <motion.div className={styles.book} whileHover={reduced ? undefined : { y: -10, rotate: book.tilt * -0.25 }} transition={quick}>
                  {book.cover}
                  <span className={styles.ribbonSlot} aria-hidden="true">
                    <AnimatePresence initial={false}>
                      {favourite ? (
                        <motion.span key="ribbon" className={styles.ribbon} initial={{ y: '-104%' }} animate={{ y: '0%' }} exit={{ y: '-104%', transition: { duration: 0.18 } }} transition={drop} />
                      ) : null}
                    </AnimatePresence>
                  </span>
                  <button type="button" className={styles.hit} aria-pressed={favourite} aria-label={`Favourite: ${book.title}, ${book.kind.toLowerCase()} cover`} onClick={() => toggle(book.title)} />
                </motion.div>
              </motion.div>
              <span className={styles.plank} aria-hidden="true" />
              <span className={`meta ${styles.kind}`}>{book.kind}</span>
            </li>
          )
        })}
      </ul>
    </figure>
  )
}
