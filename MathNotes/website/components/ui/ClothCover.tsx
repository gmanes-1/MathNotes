import type { CSSProperties } from 'react'
import styles from './ClothCover.module.css'

export const clothColors = {
  oxblood: '#6e2a2a',
  tomato: '#c9452f',
  mustard: '#d6a02a',
  moss: '#3d5a40',
  jade: '#2f7d6b',
  cobalt: '#2f4da0',
  navy: '#1e2a45',
  slate: '#56606b',
  rose: '#c98a86',
  oat: '#cdbf9f',
} as const

export type ClothColor = keyof typeof clothColors

type Props = {
  title: string
  /** Small caps under the title: the shelf's name, or the month the notebook was started. */
  meta?: string
  color?: ClothColor
  /** The tomato favourite ribbon. */
  ribbon?: boolean
  className?: string
}

/** A closed cloth-bound notebook, 3:4, with its page block, spine, hinge groove and cream label. */
export function ClothCover({ title, meta, color = 'cobalt', ribbon = false, className }: Props) {
  return (
    <div className={[styles.cover, className].filter(Boolean).join(' ')} style={{ '--cover': clothColors[color] } as CSSProperties}>
      <span className={styles.leaves} aria-hidden="true" />
      <span className={styles.board}>
        <span className={styles.label}>
          <span className={styles.title}>{title}</span>
          {meta ? <span className={styles.meta}>{meta}</span> : null}
        </span>
        {ribbon ? <span className={styles.ribbon} aria-hidden="true" /> : null}
      </span>
    </div>
  )
}
