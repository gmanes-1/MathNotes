import { BentoHero } from '@/components/hero/BentoHero'
import { More } from '@/components/sections/More'
import { Notebooks } from '@/components/sections/Notebooks'
import { OpenSource } from '@/components/sections/OpenSource'
import { Pledge } from '@/components/sections/Pledge'
import { PrivacySummary } from '@/components/sections/PrivacySummary'
import { Prototypes } from '@/components/sections/Prototypes'
import { Story } from '@/components/sections/Story'
import { Study } from '@/components/sections/Study'
import { Writing } from '@/components/sections/Writing'

export default function Home() {
  return (
    <>
      <BentoHero />
      <Pledge />
      <div id="features">
        <Writing />
        <Notebooks />
        <Study />
        <More />
      </div>
      <PrivacySummary />
      <Story />
      <Prototypes />
      <OpenSource />
    </>
  )
}
