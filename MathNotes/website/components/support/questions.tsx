import Link from 'next/link'
import { Fragment, type ReactNode } from 'react'
import { site } from '@/lib/site'
import styles from './QuestionGroup.module.css'

export type Question = { id: string; question: string; answer: ReactNode }
export type Group = { id: string; title: string; questions: Question[] }

const more = '⋯'

function Path({ steps }: { steps: string[] }) {
  return (
    <span className={styles.path}>
      {steps.map((step, index) => (
        <Fragment key={step}>
          {index > 0 ? '\u00a0›\u00a0' : null}
          {step === more ? (
            <>
              <span aria-hidden="true">{more}</span>
              <span className="visually-hidden">More</span>
            </>
          ) : (
            step
          )}
        </Fragment>
      ))}
    </span>
  )
}

export const groups: Group[] = [
  {
    id: 'getting-started',
    title: 'Getting started',
    questions: [
      {
        id: 'cost',
        question: 'What does OwlLuna cost?',
        answer: (
          <p>
            Nothing. OwlLuna is free and open source, released under the <a href={site.license}>MIT License</a>. There
            are no subscriptions, no ads and no accounts.
          </p>
        ),
      },
      {
        id: 'requirements',
        question: 'What do I need to run it?',
        answer: (
          <p>
            An iPad with iPadOS 18 or later. It also runs on Apple silicon Macs, as an app designed for iPad. You write
            with an Apple Pencil or, if you choose, with a finger.
          </p>
        ),
      },
      {
        id: 'pdfs',
        question: 'Can I bring in PDFs?',
        answer: (
          <p>
            Yes. A PDF can be imported as a new notebook or inserted into one you already have, and then written on.
            To copy or highlight a PDF’s own text, choose <Path steps={[more, 'Select PDF Text']} />.
          </p>
        ),
      },
      {
        id: 'languages',
        question: 'Which languages is it in?',
        answer: (
          <p>
            English, Spanish, French and German. The translations were machine-made for this release and have not been
            reviewed by native speakers, so corrections are very welcome in{' '}
            <a href={site.issues}>GitHub Issues</a>.
          </p>
        ),
      },
    ],
  },
  {
    id: 'notes-and-icloud',
    title: 'Your notes and iCloud',
    questions: [
      {
        id: 'where-notes-are-kept',
        question: 'Where are my notes kept?',
        answer: (
          <p>
            On your iPad. With iCloud sync on, your notebooks, folders and stickers are also copied to the app’s
            private container in your own iCloud storage, which Apple syncs between your devices. OwlLuna asks before
            it syncs for the first time. Sync is still experimental.
          </p>
        ),
      },
      {
        id: 'icloud-off',
        question: 'How do I turn iCloud sync off?',
        answer: (
          <p>
            In the app, open <Path steps={['Settings', 'iCloud']} /> and turn sync off. The switch can be set at any
            time, also before the iPad is signed in to iCloud. Your writing history is never synced, whichever way
            the switch is set. Each device has its own switch, and turning it
            off does not remove what is already in iCloud. The <Link href="/privacy/#icloud">Privacy Policy</Link> says
            how to remove that.
          </p>
        ),
      },
      {
        id: 'backup',
        question: 'How do I back up, or move to another iPad?',
        answer: (
          <p>
            <Path steps={['Settings', 'Backup']} /> puts the whole library into one file, which you can restore on this or
            another iPad. Restoring adds what is missing and never replaces a notebook. One that differs from the
            backup comes back beside yours as a copy.
          </p>
        ),
      },
      {
        id: 'deleted-notebook',
        question: 'I deleted a notebook by mistake. Can I get it back?',
        answer: (
          <p>
            Yes, for 30 days. A deleted notebook goes to Recently Deleted in the library’s sidebar, and Restore puts it
            back. After 30 days there it is removed for good.
          </p>
        ),
      },
    ],
  },
  {
    id: 'privacy',
    title: 'Privacy',
    questions: [
      {
        id: 'collection',
        question: 'Does OwlLuna collect anything about me?',
        answer: (
          <p>
            No. There are no accounts and no analytics, and handwriting and speech are recognised on the iPad. The{' '}
            <Link href="/privacy/">Privacy Policy</Link> has the details.
          </p>
        ),
      },
      {
        id: 'locks',
        question: 'Does locking a notebook encrypt it?',
        answer: (
          <p>
            No. A lock keeps a notebook closed in the app: it asks for Face ID, Touch ID or the iPad’s passcode every
            time the notebook is opened. Its files are not encrypted beyond what iPadOS does for every app, and a
            backup or an iCloud copy holds it like any other notebook. Making a backup of a library with locked
            notebooks, or sharing one again, asks you to unlock first.
          </p>
        ),
      },
      {
        id: 'spotlight',
        question: 'Can I keep my notebooks out of Spotlight?',
        answer: (
          <p>
            Yes. <Path steps={['Settings', 'Search']} /> in the app turns it off. The index is kept by iPadOS on the iPad, and
            locked notebooks are left out of it.
          </p>
        ),
      },
    ],
  },
  {
    id: 'troubleshooting',
    title: 'Troubleshooting',
    questions: [
      {
        id: 'finger-drawing',
        question: 'Why doesn’t my finger draw?',
        answer: (
          <p>
            Only the Apple Pencil draws until you choose otherwise. In a notebook, choose{' '}
            <Path steps={[more, 'Draw With', 'Pencil and Finger']} /> and a finger draws too.
          </p>
        ),
      },
      {
        id: 'study-guide',
        question: 'Why is there no study guide on my iPad?',
        answer: (
          <p>
            The study guide is written by Apple Intelligence on the iPad itself. It needs iPadOS 26 or later, an iPad
            that has Apple Intelligence, and Apple Intelligence turned on in the iPad’s Settings. When one of these is
            missing, the sheet says which and nothing else happens.
          </p>
        ),
      },
      {
        id: 'transcripts',
        question: 'Why won’t a recording transcribe?',
        answer: (
          <p>
            A recording is transcribed on the iPad, never on a server, and only if the iPad can do that for the
            language spoken. If it can’t, the app says so and sends nothing. If the app says speech recognition is off,
            turn it on for OwlLuna in the iPad’s{' '}
            <Path steps={['Settings', 'Privacy & Security', 'Speech Recognition']} />.
          </p>
        ),
      },
      {
        id: 'features-and-fixes',
        question: 'How do I ask for a feature or send a fix?',
        answer: (
          <p>
            Feature requests go in <a href={site.issues}>GitHub Issues</a>, with the bug reports. To send a fix, read{' '}
            <a href={site.contributing}>CONTRIBUTING.md</a> first: for anything larger than a
            small fix, open an issue before you start.
          </p>
        ),
      },
    ],
  },
]
