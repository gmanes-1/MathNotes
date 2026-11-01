import { Pile } from '../prototypes/Pile'
import { Button } from '../ui/Button'
import { SectionHeading } from '../ui/SectionHeading'
import styles from './Prototypes.module.css'

/** The screenshots saved while the app was being finished, loose on a desk, with the way to them in order. */
export function Prototypes() {
  return (
    <section id="prototypes" className="section" aria-labelledby="prototypes-title">
      <div className="wrap">
        <div className={styles.head}>
          <SectionHeading id="prototypes-title" eyebrow="Prototypes" title="The drafts, tipped out on the desk.">
            <p>
              Screenshots saved while the app was being finished: first tries, options side by side, and a few dead
              ends.
            </p>
          </SectionHeading>
          <div className={styles.action}>
            <Button href="/prototypes/">See them in order</Button>
          </div>
        </div>
        <Pile />
      </div>
    </section>
  )
}
