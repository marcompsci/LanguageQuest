# App Review notes: Language Quest 1.1.0

Paste the "Review Notes" section into App Store Connect › TestFlight › Test Information (Beta App Review) and, later, into App Review Information for the App Store. Guideline 2.3.1(a) asks for features to be described specifically, so keep this list current with every build.

---

## Review Notes (copy from here)

Language Quest is an offline language-learning game for ages 11 and up. Players explore a pixel-art village, talk to characters in the language they are learning, complete short quests, and play word games.

NO SIGN-IN. There are no accounts, so no demo account is needed. On first launch, create an explorer: tap Next through the short setup, choose any age band (11–12, 13–15 or 16+), choose a language (Spanish is the most complete) and a variety, enter any name, and tap "Start exploring". A short placement quiz is offered next; tap "I'm new to Spanish: skip" to go straight to the village.

NO NETWORK, ADS, ANALYTICS OR TRACKING. All data stays on the device. Privacy label: Data Not Collected.

IN-APP PURCHASE: FAMILY PLUS (auto-renewable subscription, Apple In-App Purchase only).
- Products: com.phoronomics.languagequest.familyplus.monthly and .yearly, one subscription group, 1-week free trial.
- What it is: an ongoing course service. It opens Units 2 and 3 of Spanish, French and Japanese (new units are added over time), two extra games (Memory Match, Speed duel) and up to 4 explorers. Unit 1 of every language, every starter course, reviews, lesson quizzes, memory checks, parent tools and accessibility stay free.
- Where: ☰ › Family Plus, or tap a "Family Plus" lock (Quest journal, Your units, Memory Match, Speed duel). Every path shows the parent question first (the answer is shown as a sum or multiplication), then the offer with price, period, renewal and cancel terms, Restore purchases, Manage subscription, and links to the Terms of Use (Apple standard EULA) and privacy policy.
- To test a purchase: in the offer, a parent must first switch on "Allow purchases"; then use a Sandbox account.
- Units a player started before 1.0 stay open without a subscription.

HOW TO NAVIGATE
- Main menu: explorer level card, Recent lesson (Continue, plus a multiple-choice quick flashcard), Bonus lesson, Daily challenges, Weekly goal, then languages in three sections: Choose a language; African Languages; Old Languages.
- Tap a language to open its page: Play (enters the village), Today, Word of the day, Games, Flashcards, Bonus lesson, Write Out, Word Library, Unit quizzes (and Kana Dojo for Japanese).
- ☰ (top right): Review, Phrasebook, Word Library, Write Out, Bonus lesson, Quest journal, Wardrobe, Bag and badges, Mistakes notebook, Trophies, My stats, Settings, Parents, Privacy policy.
- In the village: use the arrow pad to walk; "Go to" walks to a character; the house button returns to the language page; the flag button switches language.

NEW IN 1.1
- Today's path on the language page: memory check, next quest, review; each ticks off when done.
- Warm-up: before a new quest, up to 3 optional guesses about its words ("Skip the warm-up" is always there). Guesses are not recorded as mistakes.
- Quiz upgrades: picture cues, fill-in-the-blank sentences in memory checks, "You'll see this again in N days", an optional first-letter Hint on typed questions, accent keys (á, ñ, ç, ß…) above the keyboard, and VoiceOver announcements of each result.
- After a miss, the player can write a private memory hook (stored on the device as a word note).
- Memory check: choose 5 or 10 questions. Lesson quizzes can be retaken from the Quest journal.
- Streak calendar and personal bests in My progress; outfits for 7- and 30-day streaks (cosmetic only); a weekly recap card early in the week.
- Parents area: a Learning section per explorer (quizzes, average, streak, words locked in).
- Family Plus: if notifications are already allowed, a local heads-up 2 days before a free trial ends.
- Siri & Shortcuts: "Start a memory check in Language Quest", "Continue learning in Language Quest". They only open the app.

NEW IN 1.0
- Lesson quiz: every finished quest ends with 5 questions on the words that most need remembering (new in the lesson, starting to fade, or missed before), from recognition to typing from memory. Missed words come back at the end of the quiz.
- Memory check: the same 5-question quiz on fading words, from the language page or a "Welcome back" card after 2+ days away.
- My progress: words remembered now (estimated), locked-in and fading words, quiz scores by week, recent quizzes.
- Daily streak with 2 free streak freezes a week; a lesson, quiz, memory check or review counts. Missed days restart gently ("Fresh start!").
- Come-back reminders: off by default; the player can turn them on in Settings (the app explains, then iOS asks for permission); a parent can block them in the Parents area. Local notifications at the player's usual time, never after 8:30 pm, fewer after a break.
- Family Plus subscription (see IN-APP PURCHASE above).

NEW IN 0.9
- Games: Listen & Type (hear a word, type it) and Right or Wrong (is this the right meaning?).
- A turtle button plays words slowly (Word Library, Word of the day, Listen & Type).
- Language page: "Your units" map with quests, strong words and quiz scores; a pin button (top right) pins the language to the top of the main menu (up to 3).
- Unit quizzes show the missed answers at the end. Sentence Builder has a Hint button.
- Quest journal: "Read the conversation again" for finished quests, with an English toggle.
- Word Library: the explorer can write a private note on any word (max 200 characters). Notes stay on the device, are never shared, and are not visible to other users: this is not user-generated content shared with others.
- My stats: what's coming up for review, and a 30-day activity calendar. Trophies show progress toward each one.
- Settings: High-contrast colors (black and white) and Arrow pad on the right (left-handed).

