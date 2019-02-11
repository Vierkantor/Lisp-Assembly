import gdb
import traceback

# TEDOEN: maak hier een fijner datatype van.
generieke_wijzer = gdb.lookup_type('void').pointer().pointer()
karakterlijst = gdb.lookup_type('unsigned char').pointer()

def als_wijzer(waarde):
	return gdb.Value(waarde).cast(generieke_wijzer)

beschrijving_functie = gdb.parse_and_eval('&beschrijving_functie')
beschrijving_getal = gdb.parse_and_eval('&beschrijving_getal')
beschrijving_lambda = gdb.parse_and_eval('&beschrijving_lambda')
beschrijving_koppel = gdb.parse_and_eval('&beschrijving_koppel')
beschrijving_ster = gdb.parse_and_eval('&beschrijving_ster')
beschrijving_streng = gdb.parse_and_eval('&beschrijving_streng')

class Waarde:
	def __init__(self, wijzer):
		self.wijzer = als_wijzer(wijzer)
	@property
	def beschrijving(self):
		return als_wijzer(self.wijzer.dereference())
	def __eq__(self, ander):
		return self.wijzer == ander.wijzer
	def __str__(self):
		return '<beschrijving {}>'.format(self.beschrijving)

class _niks(Waarde):
	def __init__(self, wijzer):
		super().__init__(wijzer)
	def __str__(self):
		return '()'

Niks = _niks(gdb.parse_and_eval('&niks'))

class Functie(Waarde):
	def __init__(self, wijzer):
		super().__init__(wijzer)
	def __str__(self):
		return 'fn {}'.format(als_wijzer(self.wijzer + 1))

class Getal(Waarde):
	def __init__(self, wijzer):
		super().__init__(wijzer)
	def __str__(self):
		return '(getal {})'.format(als_wijzer(self.wijzer + 1).dereference())

class Koppel(Waarde):
	def __init__(self, wijzer):
		super().__init__(wijzer)
		self.kop = verken_waarde(als_wijzer(wijzer + 1).dereference())
		self.pel = verken_waarde(als_wijzer(wijzer + 2).dereference())
	def streng_los_koppel(self):
		if isinstance(self.pel, Koppel):
			return '({} {})'.format(self.kop, self.pel.streng_in_koppel())
		elif self.pel == Niks:
			return '({})'.format(self.kop)
		else:
			return '({} . {})'.format(self.kop, self.pel)
	def streng_in_koppel(self):
		if isinstance(self.pel, Koppel):
			return '{} {}'.format(self.kop, self.pel.streng_in_koppel())
		elif self.pel == Niks:
			return str(self.kop)
		else:
			return '{} . {}'.format(self.kop, self.pel)
	def __str__(self):
		return self.streng_los_koppel()

class Lambda(Waarde):
	def __init__(self, wijzer):
		super().__init__(wijzer)
		self.params = verken_waarde(als_wijzer(wijzer + 1).dereference())
		self.code = verken_waarde(als_wijzer(wijzer + 2).dereference())
	def __str__(self):
		return '(fn {} {})'.format(self.params, self.code)

class Ster(Waarde):
	def __init__(self, wijzer):
		super().__init__(wijzer)
		self.params = verken_waarde(als_wijzer(wijzer + 1).dereference())
		self.code = verken_waarde(als_wijzer(wijzer + 2).dereference())
	def __str__(self):
		return '(fn* {} {})'.format(self.params, self.code)

class Streng(Waarde):
	def __init__(self, wijzer):
		super().__init__(wijzer)
		self.lengte = als_wijzer(wijzer + 1).dereference()

		# Lees inhoud van de streng in.
		inhoud_bytes = []
		wijzer = gdb.Value(wijzer).cast(karakterlijst) + 16
		for afstand in range(0, self.lengte):
			inhoud_bytes.append(int(wijzer[afstand]))
		self.karakters = bytes(inhoud_bytes).decode('utf-8')
	def __str__(self):
		return '"{}"'.format(self.karakters)

beschrijving_naar_waarde = {
	int(beschrijving_functie): Functie,
	int(beschrijving_getal): Getal,
	int(beschrijving_lambda): Lambda,
	int(beschrijving_koppel): Koppel,
	int(beschrijving_ster): Ster,
	int(beschrijving_streng): Streng,
}

def verken_waarde(wijzer):
	wijzer = als_wijzer(wijzer)

	if wijzer == Niks.wijzer:
		return Niks

	domme_waarde = Waarde(wijzer)
	klasse = beschrijving_naar_waarde.get(int(domme_waarde.beschrijving), Waarde)
	return klasse(wijzer)

