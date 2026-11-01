'use client'

import { motion, useReducedMotion } from 'motion/react'
import { useRef } from 'react'
import { ease } from '@/lib/motion'
import { useArrival } from '@/components/ui/useArrival'

const capitals: Record<string, [number, string]> = {
  A: [15.4, 'M0,21.1 L7.6,-0.2 L15.4,21 M3.3,13.7 L12.3,13.5'],
  H: [14.3, 'M-0.2,-0.2 L-0.1,20.6 M14.1,0.3 L14.2,21.1 M-0.2,10.7 L14.1,10.7'],
  I: [4.3, 'M2.2,0 L2.1,21'],
  K: [13.7, 'M0,0 L0,21 M12.6,0.4 L0.5,12.7 M4.7,9.1 L13.7,21.5'],
  N: [14.4, 'M0.1,21.1 L0,0 L14.3,20.8 L14.4,-0.2'],
  O: [15.6, 'M8.6,-0.2 Q-0.3,-0.4 -0.1,10.6 Q0.2,21.6 7.9,21.3 Q15.8,21 15.5,10.2 Q15.2,-0.6 6.9,0.3'],
  S: [13.1, 'M11.1,3.2 Q5.1,-2.6 1.1,3.2 Q-2.4,8.9 5.6,10.5 Q14,12.5 11.1,17.8 Q7,23.5 -0.5,17.8'],
  W: [20.4, 'M-1.2,0 L4.4,21 L9.2,8.4 L14.9,21 L19,0.1'],
}

const capHeight = 21
const slant = 0.158
const letterGap = 5.7
const wordGap = 13
const unevenness: [number, number][] = [
  [-0.9, -2.7], [-0.7, 0.65], [0, -0.3], [0.2, -1.05], [0.95, -2.2], [-0.85, -2.9],
  [0.4, -0.8], [-0.3, 0.4], [0.7, -1.9], [-0.6, -0.5], [0.1, -2.5], [0.8, 0.2],
]

function sign(name: string) {
  const lean = (Math.atan(slant) * 180) / Math.PI
  let x = 0
  let count = 0
  const letters: { d: string; transform: string }[] = []
  for (const letter of name.toUpperCase()) {
    if (letter === ' ') {
      x += wordGap - letterGap
      continue
    }
    const [width, d] = capitals[letter]
    const [drop, turn] = unevenness[count % unevenness.length]
    letters.push({
      d,
      transform: `translate(${x} ${drop}) rotate(${turn} ${width / 2} ${capHeight / 2}) translate(${slant * (capHeight / 2)} 0) skewX(${-lean})`,
    })
    x += width + letterGap
    count += 1
  }
  return { letters, width: x - letterGap }
}

const name = 'Owais Khan'
const hand = sign(name)
const flourish = `M-3,32 Q${hand.width * 0.28},26.5 ${hand.width * 0.55},30.5 T${hand.width + 5},27.5`
const pen = { fill: 'none', strokeLinecap: 'round', strokeLinejoin: 'round' } as const
const dry = { pathLength: 0, opacity: 0 }
const inked = { pathLength: 1, opacity: 1 }

/** The letter's signature, printed in the hand of the splash's note page and underlined, one stroke after another. */
export function Signature({ className }: { className?: string }) {
  const ref = useRef<SVGSVGElement>(null)
  const { arrived } = useArrival(ref, { amount: 0.9 })
  const still = useReducedMotion()
  const stroke = (duration: number, after: number) => {
    if (!arrived) return { duration: 0 }
    if (still) return { duration: 0, opacity: { duration: 0.3 } }
    return { duration, ease: ease.inOut, delay: after, opacity: { duration: 0.01, delay: after } }
  }

  return (
    <svg ref={ref} className={className} viewBox={`-6 -6 ${hand.width + 16} 44`} role="img" aria-label={name}>
      {hand.letters.map((letter, index) => (
        <g key={index} transform={letter.transform}>
          <motion.path
            d={letter.d}
            {...pen}
            strokeWidth="2.7"
            style={{ stroke: 'var(--ink)' }}
            initial={false}
            animate={arrived ? inked : dry}
            transition={stroke(0.24, 0.15 + index * 0.075)}
          />
        </g>
      ))}
      <motion.path
        d={flourish}
        {...pen}
        strokeWidth="2.4"
        style={{ stroke: 'var(--tomato)' }}
        initial={false}
        animate={arrived ? inked : dry}
        transition={stroke(0.4, 0.15 + hand.letters.length * 0.075 + 0.2)}
      />
    </svg>
  )
}
