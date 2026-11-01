'use client'

import { useState, type CSSProperties } from 'react'
import { Reveal } from '@/components/ui/Reveal'
import { Print } from './Print'
import { Viewer } from './Viewer'
import { entries, sequence, type Entry } from './shots'
import styles from './Log.module.css'

const placed = new Map(sequence.map((shot) => [shot.name, shot]))

/** The screenshots as a log: a note for each part of the work, and its prints on the board beside it. */
export function Log() {
  const [open, setOpen] = useState<number | null>(null)

  return (
    <>
      <div className={styles.log}>
        {entries.map((entry, part) => (
          <section key={entry.id} id={entry.id} className={styles.entry} aria-labelledby={`${entry.id}-title`}>
            <Reveal className={styles.note}>
              <Leaf part={part + 1} />
              <h2 id={`${entry.id}-title`} className={`display ${styles.title}`}>
                {entry.title}
              </h2>
              <p className={styles.words}>{entry.note}</p>
              {entry.credit ? (
                <p className={styles.words}>
                  {entry.credit.lead}{' '}
                  <a href={entry.credit.url} target="_blank" rel="noopener noreferrer">
                    {entry.credit.name}
                    <span className="visually-hidden"> (opens in a new tab)</span>
                  </a>
                  .
                </p>
              ) : null}
              <p className="meta">{span(entry)}</p>
            </Reveal>

            <div className={styles.board}>
              {entry.bands.map((band, index) => (
                <div key={index} className={styles.band} style={{ '--columns': band.map(([share]) => `${share}fr`).join(' ') } as CSSProperties}>
                  {band.map(([, ...names], column) => (
                    <div key={names[0]} className={styles.column}>
                      {names.map((name, row) => (
                        <Print key={name} shot={placed.get(name)!} onOpen={setOpen} delay={column * 0.07 + row * 0.05} />
                      ))}
                    </div>
                  ))}
                </div>
              ))}
            </div>
          </section>
        ))}
      </div>
      <Viewer open={open} onChange={setOpen} />
    </>
  )
}

/** A numbered leaf, like one off a tear-off pad, saying which part of the log this is. */
function Leaf({ part }: { part: number }) {
  return (
    <p className={`print ${styles.leaf}`}>
      <span className={`cloth ${styles.label}`}>Part</span>
      <span className={styles.figure}>{String(part).padStart(2, '0')}</span>
    </p>
  )
}

function span(entry: Entry): string {
  const first = placed.get(entry.shots[0].name)!.number
  const last = first + entry.shots.length - 1
  return `${entry.shots.length} screenshots · Nos. ${first} to ${last}`
}
