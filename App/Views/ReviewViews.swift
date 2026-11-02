import SwiftUI
import LQCore

/// Plays a list of activities and reports per-activity correctness.
struct ActivitySequence: View {
    let activities: [Activity]
    var assessment = false
    let onEach: (Activity, ActivityResult) -> Void
    let onFinish: () -> Void
    @State private var index = 0

    var body: some View {
        if index < activities.count {
            VStack(spacing: 0) {
                ProgressView(value: Double(index), total: Double(activities.count)).padding(.horizontal, 20)
                ScrollView {
                    ActivityHost(activity: activities[index], assessment: assessment) { r in
                        onEach(activities[index], r)
                        index += 1
                        if index >= activities.count { onFinish() }
                    }
                    .id("\(index)-\(activities[index].id)")
                }
            }
        }
    }
}

/// Spaced review: items due today, plus the weekly memory check when it's due.
struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var mode: Mode = .menu
    @State private var queue: [Activity] = []
    @State private var correct = 0
    @State private var answers: [AssessmentAnswer] = []

    enum Mode { case menu, review, retention, done }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                switch mode {
                case .menu: menu
                case .review:
                    ActivitySequence(activities: queue, onEach: { a, r in
                        model.complete(a, outcome: r.outcome, verified: r.verified)
                        if r.outcome.correct && r.outcome.attempts == 1 { correct += 1 }
                    }, onFinish: { mode = .done })
                case .retention:
                    ActivitySequence(activities: queue, assessment: true, onEach: { a, r in
                        model.complete(a, outcome: r.outcome, verified: r.verified)
                        answers.append(AssessmentAnswer(activity: a, correct: r.outcome.correct))
                    }, onFinish: {
                        let result = AssessmentResult(kind: .retention, date: Date(), unitId: nil,
                                                      bySkill: AssessmentScoring.score(answers), passed: nil)
                        model.updateProfile { $0.assessments.append(result) }
                        mode = .done
                    })
                case .done:
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles").font(.system(size: 60)).accessibilityHidden(true)
                        Text(model.phrases.goodJob).font(.largeTitle.bold())
                        Text("Words you missed will come back soon. Words you knew will come back later.")
                            .multilineTextAlignment(.center)
                        Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 16) {
            let due = dueActivities()
            Text("Review is always free and never runs out.").font(.subheadline)
            if let p = model.profile, RetentionCheck.isDue(p, now: Date()), let lib = model.library {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Memory check", systemImage: "brain.head.profile").font(.headline)
                        Text("A short quiz on words you haven't seen for a week. It helps your grown-up see what's sticking.")
                        Button("Start memory check") {
                            queue = RetentionCheck.build(p, library: lib, now: Date())
                            answers = []
                            mode = queue.isEmpty ? .done : .retention
                        }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(due.isEmpty ? "Nothing is due right now." : "\(due.count) things to review").font(.headline)
                    Button(due.isEmpty ? "Practice anyway" : "Start review") {
                        queue = due.isEmpty ? practiceAnyway() : due
                        correct = 0
                        mode = queue.isEmpty ? .done : .review
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!due.isEmpty ? false : practiceAnyway().isEmpty)
                    .accessibilityIdentifier("startReview")
                }
            }
            Spacer()
        }
        .padding(20)
    }

    /// One activity per due item, preferring a different activity type than last time.
    private func dueActivities() -> [Activity] {
        guard let p = model.profile, let lib = model.library else { return [] }
        let ids = ReviewPlanner.dueItems(p.knowledge, now: Date(), limit: 10)
        let pool = lib.units.flatMap { $0.quests.flatMap(\.activities) }.filter { p.progress.completedActivities[$0.id] != nil }
        var used = Set<String>()
        var out: [Activity] = []
        for id in ids {
            let options = pool.filter { $0.items.contains(id) && !used.contains($0.id) }
            let pick = options.min { (p.progress.completedActivities[$0.id]?.lastCompleted ?? .distantPast) < (p.progress.completedActivities[$1.id]?.lastCompleted ?? .distantPast) }
            if let a = pick { out.append(a); used.insert(a.id) }
        }
        return out
    }

    private func practiceAnyway() -> [Activity] {
        guard let p = model.profile, let lib = model.library else { return [] }
        let pool = lib.units.flatMap { $0.quests.flatMap(\.activities) }.filter { p.progress.completedActivities[$0.id] != nil }
        return Array(stableShuffle(pool, seed: ActivityLog.dayKey(Date())).prefix(6))
    }
}

