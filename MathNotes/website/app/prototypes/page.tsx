import type { Metadata } from 'next'
import type { CSSProperties } from 'react'
import { Log } from '@/components/prototypes/Log'
import { Tag } from '@/components/prototypes/Print'
import { entries, sequence, source } from '@/components/prototypes/shots'
import { Away, Button } from '@/components/ui/Button'
import { SectionHeading } from '@/components/ui/SectionHeading'
import { Tape } from '@/components/ui/Tape'
import { site } from '@/lib/site'
import styles from './prototypes.module.css'

export const metadata: Metadata = {
  title: 'Prototypes',
  description:
    'Screenshots from the making of OwlLuna, in the order they were saved: first tries, options side by side, and the ones that were dropped.',
}

/** Three prints off the pile, fanned under the heading. Each leads to its part of the log. */
const fan = [
  { name: 'ink-samples', turn: -5, tape: 'sage' },
  { name: 'pen-roll-close', turn: 2, tape: 'mustard' },
  { name: 'splash-bento', turn: 6, tape: 'rose' },
] as const

export default function Prototypes() {
  return (
    <>
      <section className="section-tight">
        <div className={`wrap ${styles.intro}`}>
          <div className={styles.lead}>
            <SectionHeading as="h1" eyebrow="Prototypes" title="How it came to look like this" />
            <p className={styles.key}>
              <span className={styles.keyLine} aria-hidden="true">
                <Tag verdict="kept" className={styles.keyTag} />
                went into the app.
              </span>
              <span className={styles.keyLine} aria-hidden="true">
                <Tag verdict="dropped" className={styles.keyTag} />
                did not.
              </span>
              <span className="visually-hidden">A screenshot marked Kept went into the app. One marked Dropped did not.</span>
            </p>
            <ul className={styles.fan}>
              {fan.map(({ name, turn, tape }) => {
                const shot = sequence.find((each) => each.name === name)!
                const lie = { '--shape': shot.width / shot.height, '--turn': `${turn}deg` } as CSSProperties
                return (
                  <li key={name} className={styles.fanned} style={lie}>
                    <a href={`#${shot.entry.id}`} className={`print ${styles.loose}`}>
                      <Tape color={tape} className={styles.tape} />
                      <img src={source(shot, 'thumb')} width={shot.width} height={shot.height} alt="" />
                      <span className="visually-hidden">{shot.entry.title}</span>
                    </a>
                  </li>
                )
              })}
            </ul>
          </div>

          <nav className={styles.contents} aria-label="The parts">
            <p className={styles.band}>In order</p>
            <ol>
              {entries.map((entry, index) => (
                <li key={entry.id}>
                  <a href={`#${entry.id}`} className={styles.row}>
                    <span className={`tabular ${styles.part}`} aria-hidden="true">
                      {String(index + 1).padStart(2, '0')}
                    </span>
                    <span className={styles.what}>{entry.title}</span>
                    <span className={`tabular ${styles.count}`}>
                      {entry.shots.length}
                      <span className="visually-hidden"> screenshots</span>
                    </span>
                  </a>
                </li>
              ))}
            </ol>
          </nav>
        </div>
      </section>

      <section className={styles.pages} aria-label="The screenshots">
        <noscript>
          <style>{`[data-study-art]{opacity:1!important;stroke-dasharray:none!important}`}</style>
        </noscript>
        <div className="wrap">
          <Log />
          <div className={styles.closing}>
            <p>That is the pile. What the finished app does is on the first page, and every line of it is on GitHub.</p>
            <div className={styles.actions}>
              <Button href="/#features">What the app does</Button>
              <Button href={site.repo}>
                The repository on GitHub
                <Away />
              </Button>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
