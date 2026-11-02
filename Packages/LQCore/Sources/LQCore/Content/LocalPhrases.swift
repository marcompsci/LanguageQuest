import Foundation

/// Short target-language lines used outside authored quests: NPC small talk,
/// celebration banners, and mini-game labels. English glosses are shown with them.
public struct LocalPhrases: Sendable {
    public var helloAgain: VText          // "Hi again, {name}! Shall we practice?"
    public var yesPlease: VText
    public var duel: VText                // "A word duel!"
    public var notNow: VText
    public var letsGo: VText
    public var seeYou: VText
    public var comeBackSoon: VText
    public var veryGood: String           // praise before "That's right."
    public var questComplete: String
    public var youWon: String
    public var goodDuel: String
    public var lostWord: String
    public var goodJob: String
    public var excellent: String
    public var thanksForShopping: String
    public var shoppingList: String
    public var howMuchTotal: String
    /// Duel greetings by opponent id.
    public var duelGreetings: [String: VText]
    /// Screen-free practice ideas for parents, by unit order.
    public var offlineIdeas: [Int: String]
    public var countingIdea: String

    public static func `for`(_ language: String) -> LocalPhrases {
        switch language {
        case "fr": return french
        case "ja": return japanese
        default: return generated[language] ?? spanish
        }
    }

    public static let spanish = LocalPhrases(
        helloAgain: "¡Hola otra vez, {name}! ¿Practicamos?", yesPlease: "¡Sí, por favor!", duel: "¡Un duelo de palabras!",
        notNow: "Ahora no, gracias.", letsGo: "¡Vamos!", seeYou: "¡Hasta luego!", comeBackSoon: "¡Hola! Vuelve pronto.",
        veryGood: "¡Muy bien!", questComplete: "¡Misión cumplida!", youWon: "¡Ganaste!", goodDuel: "¡Buen duelo!",
        lostWord: "¡Palabra perdida!", goodJob: "¡Buen trabajo!", excellent: "¡Excelente!",
        thanksForShopping: "¡Gracias por su compra!", shoppingList: "La lista de compras", howMuchTotal: "¿Cuánto cuesta en total?",
        duelGreetings: ["duel-mateo": "¡Te reto a un duelo de palabras!", "duel-nico": "¡Canela y yo estamos listos!",
                        "duel-pepe": "¿Sabes los nombres de mi fruta?", "duel-sol": "Veamos todo lo que aprendiste."],
        offlineIdeas: [1: "Greet each other in Spanish at breakfast: \"¡Buenos días! ¿Cómo estás?\"",
                       2: "Look at family photos together and name each person: \"Es mi abuela.\"",
                       3: "At the store, let your child ask you \"¿Cuánto cuesta?\" and answer with numbers up to 20."],
        countingIdea: "Count steps, stairs or toys aloud in Spanish (uno, dos, tres…).")

    public static let french = LocalPhrases(
        helloAgain: VText("Re-bonjour, {name} ! On s'entraîne ?", overrides: ["fr-CA": "Re-bonjour, {name} ! On pratique ?"]),
        yesPlease: "Oui, s'il te plaît !", duel: "Un duel de mots !",
        notNow: "Pas maintenant, merci.", letsGo: "C'est parti !", seeYou: "À bientôt !", comeBackSoon: "Salut ! Reviens bientôt.",
        veryGood: "Très bien !", questComplete: "Mission accomplie !", youWon: "Tu as gagné !", goodDuel: "Beau duel !",
        lostWord: "Mot perdu !", goodJob: "Bon travail !", excellent: "Excellent !",
        thanksForShopping: "Merci pour vos achats !", shoppingList: "La liste de courses", howMuchTotal: "Ça fait combien en tout ?",
        duelGreetings: ["duel-mateo": "Je te défie en duel de mots !", "duel-nico": "Canela et moi, on est prêts !",
                        "duel-pepe": "Tu connais les noms de mes fruits ?", "duel-sol": "Voyons tout ce que tu as appris."],
        offlineIdeas: [1: "Greet each other in French at breakfast: \"Bonjour ! Comment ça va ?\"",
                       2: "Look at family photos together and name each person: \"C'est ma grand-mère.\"",
                       3: "At the store, let your child ask you \"C'est combien ?\" and answer with numbers up to 20."],
        countingIdea: "Count steps, stairs or toys aloud in French (un, deux, trois…).")

    public static let japanese = LocalPhrases(
        helloAgain: "また あいました ね、{name}！ れんしゅう しよう か？", yesPlease: "うん、おねがい！", duel: "ことば の しょうぶ！",
        notNow: "いまは いい です。", letsGo: "いこう！", seeYou: "またね！", comeBackSoon: "こんにちは！ また きて ね。",
        veryGood: "すごい！", questComplete: "ミッション クリア！", youWon: "かった！", goodDuel: "いい しょうぶ！",
        lostWord: "なくした ことば！", goodJob: "よく できました！", excellent: "すばらしい！",
        thanksForShopping: "ありがとう ございました！", shoppingList: "かいもの リスト", howMuchTotal: "ぜんぶで いくら？",
        duelGreetings: ["duel-mateo": "ことば の しょうぶ を しよう！", "duel-nico": "カネラ と ぼく は じゅんび オッケー！",
                        "duel-pepe": "くだもの の なまえ、わかる？", "duel-sol": "ならった こと を みて みましょう。"],
        offlineIdeas: [1: "Greet each other in Japanese at breakfast: \"おはよう！\" (ohayō) and bow a little.",
                       2: "Look at family photos together and name each person: \"おばあさん\" (obāsan, grandma).",
                       3: "At the store, let your child ask \"いくら ですか？\" (ikura desu ka, how much?) and answer in yen."],
        countingIdea: "Count steps, stairs or toys aloud in Japanese (いち, に, さん… ichi, ni, san…).")
}
