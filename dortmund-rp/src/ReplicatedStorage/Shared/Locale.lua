--!strict
-- German + English strings. Locale.T(lang, key, ...) formats with string.format.

local Locale = {}

local S: { [string]: { de: string, en: string } } = {
	-- generic
	ok = { de = "OK", en = "OK" },
	close = { de = "Schließen", en = "Close" },
	back = { de = "Zurück", en = "Back" },
	buy = { de = "Kaufen", en = "Buy" },
	owned = { de = "Im Besitz", en = "Owned" },
	equip = { de = "Benutzen", en = "Use" },
	equipped = { de = "In Benutzung", en = "In use" },
	free = { de = "Gratis", en = "Free" },
	spawn = { de = "Ausparken", en = "Spawn" },
	despawn = { de = "Einparken", en = "Park" },
	send = { de = "Senden", en = "Send" },
	cancel = { de = "Abbrechen", en = "Cancel" },
	loading = { de = "Lädt …", en = "Loading …" },
	coming_soon = { de = "Kommt bald", en = "Coming soon" },
	level = { de = "Level %d", en = "Level %d" },

	-- errors / notifications (keys are also sent by the server)
	bad_request = { de = "Ungültige Anfrage.", en = "Invalid request." },
	server_error = { de = "Serverfehler, bitte erneut versuchen.", en = "Server error, please try again." },
	too_fast = { de = "Langsam! Bitte kurz warten.", en = "Slow down! Please wait a moment." },
	no_money = { de = "Nicht genug Geld auf dem Konto.", en = "Not enough money in your account." },
	not_near = { de = "Du bist nicht am richtigen Ort.", en = "You are not at the right place." },
	already_owned = { de = "Hast du schon.", en = "You already own this." },
	not_owned = { de = "Gehört dir nicht.", en = "You don't own this." },
	bad_item = { de = "Unbekannter Artikel.", en = "Unknown item." },
	no_permission = { de = "Keine Berechtigung.", en = "No permission." },
	locked = { de = "Gesperrt.", en = "Locked." },
	pack_locked = {
		de = "Dieses Paket musst du erst mit Robux freischalten.",
		en = "Unlock this pack with Robux first.",
	},
	need_xp = { de = "Nicht genug Job-XP.", en = "Not enough job XP." },
	wrong_job = { de = "Falscher Job.", en = "Wrong job." },
	same_job = { de = "Du hast diesen Job schon.", en = "You already have this job." },
	bad_job = { de = "Unbekannter Job.", en = "Unknown job." },
	job_changed = { de = "Neuer Job: %s", en = "New job: %s" },
	paycheck = { de = "Gehalt erhalten: %s", en = "Paycheck received: %s" },
	transfer_in = { de = "%s von %s erhalten.", en = "Received %s from %s." },
	bad_amount = { de = "Ungültiger Betrag.", en = "Invalid amount." },
	bad_target = { de = "Ungültiger Empfänger.", en = "Invalid recipient." },
	target_offline = { de = "Spieler ist nicht auf diesem Server.", en = "Player is not on this server." },
	bad_message = { de = "Nachricht ungültig.", en = "Invalid message." },
	bad_number = { de = "Diese Nummer gibt es nicht.", en = "This number doesn't exist." },
	filter_failed = { de = "Nachricht konnte nicht geprüft werden.", en = "Message could not be checked." },
	send_failed = { de = "Senden fehlgeschlagen.", en = "Sending failed." },
	call_cooldown = { de = "Du hast gerade erst angerufen.", en = "You just made a call." },
	call_accepted = { de = "Hilfe ist unterwegs!", en = "Help is on the way!" },
	call_gone = { de = "Einsatz existiert nicht mehr.", en = "This call no longer exists." },
	own_call = { de = "Das ist dein eigener Notruf.", en = "That is your own call." },
	not_accepted = { de = "Einsatz nicht angenommen.", en = "Call not accepted." },
	not_arrived = { de = "Du bist noch nicht am Einsatzort.", en = "You have not arrived yet." },
	call_no_reward = { de = "Einsatz abgeschlossen (keine Belohnung).", en = "Call closed (no reward)." },
	call_new = { de = "🚨 Neuer Notruf (%s): %s", en = "🚨 New emergency call (%s): %s" },
	inventory_full = {
		de = "Du kannst nicht mehr tragen. Iss oder trink erst etwas.",
		en = "You can't carry more. Eat or drink something first.",
	},
	ate = { de = "😋 %s gegessen.", en = "😋 Ate %s." },
	drank = { de = "🥤 %s getrunken.", en = "🥤 Drank %s." },
	hunger = { de = "Hunger", en = "Hunger" },
	thirst = { de = "Durst", en = "Thirst" },
	hungry = { de = "Du hast Hunger! Kauf dir etwas zu essen.", en = "You are hungry! Buy something to eat." },
	thirsty = { de = "Du hast Durst! Kauf dir etwas zu trinken.", en = "You are thirsty! Buy something to drink." },
	store_hint = {
		de = "Antippen zum Kaufen. Danach im Inventar auswählen und klicken zum Essen/Trinken.",
		en = "Tap to buy. Then select it in your inventory and click to eat/drink.",
	},
	app_navi = { de = "Navi", en = "Maps" },
	navi_shops = { de = "Einkaufen", en = "Shopping" },
	navi_jobs = { de = "Dienststellen", en = "Stations" },
	navi_places = { de = "Orte", en = "Places" },
	no_space = {
		de = "Hier ist kein Platz zum Ausparken. Stell dich an die Straße.",
		en = "No space here. Stand next to a road.",
	},
	no_character = { de = "Kein Charakter.", en = "No character." },
	not_your_car = { de = "Das ist nicht dein Fahrzeug.", en = "This is not your vehicle." },
	not_driving = { de = "Du fährst gerade nicht.", en = "You are not driving." },
	not_emergency = { de = "Kein Einsatzfahrzeug.", en = "Not an emergency vehicle." },
	no_vehicle = { de = "Du hast kein Fahrzeug ausgeparkt.", en = "You have no vehicle out." },
	vehicle_too_far = { de = "Dein Fahrzeug ist zu weit weg.", en = "Your vehicle is too far away." },
	tank_full = { de = "Der Tank ist voll.", en = "The tank is full." },
	refueled = { de = "%d Liter getankt für %s.", en = "Refueled %d litres for %s." },
	bad_plate = { de = "Kennzeichen ungültig. Format: DO-AB 1234", en = "Invalid plate. Format: DO-AB 1234" },
	plate_taken = { de = "Dieses Kennzeichen ist schon vergeben.", en = "This plate is already taken." },
	garage_full = { de = "Deine Garage ist voll.", en = "Your garage is full." },
	ban_failed = { de = "Bannen fehlgeschlagen.", en = "Ban failed." },
	loading_data = { de = "Daten werden geladen …", en = "Loading data …" },
	xp_gain = { de = "+%d XP", en = "+%d XP" },
	level_up = { de = "Level aufgestiegen! Level %d", en = "Level up! Level %d" },
	announce = { de = "📢 Ankündigung", en = "📢 Announcement" },
	admin_chat_new = { de = "💬 23646: Nachricht von %s", en = "💬 23646: message from %s" },
	message_from = { de = "💬 %s: %s", en = "💬 %s: %s" },
	housing_soon = { de = "Wohnungen kommen in der nächsten Phase.", en = "Housing is coming in the next phase." },
	starter_needed = {
		de = "Wähle zuerst dein kostenloses Startauto in der Garage-App.",
		en = "Choose your free starter car in the Garage app first.",
	},
	error = { de = "Fehler.", en = "Error." },

	-- apps
	app_phone = { de = "Telefon", en = "Phone" },
	app_chatsapp = { de = "ChatsApp", en = "ChatsApp" },
	app_bank = { de = "Bank", en = "Bank" },
	app_jobs = { de = "Jobs", en = "Jobs" },
	app_garage = { de = "Garage", en = "Garage" },
	app_calls = { de = "Einsätze", en = "Calls" },
	app_settings = { de = "Einstellungen", en = "Settings" },
	app_admin = { de = "Admin", en = "Admin" },

	-- dialer
	your_number = { de = "Deine Nummer: %s", en = "Your number: %s" },
	emergency_what = { de = "Was ist passiert? Wo bist du?", en = "What happened? Where are you?" },
	call_sent = { de = "Notruf abgesetzt. Bleib wo du bist.", en = "Emergency call placed. Stay where you are." },
	calls_soon = {
		de = "Sprachanrufe kommen bald. Schreib per ChatsApp!",
		en = "Voice calls are coming soon. Use ChatsApp!",
	},

	-- chatsapp
	new_chat = { de = "Neuer Chat", en = "New chat" },
	enter_number = { de = "Nummer eingeben", en = "Enter number" },
	type_message = { de = "Nachricht …", en = "Message …" },
	admin_team = { de = "Admin-Team (23646)", en = "Admin team (23646)" },
	no_chats = { de = "Noch keine Chats.", en = "No chats yet." },

	-- bank
	balance = { de = "Kontostand", en = "Balance" },
	transfer = { de = "Überweisen", en = "Transfer" },
	amount = { de = "Betrag", en = "Amount" },
	recipient = { de = "Empfänger", en = "Recipient" },
	transactions = { de = "Umsätze", en = "Transactions" },
	transfer_done = { de = "Überweisung erfolgreich.", en = "Transfer successful." },

	-- jobs
	current_job = { de = "Aktueller Job", en = "Current job" },
	job_xp = { de = "Job-XP: %d", en = "Job XP: %d" },
	next_unlock = { de = "Nächstes Fahrzeug: %s (%d XP)", en = "Next vehicle: %s (%d XP)" },
	quit_job = { de = "Kündigen", en = "Quit job" },
	navigate = { de = "Navi", en = "Navigate" },
	paycheck_short = { de = "%s / Gehalt", en = "%s / paycheck" },
	start_at_station = { de = "Job an der Wache / am Standort antreten.", en = "Start the job at its station." },

	-- garage
	choose_starter = { de = "Wähle dein kostenloses Startauto", en = "Choose your free starter car" },
	plate = { de = "Kennzeichen", en = "Plate" },
	color = { de = "Farbe (500 €)", en = "Colour (€500)" },
	change_plate = { de = "Kennzeichen ändern (250 €)", en = "Change plate (€250)" },
	fuel = { de = "Tank", en = "Fuel" },
	no_cars = { de = "Keine Autos. Besuch das Autohaus!", en = "No cars. Visit the dealership!" },
	sell = { de = "Verkaufen (50 %)", en = "Sell (50%)" },

	-- calls app
	accept = { de = "Annehmen", en = "Accept" },
	complete = { de = "Abschließen", en = "Complete" },
	no_calls = { de = "Keine offenen Einsätze.", en = "No open calls." },
	not_emergency_job = {
		de = "Nur für Polizei, Feuerwehr, Rettungsdienst und Notarzt.",
		en = "Only for police, fire, ambulance and doctors.",
	},

	-- settings
	language = { de = "Sprache", en = "Language" },
	wallpaper = { de = "Hintergrund", en = "Wallpaper" },
	my_phones = { de = "Meine Handys", en = "My phones" },

	-- shops
	handyland = { de = "Handyland", en = "Handyland" },
	dealership = { de = "Autohaus Dortmund", en = "Dortmund car dealership" },
	dealer_tab = { de = "Neuwagen", en = "New cars" },
	packs_tab = { de = "Pakete", en = "Packs" },
	sell_tab = { de = "Ankauf", en = "Sell" },
	unlock_pack = { de = "Freischalten (%d R$)", en = "Unlock (%d R$)" },
	pack_not_setup = { de = "Paket noch nicht verfügbar.", en = "Pack not available yet." },
	job_garage = { de = "Dienstfahrzeuge", en = "Service vehicles" },
	requires_xp = { de = "Benötigt %d XP", en = "Requires %d XP" },
	camera_quality = { de = "Kamera %d/5", en = "Camera %d/5" },

	-- vehicle hud
	lights = { de = "Licht", en = "Lights" },
	hazard = { de = "Warnblinker", en = "Hazards" },
	bluelight = { de = "Blaulicht", en = "Blue lights" },
	siren = { de = "Martinshorn", en = "Siren" },
	camera = { de = "Kamera", en = "Camera" },
	out_of_fuel = { de = "Tank leer! Fahr zur Arol-Tankstelle.", en = "Out of fuel! Drive to an Arol station." },

	-- admin
	admin_players = { de = "Spieler", en = "Players" },
	admin_self = { de = "Ich", en = "Me" },
	admin_server = { de = "Server", en = "Server" },
	admin_vehicles = { de = "Fahrzeuge", en = "Vehicles" },
	admin_inbox = { de = "23646", en = "23646" },
	admin_logs = { de = "Logs", en = "Logs" },
	reason = { de = "Grund", en = "Reason" },
	minutes = { de = "Minuten (0 = permanent)", en = "Minutes (0 = permanent)" },
	announce_text = { de = "Ankündigung …", en = "Announcement …" },
	global = { de = "Alle Server", en = "All servers" },
	this_server = { de = "Dieser Server", en = "This server" },
	shutdown = { de = "Herunterfahren", en = "Shut down" },
	done = { de = "Erledigt.", en = "Done." },
	reply = { de = "Antworten", en = "Reply" },
	username = { de = "Benutzername", en = "Username" },
}

function Locale.T(lang: string?, key: string, ...: any): string
	local entry = S[key]
	if not entry then
		return key
	end
	local text = if lang == "en" then entry.en else entry.de
	if select("#", ...) > 0 then
		local ok, result = pcall(string.format, text, ...)
		return if ok then result else text
	end
	return text
end

function Locale.Has(key: string): boolean
	return S[key] ~= nil
end

-- German money format: 1.234.567 €
function Locale.Euro(n: number): string
	local negative = n < 0
	n = math.abs(n)
	local whole = math.floor(n + 1e-6)
	local cents = math.floor((n - whole) * 100 + 0.5)
	if cents >= 100 then
		whole += 1
		cents -= 100
	end
	local s = tostring(whole)
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1.")))
	if string.sub(out, 1, 1) == "." then
		out = string.sub(out, 2)
	end
	if cents > 0 then
		out ..= string.format(",%02d", cents)
	end
	return (if negative then "-" else "") .. out .. " €"
end

return Locale
