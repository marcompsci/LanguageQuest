"""Builds the one-unit starter courses in starter_langs.py.

Usage: starter.py <content-dir> <swift-out-file>
Writes <content-dir>/<course-id>/course.json and unit1-starter.json for every course,
plus a Swift file with each language's village signs, treasure words, NPC phrases and
badge names (so the village and side games speak the language too).
"""
import sys, os, json, unicodedata
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import item, phrase, listen, read, match, build, write, speak, reply, node, quest, dump, mkunit
from starter_langs import ALL

CONTENT, SWIFT_OUT = sys.argv[1], sys.argv[2]

def fold(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if not unicodedata.combining(c))

class Lang:
    def __init__(self, d):
        self.d = d
        self.latin = d["script"] == "latin"
        self.rom = {}           # native -> romanization (non-Latin scripts)
        self.code = d["code"]

    def nr(self, x):
        """(native, roman) from a data entry; registers the romanization."""
        if x is None: return None
        if isinstance(x, str): return (x, None)
        native, roman = x[0], (None if self.latin else x[1])
        if roman: self.rom[native] = roman
        return (native, roman)

    def w(self, key):
        """A vocabulary slot: (native, roman, english) or None."""
        x = self.d["W"].get(key)
        if x is None: return None
        if self.latin: return (x[0], None, x[1])
        self.rom[x[0]] = x[1]
        return (x[0], x[1], x[2])

    def reg(self, native, roman):
        if roman and not self.latin: self.rom[native] = roman
        return native

    def compose(self, *parts, sep=None):
        """Joins (native, roman) parts with the language's separator."""
        sep = self.d["join"] if sep is None else sep
        n = sep.join(p[0] for p in parts)
        r = " ".join(p[1] for p in parts) if not self.latin else None
        self.reg(n, r)
        return (n, r)

    def excl(self, entry):
        n, r = entry[0], entry[1]
        e = self.d["excl"]
        out = (n + e, (r + "!") if r else None)
        self.reg(*out)
        return out

    def name(self, who):
        x = self.d["names"][who]
        return self.nr(x)

    def sub(self, entry, X):
        """Fills {X} in a template entry with a (native, roman) name."""
        n = entry[0].replace("{X}", X[0])
        r = entry[1].replace("{X}", X[1] or X[0]) if entry[1] else None
        self.reg(n, r)
        return (n, r)

    def accepted(self, entry):
        n, r = entry[0], entry[1]
        out = [n]
        if r:
            out.append(r)
        return out

    def line(self, key):
        x = self.d["lines"][key]
        if self.latin: return (x[0], None, x[1])
        self.rom[x[0]] = x[1]
        return (x[0], x[1], x[2])


def expl(e):
    n, r, en = e
    return f"{n} ({r}) = {en}." if r else f"{n} = {en}."


