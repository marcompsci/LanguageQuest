import sys; import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
OUT=sys.argv[1]
def cur(code,s,p,sym): return {"code":code,"singular":s,"plural":p,"symbol":sym}
course={"schemaVersion":1,"id":"en-es","title":"Spanish for English speakers","sourceLanguage":"en","targetLanguage":"es",
 "languageName":"Spanish","nativeName":"Español",
 "defaultVariant":"es-419",
 "variants":[
  {"id":"es-419","name":"Latin America (general)","nativeName":"Latinoamérica","flagEmoji":"🌎","voiceLocales":["es-MX","es-US","es-419"],"speechLocales":["es-419","es-MX","es-US"],"currency":cur("MXN","peso","pesos","$"),"usesVoseo":False,"note":"A neutral Latin American Spanish understood everywhere. Uses Mexican pesos in market examples."},
  {"id":"es-MX","name":"Mexico","nativeName":"México","flagEmoji":"🇲🇽","voiceLocales":["es-MX","es-US"],"speechLocales":["es-MX","es-US"],"currency":cur("MXN","peso","pesos","$"),"usesVoseo":False,"note":"The Spanish most often heard in the United States."},
  {"id":"es-ES","name":"Spain","nativeName":"España","flagEmoji":"🇪🇸","voiceLocales":["es-ES"],"speechLocales":["es-ES"],"currency":cur("EUR","euro","euros","€"),"usesVoseo":False,"note":"Spain uses words like zumo and patata. (Plural vosotros is introduced in a later unit.)"},
  {"id":"es-AR","name":"Argentina","nativeName":"Argentina","flagEmoji":"🇦🇷","voiceLocales":["es-AR","es-419","es-MX"],"speechLocales":["es-AR","es-419","es-MX"],"currency":cur("ARS","peso","pesos","$"),"usesVoseo":True,"note":"Argentina uses vos instead of tú: ¿Cómo te llamás? ¿Tenés…?"},
  {"id":"es-CO","name":"Colombia","nativeName":"Colombia","flagEmoji":"🇨🇴","voiceLocales":["es-CO","es-419","es-MX"],"speechLocales":["es-CO","es-419","es-MX"],"currency":cur("COP","peso","pesos","$"),"usesVoseo":False,"note":"Colombian Spanish is known for being clear and polite; usted is very common."},
  {"id":"es-PR","name":"Caribbean (Puerto Rico)","nativeName":"El Caribe (Puerto Rico)","flagEmoji":"🇵🇷","voiceLocales":["es-US","es-PR","es-MX"],"speechLocales":["es-US","es-MX"],"currency":cur("USD","dólar","dólares","$"),"usesVoseo":False,"note":"Puerto Rico uses U.S. dollars and words like guineo for banana."}
 ],
 "unitFiles":["unit1-saludos.json","unit2-familia.json","unit3-mercado.json"]}
dump(course, OUT+"/course.json")
