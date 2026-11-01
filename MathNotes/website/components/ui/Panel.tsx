import type { ReactNode } from 'react'
import styles from './Panel.module.css'

type Props = {
  /** Printed on the cloth band that names the card. */
  title: string
  children: ReactNode
  /** Small caps at the band's trailing end. */
  note?: string
  className?: string
}

/** The app's Card: a flat, ink-outlined panel under a cloth band that names it. */
export function Panel({ title, note, children, className }: Props) {
  return (
    <div className={[styles.panel, className].filter(Boolean).join(' ')}>
      <div className={`cloth ${styles.band}`}>
        <span className={styles.title}>{title}</span>
        {note ? <span className={styles.note}>{note}</span> : null}
      </div>
      <div className={styles.body}>{children}</div>
    </div>
  )
}

/** A row of a Card, ruled like an index card. */
export function PanelRow({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={[styles.row, className].filter(Boolean).join(' ')}>{children}</div>
}
