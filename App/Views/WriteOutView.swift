import SwiftUI
import PencilKit
import Vision
import LQCore

/// Write Out: learn to write the words (and letters) of the language you're learning,
/// in print or cursive, on a canvas that can turn sideways for more room.
struct WriteOutView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.dismiss) var dismiss
    @State private var style: WritingStyle = .print
    @State private var selected: WritingTarget?

    var body: some View {
        NavigationStack {
            Group {
                if let t = selected {
                    WritingPad(target: t, style: style) { selected = nil }
                } else {
                    wordList
                }
            }
            .background(ThemedBackground())
            .navigationTitle(selected == nil ? "Write Out" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { OrientationDelegate.allowLandscape(true) }
        .onDisappear { OrientationDelegate.allowLandscape(false) }
    }

    private var wordList: some View {
        List {
            if let lib = model.library, let prof = model.profile {
                Section {
                    Text("Trace a word, copy it, then write it from memory. Turn your phone sideways for a bigger canvas.")
                        .font(.subheadline)
                    if WriteOut.supportsCursive(lib.course) {
                        Picker("Style", selection: $style) {
                            Text("Print").tag(WritingStyle.print)
                            Text("Cursive").tag(WritingStyle.cursive)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("writingStyle")
                    }
                    Label("\(prof.extrasOrEmpty.wordsWritten?.count ?? 0) words written", systemImage: "pencil.and.scribble")
                }
                let letters = WritingLetters.for(lib.course)
                if !letters.isEmpty {
                    Section("Letters") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(letters, id: \.self) { l in
                                    Button {
                                        selected = WritingTarget(itemId: nil, text: l, romanized: lib.course.romanize(l), english: "the letter \(l)")
                                    } label: {
                                        Text(l).font(style.font(size: 30, course: lib.course))
                                            .frame(minWidth: 52, minHeight: 52)
                                            .background(Color(p.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Practice the letter \(l)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section("Words") {
                    ForEach(WriteOut.words(prof, library: lib)) { w in
                        Button {
                            selected = WritingTarget(itemId: w.itemId, text: w.text, romanized: w.romanized, english: w.english)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.text).font(style.font(size: 22, course: lib.course))
                                    if let r = w.romanized { Text(r).font(.caption).foregroundStyle(Color(p.secondaryText)) }
                                }
                                Spacer()
                                Text(w.english).font(.caption).foregroundStyle(Color(p.secondaryText)).multilineTextAlignment(.trailing)
                                if prof.extrasOrEmpty.wordsWritten?.contains(w.itemId) == true {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color(p.accent)).accessibilityLabel("Written")
                                }
                            }
                        }
                        .accessibilityIdentifier("write-\(w.itemId)")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

struct WritingTarget: Equatable {
    var itemId: String?
    var text: String
    var romanized: String?
    var english: String
}

enum WritingStyle: String { case print, cursive }

extension WritingStyle {
    /// Print uses a clear handwriting-like face; cursive uses a joined script.
    func font(size: CGFloat, course: Course) -> Font {
        switch self {
        case .cursive where WriteOut.supportsCursive(course):
            return .custom("SnellRoundhand-Bold", size: size * 1.15)
        default:
            return course.script == .latin ? .custom("Noteworthy-Bold", size: size) : .system(size: size, weight: .regular)
        }
    }
}

/// Letters to practice for each writing system.
enum WritingLetters {
    static func `for`(_ c: Course) -> [String] {
        switch c.targetLanguage {
        case "zh", "egy": return []
        case "ja": return KanaDojo.hiragana
        case "grc": return "α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω".split(separator: " ").map(String.init)
        case "he", "hbo": return "א ב ג ד ה ו ז ח ט י כ ל מ נ ס ע פ צ ק ר ש ת".split(separator: " ").map(String.init)
        case "am": return "ሀ ለ ሐ መ ሠ ረ ሰ ሸ ቀ በ ተ ቸ ኀ ነ ኘ አ ከ ኸ ወ ዐ ዘ ዠ የ ደ ጀ ገ ጠ ጨ ጰ ጸ ፀ ፈ ፐ".split(separator: " ").map(String.init)
        default:
            let base = "abcdefghijklmnopqrstuvwxyz".map(String.init)
            return base + (c.typingKeys ?? []).filter { $0.count == 1 && $0 != "-" }
        }
    }
}

/// The canvas with handwriting lines, a guide, and pen/eraser tools.
struct WritingPad: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.palette) var p
    @Environment(\.verticalSizeClass) var vSize
    let target: WritingTarget
    let style: WritingStyle
    let onBack: () -> Void

    enum Step: String, CaseIterable { case trace = "Trace", copy = "Copy", memory = "From memory" }
    @State private var step: Step = .trace
    @State private var canvas = PKCanvasView()
    @State private var erasing = false
    @State private var feedback: String?
    @State private var showSelfCheck = false
    @State private var checking = false

    var body: some View {
        let landscape = vSize == .compact
        VStack(spacing: landscape ? 6 : 12) {
            header(landscape)
            stepPicker
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color.white)
                HandwritingLines().stroke(Color.blue.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                if step == .trace, let c = model.library?.course {
                    Text(target.text)
                        .font(style.font(size: landscape ? 110 : 84, course: c))
                        .foregroundStyle(Color.gray.opacity(0.28))
                        .minimumScaleFactor(0.3).lineLimit(1)
                        .padding(.horizontal, 16)
                        .environment(\.layoutDirection, model.library?.course.rightToLeft == true ? .rightToLeft : .leftToRight)
                        .accessibilityHidden(true)
                }
                CanvasRepresentable(canvas: canvas, erasing: erasing)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Writing canvas. Write \(target.text) with your finger.")
            }
            .frame(maxHeight: .infinity)
            tools
            if let f = feedback {
                Text(f).font(.subheadline.bold()).multilineTextAlignment(.center)
            }
            if showSelfCheck {
                HStack(spacing: 10) {
                    Button("Try again") { clear() }.buttonStyle(SecondaryButtonStyle())
                    Button("It matches") { success(selfChecked: true) }.buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("writeSelfCheck")
                }
            }
        }
        .padding(landscape ? 8 : 16)
        .onAppear { model.say(VText(target.text)) }
    }

    private func header(_ landscape: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { onBack() } label: { Label("Words", systemImage: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                if step != .memory, let c = model.library?.course {
                    Text(target.text).font(style.font(size: landscape ? 26 : 32, course: c))
                }
                if step != .memory, let r = target.romanized { Text(r).font(.caption) }
                Text(step == .memory ? "Write: “\(target.english)”" : target.english).font(.caption).foregroundStyle(Color(p.secondaryText))
            }
            Spacer()
            Button { model.say(VText(target.text)) } label: { Image(systemName: "speaker.wave.2.fill") }
                .accessibilityLabel("Hear it")
            if !landscape {
                Button { OrientationDelegate.allowLandscape(true, rotateNow: true) } label: {
                    Image(systemName: "rectangle.landscape.rotate")
                }
                .accessibilityLabel("Turn sideways for a bigger canvas")
                .accessibilityIdentifier("rotateCanvas")
            }
        }
    }

    private var stepPicker: some View {
        Picker("Step", selection: $step) { ForEach(Step.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented)
            .onChange(of: step) { _, _ in clear() }
            .accessibilityIdentifier("writeStep")
    }

    private var tools: some View {
        HStack(spacing: 10) {
            toolButton("pencil.tip", "Pen", on: !erasing) { erasing = false }
            toolButton("eraser", "Eraser (scribble out)", on: erasing) { erasing = true }
            toolButton("arrow.uturn.backward", "Undo", on: false) { canvas.undoManager?.undo() }
            toolButton("trash", "Clear", on: false) { clear() }
            Spacer()
            Button { check() } label: {
                Label(checking ? "Checking…" : "Check", systemImage: "checkmark.circle.fill").font(.headline)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(checking)
            .accessibilityIdentifier("writeCheck")
        }
    }

    private func toolButton(_ icon: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).frame(width: 44, height: 44)
                .background(on ? Color(p.accent).opacity(0.3) : Color(p.surface), in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func clear() {
        canvas.drawing = PKDrawing()
        feedback = nil
        showSelfCheck = false
    }

    /// Reads the handwriting on the device with Vision when it supports the language;
    /// otherwise (or if it can't read it) the learner compares with the example.
    private func check() {
        let drawing = canvas.drawing
        guard !drawing.strokes.isEmpty else { feedback = "Write the word first!"; return }
        let langs = HandwritingReader.languages(for: model.library?.course)
        guard !langs.isEmpty else {
            feedback = "Compare your writing with the example. Does it match?"
            showSelfCheck = true
            return
        }
        checking = true
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        let image = drawing.image(from: bounds, scale: 2)
        Task {
            let lines = await HandwritingReader.read(image, languages: langs)
            checking = false
            if WriteOut.matches(recognized: lines, word: target.text) || (target.romanized.map { WriteOut.matches(recognized: lines, word: $0) } ?? false) {
                success(selfChecked: false)
            } else {
                feedback = lines.first.map { "I read “\($0)”. Compare with the example. Does yours match?" }
                    ?? "I couldn't read that one (handwriting is hard for phones too!). Does yours match the example?"
                showSelfCheck = true
            }
        }
    }

    private func success(selfChecked: Bool) {
        model.sfx(.correct)
        feedback = selfChecked ? "Great writing! ✍️" : "I can read it: \(target.text)! ✍️"
        showSelfCheck = false
        if let id = target.itemId { model.updateProfile { WriteOut.record(id, profile: &$0) } }
        if step != .memory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                step = step == .trace ? .copy : .memory
            }
        }
    }
}

/// Top line, dashed middle line and baseline, like a handwriting notebook.
struct HandwritingLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.minY + r.height * 0.22, mid = r.minY + r.height * 0.45, base = r.minY + r.height * 0.68
        for y in [top, mid, base] { p.move(to: CGPoint(x: r.minX + 12, y: y)); p.addLine(to: CGPoint(x: r.maxX - 12, y: y)) }
        return p
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView
    let erasing: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput          // fingers work, not just Apple Pencil
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 9)
        return canvas
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        v.tool = erasing ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .black, width: 9)
    }
}

/// On-device handwriting reading with Vision (no network).
enum HandwritingReader {
    /// Vision languages for a course, or empty when Vision can't read that script.
    static func languages(for course: Course?) -> [String] {
        guard let c = course else { return [] }
        let wanted: [String]
        switch c.targetLanguage {
        case "es": wanted = ["es-ES"]
        case "fr": wanted = ["fr-FR"]
        case "de": wanted = ["de-DE"]
        case "it", "la": wanted = ["it-IT"]
        case "zh": wanted = ["zh-Hans"]
        case "ja": wanted = ["ja-JP"]
        case "yo", "egy": wanted = ["en-US"]
        default: wanted = []
        }
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
        return wanted.filter { supported.contains($0) }
    }

    static func read(_ image: UIImage, languages: [String]) async -> [String] {
        // Ink on white so Vision sees normal writing.
        let r = UIGraphicsImageRenderer(size: image.size)
        let flat = r.image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
        guard let cg = flat.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let req = VNRecognizeTextRequest()
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = false
                req.recognitionLanguages = languages
                try? VNImageRequestHandler(cgImage: cg).perform([req])
                let obs = req.results ?? []
                cont.resume(returning: obs.flatMap { $0.topCandidates(3).map(\.string) })
            }
        }
    }
}
