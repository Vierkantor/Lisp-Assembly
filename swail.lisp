( doe
	( def lus ( gewoon ( doe ( ruim-vuilnis-op ) ( voer-uit ( lees-uitdrukking ) ) ) ) )
	( steeds ( voer-uit lus ) ) )

( def niks ( gewoon ( ) ) )

( def niet ( fn ( waarde )
	( beslis waarde niks iets ) ) )
( def en ( fn* a,b
	( laat a ( kop a,b )
	( laat b ( kop ( pel a,b ) )
	( beslis ( voer-uit a )
		( voer-uit b )
		niks ) ) ) ) )
( def of ( fn* a,b
	( laat a ( kop a,b )
	( laat b ( kop ( pel a,b ) )
	( beslis ( voer-uit a )
		iets
		( voer-uit b ) ) ) ) ) )

( def ! zet-op-adres )
( def @ geef-uit-adres )

( def beschrijving ( fn ( object )
	( @ ( adres object ) ) ) )

( def beschrijving-fn ( beschrijving ( fn ( ) ( niks ) ) ) )
( def beschrijving-getal ( beschrijving ( getal 0 ) ) )
( def beschrijving-koppel ( beschrijving ( koppel niks niks ) ) )
( def beschrijving-streng ( beschrijving ( streng _ ) ) )
( def beschrijving-ster ( beschrijving ( fn* _ ( niks ) ) ) )

( def ≠ ( fn ( a b )
	( niet ( = a b ) ) ) )
( def > ( fn ( a b )
	( < b a ) ) )
( def ≤ ( fn ( a b )
	( niet ( < b a ) ) ) )
( def ≥ ( fn ( a b )
	( niet ( < a b ) ) ) )

( def lengte ( fn ( str )
	( @ ( + ( adres str ) ( getal 8 ) ) ) ) )
( def karakters ( fn ( str )
	( + ( adres str ) ( getal 16 ) ) ) )
( def streng= ( fn ( str1 str2 )
	( beslis ( = ( lengte str1 ) ( lengte str2 ) )
		( gelijkheid-geheugen ( lengte str1 ) ( karakters str1 ) ( karakters str2 ) )
		niks ) ) )
( def maak-streng ( fn ( lengte )
	( laat resultaat-adres ( reserveer ( + lengte ( getal 16 ) ) )
	( doe
		( ! resultaat-adres beschrijving-streng )
		( ! ( + resultaat-adres ( getal 8 ) ) lengte )
		resultaat-adres ) ) ) )
( def leeg ( adres→object ( maak-streng ( getal 0 ) ) ) )
( def getal→karakter ( fn ( n )
	( laat n-adres ( adres n )
	( laat resultaat-adres ( maak-streng ( getal 1 ) )
	( doe
		( kopieer-byte ( + resultaat-adres ( getal 16 ) ) ( + n-adres ( getal 8 ) ) )
		( adres→object resultaat-adres ) ) ) ) ) )

( def spatie ( getal→karakter ( getal 32 ) ) )
( def '(' ( getal→karakter ( getal 40 ) ) )
( def ')' ( getal→karakter ( getal 41 ) ) )
( def symbool-begin-lijst '(' )
( def symbool-einde-lijst ')' )
( def symbool-begin-commentaar ( streng (* ) )
( def symbool-einde-commentaar ( streng *) ) )

( def lees-uitdrukkinglijst ( fn ( )
	( laat de-kop ( lees-uitdrukking )
	( beslis ( = ( adres de-kop ) ( adres einde-uitdrukking ) )
		niks
		( koppel de-kop ( lees-uitdrukkinglijst ) ) ) ) ) )
( def lees-tot-symbool-einde-commentaar ( fn ( diepte )
	( laat gelezen ( lees-woord )
	( beslis ( streng= gelezen symbool-einde-commentaar )
		( beslis ( < diepte ( getal 1 ) )
			niks
			( lees-tot-symbool-einde-commentaar ( - diepte ( getal 1 ) ) ) )
	( beslis ( streng= gelezen symbool-begin-commentaar )
		( lees-tot-symbool-einde-commentaar ( + diepte ( getal 1 ) ) )
		( lees-tot-symbool-einde-commentaar diepte ) ) ) ) ) )

