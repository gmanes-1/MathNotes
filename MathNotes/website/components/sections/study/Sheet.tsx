import type { ReactNode } from 'react'
import styles from './Sheet.module.css'

type Props = { lead: string; trail?: string; children: ReactNode; className?: string }

/** A punched sheet of ruled paper with a red margin and two labels at its head. */
export function Sheet({ lead, trail, children, className }: Props) {
  return (
    <div className={[styles.frame, className].filter(Boolean).join(' ')}>
      <div className={`print ${styles.sheet}`}>
        <div className={styles.head}>
          <span>{lead}</span>
          {trail ? <span>{trail}</span> : null}
        </div>
        <div className={styles.lines}>{children}</div>
        <span className={styles.margin} aria-hidden="true" />
        {[0, 1, 2].map((index) => (
          <span key={index} className={`${styles.hole} ${styles[`hole${index}`]}`} aria-hidden="true" />
        ))}
      </div>
    </div>
  )
}