def build_course(d):
    L = Lang(d)
    lib.set_language(d["name"])
    code = d["code"]; cid = d["id"]
    out = os.path.join(CONTENT, cid); os.makedirs(out, exist_ok=True)
    vid, vname, vnative, flag, voice, rvoice, cur, vnote = d["variant"]
    P = lambda s: f"{code}u1-{s}"
    rtl = d.get("rtl", False)

    # ---------- vocabulary ----------
    greet_keys = [k for k in ["hello","g2","g3","g4","bye"] if L.w(k)]
    polite_keys = [k for k in ["please","thanks","welcome","sorry","yes","no"] if L.w(k)]
    extra = d["W"].get("extra") or []
    phrase_keys = ["whatname","myname","nice","how","imfine","andyou"]
    W = {k: L.w(k) for k in greet_keys + polite_keys + phrase_keys}
    nums = [L.nr(x) for x in d["nums"]]
    num_en = ["one (1)","two (2)","three (3)","four (4)","five (5)","six (6)","seven (7)","eight (8)","nine (9)","ten (10)"]
    pics = {"hello":("👋","a waving hand"), "g4":("🌙","a crescent moon"), "thanks":("🙏","hands pressed together")}

    vocab = []
    for k in greet_keys + polite_keys:
        n, r, en = W[k]
        pic = pics.get(k)
        vocab.append(item(k, n, en, pic=pic[0] if pic else None, alt=pic[1] if pic else None))
    for i, (n, r) in enumerate(nums):
        vocab.append(item(f"n{i+1}", n, num_en[i], pos="number"))
    for (n, en, pic, alt) in extra:
        vocab.append(item(f"x-{fold(n)}", n, en, pic=pic, alt=alt))
    mateo = L.name("mateo")
    myname_mateo = L.sub(W["myname"][:2], mateo)
    phrases = []
    for k in phrase_keys:
        n, r, en = W[k]
        if k == "myname":
            phrases.append(phrase(k, n.replace("{X}", "…"), en.replace("{X}", "…"),
                                  ex=(myname_mateo[0], en.replace("{X}", "Mateo"))))
            L.reg(n.replace("{X}", "…"), r.replace("{X}", "…") if r else None)
        else:
            phrases.append(phrase(k, n, en))

    def ent(k):
        return W[k] if k in W else None

    def eng(k): return W[k][2]
    def nat(k): return W[k][0]
    def opts_for(right_en, pool_en, idx):
        """3 English options with the right one at idx."""
        others = [e for e in pool_en if e != right_en][:2]
        o = others[:]
        o.insert(idx, right_en)
        return o

    all_en = [W[k][2] for k in W] + num_en
    excl = L.excl
    quests = []

    # ---------- Quest 1: greetings (Luna) ----------
    hello, bye = W["hello"], W["bye"]
    wrong_greet = W.get("g4") or W.get("bye")
    l1, l2 = L.line("L1"), L.line("L2")
    gpairs = [(W[k][0], W[k][2]) for k in greet_keys]
    titles = d.get("titles", {})
    quests.append(quest(P("q1"), 1, titles.get(1, "Hello, village!"), "luna", "Luna's house",
        "Luna shows you around and teaches the first greetings.", "Greet people and say goodbye.",
        [node("n1","Luna",l1[0],l1[2],
              choices=[(excl(hello)[0], hello[2].capitalize()+"!","n2",True),
                       (excl(wrong_greet)[0], wrong_greet[2].capitalize()+"!","n1",False,
                        f"Luna just said hello! Try {hello[0]}.")],
              hint=f"Coco says: Answer with {hello[0]}{' ('+hello[1]+')' if hello[1] else ''}."),
         node("n2","Luna",l2[0],l2[2],effects=[("startQuest",P("q1"))])],
        [listen(P("q1-a1"), excl(bye)[0], bye[2].capitalize()+"!", opts_for(bye[2], [W[k][2] for k in greet_keys], 2), 2,
                ["bye"], "You say it when you leave.", expl(bye)),
         match(P("q1-a2"), gpairs, greet_keys, "Start with the ones you're sure of.", "Greetings: " + ", ".join(p[0] for p in gpairs) + ".",
               prompt=f"Match the {d['name']} to the English."),
         reply(P("q1-a3"), excl(hello)[0], hello[2].capitalize()+"!",
               [excl(W[polite_keys[0]] if polite_keys else W["g3"])[0], excl(hello)[0], excl(bye)[0]], 1, ["hello"],
               "Say the same greeting back.", expl(hello)),
         speak(P("q1-a4"), excl(hello)[0], hello[2].capitalize()+"!", ["hello"], "Listen first, then copy the sound.",
               expl(hello), accepted=L.accepted(hello))],
        30, cosmetic="scarf-yellow"))

    # ---------- Quest 2: names (Mateo) ----------
    l3, l4 = L.line("L3"), L.line("L4")
    myname_you = (W["myname"][0].replace("{X}", "{name}"), W["myname"][1].replace("{X}", "{name}") if W["myname"][1] else None)
    L.reg(*myname_you)
    acts2 = [read(P("q2-a1"), W["whatname"][0], W["whatname"][2], opts_for(W["whatname"][2], [W["how"][2], W["andyou"][2]], 0), 0,
                  ["whatname"], "Mateo asks this when he meets someone.", expl(W["whatname"]))]
    if rtl:
        acts2.append(reply(P("q2-a2"), W["whatname"][0], W["whatname"][2],
                           [myname_mateo[0], excl(W["thanks"])[0], W["andyou"][0]], 0, ["myname","whatname"],
                           "Answer with your name.", f"{myname_mateo[0]} = My name is Mateo."))
    else:
        tiles_src = d.get("myname_tiles")
        if tiles_src:
            tiles = [mateo[0] if t == "X" else L.nr(t)[0] for t in tiles_src]
        else:
            tiles = myname_mateo[0].rstrip(".。").split(" ")
        for t in tiles:
            pass
        acts2.append(build(P("q2-a2"), tiles, "My name is Mateo.", ["myname"], f"Start with {tiles[0]}.",
                           f"{myname_mateo[0]} = My name is Mateo.", distractors=[W["hello"][0]]))
    acts2 += [listen(P("q2-a3"), W["nice"][0], W["nice"][2], opts_for(W["nice"][2], [W["how"][2], W["bye"][2]], 2), 2,
                     ["nice"], "You say it when you meet someone new.", expl(W["nice"])),
              write(P("q2-a4"), W["nice"][2], L.accepted(W["nice"]), ["nice"],
                    "Mateo said it after hearing your name." + (f" You can type {W['nice'][1]}." if W['nice'][1] else ""), expl(W["nice"]))]
    quests.append(quest(P("q2"), 2, titles.get(2, "What's your name?"), "mateo", "The plaza",
        "Mateo wants to know your name.", "Ask someone's name and say your own.",
        [node("n1","Mateo",l3[0],l3[2],
              choices=[(myname_you[0], "My name is {name}.","n2",True),
                       (excl(W["thanks"])[0], W["thanks"][2].capitalize()+"!","n1",False,"Mateo asked your name! Say your name.")],
              hint="Coco says: Copy how Mateo said his name, then use yours."),
         node("n2","Mateo",l4[0],l4[2],effects=[("startQuest",P("q2"))])],
        acts2, 30, cosmetic="cap-red"))

    # ---------- Quest 3: how are you (Doña Rosa) ----------
    l5, l6 = L.line("L5"), L.line("L6")
    fine_andyou = L.compose(W["imfine"][:2], W["andyou"][:2])
    quests.append(quest(P("q3"), 3, titles.get(3, "How are you?"), "dona-rosa", "The bakery",
        "Doña Rosa the baker asks how you are.", "Ask how someone is and answer.",
        [node("n1","Doña Rosa",l5[0],l5[2],
              choices=[(fine_andyou[0], W["imfine"][2]+" "+W["andyou"][2],"n2",True),
                       (myname_mateo[0], "My name is Mateo.","n1",False,"She asked how you are, not your name!")],
              hint=f"Coco says: Say how you are, then ask back: {W['andyou'][0]}"),
         node("n2","Doña Rosa",l6[0],l6[2],effects=[("startQuest",P("q3"))])],
        [reply(P("q3-a1"), W["how"][0], W["how"][2], [W["whatname"][0], W["imfine"][0], excl(bye)[0]], 1,
               ["how","imfine"], "She wants to know how you are.", expl(W["imfine"])),
         read(P("q3-a2"), W["andyou"][0], W["andyou"][2], opts_for(W["andyou"][2], [W["how"][2], W["whatname"][2]], 1), 1,
              ["andyou"], "You use it to ask the question back.", expl(W["andyou"])),
         listen(P("q3-a3"), W["how"][0], W["how"][2], opts_for(W["how"][2], [W["whatname"][2], W["nice"][2]], 0), 0,
                ["how"], "Doña Rosa asked you this.", expl(W["how"])),
         speak(P("q3-a4"), W["imfine"][0], W["imfine"][2], ["imfine"], "Say it slowly.", expl(W["imfine"]),
               accepted=L.accepted(W["imfine"]))],
        30, cosmetic="apron"))

    # ---------- Quest 4: polite words / extra words (Don Pepe) ----------
    l7, l8 = L.line("L7"), L.line("L8")
    thanks = W["thanks"]
    wordset = [(W[k][0], W[k][2], k) for k in polite_keys]
    for (n, en, pic, alt) in extra:
        wordset.append((n, en, f"x-{fold(n)}"))
    wordset = wordset[:5]
    listen_pick = next((w for w in wordset if w[2] in ("sorry","please")), wordset[-1])
    wrong4 = W.get("sorry") or W.get("bye")
    quests.append(quest(P("q4"), 4, titles.get(4, "Magic words"), "don-pepe", "The market",
        "Don Pepe gives you a gift at his fruit stand.", "Say thank you and use polite words.",
        [node("n1","Don Pepe",l7[0],l7[2],
              choices=[(excl(thanks)[0], thanks[2].capitalize()+"!","n2",True),
                       (excl(wrong4)[0], wrong4[2].capitalize()+"!","n1",False,f"He's giving you a present! Try {thanks[0]}.")],
              hint=f"Coco says: When someone gives you something, say {thanks[0]}."),
         node("n2","Don Pepe",l8[0],l8[2],effects=[("startQuest",P("q4"))])],
        [match(P("q4-a1"), [(w[0], w[1]) for w in wordset], [w[2] for w in wordset], "Thank you is the one you hear most.",
               ", ".join(w[0] for w in wordset) + ".", prompt=f"Match the {d['name']} to the English."),
         reply(P("q4-a2"), l7[0], l7[2], [excl(thanks)[0], excl(bye)[0], W["whatname"][0]], 0, ["thanks"],
               "Someone gives you a present. What do you say?", expl(thanks)),
         listen(P("q4-a3"), listen_pick[0], listen_pick[1], opts_for(listen_pick[1], [thanks[2], hello[2]], 1), 1,
                [listen_pick[2]], "Listen for a polite word.", f"{listen_pick[0]} = {listen_pick[1]}."),
         write(P("q4-a4"), thanks[2], L.accepted(thanks), ["thanks"],
               "You just said it to Don Pepe." + (f" You can type {thanks[1]}." if thanks[1] else ""), expl(thanks))],
        30, cosmetic="glasses-round"))

    # ---------- Quest 5: numbers (Nico) ----------
    l9, l10 = L.line("L9"), L.line("L10")
    letsgo = L.nr(d["PH"]["letsGo"])
    quests.append(quest(P("q5"), 5, titles.get(5, "Count with Nico"), "nico", "Near the pond",
        "Nico and his dog Canela count everything they see.", "Count from 1 to 10.",
        [node("n1","Nico",l9[0],l9[2],
              choices=[(letsgo[0], "Let's go!","n2",True),
                       (excl(bye)[0], bye[2].capitalize()+"!","n1",False,"Nico wants to count with you! Say let's go.")]),
         node("n2","Nico",l10[0],l10[2],effects=[("startQuest",P("q5"))])],
        [listen(P("q5-a1"), nums[2][0], "three", ["2","3","8"], 1, ["n3"], "Count on your fingers.", f"{nums[2][0]} = 3."),
         match(P("q5-a2"), [(nums[i][0], str(i+1)) for i in range(5)], [f"n{i+1}" for i in range(5)], "Start with one.",
               ", ".join(nums[i][0] for i in range(5)) + ": 1 to 5.", prompt=f"Match the {d['name']} numbers."),
         read(P("q5-a3"), nums[6][0], "seven", ["6","7","9"], 1, ["n7"], "It comes after six.", f"{nums[6][0]} = 7."),
         write(P("q5-a4"), "two", L.accepted(nums[1]), ["n2"], "It comes after one." + (f" You can type {nums[1][1]}." if nums[1][1] else ""), f"{nums[1][0]} = 2."),
         speak(P("q5-a5"), nums[9][0], "ten", ["n10"], "The last number in this lesson.", f"{nums[9][0]} = 10.", accepted=L.accepted(nums[9]))],
        40, cosmetic="basket", badge="badge-u1"))

    mastery = {"id": P("mastery"), "passPercent": 80, "activities": [
        listen(P("m1"), excl(bye)[0], bye[2].capitalize()+"!", opts_for(bye[2], [hello[2], thanks[2]], 1), 1, ["bye"],
               "You say it when you leave.", expl(bye), practice="independent"),
        write(P("m2"), "hello", L.accepted(hello), ["hello"], "The first word Luna taught you.", expl(hello)),
        read(P("m3"), W["andyou"][0], W["andyou"][2], opts_for(W["andyou"][2], [W["whatname"][2], W["nice"][2]], 2), 2,
             ["andyou"], "You use it to ask back.", expl(W["andyou"]), practice="independent"),
        write(P("m4"), "five", L.accepted(nums[4]), ["n5"], "Count on one hand.", f"{nums[4][0]} = 5."),
        speak(P("m5"), W["nice"][0], W["nice"][2], ["nice"], "What do you say when you meet someone?", expl(W["nice"]),
              accepted=L.accepted(W["nice"]), practice="independent")]}

    notes = [{"id": f"{code}n-u1-{i+1}", "title": t, "body": b} for i, (t, b) in enumerate(d["notes"])]
    unit = mkunit(f"{code}u1-starter", 1, "Greetings & Introductions", d["title"],
                  "Greet people, introduce yourself, ask how someone is, use polite words, and count to ten.",
                  ["I can greet people and say goodbye.", "I can say my name and ask someone's name.",
                   "I can ask how someone is and answer.", "I can say thank you and use polite words.", "I can count from 1 to 10."],
                  "Novice Low", ["Cultures", "Comparisons"], vocab, phrases, notes, quests, mastery)
    unit["review"] = dict(lib.REVIEW, notes="Starter unit written by the development team. Needs review by a native speaker"
                          + (" or specialist in the ancient language" if d["category"] == "ancient" or code == "egy" else "")
                          + " before release. Audio uses on-device text-to-speech, which may not exist for this language.")

    # ---------- village words and phrases (also romanized) ----------
    signs = [L.nr(s) for s in d["signs"]]
    treasures = []
    for t in d["treasures"]:
        if t is None: treasures.append(None); continue
        if L.latin: treasures.append(((t[0], None), t[1]))
        else: treasures.append((L.nr((t[0], t[1])), t[2]))
    ph = {k: L.nr(v) for k, v in d["PH"].items()}
    ph["seeYou"] = excl(bye)

    course = {"schemaVersion": 1, "id": cid, "title": f"{d['name']} for English speakers", "sourceLanguage": "en",
              "targetLanguage": code, "languageName": d["name"], "nativeName": d["native"], "writingSystem": d["script"],
              "category": d["category"], "defaultVariant": vid,
              "variants": [{"id": vid, "name": vname, "nativeName": vnative, "flagEmoji": flag, "voiceLocales": voice,
                            "speechLocales": voice, "currency": {"code": cur[0], "singular": cur[1], "plural": cur[2], "symbol": cur[3]},
                            "usesVoseo": False, "note": vnote}],
              "unitFiles": ["unit1-starter.json"]}
    if rtl: course["rightToLeft"] = True
    if rvoice: course["variants"][0]["romanizedVoiceLocales"] = rvoice
    if d.get("typing"): course["typingKeys"] = d["typing"]
    if L.rom: course["romanizationOverrides"] = dict(sorted(L.rom.items()))
    dump(course, os.path.join(out, "course.json"))
    dump(unit, os.path.join(out, "unit1-starter.json"))
    return dict(code=code, cid=cid, signs=signs, treasures=treasures, ph=ph, d=d)


