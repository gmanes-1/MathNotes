import styles from './Tape.module.css'

type Props = {
  color?: 'mustard' | 'rose' | 'sage' | 'sky'
  /** Lifted, it is a dashed outline over a wash, as study tape is in the app. */
  lifted?: boolean
  className?: string
}

/** A strip of washi tape with pinked ends and pale diagonal stripes. */
export function Tape({ color = 'mustard', lifted = false, className }: Props) {
  return (
    <span
      className={[styles.tape, styles[color], lifted ? styles.lifted : '', className].filter(Boolean).join(' ')}
      aria-hidden="true"
    />
  )
}
