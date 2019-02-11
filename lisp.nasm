bits 64

; Code ------------------------------------------------------------------------
; We gebruiken het aanroepgebruik waarbij de aanroeper alles zelf opslaat,
; behalve de volgende registers:
;  rbx (wijst naar de huidige omgeving)
;  rsp (wijst naar de stapel)
; De aangeroepen code zorgt ervoor dat rbx teruggezet wordt.
; Bij aanroepen wijst rsp naar het terugkeeradres,
;  en bij terugkeren wijst het een stapelplek lager.
;  (Maar zie ook het speciale geval!)
;
; Daarnaast wordt rax gebruikt voor voorwerpen en resultaten:
;  bij het aanroepen van code staat het voorwerp in rax,
;  en het resultaat van de aanroep staat daar ook.
; Ten slotte staat bij aanroepen het object in rsi.
; (Dat wil zeggen, bij uitvoeren, doorverwijzen, afmeten en opruimen.)
; Allebei deze registers moeten ook opgeruimd worden door de aanroeper.
;
; Een speciaal geval is het teruggeven van een lijst wijzers:
;  in dat geval is rax het aantal wijzers dat teruggegeven wordt,
;  en staan de wijzers zelf bovenop de stapel.
;  (Bovenop dus de wijzers van de lijst, daaronder de overslawijzer enzovoort.)
;
; Zoals vermeld is de top van de stapel het terugkeeradres.
; Daaronder staat de overslawijzer naar het volgende terugkeeradres.
; Daaronder staan willekeurig veel wijzers naar objecten.
; Daaronder staat weer een terugkeeradres (waar de overslawijzer heenwijst).
; (Maar zie ook het speciale geval hierboven!)
; Dit is nodig om de vuilnisopruiming goed te laten verlopen.

; Objecten --------------------------------------------------------------------
; We gebruiken een dynamisch dataformaat om onze gegevens op te slaan.
; Alle informatie om uit te voeren en op te ruimen staat in code tussen de data.
; Dat betekent dat we goed overweg kunnen met exotische objecten.
; In principe hebben we veel objecten met hetzelfde formaat,
; dus we gebruiken een tweetrapsformaat.
; Een object begint met een wijzer, de `beschrijving'.
; Die wijst naar een structuur met de ``echte'' informatie.
;
; Elk object ziet er dus uit als:
; +- - - - - - - - +- - - ... +
; | beschrijving   | data     |
; +- - - - - - - - +- - - ... +
;
; Een beschrijving bestaat uit de volgende onderdelen, in deze volgorde:
; * `overbeschrijving', 64 bits; (voorlopig) gelijk aan 0.
; * `uitvoering', 64 bits; wijst naar code.
; * `afmeting', 64 bits; wijst naar code.
; * `doorverwijzing', 64 bits; wijst naar code.
; * `opruiming', 64 bits; wijst naar code.
;
; De overbeschrijving is gereserveerd voor toekomstig gebruik.
;
; De uitvoering wijst naar code die een voorwerp neemt (in rax)
; en een object (in rsi), en het object toepast op dat voorwerp.
;
; De afmeting wijst naar code die het adres van een object neemt (in rsi)
; en de lengte in bytes geeft, inclusief beschrijving.
;
; De doorverwijzing wijst naar code die het adres van een object neemt (in rsi)
; en een lijst van adressen van wijzers geeft.
; (Let op: als je bij het uitvoeren een nieuwe beschrijving aanmaakt,
; telt dit ook als een wijzer!)
;
; De opruiming wijst naar code die het adres van een object neemt (in rsi)
; en eventuele troep (zoals geopende bestanden) opruimt.
; (Deze ruimt beter *niet* objecten uit de doorverwijzing op!)

; Definities ------------------------------------------------------------------
; Een definitie is niets anders dan een adres een naam geven.
; De volgende macro's zorgen ervoor dat het net iets makkelijker gaat.

; Definieer een symbool om verderop te gebruiken.
; Liever wil je een afgeleid macro gebruiken,
; zodat je zeker weet dat je het goede soort symbool definieert.
%macro DEF 1
	global %1
	%1:
%endmacro

; Definieer een symbool dat wijst naar code.
%macro DEF_CODE 1
	section .text
	DEF %1
%endmacro

; Definieer een symbool dat wijst naar data.
%macro DEF_DATA 1
	section .data
	DEF %1
%endmacro

; Definieer een symbool dat wijst naar onwijzigbare data.
%macro DEF_VAST 1
	section .rodata
	DEF %1
%endmacro

