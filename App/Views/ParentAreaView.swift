import SwiftUI
import StoreKit
import LQCore

/// Grown-ups area: behind the parental gate.
struct ParentAreaView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var unlockedAt: Date?

    var body: some View {
        NavigationStack {
            Group {
                if unlockedAt == nil {
                    if let record = ParentPINStore.load() {
                        PINGateView(record: record) { unlockedAt = Date() }
                    } else {
                        ParentGateView { unlockedAt = Date() }
                    }
                } else {
                    ParentDashboardView(gatePassedAt: $unlockedAt)
                }
            }
            .navigationTitle("Parents")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ParentGateView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    let onPass: () -> Void
    @State private var challenge = ParentalGate.makeChallenge()
    @State private var tracker = GateAttemptTracker()
    @State private var input = ""
    @State private var message: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill").font(.system(size: 48)).accessibilityHidden(true)
            Text("For parents and guardians").font(.title.bold())
            Text("This area is for a parent or guardian.")
                .font(.subheadline).multilineTextAlignment(.center)
            Text("Type the answer in numbers:").font(.headline)
            Text(challenge.question).font(.title2.bold()).multilineTextAlignment(.center)
                .accessibilityIdentifier("gateQuestion")
            TextField("Answer", text: $input)
                .keyboardType(.numberPad)
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 220)
                .accessibilityIdentifier("gateAnswer")
            if let m = message { Text(m).foregroundStyle(Color(p.retry)).accessibilityIdentifier("gateMessage") }
            Button("Continue") {
                if tracker.submit(input, for: challenge, now: Date()) {
                    onPass()
                } else {
                    input = ""
                    challenge = ParentalGate.makeChallenge()
                    message = tracker.isLocked(now: Date()) ? "Too many tries. Please wait a minute." : "That's not it. Here's a new one."
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 320)
            .disabled(input.isEmpty || tracker.isLocked(now: Date()))
            .accessibilityIdentifier("gateContinue")
            Spacer()
        }
        .padding(24)
    }
}

/// PIN entry, used instead of the math question once a parent sets a PIN.
struct PINGateView: View {
    @Environment(\.palette) var p
    let record: ParentPINRecord
    let onPass: () -> Void
    @State private var pin = ""
    @State private var tracker = GateAttemptTracker()
    @State private var message: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 48)).accessibilityHidden(true)
            Text("Parent PIN").font(.title.bold())
            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Color(p.surface), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 220)
                .accessibilityIdentifier("pinField")
            if let m = message { Text(m).foregroundStyle(Color(p.retry)) }
            Button("Unlock") {
                if tracker.submitPIN(pin, record: record, now: Date()) { onPass() } else {
                    pin = ""
                    message = tracker.isLocked(now: Date()) ? "Too many tries. Please wait a minute." : "That PIN isn't right."
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 320)
            .disabled(pin.isEmpty || tracker.isLocked(now: Date()))
            Button("Forgot PIN?") {
                Task { @MainActor in
                    if await ParentPINStore.resetWithDeviceOwner() { onPass() } else { message = "Couldn't confirm the device owner." }
                }
            }
            .font(.subheadline)
            Text("Forgot it? The phone's own passcode or Face ID resets the PIN.").font(.caption).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }
}

