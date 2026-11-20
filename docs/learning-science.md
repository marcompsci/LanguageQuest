# How Language Quest helps players remember (v1.0)

This page explains what the research says about remembering faster and longer, and where each idea lives in the app. Researched November 19, 2026.

## What the research says

| Finding | What it means | Source |
|---|---|---|
| **Retrieval practice (the testing effect)** | Pulling a word out of memory makes it stick better than reading it again. Meta-analyses put the advantage at about half to two-thirds of a standard deviation (Rowland 2014: g ≈ 0.50; Adesope et al. 2017: g ≈ 0.70). | Cognitive Research: Principles and Implications (2023) review |
| **Spacing** | Practice spread out over days beats the same practice crammed into one session (Latimier et al. 2021: g ≈ 0.74 for spaced over massed retrieval). | Educational Psychology Review (2021); PMC review (Yan, Sana & Carvalho 2024) |
| **Expanding vs. even gaps** | Growing gaps between reviews were *not* reliably better than even gaps (g ≈ 0.03). What matters is spacing at all. | Latimier et al. 2021 |
| **Successive relearning** | Retrieve until correct, then come back in later sessions and do it again. Dunlosky et al. (2013) rated testing and spacing the two most useful study techniques; successive relearning combines them. | Rawson & Dunlosky; Dunlosky et al. 2013 |
| **Interleaving** | Mixing different items and skills often beats practicing one at a time (Brunmair & Richter 2019: g ≈ 0.42), though not in every case. | PMC review (Yan, Sana & Carvalho 2024) |
| **Corrective feedback and errors** | Mistakes followed straight away by the right answer are well remembered (the hypercorrection effect, Butterfield & Metcalfe 2001); feedback should come right after the error. | Psychonomic Bulletin & Review; PMC |
| **Half-life model of forgetting** | Duolingo models the chance of recalling a word as p = 2^(−Δ/h): Δ is the time since practice, h is the word's "half-life". Settles & Meeder report this improved daily engagement by 12% in a live test. | Settles & Meeder, ACL 2016 |
| **Intensive programs (DLI, CIA's language school)** | Military and intelligence language schools rely on intensity and immersion: many hours a day of structured practice in the language, with constant testing. There's no secret shortcut; the methods are the ones above, used every day. | Defense Language Institute; CIA Intelligence Language Institute |

## What keeps people coming back (Duolingo)

| Finding | Source |
|---|---|
| Learners on a 7-day streak are 2.4× more likely to come back the next day. | Duolingo blog, "Improving the streak" |
| Streak freezes reduced churn by about 21% for learners at risk of breaking a streak. | Case study citing Duolingo |
| Reminders are chosen by a "recovering bandit": the app learns which messages bring each person back, and rests a message after it's used, because messages lose power when repeated. This raised daily active users 0.5% and new-user retention 2%. | Yancey & Settles, KDD 2020 |
| Downsides: losing a streak can make people quit, and streaks can turn into opening the app just to keep the number. | The Decision Lab, "Streak Creep" |

## Where each idea is in the app

| Idea | In Language Quest |
|---|---|
| Retrieval practice | **5-question lesson quiz after every quest** (`RetentionQuiz`), the **memory check**, reviews, Listen & Type. |
| Production beats recognition | Quiz questions go from easier to harder: see the word, hear the word, pick the word, then **type it from memory** twice. |
| Prioritize what's about to be forgotten | Each word's chance of being remembered is estimated with the **half-life model** (`RecallModel`). The quiz picks words that are new in the lesson, fading, or missed before; each question shows why it was chosen. |
| Successive relearning | Missed questions **come back at the end of the quiz** until they're answered right. They also come back sooner in reviews. A word is **"locked in"** after 3 correct recalls after a break. |
| Spacing | The spaced review scheduler (unchanged), plus memory checks and the **Welcome back** card after 2+ days away. |
| Interleaving | Quiz words and question types are mixed. A lesson quiz can include a fading word from an earlier lesson. |
| Immediate corrective feedback | After every answer: the word, its meaning and its sound, right away. |
| Progress over time | **My progress**: words remembered now (estimated), locked in and fading; quiz scores by week (chart); recent quizzes; words to practice. |
| Streaks (with the downsides handled) | **Daily streak with 2 free freezes a week**. Only real practice counts (a lesson, quiz, memory check or review), not opening the app. A missed streak restarts with "Fresh start!" and keeps your best; nothing warns about losing. |
| Bandit-style reminders | **Come-back reminders** (`SmartReminders`): timed to when the player usually plays, chosen by open rate with recently used messages resting, eligible messages only (streak, words due, new quest, comeback). Fewer after a break: day 0, 1, 2, 3, 5, 7 and 14. Never after 8:30 pm. All on the device. |

## What we deliberately didn't copy

- **No loss-aversion messages** ("your streak will be lost!"). The audience is 11+, and research shows broken streaks can push people to quit.
- **No leaderboards against strangers**: they'd need accounts and a server, which would mean collecting children's data.
- **No server-side machine learning**: every model here runs on the phone, so the privacy label stays "Data Not Collected".

## Sources

- [Latimier, Peyre & Ramus (2021), A Meta-Analytic Review of the Benefit of Spacing out Retrieval Practice Episodes on Retention](https://link.springer.com/10.1007/s10648-020-09572-8)
- [Cognitive perspectives on maintaining physicians' medical expertise IV: testing (2023)](https://link.springer.com/10.1186/s41235-023-00508-8)
- [Yan, Sana & Carvalho (2024), One size does not fit all (spacing, interleaving, retrieval)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10950551)
- [Spaced retrieval practice and successive relearning, Educational Psychology Review (2023)](https://link.springer.com/article/10.1007/s10648-023-09809-2)
- [Rawson & Dunlosky, Successive Relearning (2022)](https://journals.sagepub.com/doi/full/10.1177/09637214221100484)
- [Hypercorrection: errors corrected with feedback](https://pmc.ncbi.nlm.nih.gov/articles/PMC4036076)
- [Settles & Meeder (2016), A Trainable Spaced Repetition Model for Language Learning](https://preview.aclanthology.org/fix_video/P16-1174.pdf)
- [Yancey & Settles (2020), A Sleeping, Recovering Bandit Algorithm for Optimizing Recurring Notifications](https://research.Duolingo.com/papers/yancey.kdd20.pdf)
- [Duolingo blog: Improving the streak](https://blog.duolingo.com/improving-the-streak)
- [The Decision Lab: Streak Creep](https://thedecisionlab.com/insights/consumer-insights/streak-creep-the-perils-of-too-much-gamification)
- [Defense Language Institute: Language Schools](https://www.dliflc.edu/academics/language-schools)
- [CIA: Intelligence Language Institute](https://www.cia.gov/careers/language-opportunities/intelligence-language-institute/)