def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def main():
    built = [build_course(d) for d in ALL]
    sign_keys = ["Luna's house","The school","The bakery","The fountain","The market","Conversation Town lookout"]
    t_ids = ["t-flor","t-mariposa","t-abeja","t-sol","t-estrella","t-luna","t-arbol","t-nube","t-caracol","t-rana"]
    o = ["// Generated by tools/content-authoring/starter.py. Do not edit by hand.", "import Foundation", "",
         "extension StarterVillage {",
         "    /// Languages whose village words come from this file.",
         "    public static let generatedLanguages: Set<String> = [" + ", ".join(swift_str(b["code"]) for b in built) + "]", "",
         "    /// Sign text by English sign label, then language code.",
         "    public static let generatedSigns: [String: [String: String]] = ["]
    for i, k in enumerate(sign_keys):
        o.append(f"        {swift_str(k)}: [" + ", ".join(f"{swift_str(b['code'])}: {swift_str(b['signs'][i][0])}" for b in built) + "],")
    o += ["    ]", "",
          "    /// Treasure words by treasure id, then language code (fact nil = use the general fact).",
          "    public static let generatedTreasures: [String: [String: (word: String, fact: String?)]] = ["]
    for i, tid in enumerate(t_ids):
        parts = []
        for b in built:
            t = b["treasures"][i]
            if t is None: continue
            (w, _), fact = t
            parts.append(f"{swift_str(b['code'])}: ({swift_str(w)}, {swift_str(fact) if fact else 'nil'})")
        o.append(f"        {swift_str(tid)}: [" + ", ".join(parts) + "],")
    o += ["    ]", "}", "", "extension LocalPhrases {", "    static let generated: [String: LocalPhrases] = ["]
    for b in built:
        ph = {k: v[0] for k, v in b["ph"].items()}; d = b["d"]
        g = swift_str(ph["duelGreeting"])
        o.append(f"        {swift_str(b['code'])}: LocalPhrases(")
        o.append(f"            helloAgain: {swift_str(ph['helloAgain'])}, yesPlease: {swift_str(ph['yesPlease'])}, duel: {swift_str(ph['duel'])},")
        o.append(f"            notNow: {swift_str(ph['notNow'])}, letsGo: {swift_str(ph['letsGo'])}, seeYou: {swift_str(ph['seeYou'])}, comeBackSoon: {swift_str(ph['comeBackSoon'])},")
        o.append(f"            veryGood: {swift_str(ph['veryGood'])}, questComplete: {swift_str(ph['questComplete'])}, youWon: {swift_str(ph['youWon'])}, goodDuel: {swift_str(ph['goodDuel'])},")
        o.append(f"            lostWord: {swift_str(ph['lostWord'])}, goodJob: {swift_str(ph['veryGood'])}, excellent: {swift_str(ph['excellent'])},")
        o.append(f"            thanksForShopping: {swift_str(ph['thanksForShopping'])}, shoppingList: {swift_str(ph['shoppingList'])}, howMuchTotal: {swift_str(ph['howMuchTotal'])},")
        o.append(f"            duelGreetings: [\"duel-mateo\": {g}, \"duel-nico\": {g}, \"duel-pepe\": {g}, \"duel-sol\": {g}],")
        o.append(f"            offlineIdeas: [1: {swift_str(d['offline'])}],")
        o.append(f"            countingIdea: {swift_str(d['counting'])}),")
    o += ["    ]", "}", "", "extension Catalog {", "    static let generatedHeroNames: [String: (unit1: String, unit2: String, unit3: String, lang: String)] = ["]
    for b in built:
        d = b["d"]
        o.append(f"        {swift_str(b['cid'])}: ({swift_str(d['hero'])}, {swift_str(d['name'] + ' Friend')}, {swift_str(d['name'] + ' Pro')}, {swift_str(d['name'])}),")
    o += ["    ]", "}", ""]
    with open(SWIFT_OUT, "w", encoding="utf-8") as f: f.write("\n".join(o))

if __name__ == "__main__":
    main()
