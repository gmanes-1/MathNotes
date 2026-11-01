'use client'

import { motion, useSpring } from 'motion/react'
import { useEffect, useId, useRef } from 'react'
import { ease } from '@/lib/motion'
import { about, inks, useScene } from '../scene'
import styles from '../BentoHero.module.css'

const tones = {
  body: '#8C5A32',
  bodyDark: '#6E4424',
  face: '#E9B48A',
  belly: '#F4C69E',
  feet: '#F0922A',
  iris: '#F7C73A',
  irisRing: '#E8891E',
  pupil: '#2B1A12',
  beak: '#F07019',
  pad: '#F6F0DC',
  pencil: '#F2A531',
  pencilShade: '#D4821C',
  pencilWood: '#E8C08A',
  pencilTip: '#4A4A4A',
  eraser: '#F2A4B2',
  ferrule: '#C9CCD2',
}

const eyes = [
  { x: 148, y: 144 },
  { x: 252, y: 144 },
]
const feet = [143, 158, 173, 213, 228, 243]
const chin = about(200, 236)
const shoulder = about(315.2, 213.2)
/** The pencil's bobbing while it writes, on top of the arm coming up level. */
const bobbing = [7.7, 0.3, 9, -1.6, 7.05, -3.5, 5.1, -5.4, 0]
const lidTravel = 94

