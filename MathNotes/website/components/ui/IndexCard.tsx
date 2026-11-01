import type { ReactNode } from 'react'
import styles from './IndexCard.module.css'

type Props = {
  /** Small caps at the head: the side's name. */
  side?: string
  /** Small caps opposite it: the notebook's name. */
  source?: string
  children: ReactNode
  className?: string
}

/** A cream index card with a red head rule and faint ruling. It stays cream at night. */
export function IndexCard({ side, source, children, className }: Props) {
  return (
    <div className={['print', styles.card, className].filter(Boolean).join(' ')}>
      {side || source ? (
        <div className={styles.head}>
          <span>{side}</span>
          <span>{source}</span>
        </div>
      ) : null}
      <div className={styles.body}>{children}</div>
    </div>
  )
}
