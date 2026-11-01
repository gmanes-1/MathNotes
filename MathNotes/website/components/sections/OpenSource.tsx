import { site } from '@/lib/site'
import { Away, Button } from '../ui/Button'
import { ClothCover } from '../ui/ClothCover'
import { Reveal } from '../ui/Reveal'
import { SectionHeading } from '../ui/SectionHeading'
import { Stamp } from '../ui/Stamp'
import styles from './OpenSource.module.css'

const guide = site.contributing

/** The closing call: the repository, its issues, the contributing guide and the licence. */
export function OpenSource() {
  return (
    <section className="section" aria-labelledby="open-source-title">
      <div className={`wrap ${styles.layout}`}>
        <div className={styles.intro}>
          <SectionHeading id="open-source-title" eyebrow="Open source" title="Read the code, or help write it.">
            <p>
              OwlLuna is released under the MIT License, and the whole project is on GitHub. Clone it, build it
              yourself, and see what it does with your notes.
            </p>
          </SectionHeading>

          <Reveal className={styles.actions}>
            <Button href={site.repo} variant="cloth" size="large">
              The repository on GitHub
              <Away />
            </Button>
            <Button href={site.license} size="large">
              MIT License
              <Away />
            </Button>
          </Reveal>
        </div>

        <Reveal className={styles.shelf} tilt={5} rise={40}>
          <div className={styles.cover} aria-hidden="true">
            <ClothCover title="OwlLuna" meta="MIT License" color="mustard" ribbon />
          </div>
        </Reveal>

        <Reveal className={styles.notice} delay={0.08}>
          <Stamp
            tone="mustard"
            title="Found a problem, or missing a feature?"
            actions={
              <>
                <Button href={guide} className={styles.reply}>
                  Contributing guide
                  <Away />
                </Button>
                <Button href={site.issues} className={styles.reply}>
                  Open an issue
                  <Away />
                </Button>
              </>
            }
          >
            <p>
              Bug reports and feature requests go in GitHub Issues. To send a change of your own, read the
              contributing guide first: for anything larger than a small fix, it asks for an issue before the code.
            </p>
          </Stamp>
        </Reveal>
      </div>
    </section>
  )
}
