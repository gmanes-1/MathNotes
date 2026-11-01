import type { Metadata } from 'next'
import { Button } from '@/components/ui/Button'
import styles from './not-found.module.css'

export const metadata: Metadata = { title: 'Page not found' }

export default function NotFound() {
  return (
    <div className={`wrap ${styles.page}`}>
      <div className={styles.plate}>
        <span className={styles.symbol} aria-hidden="true">
          <svg viewBox="0 0 24 24" width="24" height="24">
            <path d="M6 3.5h9l3 3V20.5H6z M15 3.5v3h3 M9 11h6 M9 14.5h6 M9 18h3" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
        <h1 className={`display ${styles.title}`}>This page is blank.</h1>
        <p className={styles.line}>There is nothing at this address. The shelf is this way.</p>
        <div className={styles.actions}>
          <Button href="/" variant="cloth">
            Back to the start
          </Button>
          <Button href="/support/">Support</Button>
        </div>
      </div>
    </div>
  )
}