def maak_lijst(waarde):
	waarde = als_wijzer(waarde)
	resultaat = []
	while waarde != Niks.wijzer:
		resultaat.append(als_wijzer(waarde + 1).dereference())
		waarde = als_wijzer(als_wijzer(waarde + 2).dereference())
	return resultaat

def geef_inhoud(waarde, recursief=False):
	waarde = verken_waarde(waarde)
	return str(waarde)

def print_inhoud(waarde, recursief=False):
	waarde = als_wijzer(waarde)
	try:
		print('{}: {}'.format(waarde, geef_inhoud(waarde, recursief=recursief)))
	except gdb.MemoryError:
		print(waarde)

def print_omgeving(waarde):
	for lemma in maak_lijst(waarde):
		print(geef_inhoud(lemma, recursief=True))

def print_stapel(afstand=0):
	"""Geef de inhoud van de waardenstapel.

	De afstand is het aantal qwords om over te slaan.
	"""
	stapel_top = als_wijzer(gdb.parse_and_eval('$rsp')) + afstand
	stapel_bodem = gdb.parse_and_eval('(void *)stapel_bodem')
	while stapel_top < stapel_bodem:
		object_bovenop = stapel_top.dereference()
		print_inhoud(object_bovenop)
		stapel_top = als_wijzer(stapel_top + 1) # +1 want het is een void*

def print_terugkeerstapel(afstand=0):
	"""Geef de inhoud van de terugkeerstapel.

	De afstand is het aantal qwords om over te slaan.
	"""
	stapel_top = als_wijzer(gdb.parse_and_eval('$rbp')) + afstand
	stapel_bodem = gdb.parse_and_eval('(void *)&\'terugkeerstapel.onderop\'')
	while stapel_top < stapel_bodem:
		functie_bovenop = als_wijzer(stapel_top.dereference())
		print(functie_bovenop)
		stapel_top = als_wijzer(stapel_top + 1) # +1 want het is een void*

def print_uitvoering_functie():
	print_stapel()
	print_terugkeerstapel()

class LispCommando(gdb.Command):
	def __init__(self):
		gdb.Command.__init__(self, 'lisp', gdb.COMMAND_USER, prefix=True)
	def invoke(self, argument, from_tty):
		print('Vergeet niet een subcommando te geven, joh!')
class LispInhoudCommando(gdb.Command):
	def __init__(self):
		gdb.Command.__init__(self, 'lisp i', gdb.COMMAND_USER)
	def invoke(self, argument, from_tty):
		waarde = gdb.parse_and_eval(argument)
		print_inhoud(waarde, recursief=False)
class LispInhoudRecursiefCommando(gdb.Command):
	def __init__(self):
		gdb.Command.__init__(self, 'lisp ir', gdb.COMMAND_USER)
	def invoke(self, argument, from_tty):
		waarde = gdb.parse_and_eval(argument)
		print_inhoud(waarde, recursief=True)
class LispOmgevingCommando(gdb.Command):
	def __init__(self):
		gdb.Command.__init__(self, 'lisp o', gdb.COMMAND_USER)
	def invoke(self, argument, from_tty):
		try:
			waarde = gdb.parse_and_eval('$rbx')
			print_omgeving(waarde)
		except:
			print(traceback.format_exc())
			raise
class LispStapelCommando(gdb.Command):
	def __init__(self):
		gdb.Command.__init__(self, 'lisp s', gdb.COMMAND_USER)
	def invoke(self, argument, from_tty):
		if argument:
			afstand = int(argument)
		else:
			afstand = 0
		print_stapel(afstand=afstand)
class LispTerugkeerStapelCommando(gdb.Command):
	def __init__(self):
		gdb.Command.__init__(self, 'lisp t', gdb.COMMAND_USER)
	def invoke(self, argument, from_tty):
		if argument:
			afstand = int(argument)
		else:
			afstand = 0
		print_terugkeerstapel(afstand=afstand)
class LispVolgendeFunctieCommando(gdb.Command):
	def __init__(self):
		gdb.Command.__init__(self, 'lisp vf', gdb.COMMAND_USER)
	def invoke(self, argument, from_tty):
		gdb.execute('tbreak uitvoering_functie')
		gdb.execute('continue')
		print_uitvoering_functie()
# Installeer de commando's.
LispCommando()
LispInhoudCommando()
LispInhoudRecursiefCommando()
LispOmgevingCommando()
LispStapelCommando()
LispTerugkeerStapelCommando()
LispVolgendeFunctieCommando()