( def lees-uitdrukking ( fn ( )
	( laat het-woord ( lees-woord )
	( beslis ( streng= het-woord symbool-begin-commentaar )
		( doe ( lees-tot-symbool-einde-commentaar ( getal 0 ) ) ( lees-uitdrukking ) )
	( beslis ( streng= het-woord symbool-begin-lijst )
		( lees-uitdrukkinglijst )
	( beslis ( streng= het-woord symbool-einde-lijst )
		einde-uitdrukking
	( koppel var ( koppel het-woord niks ) ) ) ) ) ) ) )

(* op dit punt kunnen we de haakjes (* en *) gebruiken voor commentaar *)
(* bovendien kun je ze stapelen, zoals hierboven :D *)

(* geef een getal met de waarde van de byte op het gegeven adres *)
( def @byte ( fn ( n-adres )
	( laat resultaat ( getal 0 )
	( laat resultaat-adres ( adres resultaat )
	( doe
		( kopieer-byte ( + resultaat-adres ( getal 16 ) ) ( + n-adres ( getal 8 ) ) )
		resultaat-adres ) ) ) ) )

(* voor n in [0..10[, geef een streng met het corresponderende cijfer *)
( def cijfer→streng ( fn ( n )
	( getal→karakter ( + ( getal 48 ) n ) ) ) )

(* geef een lijst van alle getallen tussen de twee eindpunten: [van..tot[ *)
( def herhaal ( fn ( van tot )
	( beslis ( < van tot )
		( koppel van ( herhaal ( + van ( getal 1 ) ) tot ) )
		niks ) ) )
(* geef een lijst van oplopende getallen beginnend bij een zeker getal *)
( def herhaal-keren ( fn ( van keren )
	( herhaal van ( + van keren ) ) ) )

(* lijstfunctor: pas een functie toe op elk element van de lijst *)
( def mep ( fn ( mepper gemept )
	( beslis gemept
		( koppel ( mepper ( kop gemept ) ) ( mep mepper ( pel gemept ) ) )
		niks ) ) )

(* lijstkatamorfisme: plak de elementen van de lijst aan elkaar met een functie
 * zo is ( vervouw + ( getal 0 ) een-lijst ) de som van de elementen in de lijst
 * de vervouwing is rechts-associatief: het laatste element van de lijst
 * wordt verkoppeld met het verniks, het een-na-laatste met de uitkomst, enz.
 *)
( def vervouw ( fn ( verkoppel verniks lijst )
	( beslis lijst
		( verkoppel ( kop lijst ) ( vervouw verkoppel verniks ( pel lijst ) ) )
		verniks ) ) )

(* mep een functie over het interval [van..tot[ *)
( def doe-herhaald ( fn ( van tot mepper )
	( mep mepper ( herhaal van tot ) ) ) )

(* kopieer een gegeven hoeveelheid bytes tussen adressen *)
( def kopieer-bytes ( fn ( adres-naar adres-van lengte )
	( doe-herhaald ( getal 0 ) lengte
		( fn ( afstand ) ( kopieer-byte ( + adres-naar afstand ) ( + adres-van afstand ) ) ) ) ) )

(* geef een streng die bestaat uit twee anderen op elkaar gelijmd *)
( def lijm-strengen ( fn ( voor achter )
	( laat lengte-voor ( lengte voor )
	( laat lengte-achter ( lengte achter )
	( laat lengte-totaal ( + lengte-voor lengte-achter )
	( laat adres-voor ( adres voor )
	( laat adres-achter ( adres achter )
	( laat adres-samen ( maak-streng lengte-totaal )
	( doe
		( kopieer-bytes ( + adres-samen ( getal 16 ) ) ( + adres-voor ( getal 16 ) ) lengte-voor )
		( kopieer-bytes ( + ( + adres-samen lengte-voor ) ( getal 16 ) ) ( + adres-achter ( getal 16 ) ) lengte-achter )
		( adres→object adres-samen ) ) ) ) ) ) ) ) ) )

(* geef een niet-negatief getal weer in een streng *)
( def getal→streng ( fn ( n )
	( laat q.r ( /% n ( getal 10 ) )
	( laat q ( kop q.r )
	( laat r ( pel q.r )
	( laat r-streng ( cijfer→streng r )
	( beslis ( = q ( getal 0 ) )
		r-streng
		( lijm-strengen ( getal→streng q ) r-streng ) ) ) ) ) ) ) )

(* zet een lijst van de vorm ( var naam ) om in een streng met de naam *)
( def var→streng ( fn ( var )
	( voer-uit ( koppel streng ( koppel var niks ) ) ) ) )

(* plak de stervoorwerpen, namen, aan elkaar met spaties *)
( def strengen ( fn* strs
	( vervouw
		( fn ( str rest ) ( lijm-strengen ( var→streng str ) ( lijm-strengen spatie rest ) ) )
		leeg
		strs ) ) )

(* geef of het voorwerp de beschrijving van een koppel heeft *)
( def is-koppel ( fn ( voorwerp )
	( = ( beschrijving voorwerp ) beschrijving-koppel ) ) )
(* geef of de uitdrukking een aanroep is naar var *)
( def is-aanroep-var ( fn ( uitdrukking )
	( en ( is-koppel uitdrukking ) ( = ( kop uitdrukking ) var ) ) ) )
(* vervang aanroepen naar var met de waarde in deze omgeving *)
( def vervang-var ( fn ( uitdrukking )
	( beslis ( is-aanroep-var uitdrukking )
		( voer-uit uitdrukking )
		uitdrukking ) ) )
(* vervang alle aanroepen naar var met de waarde in deze omgeving *)
( def verontvar-uitdrukking ( fn ( uitdrukking )
	( beslis ( is-koppel uitdrukking )
		( koppel ( vervang-var ( kop uitdrukking ) ) ( mep verontvar-uitdrukking ( pel uitdrukking ) ) )
		uitdrukking ) ) )
(* vervang alle aanroepen naar var met de waarde in deze omgeving *)
( def verontvar ( fn* uitdrukkingen ( verontvar-uitdrukking ( kop uitdrukkingen ) ) ) )

(* gegeven een lijst van alternatieven en wanneer ze geldig zijn,
 * geef de eerste die geldt.
 * de aanroep is dus van de vorm ( gevallen ( eis alternatief ) ... )
 * indien niets geldt, dan krijg je `niks'.
 * (merk op dat in principe alle eisen worden uitgevoerd,
 * maar alleen het kloppende alternatief.)
 *)
( def gevallen ( fn* alternatieven
	( laat geval' ( fn ( alternatieven )
		( vervouw alternatieven
		( fn ( eis.alt.niks zo-niet )
		( laat eis ( kop eis.alt.niks )
		( laat alt ( kop ( pel ( eis.alt.niks ) ) )
		( beslis ( voer-uit eis ) alt zo-niet ) ) ) )
		( gewoon niks ) ) )
	( voer-uit ( geval' alternatieven ) ) ) ) )

(* hexadecimaal ************************************************************ *)
(* om de een of andere reden moeten we wel eens omschakelen
 * tussen hexadecimale getallen en decimale getallen.
 * in deze Lisp gebeurt dat door expliciet aan te geven welk grondtal we hebben:
 * ( getal 10 ) staat voor het decimale grondtal,
 * en ( hex 10 ) staat voor het hexadecimale grondtal.
 *)

(* functie: zet een hexadecimaal cijfer om in een getal
 * het cijfer is weergegeven als een getal met de karakterwaarde.
 *)
( def cijfer-hex→getal ( fn ( ord )
	( gevallen
		( ( en ( ≥ ord ( getal 48 ) ) ( < ord ( getal 58 ) ) ) ( - ord ( getal 48 ) ) ) (* voor 0..9 *)
		( ( en ( ≥ ord ( getal 65 ) ) ( < ord ( getal 91 ) ) ) ( - ord ( getal 65 ) ) ) (* voor A..F *)
		( ( en ( ≥ ord ( getal 97 ) ) ( < ord ( getal 123 ) ) ) ( - ord ( getal 97 ) ) ) ) ) ) (* voor a..f *)

(* functie: lees een hexadecimaal getal uit een streng *)
( def streng-hex→getal ( fn ( str tot-nu-toe afstand )
	( beslis ( ≥ afstand ( lengte str ) )
		tot-nu-toe
		( laat adres-byte ( + ( adres str ) ( + ( getal 16 ) afstand ) )
		( laat cijfer ( cijfer-hex→getal ( @byte adres-byte ) )
		( + ( * tot-nu-toe ( getal 16 ) ) cijfer ) ) ) ) ) )
(* sterfunctie: lees een hexadecimaal getal uit een naam *)
( def hex ( fn* getal-niks
	( streng-hex→getal ( var→streng ( kop getal-niks ) ) ( getal 0 ) ( getal 0 ) ) ) )

(* assembly **************************************************************** *)
(* hoewel Lisp fijn is om in te programmeren, willen we vaak wat meer,
 * bijvoorbeeld een beroep doen op het systeem (dus een syscall).
 * hiervoor moeten we assembly kunnen programmeren in Lisp,
 * en daarvoor gaan we wat primitieve operaties definieren.
 * TEDOEN: denk na over het formaat:
 * geven we instructies weer als een lijst van getallen?
 * dat zijn precies de bytes in machinecode.
 * soms zijn instructies een functie, als er meer info nodig is.
 * (denk hier aan: welke registers er betrokken zijn)
 *
 * dus bijvoorbeeld:
 * ( def syscall ( koppel ( hex 0f ) ( hex 05 ) ) )
 * en:
 * ( def add ( fn ( van naar ) ( gevallen ( ( = van RAX ) ( ... ) ) ... ) ) )
 *)
(* TEDOEN: is dit het beste formaat om registers in weer te geven?
 * aangezien bijvoorbeeld eax en rax dezelfde encodering hebben,
 * alleen is het gebruik van RAX meestal voorafgegaan door REX.W
 *)
( def RAX ( getal 0 ) )
( def RCX ( getal 1 ) )
( def RDX ( getal 2 ) )
( def RBX ( getal 3 ) )
( def RSP ( getal 4 ) )
( def RBP ( getal 5 ) )
( def RSI ( getal 6 ) )
( def RDI ( getal 7 ) )
( def R8 ( getal 8 ) )
( def R9 ( getal 9 ) )
( def R10 ( getal 10 ) )
( def R11 ( getal 11 ) )
( def R12 ( getal 12 ) )
( def R13 ( getal 13 ) )
( def R14 ( getal 14 ) )
( def R15 ( getal 15 ) )

(* "leuke" uitdaging: herschrijf de implementatie met deze assembler :P *)

(* lokale functies ********************************************************* *)
(* nu wordt het tijd om functies iets netter te maken:
 * tot nu toe is de omgeving die ze gebruiken die van de aanroep,
 * maar beter is om ze de omgeving van definitie mee te geven.
 *
 * TEDOEN!
 *)

(* meta-informatie ********************************************************* *)
(* functie: bepaal hoeveel bytes aan geheugen nog niet volgeschreven zijn *)
( def ruimte-over ( fn ( )
	( - ( @ vrije-ruimte ) ( @ begin-vrije-ruimte ) ) ) )
(* functie: bepaal hoeveel bytes aan geheugen volgeschreven kunnen worden *)
( def ruimte-totaal ( fn ( )
	( - ( @ einde-vrije-ruimte ) ( @ begin-vrije-ruimte ) ) ) )

(* functie: toon hoeveel geheugenruimte gebruikt en beschikbaar is *)
( def geheugenoverzicht ( fn ( ) ( doe
	( schrijf ( streng Ruimtegebruik: ) )
	( schrijf ( getal→karakter ( getal 32 ) ) )
	( schrijf ( getal→streng ( ruimte-over ) ) )
	( schrijf ( streng / ) )
	( schrijf ( getal→streng ( ruimte-totaal ) ) )
	( schrijf ( getal→karakter ( getal 10 ) ) ) ) ) )

(* functie: schrijf een regeltje voor gebruikersinvoer *)
( def prompt ( fn ( ) ( doe
	( geheugenoverzicht )
	( schrijf ( strengen >>> ) ) ) ) )

(* we stoppen de prompt in de lus pas zodra de bieb ingelezen is *)
( def lus ( gewoon ( doe ( ruim-vuilnis-op ) ( prompt ) ( voer-uit ( lees-uitdrukking ) ) ) ) )
