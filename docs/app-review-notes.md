# App Review notes: Language Quest 0.7.0

Paste the "Review Notes" section into App Store Connect › TestFlight › Test Information (Beta App Review) and, later, into App Review Information for the App Store. Guideline 2.3.1(a) asks for features to be described specifically, so keep this list current with every build.

---

## Review Notes (copy from here)

Language Quest is an offline language-learning game for ages 11 and up. Players explore a pixel-art village, talk to characters in the language they are learning, complete short quests, and play word games.

NO SIGN-IN. There are no accounts, so no demo account is needed. On first launch, create an explorer: tap Next through the short setup, choose any age band (11–12, 13–15 or 16+), choose a language (Spanish is the most complete) and a variety, enter any name, and tap "Start exploring". A short placement quiz is offered next; tap "I'm new to Spanish: skip" to go straight to the village.

NO NETWORK, ADS, ANALYTICS OR TRACKING. All data stays on the device. Privacy label: Data Not Collected.

NO PURCHASES IN THIS VERSION. The app contains StoreKit code for a possible future family subscription. It is switched off in this build (StoreConfig.paidPlansEnabled = false): no products are loaded and no purchase screen can be reached. No in-app purchase products are configured in App Store Connect.

HOW TO NAVIGATE
- Main menu: explorer level card, Recent lesson (Continue, plus a multiple-choice quick flashcard), Bonus lesson, Daily challenges, then languages in three sections: Choose a language; African Languages; Old Languages.
- Tap a language to open its page: Play (enters the village), Today, Games, Flashcards, Bonus lesson, Write Out (and Kana Dojo for Japanese).
- ☰ (top right): Review, Phrasebook, Write Out, Bonus lesson, Quest journal, Wardrobe, Bag and badges, Mistakes notebook, Trophies, My stats, Settings, Parents, Privacy policy.
- In the village: use the arrow pad to walk; "Go to" walks to a character; the house button returns to the language page; the flag button switches language.

FEATURES IN THIS BUILD
- 13 courses: Spanish (6 regional varieties), French (France, Québec) and Japanese (kana with romaji) with 3 units each; starter units (5 quests) for German, Italian, Chinese, Yoruba, Hebrew, Ancient Egyptian, Amharic, Ancient Greek, Latin and Biblical Hebrew. Course text is written by the developer and is being reviewed by native speakers and specialists.
- Activities: listening, reading, matching, sentence building, typing, dialogue replies, optional speaking.
- Games: Word Battles (classic, or an opt-in speed mode with no time penalty), Word Scramble, Market Rush, Echo, Memory Match, Spelling Bee, Flashcards (multiple choice), Kana Dojo.
- Write Out: trace, copy and write words on a canvas; the screen may rotate to landscape for more room; print or cursive for Latin-alphabet languages. Handwriting is read on-device with Apple's Vision framework and never stored.
- Progress: spaced review, XP and levels, daily challenges, achievements, a mistakes notebook, and a 7-day stats chart. There are no streaks or penalties for missing a day.
- Accessibility: VoiceOver labels, Reduce Motion, larger text, and an easy-read text option.

PARENTS AREA (☰ › Parents)
- Protected by a parental gate: type the answer to a written-out sum or multiplication (for example "Forty-seven plus thirty-eight"), in digits. An optional parent PIN can replace it. "Forgot PIN" uses the device passcode or Face ID.
- Contains: on-device speech checking toggle (off by default; requests microphone and speech recognition permission only when turned on, and recognition is on-device only), break reminders, settings, optional parent PIN, data export, and delete explorer / delete all data.

PERMISSIONS: The microphone and speech recognition are requested only after a parent enables speech practice (the mic listens after the talk button is tapped, until "I'm done" or speech ends). Face ID is used only if a parent chooses "Forgot PIN". No other permissions are used.

---

## Reviewer navigation (2-minute path)

1. Launch → create an explorer (age band 13–15, Spanish, Mexico, any name) → Start exploring → skip the placement quiz.
2. You're in the Spanish village. Tap **Go to › Luna**, talk to her, and finish the first quest (4 short activities).
3. Tap the **house** button → language page → **Games** → **Echo** or **Memory Match**.
4. **☰ › Write Out** → pick a word → turn the phone sideways → write it → **Check**.
5. **☰ › Parents** → answer the sum → see Privacy and data, speech practice and deletion.
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