/// Optional baseline placement. Age is never used.
struct PlacementView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var session: PlacementSession?
    @State private var started = false

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                if let s = session, started, !s.finished, let q = s.currentQuestion {
                    ScrollView {
                        ActivityHost(activity: q, assessment: true) { r in
                            session?.answer(correct: r.outcome.correct)
                            if session?.finished == true { applyResult() }
                        }
                        .id("\(s.answers.count)")
                    }
                } else if let s = session, s.finished {
                    VStack(spacing: 16) {
                        Text("All done!").font(.largeTitle.bold())
                        if s.placedOut.isEmpty {
                            Text("We'll start at the beginning. That's a great place to start!")
                        } else {
                            Text("You can skip ahead: \(s.placedOut.count) unit(s) opened. You can still play them any time.")
                        }
                        Button("Back to the village") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                    }.padding(24)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Placement test").font(.largeTitle.bold())
                        Text("A few questions to find the right starting point. There's no score to worry about, and you can skip it.")
                        Button("Start") {
                            if let lib = model.library { session = PlacementSession(library: lib); started = true }
                        }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("startPlacement")
                        Button("I'm new to \(model.languageName): skip") {
                            if let lib = model.library {
                                var s = PlacementSession(library: lib); s.skip(); session = s
                                model.updateProfile { s.apply(to: &$0, now: Date()) }
                            }
                        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("skipPlacement")
                        Spacer()
                    }.padding(24)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func applyResult() {
        guard let s = session else { return }
        model.updateProfile { s.apply(to: &$0, now: Date()) }
    }
}

/// End-of-unit mastery check: independent practice, one try each.
struct MasteryCheckView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let unitId: String
    @State private var answers: [AssessmentAnswer] = []
    @State private var result: AssessmentResult?
    @State private var started = false

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                if let u = model.library?.unit(unitId) {
                    if let r = result {
                        VStack(spacing: 16) {
                            Text(r.passed == true ? model.phrases.excellent : "Good practice!").font(.largeTitle.bold())
                            Text("\(r.overall.correct) of \(r.overall.total) right on the first try.")
                            Text(r.passed == true ? "You passed the \(u.title) mastery check."
                                 : "Keep reviewing and try again any time. Nothing is lost.")
                                .multilineTextAlignment(.center)
                            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                        }.padding(24)
                    } else if started {
                        ActivitySequence(activities: u.masteryCheck.activities, assessment: true, onEach: { a, r in
                            model.complete(a, outcome: r.outcome, verified: r.verified)
                            // A self-checked spoken answer is left out of the score rather than marked wrong.
                            if r.verified { answers.append(AssessmentAnswer(activity: a, correct: r.outcome.correct)) }
                        }, onFinish: {
                            let r = MasteryCheckGrader.grade(unit: u, answers: answers, now: Date())
                            model.updateProfile { MasteryCheckGrader.apply(r, unit: u, badge: Catalog.masteryBadge(forUnitOrder: u.order, courseId: model.activeCourseId), profile: &$0) }
                            result = r
                        })
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Mastery check: \(u.title)").font(.title.bold())
                            Text("\(u.masteryCheck.activities.count) questions, no hints, one try each. You'll see the right answer after each one.")
                            Button("Start") { started = true }.buttonStyle(PrimaryButtonStyle())
                            Spacer()
                        }.padding(24)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
