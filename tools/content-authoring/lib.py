import json
LANG_NAME="Spanish"
def set_language(name):
    global LANG_NAME
    LANG_NAME=name
def V(base, **ov):
    if not ov: return base
    d={"base":base}
    for k,v in ov.items(): d[k.replace("_","-")]=v
    return d
def item(id, es, en, kind="word", pic=None, alt=None, ex=None, pos=None, gender=None, note=None):
    d={"id":id,"kind":kind,"target":es,"english":en}
    if pos: d["partOfSpeech"]=pos
    if gender: d["gender"]=gender
    if pic: d["picture"]=pic; d["altText"]=alt
    if ex: d["example"]={"target":ex[0],"english":ex[1]}
    if note: d["note"]=note
    return d
def phrase(id, es, en, **kw): return item(id, es, en, kind="phrase", **kw)
LET="abcd"
def _choices(opts, answer, pics=None):
    cs=[]
    for i,o in enumerate(opts):
        c={"id":LET[i],"text":o}
        if pics and pics[i]: c["picture"]=pics[i][0]; c["altText"]=pics[i][1]
        cs.append(c)
    return cs, LET[answer]
def _base(id,typ,skill,mode,practice,prompt,items,hint,expl):
    return {"id":id,"type":typ,"skill":skill,"mode":mode,"practice":practice,"prompt":prompt,"items":items,"hint":hint,"explanation":expl}
def listen(id, es, en, opts, ans, items, hint, expl, practice="guided", pics=None, prompt="Listen. What does it mean?"):
    d=_base(id,"listenChoose","listening","interpretive",practice,prompt,items,hint,expl)
    d["target"]=es; d["targetEnglish"]=en
    d["choices"],d["answer"]=_choices(opts,ans,pics); return d
def read(id, es, en, opts, ans, items, hint, expl, practice="guided", prompt="Read. What does it mean?"):
    d=_base(id,"readChoose","reading","interpretive",practice,prompt,items,hint,expl)
    d["target"]=es; d["targetEnglish"]=en
    d["choices"],d["answer"]=_choices(opts,ans); return d
def match(id, pairs, items, hint, expl, prompt="Match the Spanish to the English."):
    d=_base(id,"match","reading","interpretive","guided",prompt,items,hint,expl)
    d["pairs"]=[{"target":a,"english":b} for a,b in pairs]; return d
def build(id, tiles, en, items, hint, expl, distractors=(), prompt=None):
    d=_base(id,"buildSentence","writing","presentational","guided",prompt or f"Build the sentence: “{en}”",items,hint,expl)
    d["tiles"]=list(tiles); d["targetEnglish"]=en
    if distractors: d["distractors"]=list(distractors)
    return d
def fill(id, sentence, opts, ans, items, hint, expl, en=None, prompt="Pick the word that fits."):
    d=_base(id,"fillBlank","reading","interpretive","guided",prompt,items,hint,expl)
    d["sentence"]=sentence
    if en: d["targetEnglish"]=en
    d["choices"],d["answer"]=_choices(opts,ans); return d
def write(id, en, accepted, items, hint, expl, practice="independent", prompt=None):
    d=_base(id,"typeAnswer","writing","presentational",practice,prompt or f"Write in {LANG_NAME}: “{en}”",items,hint,expl)
    d["targetEnglish"]=en; d["accepted"]=list(accepted); return d
def speak(id, es, en, items, hint, expl, accepted=None, practice="guided", prompt=None):
    d=_base(id,"speak","speaking","presentational",practice,
            prompt or ("Say it out loud." if practice=="guided" else f"Say in {LANG_NAME}: “{en}”"),items,hint,expl)
    d["target"]=es; d["targetEnglish"]=en; d["accepted"]=list(accepted or [es]); return d
def reply(id, heard, heard_en, opts, ans, items, hint, expl, practice="guided", prompt="Pick the best reply."):
    d=_base(id,"dialogueReply","listening","interpersonal",practice,prompt,items,hint,expl)
    d["target"]=heard; d["targetEnglish"]=heard_en
    d["choices"],d["answer"]=_choices(opts,ans); return d
def node(id, speaker, line, gloss, next=None, choices=None, effects=None, hint=None):
    d={"id":id,"speaker":speaker,"line":line,"gloss":gloss}
    if next: d["next"]=next
    if choices:
        d["choices"]=[]
        for c in choices:
            t,g,n=c[0],c[1],c[2]
            cc={"text":t,"gloss":g,"next":n}
            if len(c)>3:
                cc["correct"]=c[3]
                if len(c)>4: cc["feedback"]=c[4]
            d["choices"].append(cc)
    if effects: d["effects"]=[{"kind":k,"value":v} for k,v in effects]
    if hint: d["hint"]=hint
    return d
def quest(id, order, title, npc, location, summary, objective, nodes, acts, xp, cosmetic=None, badge=None):
    r={"xp":xp}
    if cosmetic: r["cosmetic"]=cosmetic
    if badge: r["badge"]=badge
    return {"id":id,"order":order,"title":title,"npc":npc,"location":location,"summary":summary,"objective":objective,
            "dialogue":{"start":nodes[0]["id"],"nodes":nodes},"activities":acts,"reward":r}
def dump(obj, path):
    with open(path,"w",encoding="utf-8") as f: json.dump(obj,f,ensure_ascii=False,indent=2); f.write("\n")
REVIEW={"text":"authored","audio":"draft","reviewers":[],
        "notes":"Written by the development team. Needs review by native-speaker linguists for each regional variant before release. Audio uses on-device text-to-speech until native recordings are made."}
def mkunit(id, order, title, target_title, objective, can_do, level, goals, vocab, phrases, notes, quests, mastery):
    return {"id":id,"version":1,"order":order,"title":title,"targetTitle":target_title,"world":"starter-village",
            "objective":objective,"canDo":can_do,
            "actfl":{"modes":["interpretive","interpersonal","presentational"],"targetLevel":level,"otherGoals":goals},
            "ageBands":["11-12","13-15","16+"],"review":REVIEW,"vocabulary":vocab,"phrases":phrases,
            "culturalNotes":notes,"quests":quests,"masteryCheck":mastery}