/** The owl tile: the owl hops onto its perch, writes a line, looks up and blinks. */
export function OwlTile() {
  const { play, loop, at, beat, draw } = useScene()
  const id = useId()
  const head = useRef<SVGCircleElement>(null)
  const gazeX = useSpring(0, { stiffness: 140, damping: 18 })
  const gazeY = useSpring(0, { stiffness: 140, damping: 18 })
  const startsFollowing = at(2300)

  useEffect(() => {
    if (!loop) {
      gazeX.set(0)
      gazeY.set(0)
      return
    }
    const follow = (event: PointerEvent) => {
      const box = head.current?.getBoundingClientRect()
      if (!box || event.pointerType === 'touch') return
      const dx = event.clientX - (box.left + box.width / 2)
      const dy = event.clientY - (box.top + box.height / 2)
      const distance = Math.hypot(dx, dy) || 1
      const reach = Math.min(1, distance / 280)
      gazeX.set((dx / distance) * 10 * reach)
      gazeY.set((dy / distance) * 8 * reach)
    }
    const timer = window.setTimeout(() => window.addEventListener('pointermove', follow), startsFollowing * 1000)
    return () => {
      window.clearTimeout(timer)
      window.removeEventListener('pointermove', follow)
    }
  }, [loop, startsFollowing, gazeX, gazeY])

  return (
    <div className={styles.owl}>
      <motion.span className={styles.perch} style={{ originX: 0 }} {...beat({ scaleX: 0 }, { scaleX: 1 }, 330, { duration: 0.6, ease: ease.glide })} />
      <svg className={styles.art} viewBox="20 0 360 400" preserveAspectRatio="xMidYMax meet" role="img" aria-label="An owl in round glasses writing on a notepad with a pencil">
        <motion.circle cx="200" cy="204" r="156" fill={inks.moonLight} style={about(200, 204)} {...beat({ scale: 0 }, { scale: 1 }, 350, { duration: 0.7, ease: ease.bounce })} />
        <motion.g {...beat({ y: 470 }, { y: 0 }, 470, { type: 'spring', duration: 0.9, bounce: 0.32 })}>
          <g transform="translate(200 378) scale(0.93) translate(-200 -378)" strokeLinecap="round" strokeLinejoin="round">
            {feet.map((x) => (
              <rect key={x} x={x} y={x === 158 || x === 228 ? 360 : 358} width="14" height="25" rx="7" fill={tones.feet} stroke={inks.ink} strokeWidth="5" />
            ))}
            <path d="M200,150 C275,150 316,215 316,278 C316,338 268,368 200,368 C132,368 84,338 84,278 C84,215 125,150 200,150 Z" fill={tones.body} stroke={inks.ink} strokeWidth="6" />
            <ellipse cx="200" cy="298" rx="70" ry="62" fill={tones.belly} />
            <path d="M210,258 q7,9 14,0 M238,266 q7,9 14,0 M222,284 q7,9 14,0 M210,338 q7,9 14,0 M236,330 q7,9 14,0" fill="none" stroke={tones.body} strokeWidth="4" />

            <motion.g style={chin} {...beat({ rotate: -5 }, { rotate: 3.5 }, 1540, { duration: 0.62, ease: ease.bounce })}>
              <path d="M98,116 L80,26 L164,60 Z M302,116 L320,26 L236,60 Z" fill={tones.bodyDark} stroke={inks.ink} strokeWidth="6" />
              <path d="M200,40 C270,40 324,70 324,142 C324,206 270,236 200,236 C130,236 76,206 76,142 C76,70 130,40 200,40 Z" fill={tones.body} stroke={inks.ink} strokeWidth="6" />
              <circle ref={head} cx="200" cy="144" r="1" fill="none" />
              {eyes.map((eye) => (
                <circle key={eye.x} cx={eye.x} cy={eye.y} r="62" fill={tones.face} />
              ))}
              {eyes.map((eye) => (
                <circle key={eye.x} cx={eye.x} cy={eye.y} r="45" fill={inks.white} stroke={inks.ink} strokeWidth="6" />
              ))}
              <motion.g {...beat({ x: -7, y: 7.8 }, { x: 0, y: 0 }, 1560, { duration: 0.32, ease: ease.glide })}>
                <motion.g style={{ x: gazeX, y: gazeY }}>
                  {eyes.map((eye) => (
                    <g key={eye.x}>
                      <circle cx={eye.x} cy={eye.y} r="26" fill={tones.iris} stroke={tones.irisRing} strokeWidth="6" />
                      <circle cx={eye.x} cy={eye.y} r="14" fill={tones.pupil} />
                      <circle cx={eye.x + 7} cy={eye.y - 8} r="5" fill={inks.white} />
                    </g>
                  ))}
                </motion.g>
              </motion.g>
              {play && eyes.map((eye, index) => (
                <g key={eye.x} clipPath={`url(#${id}-eye-${index})`}>
                  <clipPath id={`${id}-eye-${index}`}>
                    <circle cx={eye.x} cy={eye.y} r="42" />
                  </clipPath>
                  <motion.g
                    initial={{ y: -lidTravel }}
                    animate={loop ? { y: [-lidTravel, 0, 0, -lidTravel, -lidTravel] } : { y: -lidTravel }}
                    transition={loop ? { duration: 2.6, times: [0, 0.035, 0.048, 0.09, 1], repeat: Infinity, delay: at(1700), ease: 'easeInOut' } : { duration: 0.1 }}
                  >
                    <rect x={eye.x - 45} y="97" width="90" height="94" fill={tones.face} />
                    <path d={`M${eye.x - 45},191 h90 M${eye.x - 24},150 q24,18 48,0`} fill="none" stroke={inks.ink} strokeWidth="5" />
                  </motion.g>
                </g>
              ))}
              <path d="M184,176 L216,176 L200,208 Z" fill={tones.beak} stroke={inks.ink} strokeWidth="5" />
            </motion.g>

            <g transform="rotate(-7 138 300)">
              <rect x="80" y="240" width="118" height="110" rx="5" fill={tones.pad} stroke={inks.ink} strokeWidth="5" />
              <path d="M80,245 a5,5 0 0 1 5,-5 h108 a5,5 0 0 1 5,5 v14 h-118 z" fill={inks.ink} />
              <path d="M92,286 h94 M92,306 h94 M92,326 h94" fill="none" stroke={inks.rule} strokeWidth="2.5" />
              <path
                d="M96,281 q5,-9 10,0 t10,0 t10,0 t10,0 m9,0 q5,-9 10,0 t10,0 t10,0 M96,301 q5,-9 10,0 t10,0 m9,0 q5,-9 10,0 t10,0 t10,0 t10,0 t10,0"
                fill="none"
                stroke={inks.ink}
                strokeWidth="3.2"
              />
              <motion.path
                d="M96,321 q4,-9 8,0 t8,0 t8,0 m8,0 q4.7,-9 9.3,0 t9.3,0 t9.3,0 t9.3,0 t9.3,0 t9.3,0"
                fill="none"
                stroke={inks.ink}
                strokeWidth="3.2"
                {...draw(1040, { duration: 0.52, ease: 'linear' })}
              />
            </g>

            <path d="M88,216 C58,246 54,300 76,332 C100,320 110,278 104,238 Z" fill={tones.bodyDark} stroke={inks.ink} strokeWidth="5" />
            <motion.g
              style={shoulder}
              initial={{ rotate: -30, x: -58.3, y: bobbing[0] }}
              animate={play ? { rotate: 0, x: 0, y: bobbing } : { rotate: -30, x: -58.3, y: bobbing[0] }}
              transition={{
                rotate: { delay: at(800), duration: 0.52, ease: ease.bounce },
                x: { delay: at(1040), duration: 0.52, ease: 'linear' },
                y: { delay: at(1040), duration: 0.52, ease: 'linear' },
              }}
            >
              <path d="M318,208 C342,254 306,298 254,284 C260,244 288,220 318,208 Z" fill={tones.bodyDark} stroke={inks.ink} strokeWidth="5" />
              <g transform="translate(186 314) rotate(-38)">
                <rect x="28" y="-11" width="124" height="22" fill={tones.pencil} />
                <rect x="28" y="3" width="124" height="8" fill={tones.pencilShade} />
                <path d="M0,0 L28,-11 V11 Z" fill={tones.pencilWood} />
                <path d="M0,0 L11,-4.4 V4.4 Z" fill={tones.pencilTip} />
                <rect x="152" y="-11" width="12" height="22" fill={tones.ferrule} />
                <path d="M164,-11 h10 a6,6 0 0 1 6,6 v10 a6,6 0 0 1 -6,6 h-10 z" fill={tones.eraser} />
                <path d="M0,0 L28,-11 H174 a6,6 0 0 1 6,6 v10 a6,6 0 0 1 -6,6 H28 Z" fill="none" stroke={inks.ink} strokeWidth="5" />
                <path d="M152,-11 V11 M164,-11 V11" fill="none" stroke={inks.ink} strokeWidth="3" />
                <ellipse cx="98" cy="1" rx="11" ry="18" fill={tones.bodyDark} stroke={inks.ink} strokeWidth="4" />
              </g>
            </motion.g>
          </g>
        </motion.g>
      </svg>
      <motion.span className={`${styles.label} ${styles.labelLead}`} {...beat({ opacity: 0, y: '90%' }, { opacity: 1, y: '0%' }, 500, { duration: 0.45, ease: ease.glide })}>
        Notebook
      </motion.span>
    </div>
  )
}
