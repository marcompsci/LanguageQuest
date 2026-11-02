import Foundation

public enum ContentError: Error, CustomStringConvertible {
    case missingFile(String)
    case decode(file: String, underlying: Error)
    case invalid([String])

    public var description: String {
        switch self {
        case .missingFile(let f): return "Missing content file: \(f)"
        case .decode(let f, let e): return "Could not read \(f): \(e)"
        case .invalid(let problems): return "Content has \(problems.count) problem(s):\n- " + problems.joined(separator: "\n- ")
        }
    }
}

/// A loaded, validated course: the course manifest plus its units.
/// Loading is fully offline: content ships inside the app bundle.
public struct ContentLibrary: Sendable {
    public let course: Course
    public let units: [LessonUnit]

    public init(course: Course, units: [LessonUnit]) {
        self.course = course
        self.units = units.sorted { $0.order < $1.order }
    }

    /// Loads the course from a directory containing `course.json` and unit files.
    public static func load(from directory: URL, validate: Bool = true) throws -> ContentLibrary {
        let decoder = JSONDecoder()
        func read<T: Decodable>(_ name: String, as: T.Type) throws -> T {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { throw ContentError.missingFile(name) }
            do { return try decoder.decode(T.self, from: data) } catch { throw ContentError.decode(file: name, underlying: error) }
        }
        let course = try read("course.json", as: Course.self)
        let units = try course.unitFiles.map { try read($0, as: LessonUnit.self) }
        let lib = ContentLibrary(course: course, units: units)
        if validate {
            let problems = ContentValidator.validate(lib).filter { $0.severity == .error }
            if !problems.isEmpty { throw ContentError.invalid(problems.map(\.message)) }
        }
        return lib
    }

    /// Courses that ship in the app, in menu order.
    public static let bundledCourseIds = ["en-es", "en-fr", "en-ja"]

    /// A course bundled with LQCore, by id ("en-es", "en-fr", "en-ja").
    public static func bundled(_ id: String) throws -> ContentLibrary {
        guard let base = Bundle.module.url(forResource: "Content", withExtension: nil) else {
            throw ContentError.missingFile("Content")
        }
        return try load(from: base.appendingPathComponent(id))
    }

    /// The English → Spanish course.
    public static func bundledSpanish() throws -> ContentLibrary { try bundled("en-es") }

    /// How answers are compared for this course.
    public var checkContext: CheckContext { CheckContext(course: course) }

    /// Phrases NPCs and screens use in this course's language.
    public var phrases: LocalPhrases { LocalPhrases.for(course.targetLanguage) }

    // MARK: Lookup

    public func unit(_ id: String) -> LessonUnit? { units.first { $0.id == id } }

    public func quest(_ id: String) -> (unit: LessonUnit, quest: Quest)? {
        for u in units { if let q = u.quests.first(where: { $0.id == id }) { return (u, q) } }
        return nil
    }

    public var allQuests: [Quest] { units.flatMap { $0.quests.sorted { $0.order < $1.order } } }

    public func item(_ id: String) -> LexItem? {
        for u in units { if let i = u.allItems.first(where: { $0.id == id }) { return i } }
        return nil
    }

    public func activity(_ id: String) -> Activity? {
        for u in units { if let a = u.allActivities.first(where: { $0.id == id }) { return a } }
        return nil
    }

    public var allItems: [LexItem] { units.flatMap(\.allItems) }
}
