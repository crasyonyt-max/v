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
	apt_taken = { de = "Diese Wohnung gehört %s.", en = "This apartment belongs to %s." },
	apt_have_one = { de = "Du wohnst schon in Wohnung %d.", en = "You already live in apartment %d." },
	apt_moved_in = {
		de = "🏠 Willkommen zu Hause! Wohnung %d gehört jetzt dir.",
		en = "🏠 Welcome home! Apartment %d is yours now.",
	},
	no_apartment = { de = "Du hast keine Wohnung.", en = "You don't have an apartment." },
	my_apartment = { de = "🏠 Meine Wohnung %d (Dortmund Tower)", en = "🏠 My apartment %d (Dortmund Tower)" },
	tower = {
		de = "🏙️ Dortmund Tower (32 Wohnungen, gratis)",
		en = "🏙️ Dortmund Tower (32 apartments, free)",
	},
	move_out = { de = "Ausziehen", en = "Move out" },
	elevator = { de = "Aufzug", en = "Elevator" },
	floor = { de = "Etage %d", en = "Floor %d" },
	lobby = { de = "Lobby (EG)", en = "Lobby" },
	inventory = { de = "Inventar", en = "Inventory" },
	empty_inventory = {
		de = "Du trägst nichts bei dir. Kauf etwas im Supermarkt!",
		en = "You carry nothing. Buy something at a supermarket!",
	},
	eat = { de = "Essen", en = "Eat" },
	drink = { de = "Trinken", en = "Drink" },
	hold = { de = "In die Hand", en = "Hold" },
	put_away = { de = "Wegstecken", en = "Put away" },
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
	bad_plate = {
		de = "Kennzeichen ungültig. Format: AB 123 (Stadt immer DO, max. 3 Ziffern)",
		en = "Invalid plate. Format: AB 123 (city always DO, max 3 digits)",
	},
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
	change_plate = { de = "Kennzeichen ändern (4.000 €)", en = "Change plate (€4,000)" },
	fuel = { de = "Tank", en = "Fuel" },
	no_cars = { de = "Dein Motorrad kommt gleich …", en = "Your motorbike is on its way …" },
	cars_refunded = {
		de = "Die Autos wurden entfernt. Du hast %s zurückbekommen und fährst jetzt Motorrad!",
		en = "Cars were removed. You got %s back and ride a motorbike now!",
	},
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
	out_of_fuel = {
		de = "Tank leer! Der ADMC kann dich auftanken.",
		en = "Out of fuel! ADMC can refuel you.",
	},

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
	-- votes
	vote = { de = "Abstimmung", en = "Vote" },
	vote_over = { de = "Beendet", en = "Ended" },
	vote_count = { de = "%d Stimmen", en = "%d votes" },
	vote_question = { de = "Frage", en = "Question" },
	vote_answer = { de = "Antwort %d", en = "Answer %d" },
	vote_start = { de = "Starten", en = "Start" },
	vote_end = { de = "Beenden", en = "End" },
	vote_need_two = { de = "Mindestens 2 Antworten.", en = "At least 2 answers." },
	vote_running = { de = "Es läuft schon eine Abstimmung.", en = "A vote is already running." },
	no_vote = { de = "Gerade keine Abstimmung.", en = "No vote right now." },
	already_voted = { de = "Du hast schon abgestimmt.", en = "You already voted." },
	-- AA (Owner + Co-Owner)
	admin_aa = { de = "AA", en = "AA" },
	aa_running = { de = "Läuft gerade", en = "Running now" },
	aa_nothing = { de = "Kein Event aktiv.", en = "No event running." },
	aa_weekly_now = {
		de = "Samstags-Event läuft (2x Cash + 2x XP)",
		en = "Saturday event running (2x cash + 2x XP)",
	},
	aa_weekly_info = {
		de = "Jeden Samstag 18:00 (deutsche Zeit): automatisch 2x Cash + 2x XP für 30 Minuten.",
		en = "Every Saturday 6 PM (German time): automatic 2x cash + 2x XP for 30 minutes.",
	},
	aa_multiplier = { de = "Faktor (z. B. 2 = 2x)", en = "Multiplier (e.g. 2 = 2x)" },
	aa_start = { de = "Starten (alle Server)", en = "Start (all servers)" },
	stop = { de = "Stopp", en = "Stop" },
	duration_min = { de = "Dauer in Minuten", en = "Duration in minutes" },
	admin_fulllog = { de = "📜 Log", en = "📜 Log" },
	full_log = { de = "Alles-Log (alle Server)", en = "Full log (all servers)" },
	today = { de = "Heute", en = "Today" },
	plate_filtered = { de = "Diese Buchstaben sind nicht erlaubt.", en = "These letters are not allowed." },
	plate_service = { de = "ADMC Kennzeichen-Service", en = "ADMC plate service" },
	plate_personal_title = {
		de = "Persönliches Kennzeichen (Dienst- & Admin-Autos)",
		en = "Personal plate (service & admin cars)",
	},
	plate_change_where = {
		de = "Kennzeichen ändern: beim ADMC Kennzeichen-Service (Navi).",
		en = "Change plates at the ADMC plate service (Navi).",
	},
	plate_service_only = {
		de = "Kennzeichen ändern geht nur beim ADMC Kennzeichen-Service.",
		en = "Plates can only be changed at the ADMC plate service.",
	},
	plate_choose = { de = "Wähle dein Kennzeichen (kostenlos)", en = "Choose your plate (free)" },
	plate_for_car = { de = "Für dein Auto: %s", en = "For your car: %s" },
	plate_personal = {
		de = "Dein persönliches Kennzeichen für Dienst- und Admin-Autos.",
		en = "Your personal plate for service and admin cars.",
	},
	plate_set_go = { de = "Festlegen & ausparken", en = "Set & take out" },
	plate_required = { de = "Wähle zuerst ein Kennzeichen.", en = "Choose a plate first." },
	livery_locked = { de = "Dienstfahrzeuge behalten ihre Lackierung.", en = "Service vehicles keep their livery." },
	all_servers = { de = "alle Server", en = "all servers" },
	log_filter = { de = "Filter: Name, ID, money, chat …", en = "Filter: name, ID, money, chat …" },
	log_search = { de = "Suchen", en = "Search" },
	log_count = { de = "%d Einträge · Seite %d / %d", en = "%d entries · page %d / %d" },
	newer = { de = "Neuer", en = "Newer" },
	older = { de = "Älter", en = "Older" },
	admin_only = { de = "🛡️ Nur für Admins.", en = "🛡️ Admins only." },
	detained = {
		de = "🚔 Du wurdest von einem Admin in den Sonderraum gebracht.",
		en = "🚔 An admin put you in the holding room.",
	},
	released = { de = "✅ Du bist wieder frei.", en = "✅ You're free again." },
	detain = { de = "Sonderraum", en = "Holding room" },
	release = { de = "Freilassen", en = "Release" },
	-- droppers
	dropper_max = { de = "Du hast schon alle 10 Dropper.", en = "You already have all 10 droppers." },
	dropper_not_yours = { de = "Das ist nicht deine Wohnung.", en = "This isn't your apartment." },
	dropper_bought = { de = "✅ Dropper %d gekauft! Er droppt %s.", en = "✅ Bought dropper %d! It drops %s." },
	dropper_collected = { de = "💶 %s eingesammelt!", en = "💶 Collected %s!" },
	drop_event_start = {
		de = "%s %s! %s%% der Drops x%s",
		en = "%s %s! %s%% of drops x%s",
	},
	drop_event_ends = { de = "endet in", en = "ends in" },
	aa_drop_events = { de = "Dropper & Dropper-Events (alle Server)", en = "Droppers & dropper events (all servers)" },
	aa_droppers_on = { de = "Dropper an", en = "Droppers on" },
	aa_droppers_off = { de = "Dropper aus", en = "Droppers off" },
	aa_droppers_are_on = { de = "Dropper in den Wohnungen: an", en = "Droppers in the apartments: on" },
	aa_droppers_are_off = { de = "Dropper in den Wohnungen: aus", en = "Droppers in the apartments: off" },
	aa_no_drop_event = { de = "Kein Dropper-Event aktiv.", en = "No dropper event running." },
	-- Unemployed XP from traffic
	drive_xp = { de = "XP zum Umtauschen", en = "XP to exchange" },
	drive_xp_info = {
		de = "Deine normalen XP (Level). Als Arbeitslos geben grüne Ampeln und Blitzer im Limit XP, rote Ampel / zu schnell kostet XP. Umtausch: letzte Ziffer weg = Euro, dein Level sinkt dabei.",
		en = "Your normal XP (level). As unemployed, green lights and speed cameras within the limit give XP; red lights / speeding cost XP. Exchange: drop the last digit = euros, your level goes down.",
	},
	drive_xp_exchange = { de = "In %s umtauschen", en = "Exchange for %s" },
	drive_xp_low = { de = "Mindestens 10 XP nötig", en = "At least 10 XP needed" },
	red_light = { de = "🚦 Rote Ampel! -%d XP", en = "🚦 Red light! -%d XP" },
	speeding = {
		de = "📸 Geblitzt: %d km/h bei %d! -%d XP",
		en = "📸 Speed camera: %d km/h in a %d zone! -%d XP",
	},
	aa_countdown = { de = "Countdown (alle Server)", en = "Countdown (all servers)" },
	aa_countdown_title = { de = "Titel (leer = AA)", en = "Title (empty = AA)" },
	aa_countdown_date = { de = "Datum TT.MM.JJJJ (leer = heute)", en = "Date DD.MM.YYYY (empty = today)" },
	aa_countdown_time = { de = "Uhrzeit HH:MM (Berlin)", en = "Time HH:MM (Berlin)" },
	aa_countdown_none = { de = "Kein Countdown aktiv.", en = "No countdown running." },
	aa_your_time = { de = "deine Uhrzeit", en = "your time" },
	countdown_now = { de = "jetzt!", en = "now!" },
	bad_time = { de = "Uhrzeit bitte als HH:MM, z. B. 19:00.", en = "Time as HH:MM, e.g. 19:00." },
	bad_date = {
		de = "Datum bitte als TT.MM.JJJJ und in der Zukunft (max. 1 Jahr).",
		en = "Date as DD.MM.YYYY, in the future (max 1 year).",
	},
	admc_only = { de = "Nur der ADMC im Dienst kann hier tanken.", en = "Only ADMC on duty can refuel here." },
	admc_refueled = { de = "⛽ Aufgetankt!", en = "⛽ Refueled!" },
	admc_refueled_you = {
		de = "⛽ %s vom ADMC hat dein Fahrzeug aufgetankt.",
		en = "⛽ %s from ADMC refueled your vehicle.",
	},
	aa_music = { de = "Musik (alle Server)", en = "Music (all servers)" },
	aa_music_id = { de = "Roblox Audio-ID", en = "Roblox audio ID" },
	aa_music_volume = { de = "Lautstärke in % (50)", en = "Volume in % (50)" },
	aa_music_off = { de = "Gerade keine Musik.", en = "No music right now." },
	aa_loop_on = { de = "Wiederholen: an", en = "Repeat: on" },
	aa_loop_off = { de = "Wiederholen: aus", en = "Repeat: off" },
	aa_play = { de = "Abspielen", en = "Play" },
	aa_default_start = { de = "Standard starten", en = "Start default" },
	aa_default_stop = { de = "Standard stoppen", en = "Stop default" },
	aa_default_on = {
		de = "Standard-Musik läuft 24/7 (wenn keine AA-Musik spielt)",
		en = "Default music plays 24/7 (when no AA music runs)",
	},
	aa_default_off = { de = "Standard-Musik ist pausiert", en = "Default music is paused" },
	music_blocked = {
		de = "Audio darf in diesem Spiel nicht abgespielt werden",
		en = "This audio is not allowed in this game",
	},
	aa_save_song = { de = "Liste", en = "List" },
	bad_audio = { de = "Ungültige Audio-ID.", en = "Invalid audio ID." },
	not_audio = {
		de = "Das ist keine Audio-ID (oder sie ist nicht verfügbar).",
		en = "That is not an audio ID (or it isn't available).",
	},
	too_many_songs = { de = "Liste voll (max. 60).", en = "List full (max 60)." },
	aa_gift = { de = "Geschenk an alle", en = "Gift for everyone" },
	aa_gift_all = { de = "An alle verschenken (alle Server)", en = "Give to everyone (all servers)" },
	aa_drop = { de = "Fundstück auf der Karte", en = "Pickup on the map" },
	aa_pick_spot = { de = "Ort auf der Karte wählen", en = "Choose a spot on the map" },
	reward_cash = { de = "Geld", en = "Cash" },
	reward_xp = { de = "XP", en = "XP" },
	reward_item = { de = "Essen / Trinken", en = "Food / drink" },
	reward_phone = { de = "Handy", en = "Phone" },
	map_you = { de = "Du", en = "You" },
	map_tap = { de = "Tippe auf die Karte", en = "Tap the map" },
	map_place = { de = "Hier", en = "Here" },
	gift_got = { de = "🎁 Geschenk: %s!", en = "🎁 Gift: %s!" },
	drop_new = {
		de = "📦 Ein Fundstück (%s) ist irgendwo in der Stadt – folge dem Lichtstrahl!",
		en = "📦 A pickup (%s) is somewhere in the city – follow the light beam!",
	},
	drop_got = { de = "📦 Aufgehoben: %s", en = "📦 Picked up: %s" },
	drop_taken = { de = "Das hast du schon aufgehoben.", en = "You already picked this up." },
	drop_cant = {
		de = "Geht gerade nicht (Tasche voll oder schon im Besitz).",
		en = "Not possible right now (bag full or already owned).",
	},
	too_many_drops = { de = "Zu viele Fundstücke gleichzeitig (max. 10).", en = "Too many pickups at once (max 10)." },
	app_news = { de = "News", en = "News" },
	no_news = { de = "Noch keine News.", en = "No news yet." },
	delete = { de = "Löschen", en = "Delete" },
	admin_news = { de = "News", en = "News" },
	news_new = { de = "Neue News", en = "New post" },
	news_title = { de = "Überschrift", en = "Headline" },
	news_text = { de = "Text …", en = "Text …" },
	news_post = { de = "Veröffentlichen", en = "Publish" },
	stunt_no_hands = { de = "Freihändig! Lenken geht so nicht.", en = "No hands! You can't steer like this." },
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