; Definieer een type met een unieke bewoner.
; Dit kun je bijvoorbeeld gebruiken voor losse symbolen als `niks',
; en/of voor speciale resultaatwaarden.
%macro DEF_UNIEK 1
DEF_VAST %1
	dq 0
	dq ongeldig
	dq ongeldig
	dq ongeldig
%endmacro

; Koppels ---------------------------------------------------------------------
; Zoals het een lisp betaamt, draait alles om koppels.
; Een koppel is niets anders dan een beschrijving gevolgd door twee wijzers.
; De eerste heet `de kop' en de andere `het pel'. (Hier is over nagedacht!)
; Deze wijzers wijzen uiteraard ook weer naar andere koppels,
; maar je wilt hier niet oneindig diep mee gaan.
; Daarom is er een speciaal symbool (genaamd `niks'),
; dat op geheugenplek 0 staat,
; en staat voor "hier is niets te vinden".
; Dit wordt bijvoorbeeld gebruikt om het einde van lijsten aan te geven.
DEF_UNIEK niks

; Benodigdheden ---------------------------------------------------------------
; We definiëren wat afkortingen en speciale constanten.

; Zie <asm/unistd_64.h> voor deze definities.
syscall_read equ 0
syscall_write equ 1
syscall_brk equ 12
syscall_exit equ 60

; Code, deel 2 ----------------------------------------------------------------
; Voordat we verder gaan, moeten we eerst wat macro's maken.
; In deze macro's staat basale code voor dingen als een object toepassen.

; Geef de beschrijving van een object.
; De beschrijving komt in %1.
; Het object staat in %2.
; Past alleen %1 aan.
%macro NEEM_BESCHRIJVING 2
	mov %1, [%2]
%endmacro

; Geef de uitvoering van een object.
; De uitvoering komt in %1.
; Het object staat in %2.
; Past alleen %1 aan.
%macro NEEM_UITVOERING 2
	NEEM_BESCHRIJVING %1, %2
	mov %1, [%1 + 8]
%endmacro

; Geef de afmeting van een object.
; De afmeting komt in %1.
; Het object staat in %2.
; Past alleen %1 aan.
%macro NEEM_AFMETING 2
	NEEM_BESCHRIJVING %1, %2
	mov %1, [%1 + 16]
%endmacro

; Geef de doorverwijzing van een object.
; De afmeting komt in %1.
; Het object staat in %2.
; Past alleen %1 aan.
%macro NEEM_DOORVERWIJZING 2
	NEEM_BESCHRIJVING %1, %2
	mov %1, [%1 + 24]
%endmacro

; Pas het object in rsi toe op rax.
; Past de stapel niet aan, daar moet je zelf voor zorgen.
; Sloopt rcx.
%macro PAS_TOE 0
	NEEM_UITVOERING rcx, rsi
	jmp rcx
%endmacro

; Stop een aanroepstuk op de stapel.
; Deze macro's horen bij elkaar, en kun je gebruiken als:
; BEGIN_BEWAREN
; push een_voorwerp
; push ander_voorwerp
; EIND_BEWAREN
; push terugkeeradres
;
; BEGIN_BEWAREN en EIND_BEWAREN gebruiken rbp om dingen door te geven,
; die wordt gesloopt en mag tussendoor niet veranderen.
;
; Heb je niets om te bewaren in je aanroepstuk, gebruik dan BEWAAR_NIETS.
%macro BEGIN_BEWAREN 0
	mov rbp, rsp
%endmacro
%macro EIND_BEWAREN 0
	push rbp
%endmacro
%macro BEWAAR_NIETS 0
	push rsp
%endmacro

; Het tegenovergestelde van BEWAREN:
; haal een aanroepstuk van de stapel.
%macro VERGEET 0
	mov rsp, [rsp]
%endmacro

; Stop uitvoering met resultaatcode %1.
%macro STOP 1
	mov rdi, %1
	mov rax, syscall_exit
	syscall
%endmacro

; Geef een foutmelding, met fouttekst in %1.
%macro FOUTMELDING 1
	mov rsi, %1
	call foutmelding
%endmacro
; Geef een foutmelding, met fouttekst in rsi.
DEF_CODE foutmelding
	mov rax, rsi
	call doe_schrijven
	STOP 1

; Hulpcode om te gebruiken als een operatie ongeldig is.
; De fouttekst wordt gedefinieerd nadat MAAK_STRENG bestaat.
DEF_CODE ongeldig
	FOUTMELDING ongeldig_fouttekst

; Hulpcode om te gebruiken als er niets hoeft te gebeuren.
DEF_CODE meteen_klaar
	ret
; Hulpcode om te gebruiken als een object alleen beschrijving heeft.
DEF_CODE geen_afmeting
	mov rax, 8
	ret
; Hulpcode om te gebruiken als er geen doorverwijzing gebeurt.
DEF_CODE geen_doorverwijzing
	mov rax, 0
	ret

; Koppels, deel 2 -------------------------------------------------------------
; We beginnen met koppelspecifieke macro's.

; Geef in %1 de kop van %2.
%macro NEEM_KOP 2
	mov %1, [%2 + 8]
%endmacro
; Geef in %1 het pel van %2.
%macro NEEM_PEL 2
	mov %1, [%2 + 16]
%endmacro

; Nu is het tijd om echte koppels te maken.
; Ten eerste willen we de beschrijving:
DEF_DATA beschrijving_koppel
	dq 0 ; overbeschrijving
	dq uitvoering_koppel
	dq afmeting_koppel
	dq doorverwijzing_koppel
	dq meteen_klaar ; opruiming
; Om een koppel op een voorwerp toe te passen,
; moeten we eerst de kop toepassen op het pel,
; en het resultaat daarvan uitvoeren.
DEF_CODE uitvoering_koppel
	; Bewaar het voorwerp op de stapel.
	BEGIN_BEWAREN
	push rax
	EIND_BEWAREN
	push .koppel_is_toegepast
	; Pas de kop toe op het pel.
	NEEM_PEL rax, rsi
	NEEM_KOP rsi, rsi
	PAS_TOE

	; Het resultaat staat in rax, en het voorwerp op de stapel.
	; We zijn dus klaar om ze op elkaar aan te roepen.
.koppel_is_toegepast:
	mov rsi, rax ; We willen het resultaat aanroepen
	mov rax, [rsp + 8] ; op het voorwerp op de stapel.
	VERGEET ; We zijn klaar met deze code.
	PAS_TOE
; Een koppel heeft een beschrijving en twee wijzers, dus is 3*8 bytes lang.
DEF_CODE afmeting_koppel
	mov rax, 24
	ret
; Doorverwijzen is best makkelijk: geef gewoon de kop en het pel.
DEF_CODE doorverwijzing_koppel
	pop rcx
	add rsi, 8
	push rsi
	add rsi, 8
	push rsi
	mov rax, 2
	jmp rcx

; Reken het koppel uit dat in rax staat en zet het in rax.
; Dit is dus in principe pas (kop rax) toe op (pel rax).
; Sloopt rcx en rsi.
DEF_CODE stap
	NEEM_KOP rsi, rax
	NEEM_PEL rax, rax
	PAS_TOE
%macro STAP 0
	jmp stap
%endmacro

; Nu kunnen we macro's maken om (alleen-lezen)-koppels te definiëren.

; Definieer een koppel met naam %1, kop %2 en pel %3.
%macro MAAK_KOPPEL 3
DEF_VAST %1
	dq beschrijving_koppel
	dq %2
	dq %3
%endmacro
; Definieer een lijst met naam %1, en inhoud %2.
%macro MAAK_LIJST 2
	MAAK_KOPPEL %1, %2, niks
%endmacro
; Definieer een lijst met naam %1, en inhoud %2, %3.
%macro MAAK_LIJST 3
	MAAK_KOPPEL %%deel_2, %3, niks
	MAAK_KOPPEL %1, %2, %%deel_2
%endmacro
; Definieer een lijst met naam %1, en inhoud %2, %3, %4.
%macro MAAK_LIJST 4
	MAAK_KOPPEL %%deel_3, %4, niks
	MAAK_KOPPEL %%deel_2, %3, %%deel_3
	MAAK_KOPPEL %1, %2, %%deel_2
%endmacro

; Strengen --------------------------------------------------------------------
; De C-taal ten spijt is het toch fijner als strengen eruit zien als een lengte
; plus een rijtje karakters.
; Dat is dus ook hoe ze voorkomen in deze Lisp.

; Strengen hebben een simpele beschrijving:
DEF_DATA beschrijving_streng
	dq 0 ; overbeschrijving
	dq ongeldig ; uitvoering
	dq afmeting_streng ; staat verderop ivm benodigde macro's.
	dq geen_doorverwijzing
	dq meteen_klaar ; opruiming

; Definieer een streng met naam %1, lengte %2 en karakters %3.
%macro MAAK_STRENG 3
DEF_VAST %1
	dq beschrijving_streng
	dq %2
	db %3
%endmacro

; Geef in %1 de lengte van %2.
%macro NEEM_LENGTE 2
	mov %1, [%2 + 8]
%endmacro
; Geef in %1 het adres van de karakters van %2.
%macro NEEM_KARAKTERS 2
	lea %1, [%2 + 16]
%endmacro

DEF_CODE afmeting_streng
	NEEM_LENGTE rax, rsi
	add rax, 16 ; We hebben een beschrijving en de lengte zelf.
	ret

; Omdat MAAK_STRENG nog niet gedefinieerd was hierboven,
; moet ongeldig_fouttekst nu gedefinieerd worden.
MAAK_STRENG ongeldig_fouttekst, 27, `Deze operatie is ongeldig!\n`

; Getallen --------------------------------------------------------------------
; Zodat het geheugen er een beetje goed uitziet,
; zetten we getallen in een object in plaats van direct in geheugen.
; Een getal in geheugen ziet eruit als | beschrijving | waarde |.

DEF_DATA beschrijving_getal
	dq 0 ; overbeschrijving
	dq ongeldig ; uitvoering
	dq afmeting_getal
	dq geen_doorverwijzing
	dq meteen_klaar ; opruiming
; Een getal heeft een beschrijving en waarde.
DEF_CODE afmeting_getal
	mov rax, 16
	ret

; Definieer een streng met naam %1 en waarde %2.
%macro MAAK_GETAL 2
DEF_VAST %1
	dq beschrijving_getal
	dq %2
%endmacro

; Geef in %1 de waarde van het getal in %2.
%macro NEEM_WAARDE 2
	mov %1, [%2 + 8]
%endmacro

; Omgevingen ------------------------------------------------------------------
; We willen kunnen werken met variabelen die in een of andere omgeving staan.
; In `_start' wordt een omgeving in rbx gestopt,
; op basis van de definities die gebruik maken van de komende macro's.
;
; Een omgeving ziet eruit als een lijst van lemmata: koppels (naam . waarde),
; met naam een streng.
; Deze vorm is makkelijk doorzoekbaar en niet te onvriendelijk te definiëren

; De buitenomgeving is de omgeving die we gebruiken bij het opstarten.
; Zet een kop op de buitenomgeving om een nieuwe waarde beschikbaar te maken.
%define BUITENOMGEVING niks

; Stop een waarde in de buitenomgeving.
; %1 is de naam,
; %2 is de waarde.
%macro ZET_BUITEN 2
%strlen naamlengte %1
MAAK_STRENG %%naam, naamlengte, %1
MAAK_KOPPEL %%lemma, %%naam, %2
MAAK_KOPPEL %%omgeving, %%lemma, BUITENOMGEVING
%define BUITENOMGEVING %%omgeving
%endmacro

; Variabelen ------------------------------------------------------------------
; Variabelen worden hier weergegeven als adressen.
; Om een variabele uit te lezen, moet je dus de waarde op het adres uitlezen.

; Definieer een variabele met Lispnaam %1 en adres %2.
%macro VARIABELE 2
MAAK_GETAL %%var, %2
ZET_BUITEN %1, %%var
%endmacro

; Opstarten -------------------------------------------------------------------
; We hebben gelukkig niet heel veel nodig om op te starten:
; we moeten een omgeving hebben en een stuk geheugen om op te werken.

; Wijst naar de eerste byte van vrij bewerkbare ruimte.
; Wordt door _start geïnitialiseerd.
DEF_DATA begin_vrije_ruimte
	dq 0
VARIABELE "begin-vrije-ruimte", begin_vrije_ruimte
; Wijst naar de eerste ongebruikte byte van vrij bewerkbare ruimte.
; Wordt door _start geïnitialiseerd.
DEF_DATA vrije_ruimte
	dq 0
VARIABELE "vrije-ruimte", vrije_ruimte
; Wijst naar het einde van vrij bewerkbare ruimte.
; Wordt door _start geïnitialiseerd.
DEF_DATA einde_vrije_ruimte
	dq 0
VARIABELE "einde-vrije-ruimte", einde_vrije_ruimte
; Wijst naar de eerste byte van het alternatieve stuk geheugen.
; Wordt door _start geïnitialiseerd.
DEF_DATA begin_levende_ruimte
	dq 0
VARIABELE "begin-levende-ruimte", begin_levende_ruimte
; Wijst naar de eerste ongebruikte byte van het alternatieve stuk geheugen.
; Wordt door _start geïnitialiseerd.
DEF_DATA levende_ruimte
	dq 0
VARIABELE "levende-ruimte", levende_ruimte
; Wijst naar het einde van het alternatieve geheugen.
; Wordt door _start geïnitialiseerd.
DEF_DATA einde_levende_ruimte
	dq 0
VARIABELE "einde-levende-ruimte", einde_levende_ruimte

; Zorg ervoor dat we geheugen hebben om onze koppels in te zetten.
; De bedoeling is dat dit helemaal aan het begin van uitvoering
; aangeroepen wordt (mbv call).
; Sloopt o.a. %rax en %rbx.
;
; Gebaseerd op code overgenomen uit Jones Forth.
%define INITIAL_DATA_SEGMENT_SIZE 0x1000000
DEF_CODE set_up_data_segment
	mov rdi, 0
	mov rax, syscall_brk
	syscall
	mov [begin_vrije_ruimte], rax
	mov [vrije_ruimte], rax
	mov rdi, rax
	add rdi, INITIAL_DATA_SEGMENT_SIZE
	mov rax, syscall_brk
	syscall
	mov [einde_vrije_ruimte], rax
	mov [begin_levende_ruimte], rax
	mov [levende_ruimte], rax
	add rdi, INITIAL_DATA_SEGMENT_SIZE
	mov rax, syscall_brk
	syscall
	mov [einde_levende_ruimte], rax
	; Eventueel willen we hier controleren dat we daadwerkelijk ruimte hebben?
	ret

; Data in elkaar zetten -------------------------------------------------------
; Tot nu toe konden we al wel data in de interpreter neerzetten,
; maar nog niet in de code maken.
; De volgende code lost dat op.

; Maak een nieuw koppel (%1 . %2).
; Uitkomst komt in rax.
; Sloopt r8: %1 en %2 mogen dat dus niet zijn.
; %1 en %2 mogen wel rax en [rsp] zijn(!)
%macro KOPPEL 2
	; Haal de voorwerpen uit de weg: eerst naar registers
	; en dan op de stapel (niet direct, want dan werkt [rsp] niet meer.)
	mov r8, %1
	mov rax, %2
	push rax
	push r8
	; Zet het koppel in elkaar.
	mov rax, [vrije_ruimte]
	mov qword [rax], beschrijving_koppel
	pop qword [rax + 8]
	pop qword [rax + 16]
	; Werk de vrije ruimte bij.
	mov r8, rax
	add r8, 24
	mov [vrije_ruimte], r8
%endmacro

; Maak een nieuwe streng van lengte %1.
; Uitkomst komt in rax.
; %1 mag rax zijn(!)
; Hierna kun je de karakters naar [vrije_ruimte] kopiëren.
%macro STRENG 1
	; Zie ook de inhoud van KOPPEL.
	mov rax, %1
	push rcx
	mov rcx, rax
	; Zet de streng in elkaar.
	mov rax, [vrije_ruimte]
	mov qword [rax], beschrijving_streng
	mov [rax + 8], rcx
	; Werk de vrije ruimte bij:
	; rcx is de lengte van de streng zelf
	add rcx, 8 ; plus de ruimte nodig voor de lengte
	add rcx, rax ; plus [vrije_ruimte] is de nieuwe waarde
	mov [vrije_ruimte], rcx
	pop rcx
%endmacro

; Maak een nieuw getal met waarde %1.
; Uitkomst komt in rax.
; %1 mag rax zijn(!)
%macro GETAL 1
	; Zie ook de inhoud van KOPPEL.
	mov rax, %1
	push rcx
	mov rcx, rax
	mov rax, [vrije_ruimte]
	mov qword [rax], beschrijving_getal
	mov [rax + 8], rcx
	add qword [vrije_ruimte], 16
	pop rcx
%endmacro

; Ingebakken functies ---------------------------------------------------------
; Nu zijn we klaar om functies te definiëren die in Lisp aan te roepen zijn.

; Een functie geven we weer als | beschrijving (8) | code (...) |
DEF_DATA beschrijving_functie
	dq 0 ; overbeschrijving
	dq uitvoering_functie
	dq geen_afmeting
	dq geen_doorverwijzing
	dq meteen_klaar ; opruiming
DEF_CODE uitvoering_functie
	add rsi, 8
	jmp rsi

; Begin van een functie die voorwerpen niet uitrekent.
%macro FN 1
DEF_CODE %1
	dq beschrijving_functie
.code:
%endmacro
; Begin van een functie die 1 voorwerp uitrekent.
; Hierna staat:
;  voorwerp 1 in rax
%macro FN_VOORWERPEN_1 1
FN %1
	; Eventueel willen we controleren op de juiste voorwerpvorm?
	NEEM_KOP rax, rax
	BEWAAR_NIETS
	; reken uit en kom terug
	push .klaar_1
	STAP
.klaar_1:
	VERGEET
%endmacro
; Begin van een functie die 2 voorwerpen uitrekent.
; Hierna staat:
;  voorwerp 1 in rcx
;  voorwerp 2 in rax
%macro FN_VOORWERPEN_2 1
FN %1
	; Eventueel willen we controleren op de juiste voorwerpvorm?

	; Splits voorwerpen op.
	NEEM_PEL rcx, rax
	NEEM_KOP rax, rax
	; Het pel (rcx) gaat op de stapel en de kop (rax) wordt uitgerekend.
	BEGIN_BEWAREN
	push rcx
	EIND_BEWAREN
	push .klaar_1
	STAP
.klaar_1:
	; Nu is rax de waarde van de kop en [rsp+8] een lijst uit te rekenen waarden.
	; We hadden al wat ruimte op de stapel, wissel dat in
	mov rcx, [rsp+8]
	mov [rsp+8], rax
	NEEM_KOP rax, rcx
	push .klaar_2
	STAP
.klaar_2:
	; Onthoud voorwerp 1.
	mov rcx, [rsp+8]
	VERGEET
%endmacro
; Begin van een functie die 3 voorwerpen uitrekent.
; Hierna staat:
;  voorwerp 1 in rdx
;  voorwerp 2 in rcx
;  voorwerp 3 in rax
%macro FN_VOORWERPEN_3 1
FN %1
	; Eventueel willen we controleren op de juiste voorwerpvorm?

	; Splits voorwerpen op: 1 -> rax, 2 -> rcx, 3 -> rdx
	NEEM_PEL rcx, rax
	NEEM_KOP rax, rax
	NEEM_PEL rdx, rcx
	NEEM_KOP rcx, rcx
	NEEM_KOP rdx, rdx
	; Bewaar voorwerpen, 3 onder 2.
	BEGIN_BEWAREN
	push rdx
	push rcx
	EIND_BEWAREN
	push .klaar_1
	STAP
.klaar_1:
	; Nu is rax de waarde van voorwerp 1 en [rsp+8], [rsp+16] uitdrukkingen 2 + 3
	; Wissel 1 en 2 om en reken 2 uit.
	mov rcx, [rsp+8]
	mov [rsp+8], rax
	mov rax, rcx
	push .klaar_2
	STAP
.klaar_2:
	; Wissel 2 en 3 om en reken 3 uit.
	mov rcx, [rsp+16]
	mov [rsp+16], rax
	mov rax, rcx
	push .klaar_3
	STAP
.klaar_3:
	; Stop alles weer in registers:
	; 1 -> rdx
	; 2 -> rcx
	; 3 -> rax
	mov rcx, [rsp+16]
	mov rdx, [rsp+8]
	VERGEET
%endmacro

; Lispfunctie: reken voorwerp 1 en 2 uit en koppel de uitkomsten.
FN_VOORWERPEN_2 koppel
	; Nu is rcx de waarde van de kop en rax van het pel
	KOPPEL rcx, rax
	ret
ZET_BUITEN "koppel", koppel

; Lispfunctie: reken voorwerp 1 uit en neem de kop ervan.
FN_VOORWERPEN_1 kop
	; Controleer of dit wel pelneembaar is.
	cmp qword [rax], beschrijving_koppel
	je .neem_kop
	FOUTMELDING fout_kop
.neem_kop:
	NEEM_KOP rax, rax
	ret
MAAK_STRENG fout_kop, 37, `Daar kan ik toch geen kop van nemen!\n`
ZET_BUITEN "kop", kop
; Lispfunctie: reken voorwerp 1 uit en neem het pel ervan.
FN_VOORWERPEN_1 pel
	; Controleer of dit wel pelneembaar is.
	cmp qword [rax], beschrijving_koppel
	je .neem_pel
	BEGIN_BEWAREN
	push rax
	EIND_BEWAREN
	FOUTMELDING fout_pel
.neem_pel:
	NEEM_PEL rax, rax
	ret
MAAK_STRENG fout_pel, 37, `Daar kan ik toch geen pel van nemen!\n`
ZET_BUITEN "pel", pel

; Lispfunctie: geef voorwerp 1 terug zonder verder te rekenen.
FN gewoon
	; Eventueel willen we controleren op de juiste voorwerpvorm?
	NEEM_KOP rax, rax
	ret
ZET_BUITEN "gewoon", gewoon

; Lispfunctie: reken het voorwerp uit en voer de code erin uit.
FN_VOORWERPEN_1 voer_uit
	; De uit te voeren code staat in %rax, dus we kunnen gewoon een stap zetten.
	STAP
ZET_BUITEN "voer-uit", voer_uit

; Lispfunctie: blijf steeds het voorwerp uitrekenen.
FN steeds
	NEEM_KOP rax, rax
	BEGIN_BEWAREN
	push rax
	EIND_BEWAREN
.herhaald:
	mov rax, [rsp + 8]
	push .herhaald
	STAP
ZET_BUITEN "steeds", steeds

; Lispfunctie: beslis of voorwerp 1 niet `niks' is,
; voer voorwerp 2 uit indien iets,
; en voorwerp 3 indien niks.
FN beslis
	BEGIN_BEWAREN
	NEEM_KOP rcx, rax
	NEEM_PEL rax, rax
	NEEM_KOP rdx, rax
	push rdx
	NEEM_PEL rax, rax
	NEEM_KOP rdx, rax
	push rdx
	EIND_BEWAREN
	mov rax, rcx
	push .geval_uitgerekend
	STAP
.geval_uitgerekend:
	; hier is rax de waarde van het geval,
	; [ rsp + 8 ] code bij niks
	; en [ rsp + 16 ] code bij iets
	cmp rax, niks
	je .is_niks
	mov rax, [rsp + 16]
	VERGEET
	STAP
.is_niks:
	mov rax, [rsp + 8]
	VERGEET
	STAP
ZET_BUITEN "beslis", beslis

; Lispfunctie: voer alle voorwerpen 1 voor 1 uit.
; Geeft het laatste resultaat.
; (Hebben we geen voorwerpen gekregen, is het resultaat `niks'.)
FN doe
	; rax is een lijst van uit te voeren voorwerpen
	; die komen ook in [rsp+8]
	BEGIN_BEWAREN
	push rax
	EIND_BEWAREN
.doe_meer:
	; Ga door tot we niks hebben.
	mov rcx, [rsp+8]
	cmp rcx, niks
	je .doe_niks_meer
	NEEM_PEL rax, rcx
	mov [rsp+8], rax
	NEEM_KOP rax, rcx
	push .doe_meer
	STAP
.doe_niks_meer:
	VERGEET
	ret
ZET_BUITEN "doe", doe

; Lispfunctie: wordt aangeroepen als de voortzetting leeg is.
FN klaar
	STOP rax
ZET_BUITEN "klaar", klaar

; Lispfunctie: geef het voorwerp terug, maar gdb stopt hierop.
FN_VOORWERPEN_1 kever
	ret
ZET_BUITEN "kever", kever

; Rekenen ---------------------------------------------------------------------
; Nu komen wat basale operaties op getallen.
; Ze hebben allemaal dezelfde structuur: lees de waarde van wat parameters uit,
; en stop een nieuw getal in %rax.
; Vandaar het volgende macro:

; Definieer een functie genaamd %1,
; die een voorwerp uitrekent
; en de instructie %2 op de getalswaarde (in rax) doet.
; Resultaat is het getal met getalswaarde rax.
%macro FN_GETAL_1 2
FN_VOORWERPEN_1 %1
	NEEM_WAARDE rax, rax
	%2
	GETAL rax
	ret
%endmacro
; Definieer een functie genaamd %2,
; die twee voorwerpen uitrekent
; en de instructie %2 op de getalswaarde (in rax en rdx resp) doet.
; Resultaat is het getal met getalswaarde rax.
; De reden voor rax en rdx is dat dit ook de volgorde is van idiv.
%macro FN_GETAL_2 2
FN_VOORWERPEN_2 %1
	NEEM_WAARDE rdx, rax
	NEEM_WAARDE rax, rcx
	%2
	GETAL rax
	ret
%endmacro

; Hoog voorwerp op met 1
FN_GETAL_1 incr, {inc rax}
ZET_BUITEN "+1", incr
; Verlaag voorwerp met 1
FN_GETAL_1 decr, {dec rax}
ZET_BUITEN "-1", decr
; Tel twee voorwerpen bij elkaar op
FN_GETAL_2 plus, {add rax, rdx}
ZET_BUITEN "+", plus
; Trek voorwerp 2 af van voorwerp 1
FN_GETAL_2 min, {sub rax, rdx}
ZET_BUITEN "-", min
; Vermenigvuldig twee voorwerpen.
; We negeren het geval dat de uitkomst niet in 64 bits past.
FN_GETAL_2 keer, {imul rax, rdx}
ZET_BUITEN "*", keer
; Deel voorwerp 1 door voorwerp 2 en geef een koppel (quotiënt . rest).
FN_VOORWERPEN_2 deelmod
	xchg rax, rcx ; Wissel de voorwerpen om ivm de volgorde van idiv
	NEEM_WAARDE rax, rax
	NEEM_WAARDE rcx, rcx
	cqo ; We willen rax delen op rcx, maar idiv doet rdx:rax. Signextend dus.
	idiv rcx
	GETAL rax
	mov rcx, rax
	GETAL rdx
	KOPPEL rcx, rax
	ret
ZET_BUITEN "/%", deelmod

; We moeten ook getallen kunnen invoeren in de code.
; Om verwarring met namen te voorkomen, schrijf je een getal op als
; ( getal 37 ) (dus niet `37' letterlijk).
; Dit maakt de uitdrukkinglezer ook een stukje eenvoudiger.
FN getal
	; rax is ((var . getalnaam . niks) . niks), maak daar `getalnaam' van.
	NEEM_KOP rax, rax
	NEEM_PEL rax, rax
	NEEM_KOP rax, rax
	; rcx wordt de (overgebleven) lengte, rsi de karakters en rdx het resultaat.
	NEEM_LENGTE rcx, rax
	NEEM_KARAKTERS rsi, rax
	mov rax, 0 ; zet op 0 zodat lezen naar al en optellen met rax goed gaat
	mov rdx, 0
	; TEDOEN: negatieve getallen
.lees_volgend_cijfer:
	cmp rcx, 0
	jle .getal_gelezen
	imul rdx, 10 ; er komt een extra cijfer in het resultaat
	lodsb ; lees 1 byte uit [rsi] naar al en hoog rsi op
	sub al, '0' ; gelukkig zijn cijfers opeenvolgend in ASCII
	add rdx, rax ; we hebben de bitjes die buiten al vallen al op 0 gezet
	dec rcx
	jmp .lees_volgend_cijfer
.getal_gelezen:
	; rdx bevat het resultaat, stop dat in een object
	GETAL rdx
	ret
ZET_BUITEN "getal", getal

; Lispwaarde: generieke waarde die niet `niks' is.
DEF_UNIEK iets
ZET_BUITEN "iets", iets
; Lispfunctie: beslis of twee getallen gelijk zijn.
; Zo ja, geeft `iets', zo nee, geeft `niks'.
FN_VOORWERPEN_2 gelijkheid_getallen
	; Hier is rcx het ene getal-object en rax het andere.
	NEEM_WAARDE rcx, rcx
	NEEM_WAARDE rax, rax
	cmp rax, rcx
	jne .geef_niks
	mov rax, iets
	ret
.geef_niks:
	mov rax, niks
	ret
ZET_BUITEN "=", gelijkheid_getallen
; Lispfunctie: beslis of twee getallen strikt ongelijk zijn.
; Zo ja, geeft `iets', zo nee, geeft `niks'.
FN_VOORWERPEN_2 ongelijkheid_getallen
	; Hier is rcx het ene getal-object en rax het andere.
	NEEM_WAARDE rcx, rcx
	NEEM_WAARDE rax, rax
	cmp rcx, rax
	jge .geef_niks
	mov rax, iets
	ret
.geef_niks:
	mov rax, niks
	ret
ZET_BUITEN "<", ongelijkheid_getallen

; Werken met geheugen ---------------------------------------------------------
; We hebben ook wat functies om redelijk direct met geheugen om te gaan.
; Geheugenadressen worden weergegeven als getallen.

; Lispfunctie: geef de waarde achter het adres als 64-bits getal.
FN_VOORWERPEN_1 geef_uit_adres
	; hier is rax een getal met het adres.
	NEEM_WAARDE rax, rax
	GETAL [rax]
	ret
ZET_BUITEN "geef-uit-adres", geef_uit_adres

; Lispfunctie: geef het object waar het adres naar wijst.
FN_VOORWERPEN_1 geef_object_uit_adres
	; hier is rax een getal met het adres.
	NEEM_WAARDE rax, rax
	ret
ZET_BUITEN "adres→object", geef_object_uit_adres

; Lispfunctie: zet op het adres de gegeven waarde (als 64-bits getal).
FN_VOORWERPEN_2 zet_op_adres
	; hier is rcx een getal met het adres en rax een getal met de waarde.
	NEEM_WAARDE rcx, rcx
	NEEM_WAARDE rax, rax
	mov [rcx], rax
	ret
ZET_BUITEN "zet-op-adres", zet_op_adres

; Lispfunctie: kopieer een losse byte naar het doeladres van het bronadres.
FN_VOORWERPEN_2 kopieer_byte
	; hier is rax een getal met het bronadres en rcx een getal met het doeladres.
	NEEM_WAARDE rax, rax
	NEEM_WAARDE rcx, rcx
	mov al, byte [rax]
	mov byte [rcx], al
	ret
ZET_BUITEN "kopieer-byte", kopieer_byte

; Lispfunctie: reserveer de gegeven hoeveelheid bytes aan vrij geheugen.
FN_VOORWERPEN_1 reserveer
	NEEM_WAARDE rax, rax
	mov rcx, [vrije_ruimte]
	add rax, rcx
	; hier is rax het einde van de gereserveerde ruimte en rcx het begin
	mov [vrije_ruimte], rax
	GETAL rcx
	ret
ZET_BUITEN "reserveer", reserveer

; Lispfunctie: geef een getal met het adres van het voorwerp.
; (Let op dat dit adres misschien niet meer klopt als vuilnis opgeruimd wordt!)
; Zo geeft bijvoorbeeld ( @ ( adres object ) ) de beschrijving van een object.
FN_VOORWERPEN_1 adres
	GETAL rax
	ret
ZET_BUITEN "adres", adres

; Lispfunctie: beslis of twee stukken geheugen gelijk zijn.
; Voorwerpen: lengte, wijzer 1, wijzer 2.
; Zo ja, geeft `iets', zo nee, geeft `niks'.
FN_VOORWERPEN_3 gelijkheid_geheugen
	; Hier is rax wijzer 2, rcx wijzer 1 en rdx lengte.
	NEEM_WAARDE rsi, rax
	NEEM_WAARDE rdi, rcx
	NEEM_WAARDE rcx, rdx
	; vergelijk rdi en rsi over rcx bytes.
	repe cmpsb
	jne .geef_niks
	mov rax, iets
	ret
.geef_niks:
	mov rax, niks
	ret
ZET_BUITEN "gelijkheid-geheugen", gelijkheid_geheugen

; Vuilnis opruimen ------------------------------------------------------------
; Het uitvoeren van al deze code gebruikt geheugen,
; en we hebben geen zin om al het geheugengebruik handmatig aan te pakken.
; We ruimen dit op met een dubbele buffer:
; Om de zoveel tijd verhuizen we alle bestaande waarden
; naar een ander stuk geheugen.
; Dat wordt dan de plek van de vrije ruimte.
; Na verloop van tijd raakt die vol, en doen we de omgekeerde verhuizing.

; TEDOEN: fix dat functies niet netjes worden verhuisd
; (Stel dat je een functie in de vrije ruimte hebt gedefinieerd,
;  die uitvoert, en dan `ruim-vuilnis-op' wordt aangeroepen.
;  Dan wordt de functie onder je vandaan gehaald.)

; Kopieer het object in rax naar het levende deel
; en geef de nieuwe wijzer in rax.
; (Dus [rax] is de beschrijving voor en na.)
DEF_CODE verhuis_levend_object
	; We hoeven alleen te verhuizen als het staat in de vrije ruimte.
	; (We gaan ervan uit dat dat een continu stuk geheugen is.)
	cmp rax, [begin_vrije_ruimte]
	jl .niks_te_verhuizen
	cmp rax, [einde_vrije_ruimte]
	jge .niks_te_verhuizen

	; Verhuis eerst alles waar het object naartoe wijst
	push rax ; Onthoud het oorspronkelijke object tot we het verhuizen.
	NEEM_DOORVERWIJZING rcx, rax
	mov rsi, rax
	call rcx
.verhuis_doorverwijzingen:
	; Hier is rax het aantal adressen dat op de stapel staat,
	; en staan bovenop de stapel de adressen van wijzers naar objecten.
	; Daaronder staat het oorspronkelijke object.
	cmp rax, 0
	jle .verhuis_inhoud_object

	; Verhuis het object bovenop de stapel.
	pop rsi ; De wijzer naar het object staat in [rsi].
	dec rax ; Onthoud hoeveel nog op de stapel staat.
	; Ons resultaat wordt overschreven, onthoud die dus.
	push rax
	push rsi
	; Ga in recursie: verhuis het volgende object op de stapel.
	mov rax, [rsi]
	call verhuis_levend_object
	; Nu wijst rsp naar | huidige locatie | $n$ (= # te verplaatsen) | [$n$ andere locaties] | oorspronkelijke object | rest van de stapel,
	; en is rax het verhuisde object.
	pop rsi
	mov [rsi], rax ; Update de locatie.

	; Door naar volgend object:
	; de huidige locatie is al weggepopt, nu rax nog.
	pop rax
	jmp .verhuis_doorverwijzingen
.verhuis_inhoud_object:
	; Verhuis het object zelf. Wijzers in het object zijn al goed.
	; Hier wijst [rsp] naar het object.
	; Eerst bepalen hoe groot het is.
	mov rsi, [rsp] ; We doen nog een aanroep dus houd het object op de stapel.
	NEEM_AFMETING rcx, rsi
	call rcx
	; Hier is rax de afmeting, maar die willen we liever in rcx ivm x86.
	mov rcx, rax
	pop rsi
	mov rdi, [levende_ruimte]
	mov rax, rdi ; Onthoud waar we beginnen met kopiëren: het resultaat.
	; Herhaal tot rcx=0: kopieer van [rsi++] naar [rdi++].
	rep movsb
	mov [levende_ruimte], rdi ; Update de levende ruimte.
	; rax wijst naar de kopie van het object, dus klaar :D
	ret
.niks_te_verhuizen:
	; rax is het te verhuizen object maar die staat er al prima.
	; Dus gewoon teruggeven.
	ret

; Lispfunctie: doe het vuilnisophaalproces.
; Deze werkt het beste als je data eruit ziet als een mooie boom,
; anders kunnen er nog wel eens kopietjes gemaakt worden.
; Deze werkt alleen als je data eruit ziet als een gerichte acyclische graaf.
FN ruim_vuilnis_op
	; Omdat we de stapel onder handen gaan nemen,
	; bewaren we de vuilnisophaaltoestand niet op de stapel.

	; Het laatste ongebruikte stuk stapel staat in rsi.
	mov rsi, rsp
.lees_stapelstuk:
	; Hier is rsi het volgende stapelstuk om op te ruimen.
	; Is rsi al op de bodem, dan zijn we klaar met opruimen.
	cmp rsi, [stapel_bodem]
	jge .stapel_opgeruimd

	; [rsi] is een terugkeeradres,
	; [rsi + 8] is een overslawijzer (die komt in rcx),
	; en alles tussen rsi + 16 en [rsi + 8] is een wijzer.
	mov rcx, [rsi + 8] ; rcx is de overslawijzer
	add rsi, 16
	; Ga over alle wijzers heen.
.wijzers_tussen_rsi_en_rcx:
	; Zijn we al aangekomen bij het volgende stuk?
	cmp rcx, rsi
	je .lees_stapelstuk
	push rcx
	push rsi
	; We willen het object in [rsi] verhuizen.
	mov rax, [rsi]
	call verhuis_levend_object
	; Update de wijzer.
	pop rsi
	mov [rsi], rax
	pop rcx
	; ga naar de volgende wijzer
	add rsi, 8
	jmp .wijzers_tussen_rsi_en_rcx
.stapel_opgeruimd:
	; Stapel is opgeruimd, dus ruim ook de omgeving op.
	mov rax, rbx
	call verhuis_levend_object
	mov rbx, rax

	; De levende ruimte is nu helemaal leeg,
	; maar begint bij het begin van de (oude) vrije ruimte.
	mov rax, [levende_ruimte]
	mov [vrije_ruimte], rax
	mov rax, [begin_vrije_ruimte]
	mov [levende_ruimte], rax

	; Nu hebben we de levende ruimte klaargezet om als vrije ruimte te werken,
	; dus wissel de uiteinden van de vrije en de levende ruimte om.
	; TEDOEN: kan dit beter?
	mov rax, [begin_levende_ruimte]
	xchg rax, [begin_vrije_ruimte]
	mov [begin_levende_ruimte], rax

	mov rax, [einde_levende_ruimte]
	xchg rax, [einde_vrije_ruimte]
	mov [einde_levende_ruimte], rax

	; Helemaal klaar!
	ret
ZET_BUITEN "ruim-vuilnis-op", ruim_vuilnis_op

; De stapelwijzer als er helemaal niets opstaat.
; Wordt door `_start' geïnitialiseerd.
DEF_DATA stapel_bodem
	dq 0

; Strengen --------------------------------------------------------------------
; We hadden wat functies met strengen in Assembly,
; die willen we ook in Lisp beschikbaar hebben.

; Lispfunctie: vat een woord (het voorwerp) op als streng.
; Dus bijvoorbeeld ( streng hoi ) geeft "hoi".
FN streng
	; rax is (( var . naam . niks ) . niks )
	NEEM_KOP rax, rax
	NEEM_PEL rax, rax
	NEEM_KOP rax, rax
	; Gelukkig is het voorwerp van `var' een streng, dus we zijn klaar.
	ret
ZET_BUITEN "streng", streng

; Invoer en uitvoer -----------------------------------------------------------

; Lispfunctie: lees een losse byte in en geef die als streng.
; Werkt blokkerend.
; Past [vrije_ruimte] aan.
; Roept doe_lezen aan, zie aldaar voor implementatie.
FN lees
	call doe_lezen
	mov cl, al
	STRENG 1 ; rax is nu een streng van lengte 1
	mov [rax + 8], cl
	ret

; Assemblyfunctie: lees een losse byte in en geef die in al.
; Werkt blokkerend.
; Past [vrije_ruimte] niet aan.
; Dit werkt door een buffertje bij te houden van zojuist gelezen tekst.
; Code is geïnspireerd op Jones Forth.
%define BUFFERGROOTTE 256
DEF_CODE doe_lezen
	; Bepaal of we moeten lezen of kunnen teruggeven.
	mov rsi, [huidig_leesbuffer]
	cmp rsi, [einde_leesbuffer]
	jl .bytes_klaar
	; Tijd om invoer te lezen.
	mov rdi, 0 ; lees uit stdin
	mov rsi, leesbuffer ; naar de leesbuffer
	mov rdx, BUFFERGROOTTE ; maximaal BUFFERGROOTE bytes.
	mov rax, syscall_read
	syscall
	; Uitkomst staat in rax, en is de hoeveelheid gelezen bytes.
	; TEDOEN: controleer op einde van de invoer.
	add rax, rsi ; Dus plus begin leesbuffer geeft het einde.
	mov [einde_leesbuffer], rax
	; Val door naar beneden.
.bytes_klaar:
	; In [rsi] (oftewel [leesbuffer]) staan de bytes om te lezen.
	lodsb ; Laad een byte vanuit rsi naar al en increment rsi.
	mov [huidig_leesbuffer], rsi
	ret

DEF_DATA leesbuffer
	times BUFFERGROOTTE db 0
DEF_DATA einde_leesbuffer
	dq leesbuffer
DEF_DATA huidig_leesbuffer
	dq leesbuffer

; Lispfunctie: lees een lispwoord in.
; (Dit is wat anders dan een menselijk woord!)
; Woorden worden afgescheiden met witruimte: een of meer '\n', '\t' of ' '.
; Als er witruimte voor het woord staat, dan wordt die overgeslagen.
; Als er witruimte na het woord staat, dan wordt het eerste karakter ingelezen.
; Geeft een streng.
; Werkt blokkerend.
; Past [vrije_ruimte] aan.
FN lees_woord
	; Lees een los teken in tot het niet witruimte is.
.zolang_witruimte:
	; Roep `doe_lezen' aan, zodat het volgende teken in al staat.
	call doe_lezen
	cmp al, `\n`
	je .zolang_witruimte
	cmp al, `\t`
	je .zolang_witruimte
	cmp al, ' '
	je .zolang_witruimte

	; We zijn door de witruimte heen, lees dus het woord.
	; rdi bevat de ruimte voor de hele streng.
	mov rdi, [vrije_ruimte]
	mov qword [rdi], beschrijving_streng
	add rdi, 16 ; maak ruimte voor beschrijving en lengte.
.zolang_letters:
	; Bewaar al (de zojuist gelezen byte) in [rdi] en increment rdi.
	; Bedankt, complexe instructieset!
	stosb
	; Lees het volgende karakter in.
	BEGIN_BEWAREN
	push rdi ; `doe_lezen' kan deze gaan slopen.
	EIND_BEWAREN
	call doe_lezen
	VERGEET
	mov rdi, [rsp - 8]
	; Herhaal tot er opeens witruimte langskomt.
	cmp al, `\n`
	je .opeens_witruimte
	cmp al, `\t`
	je .opeens_witruimte
	cmp al, ' '
	je .opeens_witruimte
	jmp .zolang_letters
.opeens_witruimte:
	; Einde van het woord, dus bouw een net antwoord.
	; rdi wijst naar de eerste vrije byte,
	; dus dat min het begin van de buffer is de lengte.
	; De buffer begint 16 bytes na de oorspronkelijke vrije ruimte.
	mov rax, [vrije_ruimte]
	mov [vrije_ruimte], rdi
	sub rdi, rax
	sub rdi, 16
	; Schrijf de lengte op (beschrijving en karakters waren al klaar).
	mov [rax + 8], rdi
	ret
ZET_BUITEN "lees-woord", lees_woord

; Lispfunctie: schrijf een streng naar het scherm.
; Teruggegeven waarde is niet gedefinieerd.
; De bijbehorende assemblyfunctie is doe_schrijven.
FN_VOORWERPEN_1 schrijf
doe_schrijven:
	; hier wijst rax naar de streng.
	mov rdi, 1 ; schrijf naar stdout
	lea rsi, [rax + 16] ; rsi wijst naar de karakters
	mov rdx, [rax + 8] ; rdx bevat de lengte
	mov rax, syscall_write
	syscall
	ret
ZET_BUITEN "schrijf", schrijf

; Werken met de omgeving ------------------------------------------------------

; Lispfunctie: geef het lemma dat overeenkomt met het gegeven woord.
; Indien niets gevonden is, is het resultaat `niks'.
FN_VOORWERPEN_1 geef
doe_geven:
	; hier is rax het woord dat we willen vinden
	; en rbx de lijst met doorzoekbare lemmata
	push rbx
	; Splits rax op in lengte: rdx en karakters: rdi
	NEEM_LENGTE rdx, rax
	NEEM_KARAKTERS rdi, rax

.volgend_lemma: ; probeer of rbx het gewenste lemma is
	; Eerst controleren of rbx eigenlijk wel iets bevat.
	cmp rbx, niks
	jne .niet_niks

	; rbx is een lege lijst, dus het resultaat is `niks'.
	mov rax, niks
	pop rbx
	ret

.niet_niks: ; de lijst is bewoond
	NEEM_KOP rsi, rbx ; rsi is het lemma dat we willen vergelijken.
	NEEM_KOP rsi, rsi ; rsi is de streng die we willen vergelijken.
	NEEM_LENGTE rcx, rsi ; rdx bevat de ene lengte en rcx de andere.
	; (Let op dat rdx de lengte is van het woord dat we willen,
	; want in .lengte_gelijk wordt rcx aangepast!)
	; Vergelijk strengen op lengte.
	cmp rdx, rcx
	je .lengte_gelijk
	; Lengte ongelijk dus strengen ook: zoek verder.
	NEEM_PEL rbx, rbx
	jmp .volgend_lemma

.lengte_gelijk: ; Lengte is gelijk dus vergelijk per karakter.
	NEEM_KARAKTERS rsi, rsi ; rdi bevat de ene lijst karakters en rsi de andere
	; rcx bevat nog steeds de lengte van de strengen.

	; Nu komt een fantastische CISC-instructie:
	; Vergelijk rcx keer de byte [rdi++] met [rsi++]
	; tot een verschil gevonden en zet de gelijkheidsvlag of er een verschil is.
	repe cmpsb
	je .gevonden
	; Zet de waarde van rdi weer terug.
	NEEM_KARAKTERS rdi, rax
	; Lengte ongelijk dus strengen ook: zoek verder.
	NEEM_PEL rbx, rbx
	jmp .volgend_lemma
.gevonden:
	; Resultaat is het lemma, dus de kop van rbx.
	NEEM_KOP rax, rbx
	pop rbx ; Vergeet rbx niet te ontpushen!
	ret
ZET_BUITEN "geef", geef

; Lispfunctie:
; (var naam) is een afkorting voor (pel (geef (gewoon naam))).
; Dit is handig als je macro's schrijft die variabelen gebruiken,
; want dan kun je zoeken op (var naam) de de kop van het pel nemen.
; Daarom gebruiken we (var naam) in uitdrukkingen.
; Bovendien geeft het iets betere foutmeldingen.
FN var
	; hier is rax de lijst (naam)
	; We kunnen de streng `naam' direct aan `doe_geven' doorgeven voor het lemma.
	NEEM_KOP rax, rax
	push rax
	call doe_geven
	; Hier is rax `niks' of het gevraagde lemma.
	cmp rax, niks
	je .bestaat_niet
	NEEM_PEL rax, rax
	add rsp, 8
	ret
.bestaat_niet:
	FOUTMELDING fout_var
MAAK_STRENG fout_var, 37, `Die variabele bestaat helemaal niet!\n`
; Alternatieve implementatie:
;FN var
;	; hier is rax de lijst (naam)
;	KOPPEL gewoon, rax
;	; rax is de lijst (gewoon naam)
;	KOPPEL rax, niks
;	KOPPEL geef, rax
;	; rax is de lijst (geef (gewoon naam))
;	KOPPEL rax, niks
;	KOPPEL pel, rax
;	; rax is de lijst (pel (geef (gewoon naam)))
;	STAP
ZET_BUITEN "var", var

; Lispfunctie: geef de omgeving als lijst van lemmata.
FN geef_omgeving
	; De omgeving staat in rbx dus neem over in rax en klaar.
	mov rax, rbx
	ret
ZET_BUITEN "geef-omgeving", geef_omgeving

; Lispfunctie: stel de waarde van de omgeving in.
; Als de omgeving niet een lijst lemmata is, gaan dingen goed stuk.
; Let op dat de omgeving teruggezet wordt bij het einde van een `laat'-aanroep,
; dus ook bij terugkeren uit een `fn'.
; In het bijzonder doet `zet-omgeving' aanroepen binnen een functie
; niets met de omgeving bij de functieaanroep.
FN_VOORWERPEN_1 zet_omgeving
	mov rbx, rax
	ret
ZET_BUITEN "zet-omgeving", zet_omgeving

; Lispfunctie: geef een naam een betekenis.
; Na het uitvoeren van (def naam waarde) geeft `naam' bij uitvoeren `waarde'.
; De waarde wordt eerst uitgerekend.
; We gaan ervan uit dat de naam de vorm (var streng) heeft.
FN def
	; hier is rax ((var streng) waarde),
	; splits dat tot streng in rcx en waarde in rax
	NEEM_KOP rcx, rax
	NEEM_PEL rcx, rcx
	NEEM_KOP rcx, rcx ; hier is rcx `streng'
	NEEM_PEL rax, rax ; hier is rax (waarde)
	NEEM_KOP rax, rax ; hier is rax `waarde'
	; Reken de waarde uit.
	BEGIN_BEWAREN
	push rcx
	EIND_BEWAREN
	push .waarde_uitgerekend
	STAP
.waarde_uitgerekend:
	; Hier zijn:
	; * rax: de waarde
	; * [rsp + 8]: de streng

	; Maak het lemma.
	KOPPEL [rsp + 8], rax
	VERGEET
	; Zet het in de omgeving
	KOPPEL rax, rbx
	mov rbx, rax
	ret
ZET_BUITEN "def", def

; Lispfunctie: geef een naam een tijdelijke betekenis.
; De waarde van (laat naam waarde gebied)
; is de waarde van `gebied', uitgevoerd met `naam = waarde'.
; De waarde wordt eerst uitgerekend.
FN laat
	BEGIN_BEWAREN
	; Onthoud de omgeving om straks terug te zetten.
	push rbx
	; Onthoud het gebied.
	NEEM_PEL rcx, rax ; nu is rcx (waarde gebied)
	NEEM_PEL rcx, rcx ;           (gebied)
	NEEM_KOP rcx, rcx ;           `gebied'
	push rcx
	EIND_BEWAREN
	call def.code
	; Hier is:
	; * [rsp + 8]: het gebied
	; * [rsp + 16]: de oude omgeving
	; We gaan het gebied uitvoeren.
	mov rax, [rsp + 8]
	push .gebied_uitgevoerd
	STAP
.gebied_uitgevoerd:
	; Het resultaat staat in rax,
	; dus we zijn klaar als de oorspronkelijke omgeving terug is.
	mov rbx, [rsp + 16]
	VERGEET
	ret
ZET_BUITEN "laat", laat

; Lispfunctie: definieer een functie in Lisp.
; Neemt een variabele en een uitdrukking.
; Een sterfunctie slaat de lijst van voorwerpen op in de gegeven variabele.
; Zie ook `fn'.
FN fn_ster
	; rax is (naam . uitdrukking . niks)
	; We gaan ons resultaat opbouwen via rax, dus stop voorwerpen in rdx.
	mov rdx, rax
	; Het resultaat komt in rcx.
	mov rcx, [vrije_ruimte]
	; We gaan onze data schrijven naar [rdi] = [[vrije_ruimte]].
	; Dit omdat de stos*-instructie superhandig daarvoor is.
	mov rdi, rcx
	; beschrijving
	mov rax, beschrijving_ster
	stosq
	; voorwerpnamen
	NEEM_KOP rax, rdx
	NEEM_PEL rdx, rdx ; rax is `naam' en rdx is (uitdrukking . niks)
	stosq
	; code
	NEEM_KOP rax, rdx ; rax is `uitdrukking'
	stosq
	; Klaar met uitdrukking bouwen, update de vrije ruimte.
	mov [vrije_ruimte], rdi
	mov rax, rcx
	ret
ZET_BUITEN "fn*", fn_ster
; De beschrijving voor een sterfunctie.
DEF_DATA beschrijving_ster
	dq 0 ; overbeschrijving
	dq uitvoering_ster
	dq afmeting_ster
	dq doorverwijzing_ster
	dq meteen_klaar ; opruiming
; De uitvoering is niet veel anders dan een goedgekozen aanroep op `laat'.
DEF_CODE uitvoering_ster
	; rsi wijst naar de sterfunctie en rax de voorwerpen
	; We beginnen met die te vervangen met (gewoon voorwerpen).
	KOPPEL rax, niks
	KOPPEL gewoon, rax
	; Haal dat uit de weg want we gaan een nieuwe lijst maken.
	mov rcx, rax

	; [rsi + 16] is de uitdrukking
	; [rsi + 8] is de naam
	; rcx is (gewoon voorwerpen).
	; we willen rax = (laat naam (gewoon voorwerpen) uitdrukking)
	KOPPEL [rsi + 16], niks ; (uitdrukking)
	KOPPEL rcx, rax ; ((gewoon voorwerpen) uitdrukking)
	KOPPEL [rsi + 8], rax ; (naam (gewoon voorwerpen) uitdrukking)
	KOPPEL laat, rax ; (laat naam (gewoon voorwerpen) uitdrukking)

	; rax is de code inclusief alle toewijzingen, dus voer die uit
	STAP
; Een sterfunctie heeft twee wijzers en uiteraard de beschrijvingswijzer: 24 bytes.
DEF_CODE afmeting_ster
	mov rax, 24
	ret
; Een sterfunctie verwijst door in de voorwerpnamen en de code.
DEF_CODE doorverwijzing_ster
	pop rcx
	add rsi, 8
	push rsi
	add rsi, 8
	push rsi
	mov rax, 2 ; twee wijzers
	jmp rcx

; Lispfunctie: definieer een functie in Lisp.
; Neemt een lijst variabelen en een uitdrukking.
; Om dit voor elkaar te krijgen, moeten we een eigen beschrijving maken.
; Zie ook fn_ster.
FN fn
	; rax is (voorwerpnamen . (code . niks))
	; We gaan ons resultaat opbouwen via rax, dus stop voorwerpen in rdx.
	mov rdx, rax
	; Het resultaat komt in rcx.
	mov rcx, [vrije_ruimte]
	; We gaan onze data schrijven naar [rdi] = [[vrije_ruimte]].
	; Dit omdat de stos*-instructie superhandig daarvoor is.
	mov rdi, rcx
	; beschrijving
	mov rax, beschrijving_lambda
	stosq
	; voorwerpnamen
	NEEM_KOP rax, rdx
	NEEM_PEL rdx, rdx ; rax is `voorwerpnamen' en rdx is (code . niks)
	stosq
	; code
	NEEM_KOP rax, rdx ; rax is `code'
	stosq
	; Klaar met uitdrukking bouwen, update de vrije ruimte.
	mov [vrije_ruimte], rdi
	mov rax, rcx
	ret
ZET_BUITEN "fn", fn
; De beschrijving voor een lambdafunctie.
DEF_DATA beschrijving_lambda
	dq 0 ; overbeschrijving
	dq uitvoering_lambda ; uitvoering
	dq afmeting_lambda
	dq doorverwijzing_lambda
	dq meteen_klaar ; opruiming
; Om een lambdafunctie op een lijst voorwerpen uit te voeren,
; doen we steeds (laat naam (gewoon voorwerp) ...) om de code heen.
; Die toren van `laat'jes voeren we dan uit.
DEF_CODE uitvoering_lambda
	; rsi wijst naar de lambda en rax de voorwerpen
	; Haal die uit de weg want we gaan een stuk koppelen!
	mov rdi, rax
	mov rcx, [rsi + 8]
	mov rax, [rsi + 16]
.bouw_toren:
	; rax is de code met de toewijzingen tot nu toe,
	; rcx is de lijst variabelnamen
	; rdi is de lijst voorwerpen
	; TEDOEN: We controleren alleen dat rcx `niks' is,
	; maar we willen eigenlijk dat rcx en rdi tegelijk `niks' worden.
	cmp rcx, niks
	je .voer_toren_uit
	KOPPEL rax, niks ; rax is (code)
	KOPPEL [rdi + 8], rax ; rax is (waarde code)
	KOPPEL [rcx + 8], rax ; rax is (naam waarde code)
	KOPPEL laat, rax ; rax is (laat naam waarde code)
	NEEM_PEL rcx, rcx
	NEEM_PEL rdi, rdi
	jmp .bouw_toren
.voer_toren_uit:
	; rax is de code inclusief alle toewijzingen, dus voer die uit
	STAP
; Een lambda heeft twee wijzers en uiteraard de beschrijvingswijzer: 24 bytes.
DEF_CODE afmeting_lambda
	mov rax, 24
	ret
; Een lambda verwijst door in de voorwerpnamen en de code.
DEF_CODE doorverwijzing_lambda
	pop rcx
	add rsi, 8
	push rsi
	add rsi, 8
	push rsi
	mov rax, 2 ; twee wijzers
	jmp rcx

; Programmeren ---------------------------------------------------------------
; Nu moeten we de gebruiker nog een programma laten intypen.
; We kunnen niet zomaar zeggen dat we een woord lezen, het lemma opvragen,
; en die in een lijst zetten.
; Ten eerste krijg je dan helemaal geen syntaxis behalve een platte lijst,
; en ten tweede kun je zo niet echt variabelen voor elkaar krijgen.
; In plaats daarvan lezen we het eerste woord en beslissen we wat we doen.
; Bij een haakje openen `(': lees herhaaldelijk uitdrukkingen in
;  tot we een haakje sluiten `)' tegenkomen.
;  De uiteindelijke uitdrukking bestaat uit de lijst
;  van alle tussenliggende uitdrukkingen.
; Bij geen haakjes: als we `woord' hebben gelezen,
;  dan is de uitdrukking `(var woord)'.
;
; Het lezen van een lijst uitdrukkingen doen we door
; een uitdrukking in te lezen,
; de rest van de lijst in te lezen,
; en dan de uitkomst te koppelen.
;
; Omdat we niet kunnen ontlezen, moeten we bij het lezen van de uitdrukking
; al beslissen wat we moeten doen met een `)'.
; In dat geval geven we het symbool `einde_uitdrukking' terug,
; zodat de lijst-van-uitdrukkingen-lezer `niks' kan teruggeven.
; Dit zorgt niet voor een probleem met `niks' of () zelf inlezen,
; want die geven we terug als (var "niks") en `niks' respectievelijk.

DEF_UNIEK einde_uitdrukking
ZET_BUITEN "einde-uitdrukking", einde_uitdrukking

; Lispfunctie: lees een Lispuitdrukking in en geef die,
; klaar om uitgevoerd te worden.
; Let op dat dit dus altijd een koppel is.
FN lees_uitdrukking
	; Bekom een woord
	mov rsi, lees_woord
	BEWAAR_NIETS
	push .woord_gelezen
	; lees_woord en lees_uitdrukking hebben geen voorwerpen,
	; dus rax hoeft niet aangepast te worden
	PAS_TOE
.woord_gelezen:
	push rax
	pop rax
	VERGEET
	; De streng staat in rax.
	; Kijk of het een `(' of `)' is.
	cmp qword [rax + 8], 1
	jne .geen_haakjes
	cmp byte [rax + 16], '('
	jne .geen_haakje_openen
	; Het is dus wel een `(', dus we gaan nu een lijst uitdrukkingen inlezen.
	; De lijst is ons resultaat, dus we komen niet terug.
	; Wederom hoeft rax niet aangepast te worden.
	mov rsi, lees_uitdrukkinglijst
	PAS_TOE
.geen_haakje_openen:
	; het woord in rax is 1 karakter lang maar geen `('.
	; Kijk of het misschien een `)' is.
	cmp byte [rax + 16], ')'
	jne .geen_haakjes
	; We geven `niks' terug, want dan weet de uitdrukkinglijstlezer
	; dat we klaar zijn.
	mov rax, einde_uitdrukking
	ret
.geen_haakjes:
	; Het woord in rax is geen `(' of `)'.
	; We geven nu (var woord).
	KOPPEL rax, niks
	KOPPEL var, rax
	ret
ZET_BUITEN "lees-uitdrukking", lees_uitdrukking

; Lispfunctie: lees uitdrukkingen tot we een `)' tegenkomen.
; (En dat is zo wanneer lees-uitdrukking `einde-uitdrukking' geeft.)
FN lees_uitdrukkinglijst
	; Lees de eerste uitdrukking in.
	BEWAAR_NIETS
	push .uitdrukking_gelezen
	mov rsi, lees_uitdrukking
	PAS_TOE
.uitdrukking_gelezen:
	VERGEET
	; We gaan door tot we het einde tegenkomen.
	cmp rax, einde_uitdrukking
	jne .lees_koppel_en_door
	; Het is `niks', dus klaar.
	mov rax, niks
	ret
.lees_koppel_en_door:
	; Het is niet het einde, dus lees de rest in en zet het als kop erop.
	BEGIN_BEWAREN
	push rax
	EIND_BEWAREN
	push .koppel_en_door
	mov rsi, lees_uitdrukkinglijst
	PAS_TOE
.koppel_en_door:
	; De kop staat op de stapel en het pel in rax.
	VERGEET
	KOPPEL [rsp - 8], rax
	ret
ZET_BUITEN "lees-uitdrukkinglijst", lees_uitdrukkinglijst

; Opstarten en uitvoeren ------------------------------------------------------
; Dit is de Lispcode die we gaan uitvoeren bij opstarten (plus bonuswaarden).
MAAK_LIJST gelezen, lees_uitdrukking
MAAK_LIJST begincode, voer_uit, gelezen

; De daadwerkelijke opstartfunctie.
global _start
DEF_CODE _start

	; Zorg ervoor dat we wat geheugen hebben om onze koppels in te zetten.
	; Deze aanroept sloopt alle/de meeste registers, dus doe die eerst.
	call set_up_data_segment

	; rbx zou de omgeving moeten bevatten
	mov rbx, BUITENOMGEVING

	; Als executie is afgelopen, is onze returnwaarde het laatste resultaat.
	push klaar.code
	; Bewaar het einde van de stapel (voor vuilnisophalen).
	; Alles vanaf de wijzer naar `klaar' en verder is niet relevant.
	mov [stapel_bodem], rsp

	; Uitvoeren, die hap!
	mov rax, begincode
	STAP
