import type { ReactNode } from 'react'
import styles from './Stamp.module.css'

type Props = {
  title: string
  children: ReactNode
  tone?: 'cobalt' | 'mustard'
  /** Buttons, the cancelling one first and the main one last. */
  actions?: ReactNode
  className?: string
}

/** The app's Stamp: a board with a cloth edge down its leading side. */
export function Stamp({ title, children, tone = 'cobalt', actions, className }: Props) {
  return (
    <div className={[styles.stamp, className].filter(Boolean).join(' ')}>
      <span className={[styles.edge, 'cloth', styles[tone]].join(' ')} aria-hidden="true" />
      <div className={styles.content}>
        <p className={styles.title}>{title}</p>
        <div className={styles.message}>{children}</div>
        {actions ? <div className={styles.actions}>{actions}</div> : null}
      </div>
    </div>
  )
}
