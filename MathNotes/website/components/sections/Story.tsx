import { IndexCard } from '../ui/IndexCard'
import { Ledger, LedgerRow } from '../ui/Ledger'
import { Reveal } from '../ui/Reveal'
import { SectionHeading } from '../ui/SectionHeading'
import { Tape } from '../ui/Tape'
import { Signature } from './story/Signature'
import { Stamped } from './story/Stamped'
import { TickBox } from './story/TickBox'
import styles from './Story.module.css'

/** The developer's own note, as a letter on a notebook page beside a receipt for what a notebook costs. */
export function Story() {
  return (
    <section id="story" className={`section ${styles.story}`} aria-labelledby="story-title">
      <div className="wrap">
        <SectionHeading id="story-title" eyebrow="Built by Owais Khan" title="A note from the developer" />

        <div className={styles.layout}>
          <Reveal className={styles.letter}>
            <article className={`print ${styles.sheet}`}>
              <Tape className={styles.tape} />
              <span className={styles.rule} aria-hidden="true" />
              <span className={`${styles.hole} ${styles.holeHead}`} aria-hidden="true" />
              <span className={`${styles.hole} ${styles.holeMiddle}`} aria-hidden="true" />
              <span className={`${styles.hole} ${styles.holeFoot}`} aria-hidden="true" />
              <div className={styles.head} aria-hidden="true" />

              <div className={`display-text ${styles.body}`}>
                <p>
                  When I was a student, there were only a handful of really good apps for taking notes by hand on an
                  iPad. Every one of them wanted money: a subscription, or a one-time fee if you were lucky. I used to
                  wonder whether a free app could ever be as good as the paid ones.
                </p>
                <p className={styles.noted}>
                  Then I graduated, and started working, and the question came with me. It sat in the back of my head
                  like a to-do I never ticked.
                  <TickBox ticked={false} className={`${styles.doodle} ${styles.doodleLast}`} />
                </p>
                <p>
                  Because look at the sums. First you buy the iPad. Then you buy the Pencil, which is sold separately.
                  And then, once you own both, an app asks for a monthly fee before you may write on the glass you
                  have already paid for. Paper has its faults, but it has never once sent me a renewal notice.
                </p>
                <p>So I built the app myself, from scratch. The idea was simple enough to fit on an index card:</p>

                <div className={styles.slot}>
                  <Tape color="sage" className={styles.slotTape} />
                  <IndexCard side={' '} className={styles.card}>
                    <ol role="list" className={styles.principles}>
                      <li>
                        <span className={styles.numeral} aria-hidden="true">1.</span>
                        <span>
                          <strong>Free.</strong> No subscription, no one-time fee, nothing to unlock.
                        </span>
                      </li>
                      <li>
                        <span className={styles.numeral} aria-hidden="true">2.</span>
                        <span>
                          <strong>Open source.</strong> Every line is on GitHub, so you don&rsquo;t have to take my
                          word for it.
                        </span>
                      </li>
                      <li>
                        <span className={styles.numeral} aria-hidden="true">3.</span>
                        <span>
                          <strong>No data collection.</strong> Your notes are yours. I never see them, and frankly I
                          have enough of my own handwriting to decipher.
                        </span>
                      </li>
                    </ol>
                  </IndexCard>
                </div>

                <p className={styles.noted}>
                  <TickBox className={`${styles.doodle} ${styles.doodleFirst}`} delay={0.2} />
                  &ldquo;Simple&rdquo; turned out to take a while. But here it is: the app I was looking for back then.
                  I hope it is the one you were looking for too.
                </p>
                <div className={styles.signed}>
                  <Signature className={styles.signature} />
                </div>
              </div>
            </article>
          </Reveal>

          <Reveal className={styles.aside} delay={0.08}>
            <div className={styles.receipt}>
              <Stamped word="Free">
                <Ledger title="What a notebook costs">
                  <LedgerRow label="iPad">Bought.</LedgerRow>
                  <LedgerRow label="Apple Pencil">Bought. Charged, too.</LedgerRow>
                  <LedgerRow label="A notes app">A subscription. Or a one-time fee, if you were lucky.</LedgerRow>
                  <LedgerRow label="OwlLuna">Nothing.</LedgerRow>
                </Ledger>
              </Stamped>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  )
}
