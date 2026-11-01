import type { Group } from './questions'
import styles from './QuestionGroup.module.css'

type Props = { group: Group; number: number; open?: string }

/** A chapter of questions: a numbered heading beside one ruled board of rows that open. */
export function QuestionGroup({ group, number, open }: Props) {
  const heading = `${group.id}-heading`
  return (
    <section id={group.id} className={styles.group} aria-labelledby={heading}>
      <div className={styles.head}>
        <span className={`print ${styles.number} ${styles[`tile${((number - 1) % 4) + 1}`]}`} aria-hidden="true">
          {String(number).padStart(2, '0')}
        </span>
        <h2 id={heading} className={`display ${styles.title}`}>
          {group.title}
        </h2>
        <p className={`meta ${styles.count}`}>{group.questions.length} questions</p>
      </div>
      <div className={styles.board}>
        {group.questions.map((item) => (
          <details key={item.id} id={item.id} className={styles.item} open={item.id === open}>
            <summary className={styles.question}>
              <span className={styles.row}>
                <span>{item.question}</span>
                <span className={styles.marker} aria-hidden="true" />
              </span>
            </summary>
            <div className={styles.answer}>{item.answer}</div>
          </details>
        ))}
      </div>
    </section>
  )
}
