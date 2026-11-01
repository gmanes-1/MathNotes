import { Ledger, LedgerRow } from '../ui/Ledger'
import { Reveal } from '../ui/Reveal'
import { SectionHeading } from '../ui/SectionHeading'
import { HoldDemo } from './writing/HoldDemo'
import { PenTray } from './writing/PenTray'
import { TextDemo } from './writing/TextDemo'
import styles from './Writing.module.css'

/** The first of the feature sections: the pens and their tray, draw and hold, and what else the page does. */
export function Writing() {
  return (
    <section className="section" id="writing" aria-labelledby="writing-title">
      <div className="wrap">
        <SectionHeading eyebrow="Writing" title="Pick up a pen and write." id="writing-title">
          <p>
            Handwriting with Apple Pencil runs on PencilKit, with palm rejection, pressure and tilt. The tools around
            the page are the app&rsquo;s own.
          </p>
        </SectionHeading>

        <div className={styles.blocks}>
          <div className={styles.block}>
            <Reveal className={styles.copy}>
              <p className="meta">The tool tray</p>
              <h3 className={`display ${styles.title}`}>Up to eight pens, set up once.</h3>
              <p className={styles.text}>
                One slim board at the foot of the page holds your pens, an eraser and a lasso. Each pen keeps its own
                kind, colour, width and opacity.
              </p>
              <p className={styles.text}>
                Tap a pen to write with it and tap it again to change it. The empty label at the end adds another.
              </p>
              <p className={styles.hint}>
                <span className={styles.pointer} aria-hidden="true" />
                Try the tray. Each pen writes the page again in its own ink.
              </p>
            </Reveal>
            <Reveal className={styles.art} delay={0.08}>
              <PenTray />
            </Reveal>
          </div>

          <div className={`${styles.block} ${styles.flip}`}>
            <Reveal className={styles.copy}>
              <p className="meta">Draw and hold</p>
              <h3 className={`display ${styles.title}`}>Rest the pen and the shape straightens.</h3>
              <p className={styles.text}>
                Draw a line, a circle, an ellipse, a rectangle, a triangle or any figure with straight sides, and rest
                the pen a moment before lifting.
              </p>
              <p className={styles.text}>
                Undo gives your own stroke back, and Settings&nbsp;&rsaquo;&nbsp;Apple Pencil turns it off.
              </p>
              <p className={styles.hint}>
                <span className={styles.pointer} aria-hidden="true" />
                Pick a shape, then Undo.
              </p>
            </Reveal>
            <Reveal className={styles.art} delay={0.08}>
              <HoldDemo />
            </Reveal>
          </div>

          <div className={`${styles.block} ${styles.top}`}>
            <Reveal className={styles.copy}>
              <p className="meta">Also on the page</p>
              <h3 className={`display ${styles.title}`}>Type from ink, small writing and boards with no edges.</h3>
              <p className={styles.text}>
                You choose what draws: Apple Pencil only, a finger as well, or whatever the system setting says. Focus
                mode puts the toolbar away and leaves the page and your tools.
              </p>
              <div className={styles.slip}>
                <TextDemo />
              </div>
            </Reveal>
            <Reveal className={styles.art} delay={0.08}>
              <Ledger title="Writing, continued">
                <LedgerRow label="Handwriting to text">
                  Select ink and choose Turn into Text. It is read on the device, and you can correct the words, copy
                  them or set them on the page in the handwriting&rsquo;s place.
                </LedgerRow>
                <LedgerRow label="Zoom window">
                  A magnified strip along the bottom for writing small and neat. It moves along the line as you write.
                </LedgerRow>
                <LedgerRow label="Zoom">Pinch to zoom up to 5×, with crisp ink and backgrounds at every level.</LedgerRow>
                <LedgerRow label="Whiteboards">
                  A page with no edges, for brainstorming and diagrams. Pinch out to see a whole wall of it.
                </LedgerRow>
                <LedgerRow label="Pencil gestures">
                  Scribble back and forth over ink to erase it, or draw a loop round ink and hold still to select it.
                </LedgerRow>
              </Ledger>
            </Reveal>
          </div>
        </div>
      </div>
    </section>
  )
}