NEW IN 0.8
- Word Library: every word in the language, searchable, with filters (All, Met, Practice, Starred). Tap ☆ to star a word, then "Practice starred words" for a flashcard deck of them.
- Word of the day on each language page.
- Sentence Builder (Games › Word games): put word tiles in order to rebuild a sentence from the village.
- Unit quizzes (language page › Unit quizzes): 10 questions on a unit's words; opens after one quest in that unit is finished; best score kept.
- Weekly goal on the main menu: choose 2, 3, 5 or 7 days a week; reaching it gives XP once a week. A missed week simply starts fresh (no streaks).
- Parents area: a 7-day summary that a parent can share with the iOS share sheet, and optional practice reminders (local notifications, off by default).
- iPad: content keeps a readable width and the tile grid uses the extra space.

FEATURES IN THIS BUILD
- 13 courses: Spanish (6 regional varieties), French (France, Québec) and Japanese (kana with romaji) with 3 units each; starter units (5 quests) for German, Italian, Chinese, Yoruba, Hebrew, Ancient Egyptian, Amharic, Ancient Greek, Latin and Biblical Hebrew. Course text is written by the developer and is being reviewed by native speakers and specialists.
- Activities: listening, reading, matching, sentence building, typing, dialogue replies, optional speaking.
- Games: Word Battles (classic, or an opt-in speed mode with no time penalty), Word Scramble, Market Rush, Echo, Memory Match, Spelling Bee, Sentence Builder, Listen & Type, Right or Wrong, Flashcards (multiple choice), Kana Dojo.
- Write Out: trace, copy and write words on a canvas; the screen may rotate to landscape for more room; print or cursive for Latin-alphabet languages. Handwriting is read on-device with Apple's Vision framework and never stored.
- Progress: spaced review, XP and levels, daily challenges, achievements, a mistakes notebook, and a 7-day stats chart. There are no streaks or penalties for missing a day.
- Accessibility: VoiceOver labels, Reduce Motion, larger text, and an easy-read text option.

PARENTS AREA (☰ › Parents)
- Protected by a parental gate: type the answer to a written-out sum or multiplication (for example "Forty-seven plus thirty-eight"), in digits. An optional parent PIN can replace it. "Forgot PIN" uses the device passcode or Face ID.
- Contains: a 7-day summary with a Share button, on-device speech checking toggle (off by default; requests microphone and speech recognition permission only when turned on, and recognition is on-device only), practice reminders (off by default; requests notification permission only when turned on; local notifications scheduled on the device, no push server), break reminders, settings, optional parent PIN, data export, and delete explorer / delete all data.

PERMISSIONS: The microphone and speech recognition are requested only after a parent enables speech practice (the mic listens after the talk button is tapped, until "I'm done" or speech ends). Face ID is used only if a parent chooses "Forgot PIN". Notifications are requested only when a parent turns on practice reminders or the player turns on come-back reminders. No other permissions are used.

---

## Reviewer navigation (2-minute path)

1. Launch → create an explorer (age band 13–15, Spanish, Mexico, any name) → Start exploring → skip the placement quiz.
2. You're in the Spanish village. Tap **Go to › Luna**, talk to her, and finish the first quest (4 short activities).
3. Tap the **house** button → language page → **Word Library** (star a word) → **Unit quizzes** → Unit 1. Then **Games** → **Sentence Builder**.
4. **☰ › Write Out** → pick a word → turn the phone sideways → write it → **Check**.
5. **☰ › Parents** → answer the sum → see This week (Share), Reminders, Privacy and data, speech practice and deletion.
6. **☰ › Privacy policy** → the full policy, readable offline.

## Demo account requirements

None: the app has no sign-in.

## Suggested age-rating answers (App Store Connect › App Information › Age Rating)

Answer honestly; Apple assigns the rating. These are based on the current build:

| Question area | Suggested answer |
|---|---|
| Violence (cartoon/fantasy) | None. "Word duels" are vocabulary quizzes with no combat imagery |
| Sexual content, nudity, profanity, drugs, alcohol, tobacco, gambling, horror, mature themes | None |
| Medical or wellness topics | None |
| Unrestricted web access, user-generated content, messaging or chat | No |
| In-app controls (parental controls) | Yes: parental gate and PIN for speech, data deletion and break reminders |
| Capabilities (AI chatbot, location sharing, etc.) | None |
| Contests / loot boxes / simulated gambling | No |
| Made for Kids (Kids Category) | No |

Expected result: 4+ (or 9+). You can set a higher minimum age if you want to match the app's 11+ design.

## Encryption

ITSAppUsesNonExemptEncryption = NO. The app uses no encryption, only a SHA-256 hash of the parent PIN. Answer "No" / "exempt" if App Store Connect asks.
