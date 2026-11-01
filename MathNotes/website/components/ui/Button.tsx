import Link from 'next/link'
import type { ButtonHTMLAttributes, ReactNode } from 'react'
import styles from './Button.module.css'

type Props = {
  /** With an address it is a link; without one it is a button. */
  href?: string
  children: ReactNode
  /** Cloth finishes a task: one to a group. Everything else is a plate. */
  variant?: 'plate' | 'cloth'
  size?: 'regular' | 'compact' | 'large'
  className?: string
} & Pick<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick' | 'disabled' | 'aria-pressed' | 'aria-label'>

const isExternal = (href: string) => /^(https?:|mailto:)/.test(href)

export function Button({ href, children, variant = 'plate', size = 'regular', className, ...rest }: Props) {
  const classes = [styles.button, styles[variant], styles[size], variant === 'cloth' ? 'cloth' : '', className]
    .filter(Boolean)
    .join(' ')
  if (!href) {
    return (
      <button type="button" className={classes} {...rest}>
        {children}
      </button>
    )
  }
  const { 'aria-label': label } = rest
  if (isExternal(href)) {
    const web = href.startsWith('http')
    return (
      <a href={href} className={classes} aria-label={label} {...(web ? { target: '_blank', rel: 'noopener noreferrer' } : {})}>
        {children}
      </a>
    )
  }
  return (
    <Link href={href} className={classes} aria-label={label}>
      {children}
    </Link>
  )
}

/** A small arrow for a link that leaves the site in a new tab. */
export function Away() {
  return (
    <>
      <svg className={styles.away} viewBox="0 0 12 12" width="12" height="12" aria-hidden="true">
        <path d="M3 9 9 3M4.2 3H9v4.8" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      <span className="visually-hidden"> (opens in a new tab)</span>
    </>
  )
}