struct ParentDashboardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Binding var gatePassedAt: Date?
    @State private var confirmDeleteProfile = false
    @State private var confirmDeleteAll = false
    @State private var exportURL: URL?
    @State private var speechMessage: String?
    @State private var hasPIN = ParentPINStore.load() != nil
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var pinMessage: String?

    var body: some View {
        List {
            if let prof = model.profile, let lib = model.library {
                let report = ParentReport.build(prof, library: lib, now: Date())
                profilesSection(prof)
                masterySection(report, lib)
                unitsSection(report)
                activitySection(report)
                suggestionsSection(report)
                settingsSection(prof, lib)
                speechSection
                pinSection
                privacySection(prof)
                planSection
            }
        }
    }

    // MARK: Sections

    private func profilesSection(_ prof: PlayerProfile) -> some View {
        Section("Explorers on this device") {
            ForEach(model.save.profiles) { pr in
                Button { model.switchProfile(pr.id) } label: {
                    HStack {
                        Image(uiImage: PixelArt.avatarImage(pr.avatar, scale: 3)).interpolation(.none).accessibilityHidden(true)
                        Text(pr.nickname.isEmpty ? "Explorer" : pr.nickname)
                        Text("· \(pr.ageBand.label)").foregroundStyle(Color(p.secondaryText))
                        Spacer()
                        if pr.id == prof.id { Image(systemName: "checkmark").accessibilityLabel("Active") }
                    }
                }
            }
            let canAdd = FeatureGate.isAvailable(.profileSlot(index: model.save.profiles.count), plan: model.plan, config: model.storeConfig)
            Button("Add an explorer") { model.addNewProfileFlow() }.disabled(!canAdd)
            if !canAdd { Text("This device has the most explorers allowed on your plan.").font(.caption) }
        }
    }

    private func masterySection(_ r: ParentReport, _ lib: ContentLibrary) -> some View {
        Section {
            HStack { Text("Understands (after spaced review)"); Spacer(); Text("\(r.mastery.understood.count) words") }
            HStack { Text("Can use on their own"); Spacer(); Text("\(r.mastery.canUse.count) words") }
            HStack { Text("Still learning"); Spacer(); Text("\(r.mastery.learning)") }
            HStack { Text("Due for review now"); Spacer(); Text("\(r.mastery.dueForReview)") }
            if let ret = r.mastery.delayedRetentionPercent {
                HStack { Text("Remembered after a day or more"); Spacer(); Text("\(ret)%") }
            }
            ForEach(Skill.allCases, id: \.self) { s in
                let score = r.mastery.bySkill[s] ?? SkillScore()
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(s.rawValue.capitalized); Spacer(); Text(score.total == 0 ? "No practice yet" : "\(score.percent)% first try") }
                    ProgressView(value: Double(score.correct), total: Double(max(score.total, 1)))
                }
                .accessibilityElement(children: .combine)
            }
            if !r.mastery.understood.isEmpty {
                DisclosureGroup("Words they understand") {
                    ForEach(r.mastery.understood, id: \.self) { id in
                        if let i = lib.item(id) { Text("\(model.text(i.target)) = \(i.english)") }
                    }
                }
            }
            if let b = r.latestBaseline {
                Text("Placement test (\(b.date.formatted(date: .abbreviated, time: .omitted))): \(b.overall.correct)/\(b.overall.total) correct")
            }
            ForEach(Array(r.retentionHistory.enumerated()), id: \.offset) { _, a in
                Text("Memory check \(a.date.formatted(date: .abbreviated, time: .omitted)): \(a.overall.percent)%")
            }
        } header: {
            Text("What they've learned")
        } footer: {
            Text("A word counts as understood only after it's remembered across several days. XP and time played are shown separately below and never count as mastery.")
        }
    }

    private func unitsSection(_ r: ParentReport) -> some View {
        Section("Lessons") {
            ForEach(r.units, id: \.unitId) { u in
                VStack(alignment: .leading) {
                    Text(u.title).font(.headline)
                    Text("\(u.questsDone)/\(u.questsTotal) quests\(u.masteryCheckPassed ? " · mastery check passed" : "")\(u.placedOut ? " · placed out" : "")")
                        .font(.subheadline)
                }
            }
        }
    }

    private func activitySection(_ r: ParentReport) -> some View {
        Section {
            HStack { Text("Minutes in the last 7 days"); Spacer(); Text("\(Int(r.usage.minutesLast7Days.rounded()))") }
            HStack { Text("Activities in the last 7 days"); Spacer(); Text("\(r.usage.activitiesLast7Days)") }
            HStack { Text("XP (play points)"); Spacer(); Text("\(r.usage.xp)") }
        } header: { Text("Activity (not mastery)") } footer: {
            Text("Time is counted only while the app is open, on this device. Daily totals are deleted after \(ActivityLog.retentionDays) days.")
        }
    }

    private func suggestionsSection(_ r: ParentReport) -> some View {
        Section("Screen-free practice ideas") {
            ForEach(r.offlineSuggestions, id: \.self) { Text($0) }
        }
    }

    private func settingsSection(_ prof: PlayerProfile, _ lib: ContentLibrary) -> some View {
        Section("Settings for \(prof.nickname.isEmpty ? "this explorer" : prof.nickname)") {
            Picker("Language", selection: Binding(get: { model.activeCourseId }, set: { model.switchCourse(to: $0) })) {
                ForEach(model.courses, id: \.id) { c in Text("\(c.displayLanguage) (\(c.nativeName ?? ""))").tag(c.id) }
            }
            if lib.course.variants.count > 1 {
                Picker("\(lib.course.displayLanguage) variety", selection: binding(\.variant, prof)) {
                    ForEach(lib.course.variants) { v in Text("\(v.flagEmoji) \(v.name)").tag(v.id) }
                }
            }
            if lib.course.script == .kana {
                Toggle("Show romaji under Japanese", isOn: Binding(get: { prof.settings.romanizationOn },
                                                                   set: { v in model.updateProfile { $0.settings.showRomanization = v } }))
            }
            Picker("Look", selection: binding(\.theme, prof)) {
                Text("Playful (younger)").tag(ThemeKind.playful)
                Text("Explorer (teens)").tag(ThemeKind.explorer)
            }
            Toggle("Reduce motion", isOn: settingBinding(\.reducedMotion, prof))
            Toggle("Show English subtitles in conversations", isOn: settingBinding(\.subtitles, prof))
            Toggle("Read instructions aloud", isOn: settingBinding(\.readAloudInstructions, prof))
            Toggle("Sound effects and vibration", isOn: settingBinding(\.soundEffects, prof))
            Toggle("Music", isOn: settingBinding(\.music, prof))
            VStack(alignment: .leading) {
                Text("Music volume")
                Slider(value: Binding(get: { (model.profile ?? prof).settings.musicLevel },
                                      set: { v in model.updateProfile { $0.settings.musicVolume = v } }), in: 0...1)
                Text("Music always goes quiet while words are spoken and during lessons.").font(.caption)
            }
            VStack(alignment: .leading) {
                Text("Voice volume")
                Slider(value: settingBinding(\.voiceVolume, prof), in: 0...1)
            }
            VStack(alignment: .leading) {
                Text("Speaking speed")
                Slider(value: settingBinding(\.speechRate, prof), in: 0.3...0.55)
            }
            Picker("Larger text", selection: settingBinding(\.textScale, prof)) {
                Text("Normal").tag(1.0)
                Text("Larger").tag(1.15)
            }
            Picker("Break reminder", selection: settingBinding(\.sessionReminderMinutes, prof)) {
                Text("Off").tag(Int?.none)
                Text("15 minutes").tag(Int?.some(15))
                Text("25 minutes").tag(Int?.some(25))
                Text("40 minutes").tag(Int?.some(40))
            }
        }
    }

    private var speechSection: some View {
        Section {
            Toggle("Allow on-device speech checking", isOn: Binding(
                get: { model.save.parent.allowOnDeviceSpeech },
                set: { on in
                    if on {
                        Task { @MainActor in
                            let ok = await SpeechRecognitionService.requestPermissions()
                            model.updateParent { $0.allowOnDeviceSpeech = ok }
                            if !ok { speechMessage = "Microphone or speech permission wasn't given. Speaking stays in no-microphone mode." }
                            else if SpeechRecognitionService.recognizer(for: model.variant) == nil {
                                speechMessage = "This device can't check this language offline, so speaking will stay in no-microphone mode."
                            }
                        }
                    } else {
                        model.updateParent { $0.allowOnDeviceSpeech = false }
                    }
                }))
            if let m = speechMessage { Text(m).font(.caption) }
        } header: { Text("Speaking practice") } footer: {
            Text("Off by default. When on, the microphone listens only while your child holds the talk button, recognition happens on this device, and audio is never saved or sent. When off, kids say words aloud and tap “I said it!”.")
        }
    }

    private var pinSection: some View {
        Section {
            if hasPIN {
                Label("A parent PIN is set", systemImage: "lock.fill")
                Button("Remove PIN", role: .destructive) { ParentPINStore.delete(); hasPIN = false; pinMessage = "PIN removed." }
            }
            SecureField(hasPIN ? "New PIN (4–6 digits)" : "Choose a PIN (4–6 digits)", text: $newPIN).keyboardType(.numberPad)
            SecureField("Type it again", text: $confirmPIN).keyboardType(.numberPad)
            Button(hasPIN ? "Change PIN" : "Set PIN") {
                switch ParentPIN.validateNew(newPIN, confirm: confirmPIN) {
                case .none:
                    hasPIN = ParentPINStore.save(pin: newPIN)
                    pinMessage = hasPIN ? "PIN saved." : "Couldn't save the PIN."
                case .notDigits?: pinMessage = "Use digits only."
                case .wrongLength?: pinMessage = "Use 4 to 6 digits."
                case .tooSimple?: pinMessage = "Pick something harder to guess than 1111 or 1234."
                case .mismatch?: pinMessage = "The two PINs don't match."
                }
                newPIN = ""; confirmPIN = ""
            }
            .disabled(newPIN.isEmpty)
            if let m = pinMessage { Text(m).font(.caption) }
        } header: { Text("Parent PIN") } footer: {
            Text("Teens can solve the math question, so a PIN keeps settings, data deletion and purchases for parents. Only a salted hash is stored, in this device's Keychain.")
        }
    }

    private func privacySection(_ prof: PlayerProfile) -> some View {
        Section {
            ForEach(PrivacyNotice.dataInventory.indices, id: \.self) { i in
                let row = PrivacyNotice.dataInventory[i]
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.data).font(.subheadline.bold())
                    Text("\(row.whereKept) · \(row.retention)").font(.caption)
                }
            }
            Button("Export this explorer's data") {
                if let data = try? FamilyManager.export(prof) {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("LanguageQuest-export.json")
                    try? data.write(to: url, options: .atomic)
                    exportURL = url
                }
            }
            if let url = exportURL { ShareLink("Share export file", item: url) }
            Button("Delete this explorer", role: .destructive) { confirmDeleteProfile = true }
            Button("Delete all data on this device", role: .destructive) { confirmDeleteAll = true }
        } header: { Text("Privacy and data") } footer: {
            Text("Language Quest has no accounts, ads, analytics, or tracking, and works offline. Nothing leaves this device unless you export it.")
        }
        .confirmationDialog("Delete this explorer and all their progress?", isPresented: $confirmDeleteProfile, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteProfile(prof.id) }
        }
        .confirmationDialog("Delete every explorer and setting on this device? This can't be undone.", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { model.deleteEverything() }
        }
    }

    private var planSection: some View {
        Section {
            let decision = PurchaseGate.decide(config: model.storeConfig, parent: model.save.parent, gatePassedAt: gatePassedAt, now: Date())
            if decision == .plansDisabled {
                Text("Everything in this version is free: all three Starter Village units, review, hints, and this dashboard. Paid extras aren't available yet.")
            } else {
                Toggle("Allow purchases", isOn: Binding(get: { model.save.parent.purchasesAllowed },
                                                       set: { v in model.updateParent { $0.purchasesAllowed = v } }))
                ForEach(model.store.products, id: \.id) { product in
                    Button("\(product.displayName): \(product.displayPrice)") {
                        guard PurchaseGate.decide(config: model.storeConfig, parent: model.save.parent, gatePassedAt: gatePassedAt, now: Date()) == .allowed else {
                            gatePassedAt = nil   // ask for the gate again
                            return
                        }
                        Task { _ = await model.store.purchase(product); await model.refreshEntitlements() }
                    }
                }
                Button("Restore purchases") { Task { await model.store.restore(); await model.refreshEntitlements() } }
                Text("Cancel any time in Settings > your name > Subscriptions. Learning essentials stay free.").font(.caption)
            }
        } header: { Text("Family Plus") }
        .task { await model.store.loadProducts() }
    }

    // MARK: Bindings

    /// Bindings fall back to the profile snapshot if the profile disappears mid-update (e.g. after delete).
    private func binding<T>(_ kp: WritableKeyPath<PlayerProfile, T>, _ fallback: PlayerProfile) -> Binding<T> {
        Binding(get: { (model.profile ?? fallback)[keyPath: kp] }, set: { v in model.updateProfile { $0[keyPath: kp] = v } })
    }

    private func settingBinding<T>(_ kp: WritableKeyPath<LearnerSettings, T>, _ fallback: PlayerProfile) -> Binding<T> {
        Binding(get: { (model.profile ?? fallback).settings[keyPath: kp] }, set: { v in model.updateProfile { $0.settings[keyPath: kp] = v } })
    }
}
