import type { CSSProperties } from 'react'
import { clothColors, type ClothColor } from '../../ui/ClothCover'
import styles from './covers.module.css'

const riso = { pink: '#ff48b0', yellow: '#ffe800', stock: '#f7f4ec', staple: '#b9b6ae', stapleEdge: '#8e8a80' } as const
const page = { rule: 'rgb(128 164 210 / 0.75)', margin: 'rgb(226 84 84 / 0.7)', ink: '#1b2230', tomato: '#c9452f', mustard: '#e8b023' } as const

const dots = Array.from({ length: 12 }, (_, row) => Array.from({ length: 9 }, (_, column) => ({ x: 9 + column * 38, y: 2 + row * 38 }))).flat()

/** Joined humps standing in for handwriting, a path to a word; each number is a word's length in humps. */
export function words(x: number, y: number, lengths: number[], hump = 6) {
  const fix = (value: number) => Math.round(value * 100) / 100
  let at = x
  return lengths.map((length) => {
    const word = `M${at},${y}q${fix(hump / 2)},${fix(-hump * 1.2)} ${hump},0${`t${hump},0`.repeat(length - 1)}`
    at = fix(at + length * hump + hump * 1.4)
    return word
  })
}

const hand = (x: number, y: number, lengths: number[], hump = 6) => words(x, y, lengths, hump).join('')

const rules = Array.from({ length: 15 }, (_, index) => 63 + index * 17)
const pen = { fill: 'none', stroke: page.ink, strokeLinecap: 'round', strokeLinejoin: 'round' } as const

/** A Print cover: two riso inks overprinted on paper stock, saddle-stitched, with the title on a knockout. */
export function PrintCover({ title }: { title: string }) {
  return (
    <div className={styles.cover}>
      <span className={styles.leaves} aria-hidden="true" />
      <span className={`${styles.board} ${styles.printBoard}`}>
        <svg className={styles.art} viewBox="0 0 300 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
          <rect width="300" height="400" fill={riso.stock} />
          {dots.map((dot) => (
            <circle key={`${dot.x}-${dot.y}`} cx={dot.x} cy={dot.y} r="13.4" fill={riso.pink} />
          ))}
          <circle className={styles.overprint} cx="213.5" cy="111" r="124" fill={riso.yellow} />
          <rect width="24" height="400" fill="rgb(28 28 33 / 0.09)" />
          <rect x="23.4" width="0.8" height="400" fill="rgb(0 0 0 / 0.2)" />
          {[0.28, 0.72].map((at) => (
            <rect key={at} x="10" y={400 * at - 12} width="4" height="24" fill={riso.staple} stroke={riso.stapleEdge} strokeWidth="0.8" />
          ))}
        </svg>
        <span className={styles.printTitle}>{title}</span>
      </span>
    </div>
  )
}

/** A first-page cover: the notebook's opening page behind a cloth spine. */
export function FirstPageCover({ color = 'navy' }: { color?: ClothColor }) {
  return (
    <div className={styles.cover} style={{ '--cover': clothColors[color] } as CSSProperties}>
      <span className={styles.leaves} aria-hidden="true" />
      <span className={`${styles.board} ${styles.pageBoard}`}>
        <svg className={styles.art} viewBox="0 0 300 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
          <path d={rules.map((y) => `M112,${y}H300`).join('')} stroke={page.rule} strokeWidth="1.2" />
          <path d="M27,46H300M112,46V318M27,318H300" fill="none" stroke={page.margin} strokeWidth="2" />
          <rect x="134" y="84" width="74" height="15" fill={page.mustard} opacity="0.55" />
          <path {...pen} strokeWidth="3.6" d={hand(46, 31, [7, 9], 7.5)} />
          <path {...pen} strokeWidth="2.4" d={hand(42, 79, [7]) + hand(42, 164, [5, 3]) + hand(42, 249, [8])} />
          <path
            {...pen}
            strokeWidth="2.4"
            d={
              hand(124, 61, [6, 9, 5]) +
              hand(124, 78, [4, 7, 6, 3]) +
              hand(124, 95, [11, 5]) +
              hand(124, 231, [7, 4, 8]) +
              hand(124, 248, [5, 9]) +
              hand(124, 282, [3, 8, 6]) +
              hand(42, 345, [8, 6, 9, 5]) +
              hand(42, 366, [5, 11])
            }
          />
          <path {...pen} strokeWidth="2.6" d="M181,126 L210,143 V177 L181,194 L152,177 V143 Z M210,143 L236,128 M181,194 V214" />
          <circle {...pen} strokeWidth="2.2" cx="181" cy="160" r="17" />
          <path {...pen} stroke={page.tomato} strokeWidth="2.6" d="M244,124 q10,-9 20,0 t20,0" />
        </svg>
        <span className={styles.spine} aria-hidden="true" />
      </span>
    </div>
  )
}

const padlock = (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M7.5 11V7.8a4.5 4.5 0 0 1 9 0V11" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
    <rect x="4.5" y="10.5" width="15" height="11" rx="1.6" fill="currentColor" />
    <rect x="11" y="14" width="2" height="4" rx="0.6" fill="#f7f1e3" />
  </svg>
)

/** The face of a locked notebook, filling its frame: the label can no longer be read, and a padlock stands over it. */
export function LockedBoard({ color = 'oxblood' }: { color?: ClothColor }) {
  return (
    <div className={styles.face} style={{ '--cover': clothColors[color] } as CSSProperties} role="img" aria-label="A notebook's cover under a padlock">
      <span className={`print ${styles.clothBoard} ${styles.faceBoard}`}>
        <span className={styles.blankLabel}>
          <i />
          <i />
          <i />
        </span>
        <span className={styles.padlock}>{padlock}</span>
      </span>
    </div>
  )
}
