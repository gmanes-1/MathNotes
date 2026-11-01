import type { ReactNode } from 'react'
import styles from './SectionHeading.module.css'

type Props = {
  /** Small caps over the heading. */
  eyebrow: string
  title: ReactNode
  children?: ReactNode
  id?: string
  as?: 'h1' | 'h2'
}

/** The library's editorial heading: small caps, a Fraunces line, and a lede under a hairline. */
export function SectionHeading({ eyebrow, title, children, id, as: Tag = 'h2' }: Props) {
  return (
    <header className={styles.heading}>
      <p className="meta">{eyebrow}</p>
      <Tag id={id} className={`display ${styles.title}`}>
        {title}
      </Tag>
      {children ? <div className={`lede ${styles.lede}`}>{children}</div> : null}
    </header>
  )
}
