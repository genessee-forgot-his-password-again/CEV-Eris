var/list/global/excelsior_teleporters = list() //This list is used to make turrets more efficient
var/global/excelsior_energy
var/global/excelsior_max_energy //Maximaum combined energy of all teleporters
var/global/excelsior_conscripts = 0
var/global/excelsior_last_draft = 0

/obj/machinery/complant_teleporter
	name = "excelsior long-range teleporter"
	desc = "A powerful teleporter that allows shipping matter in and out. Takes a long time to charge."
	density = TRUE
	anchored = TRUE
	icon = 'icons/obj/machines/excelsior/teleporter.dmi'
	icon_state = "idle"
	use_power = IDLE_POWER_USE
	idle_power_usage = 40
	active_power_usage = 15000
	circuit = /obj/item/electronics/circuitboard/excelsior_teleporter

	var/max_energy = 100
	var/energy_gain = 1
	var/processing_order = FALSE
	var/nanoui_menu = 0 	// Based on Uplink
	var/mob/current_user
	var/time_until_scan

	var/reinforcements_delay = 20 MINUTES
	var/reinforcements_cost = 2000

	var/list/nanoui_data = list()			// Additional data for NanoUI use
	var/list/materials_list = list(
		MATERIAL_STEEL = list("amount" = 30, "price" = 50), //base prices doubled untill new item are in
		MATERIAL_WOOD = list("amount" = 30, "price" = 50),
		MATERIAL_PLASTIC = list("amount" = 30, "price" = 50),
		MATERIAL_GLASS = list("amount" = 30, "price" = 50),
		MATERIAL_SILVER = list("amount" = 10, "price" = 100),
		MATERIAL_PLASTEEL = list("amount" = 10, "price" = 200),
		MATERIAL_GOLD = list("amount" = 10, "price" = 200),
		MATERIAL_URANIUM = list("amount" = 10, "price" = 300),
		MATERIAL_DIAMOND = list("amount" = 10, "price" = 400)
		)

	var/list/parts_list = list(
		/obj/item/stock_parts/console_screen = 50,
		/obj/item/stock_parts/capacitor = 100,
		/obj/item/stock_parts/scanning_module = 100,
		/obj/item/stock_parts/manipulator = 100,
		/obj/item/stock_parts/micro_laser = 100,
		/obj/item/stock_parts/matter_bin = 100,
		/obj/item/stock_parts/capacitor/excelsior = 350,
		/obj/item/stock_parts/scanning_module/excelsior = 350,
		/obj/item/stock_parts/manipulator/excelsior = 350,
		/obj/item/stock_parts/micro_laser/excelsior = 350,
		/obj/item/stock_parts/matter_bin/excelsior = 350,
		/obj/item/clothing/under/excelsior = 50,
		/obj/item/electronics/circuitboard/excelsior_teleporter = 500,
		/obj/item/electronics/circuitboard/excelsiorautolathe = 150,
		/obj/item/electronics/circuitboard/excelsiorreconstructor = 150,
		/obj/item/electronics/circuitboard/excelsior_turret = 150,
		/obj/item/electronics/circuitboard/excelsiorshieldwallgen = 150,
		/obj/item/electronics/circuitboard/excelsior_boombox = 150,
		/obj/item/electronics/circuitboard/excelsior_autodoc = 150,
		/obj/item/electronics/circuitboard/diesel = 150
		)
	var/entropy_value = 8

/obj/machinery/complant_teleporter/Initialize()
	excelsior_teleporters |= src
	.=..()

/obj/machinery/complant_teleporter/Destroy()
	excelsior_teleporters -= src
	RefreshParts() // To avoid energy overfills if a teleporter gets destroyed
	.=..()

/obj/machinery/complant_teleporter/RefreshParts()
	if (!component_parts.len)
		error("[src] \ref[src] had no parts on refresh")
		return //this has runtimed before
	var/man_rating = 0
	var/man_amount = 0
	for(var/obj/item/stock_parts/manipulator/M in component_parts)
		man_rating += M.rating
		entropy_value = initial(entropy_value)/M.rating
		man_amount++

	// +50% speed for each upgrade tier
	var/coef = 1 + (((man_rating / man_amount) - 1) / 2)

	energy_gain = initial(energy_gain) * coef
	active_power_usage = initial(active_power_usage) * coef

	var/obj/item/cell/C = locate() in component_parts
	if(C)
		max_energy = C.maxcharge //Big buff for max energy
		excelsior_max_energy = 0
		for (var/obj/machinery/complant_teleporter/t in excelsior_teleporters)
			excelsior_max_energy += t.max_energy
		excelsior_energy = min(excelsior_energy, excelsior_max_energy)
		if(C.autorecharging)
			energy_gain *= 2


/obj/machinery/complant_teleporter/update_icon()
	overlays.Cut()

	if(panel_open)
		overlays += image("panel")

	if(stat & (BROKEN|NOPOWER))
		icon_state = "off"
	else
		icon_state = initial(icon_state)


/obj/machinery/complant_teleporter/attackby(obj/item/I, mob/user)
	if(default_deconstruction(I, user))
		return
	..()

/obj/machinery/complant_teleporter/power_change()
	..()
	SSnano.update_uis(src) // update all UIs attached to src

/obj/machinery/complant_teleporter/Process()
	if(stat & (BROKEN|NOPOWER))
		return

	if(excelsior_energy < (excelsior_max_energy - energy_gain))
		excelsior_energy += energy_gain
		SSnano.update_uis(src)
		use_power = ACTIVE_POWER_USE
	else
		excelsior_energy = excelsior_max_energy
		use_power = IDLE_POWER_USE


/obj/machinery/complant_teleporter/ex_act(severity)
	switch(severity)
		if(1)
			qdel(src)
			return
		if(2)
			if (prob(50))
				qdel(src)
				return


 /**
  * The ui_interact proc is used to open and update Nano UIs
  * If ui_interact is not used then the UI will not update correctly
  * ui_interact is currently defined for /atom/movable
  *
  * @param user /mob The mob who is interacting with this ui
  * @param ui_key string A string key to use for this ui. Allows for multiple unique uis on one obj/mob (defaut value "main")
  *
  * @return nothing
  */
/obj/machinery/complant_teleporter/ui_interact(mob/user, ui_key = "main", datum/nanoui/ui = null, force_open = NANOUI_FOCUS)
	if(stat & (BROKEN|NOPOWER)) return
	if(user.stat || user.restrained()) return

	var/list/data = ui_data()

	time_until_scan = time2text((1800 - ((world.time - round_start_time) % 1800)), "mm:ss")

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "excelsior_teleporter.tmpl", name, 390, 450)
		ui.set_initial_data(data)
		ui.open()

/obj/machinery/complant_teleporter/ui_data()
	var/list/data = list()
	data["energy"] = round(excelsior_energy)
	data["maxEnergy"] = round(excelsior_max_energy)
	data["menu"] = nanoui_menu
	data["excel_user"] = is_excelsior(current_user)
	data["time_until_scan"] = time_until_scan
	data["conscripts"] = excelsior_conscripts
	data["reinforcements_ready"] = reinforcements_check()
	data += nanoui_data

	var/list/order_list_m = list()
	for(var/item in materials_list)
		order_list_m += list(
			list(
				"title" = material_display_name(item),
				"amount" = materials_list[item]["amount"],
				"price" = materials_list[item]["price"],
				"commands" = list("order" = item)
				)
			) // list in a list because Byond merges the first list...

	data["materials_list"] = order_list_m

	var/list/order_list_p = list()
	for(var/item in parts_list)
		var/obj/item/I = item
		order_list_p += list(
			list(
				"name_p" = initial(I.name),
				"price_p" = parts_list[item],
				"commands_p" = list("order_p" = item)
			)
		)

	data["list_of_parts"] = order_list_p

	return data


/obj/machinery/complant_teleporter/Topic(href, href_list)
	if(stat & (NOPOWER|BROKEN))
		return 0 // don't update UIs attached to this object

	if(processing_order)
		return 0

	if(href_list["order"])
		var/ordered_item = href_list["order"]
		if (materials_list.Find(ordered_item))
			var/order_energy_cost = materials_list[ordered_item]["price"]
			var/order_path = material_stack_type(ordered_item)
			var/order_amount = materials_list[ordered_item]["amount"]
			send_order(order_path, order_energy_cost, order_amount)

	if(href_list["order_p"])
		var/ordered_item = text2path(href_list["order_p"])
		if (parts_list.Find(ordered_item))
			var/order_energy_cost = parts_list[ordered_item]
			send_order(ordered_item, order_energy_cost, 1)

	if(href_list["open_menu"])
		nanoui_menu = 1

	if(href_list["close_menu"])
		nanoui_menu = 0

	if(href_list["request_reinforcements"])
		request_reinforcements(usr)

	add_fingerprint(usr)
	update_nano_data()
	return 1 // update UIs attached to this object


/obj/machinery/complant_teleporter/proc/update_nano_data()
	nanoui_data["menu"] = nanoui_menu
	if (nanoui_menu == 1)
		var/list/available_mandates = list()
		var/list/completed_mandates = list()
		for(var/datum/antag_contract/M in GLOB.excel_antag_contracts)
			var/list/entry = list(list(
				"name" = M.name,
				"desc" = M.desc,
				"reward" = M.reward,
				"status" = M.completed ? "Fulfilled" : "Available"
			))
			if(!M.completed)
				available_mandates.Add(entry)
			else
				completed_mandates.Add(entry)
		nanoui_data["available_mandates"] = available_mandates
		nanoui_data["completed_mandates"] = completed_mandates

/obj/machinery/complant_teleporter/proc/send_order(order_path, order_cost, amount)
	if(order_cost > excelsior_energy)
		to_chat(usr, SPAN_WARNING("Not enough energy."))
		return 0

	processing_order = TRUE
	excelsior_energy = max(excelsior_energy - order_cost, 0)
	flick("teleporting", src)
	spawn(17)
		complete_order(order_path, amount)

/obj/machinery/complant_teleporter/proc/complete_order(order_path, amount)
	use_power(active_power_usage * 3)
	new order_path(loc, amount)
	bluespace_entropy(entropy_value, get_turf(src))
	processing_order = FALSE

/obj/machinery/complant_teleporter/attackby(obj/item/I, mob/user)
	for(var/datum/antag_contract/excel/appropriate/M in GLOB.excel_antag_contracts)
		if(M.completed)
			continue
		if(M.target_type == I.type)
			I.Destroy()
			M.complete(user)
			flick("teleporting", src)
	..()

/obj/machinery/complant_teleporter/attack_hand(mob/user)
	if(stat & BROKEN)
		return
	current_user = user
	ui_interact(user)

/obj/machinery/complant_teleporter/affect_grab(var/mob/user, var/mob/target)
	try_put_inside(target, user)
	return TRUE

/obj/machinery/complant_teleporter/MouseDrop_T(var/mob/living/L, mob/living/user)
	if(istype(L) && istype(user))
		try_put_inside(L, user)

/obj/machinery/complant_teleporter/proc/try_put_inside(var/mob/living/affecting, var/mob/living/user) //Based on crypods

	if(!ismob(affecting) || !Adjacent(affecting) || !Adjacent(user))
		return

	visible_message("[user] starts stuffing [affecting] into \the [src].")
	src.add_fingerprint(user)

	if(!do_after(user, 20, src))
		return
	if(!user || !Adjacent(user))
		return
	if(!affecting || !Adjacent(affecting) )
		return
	if (affecting.stat == DEAD)
		to_chat(user, SPAN_WARNING("[affecting] is dead, and can't be teleported"))
		return
	for(var/datum/antag_contract/excel/targeted/M in GLOB.excel_antag_contracts) // All targeted objectives can be completed by stuffing the target in the teleporter
		if(M.completed)
			continue
		if(affecting == M.target_mind.current)
			M.complete(user)
			teleport_out(affecting, user)
			excelsior_conscripts += 1
			return
	if (is_excelsior(affecting))
		teleport_out(affecting, user)
		excelsior_conscripts += 1
		return

	visible_message("\the [src] blinks, refusing [affecting].")
	playsound(src.loc, 'sound/machines/ping.ogg', 50, 1, -3)
/obj/machinery/complant_teleporter/proc/teleport_out(var/mob/living/affecting, var/mob/living/user)
	flick("teleporting", src)
	to_chat(affecting, SPAN_NOTICE("You have been teleported to haven, your crew respawn time is reduced by [(COLLECTIVISED_RESPAWN_BONUS)/600] minutes."))
	visible_message("\the [src] teleporter closes and [affecting] disapears.")
	affecting.set_respawn_bonus("TELEPORTED_TO_EXCEL", COLLECTIVISED_RESPAWN_BONUS)
	affecting << 'sound/effects/magic/blind.ogg'  //Play this sound to a player whenever their respawn time gets reduced
	qdel(affecting)
/obj/machinery/complant_teleporter/proc/request_reinforcements(var/mob/living/user)

	if(excelsior_energy < reinforcements_cost)
		to_chat(user, SPAN_WARNING("Not enough energy."))
		return 0
	if(world.time < (excelsior_last_draft + reinforcements_delay))
		to_chat(user, SPAN_WARNING("You can call only one conscript for 20 minutes."))
		return
	if(excelsior_conscripts <= 0)
		to_chat(user, SPAN_WARNING("They have nobody to send to you."))
		return
	processing_order = TRUE
	use_power(active_power_usage * 10)
	flick("teleporting", src)
	var/mob/observer/ghost/candidate = draft_ghost("Excelsior Conscript", ROLE_BANTYPE_EXCELSIOR, ROLE_EXCELSIOR_REV)
	if(!candidate)
		processing_order = FALSE
		to_chat(user, SPAN_WARNING("Reinforcements were postponed"))
		return

	processing_order = FALSE
	excelsior_last_draft = world.time
	excelsior_energy = excelsior_energy - reinforcements_cost
	excelsior_conscripts -= 1

	var/mob/living/carbon/human/conscript = new /mob/living/carbon/human(loc)
	conscript.ckey = candidate.ckey
	make_antagonist(conscript.mind, ROLE_EXCELSIOR_REV)
	conscript.stats.setStat(STAT_TGH, 10)
	conscript.stats.setStat(STAT_VIG, 10)
	conscript.equip_to_appropriate_slot(new /obj/item/clothing/under/excelsior())
	conscript.equip_to_appropriate_slot(new /obj/item/clothing/shoes/workboots())
	conscript.equip_to_appropriate_slot(new /obj/item/device/radio/headset())
	conscript.equip_to_appropriate_slot(new /obj/item/storage/backpack/satchel())
	var/obj/item/card/id/card = new(conscript)
	conscript.set_id_info(card)
	card.assignment = "Excelsior Conscript"
	card.access = list(access_maint_tunnels)
	card.update_name()
	conscript.equip_to_appropriate_slot(card)
	conscript.update_inv_wear_id()

/obj/machinery/complant_teleporter/proc/reinforcements_check()
	if(excelsior_conscripts <= 0)
		return FALSE
	if(world.time < (excelsior_last_draft + reinforcements_delay))
		return FALSE
	if(excelsior_conscripts <= 0)
		return FALSE
	if(excelsior_energy < reinforcements_cost)
		return FALSE
	return TRUE
	
// admin teleporters
// parent

/obj/machinery/complant_teleporter/admin
	name = "ultra super advanced synthesizer"
	desc = "A powerful synthesizer that can print numerous materials for, essentially, free."
	idle_power_usage = 1
	active_power_usage = 1

	max_energy = 100000
	energy_gain = 1000

	reinforcements_delay = 2 MINUTES
	reinforcements_cost = 1
	
	entropy_value = 0
	
// parts + tools

/obj/machinery/complant_teleporter/admin/construction
	name = "Bluespace League material fabricator"
	desc = "A BSL-branded fabricator that can produce a variety of materials and parts using small amounts of electricity."

	materials_list = list(
		MATERIAL_STEEL = list("amount" = 500, "price" = 1),
		MATERIAL_WOOD = list("amount" = 500, "price" = 1),
		MATERIAL_PLASTIC = list("amount" = 500, "price" = 1),
		MATERIAL_GLASS = list("amount" = 500, "price" = 1),
		MATERIAL_SILVER = list("amount" = 500, "price" = 1),
		MATERIAL_PLASMA = list("amount" = 500, "price" = 1),
		MATERIAL_PLASTEEL = list("amount" = 500, "price" = 1),
		MATERIAL_CARDBOARD = list("amount" = 500, "price" = 1),
		MATERIAL_BIOMATTER = list("amount" = 500, "price" = 1),
		MATERIAL_PLATINUM = list("amount" = 500, "price" = 1),
		MATERIAL_GOLD = list("amount" = 500, "price" = 1),
		MATERIAL_URANIUM = list("amount" = 500, "price" = 1),
		MATERIAL_DIAMOND = list("amount" = 500, "price" = 1)
		)

	parts_list = list(
		/obj/item/spacecash/bundle/c1000 = 1,
		/obj/item/spacecash/bundle/c10000 = 1,
		/obj/item/spacecash/bundle/c100000 = 1,
		/obj/item/stock_parts/console_screen = 1,
		/obj/item/stock_parts/capacitor/debug = 1,
		/obj/item/stock_parts/scanning_module/debug = 1,
		/obj/item/stock_parts/manipulator/debug = 1,
		/obj/item/stock_parts/micro_laser/debug = 1,
		/obj/item/stock_parts/matter_bin/debug = 1,
		/obj/item/cell/large/moebius/nuclear/infinite = 1,
		/obj/item/cell/medium/moebius/nuclear/infinite = 1,
		/obj/item/cell/small/moebius/nuclear/infinite = 1,
		/obj/item/storage/deferred/crate/cells = 1,
		/obj/item/computer_hardware/hard_drive/portable/design/excelsior/weapons = 1,
		/obj/item/storage/deferred/disks = 1,
		/obj/item/storage/toolbox/syndicate = 1,
		/obj/item/storage/toolbox/mechanical = 1,
		/obj/item/storage/toolbox/electrical = 1,
		/obj/item/storage/deferred/crate/tools = 1,
		/obj/item/storage/deferred/toolmod = 1
		)

// weapons + armor

/obj/machinery/complant_teleporter/admin/armory
	name = "Bluespace League military fabricator"
	desc = "A BSL-branded fabricator that prints a large assortment of weapons and armor for use in military applications."

	materials_list = list()

	parts_list = list(
		/obj/item/gun/projectile/colt = 1,
		/obj/item/gun/projectile/mk58 = 1,
		/obj/item/gun/projectile/paco = 1,
		/obj/item/gun/projectile/lamia = 1,
		/obj/item/gun/projectile/olivaw = 1,
		/obj/item/gun/projectile/type_42 = 1,
		/obj/item/gun/projectile/type_69 = 1,
		/obj/item/gun/projectile/giskard = 1,
		/obj/item/gun/projectile/selfload = 1,
		/obj/item/ammo_magazine/pistol = 1,
		/obj/item/ammo_magazine/pistol/highvelocity = 1,
		/obj/item/ammo_magazine/hpistol = 1,
		/obj/item/ammo_magazine/hpistol/highvelocity = 1,
		/obj/item/ammo_magazine/magnum = 1,
		/obj/item/ammo_magazine/magnum/hv = 1,
		/obj/item/ammo_magazine/cspistol = 1,
		/obj/item/ammo_magazine/cspistol/hv = 1,
		/obj/item/ammo_magazine/ammobox/pistol = 1,
		/obj/item/ammo_magazine/ammobox/pistol/hv = 1,
		/obj/item/ammo_magazine/ammobox/magnum = 1,
		/obj/item/ammo_magazine/ammobox/magnum/hv = 1,
		/obj/item/ammo_magazine/ammobox/magnum/hv = 1,
		/obj/item/ammo_magazine/ammobox/clrifle_small = 1,
		/obj/item/ammo_magazine/ammobox/clrifle_small/hv = 1,
		/obj/item/gun/projectile/shotgun/bull = 1,
		/obj/item/gun/projectile/shotgun/pump = 1,
		/obj/item/gun/projectile/shotgun/bojevic = 1,
		/obj/item/gun/projectile/shotgun/doublebarrel = 1,
		/obj/item/gun/projectile/shotgun/doublebarrel/sawn = 1,
		/obj/item/gun/projectile/shotgun/pump/gladstone = 1,
		/obj/item/gun/projectile/shotgun/pump/regulator = 1,
		/obj/item/ammo_magazine/m12 = 1,
		/obj/item/ammo_magazine/m12/pellet = 1,
		/obj/item/ammo_magazine/ammobox/shotgun = 1,
		/obj/item/ammo_magazine/ammobox/shotgun/buckshot = 1,
		/obj/item/ammo_magazine/ammobox/shotgun/incendiaryshells = 1,
		/obj/item/gun/projectile/automatic/wintermute = 1,
		/obj/item/gun/projectile/automatic/z8 = 1,
		/obj/item/gun/projectile/automatic/sol = 1,
		/obj/item/gun/projectile/automatic/ak47/fs = 1,
		/obj/item/ammo_magazine/srifle = 1,
		/obj/item/ammo_magazine/srifle/hv = 1,
		/obj/item/ammo_magazine/ihclrifle = 1,
		/obj/item/ammo_magazine/ihclrifle/hv = 1,
		/obj/item/ammo_magazine/lrifle = 1,
		/obj/item/ammo_magazine/lrifle/highvelocity = 1,
		/obj/item/ammo_magazine/ammobox/srifle = 1,
		/obj/item/ammo_magazine/ammobox/srifle_small/hv = 1,
		/obj/item/ammo_magazine/ammobox/clrifle = 1,
		/obj/item/ammo_magazine/ammobox/clrifle_small/hv = 1,
		/obj/item/ammo_magazine/ammobox/lrifle = 1,
		/obj/item/ammo_magazine/ammobox/lrifle_small/hv = 1,
		/obj/item/gun/energy/gun/martin = 1,
		/obj/item/gun/energy/gun = 1,
		/obj/item/gun/energy/laser = 1,
		/obj/item/gun/energy/retro = 1,
		/obj/item/gun/energy/retro/sawn = 1,
		/obj/item/gun/energy/captain = 1,
		/obj/item/cell/small/hyper = 1,
		/obj/item/cell/medium/hyper = 1,
		/obj/item/grenade/explosive = 1,
		/obj/item/grenade/frag = 1,
		/obj/item/grenade/flashbang = 1,
		/obj/item/tool/knife/boot = 1,
		/obj/item/melee/energy/sword = 1,
		/obj/item/tool/sword/nt/shortsword = 1,
		/obj/item/tool/sword/nt/longsword = 1,
		/obj/item/tool/knife/dagger/nt = 1,
		/obj/item/tool/sword/nt/halberd = 1,
		/obj/item/tool/sword/nt/spear = 1,
		/obj/item/shield/riot/nt = 1,
		/obj/item/shield/buckler/nt = 1,
		/obj/item/storage/deferred/crate/saw = 1,
		/obj/item/storage/deferred/crate/ak = 1,
		/obj/item/storage/deferred/crate/kovacs = 1,
		/obj/item/storage/deferred/crate/grenadier = 1,
		/obj/item/storage/deferred/crate/antiarmor = 1,
		/obj/item/storage/deferred/crate/demolition = 1,
		/obj/item/storage/deferred/crate/marksman = 1,
		/obj/item/storage/deferred/crate/sidearm = 1,
		/obj/item/storage/deferred/crate/specialists_sidearm = 1,
		/obj/item/clothing/suit/armor/vest/full = 1,
		/obj/item/clothing/suit/armor/flak/full = 1,
		/obj/item/clothing/suit/armor/bulletproof/full = 1,
		/obj/item/clothing/suit/armor/platecarrier/full = 1,
		/obj/item/clothing/suit/armor/laserproof/full = 1,
		/obj/item/clothing/suit/storage/vest/merc/full = 1,
		/obj/item/clothing/head/armor/helmet/visor = 1,
		/obj/item/clothing/head/armor/helmet/merchelm = 1,
		/obj/item/clothing/head/armor/faceshield/altyn = 1,
		/obj/item/clothing/head/armor/helmet/merchelm = 1,
		/obj/item/clothing/head/armor/laserproof = 1,
		/obj/item/clothing/suit/space/void/security = 1,
		/obj/item/clothing/suit/space/void/engineering = 1,
		/obj/item/clothing/suit/space/void/science = 1,
		/obj/item/clothing/suit/space/void/merc = 1,
		/obj/item/clothing/suit/space/void/SCAF = 1,
		/obj/item/storage/deferred/crate/uniform_green = 1,
		/obj/item/storage/deferred/crate/uniform_brown = 1,
		/obj/item/storage/deferred/crate/uniform_black = 1,
		/obj/item/storage/deferred/crate/uniform_flak = 1,
		/obj/item/storage/deferred/crate/uniform_light = 1,
		/obj/item/storage/deferred/crate/german_uniform = 1,
		/obj/item/storage/deferred/pouches = 1,
		/obj/item/storage/belt/holding = 1,
		/obj/item/storage/backpack/holding/bst = 1,
		/obj/item/storage/pouch/holding = 1
		)

// food + medicine

/obj/machinery/complant_teleporter/admin/medical
	name = "Bluespace League organic fabricator"
	desc = "A BSL-branded fabricator that prints an assortment of foods, drinks, and medical supplies for everyday use."

	materials_list = list()

	parts_list = list(
		/obj/item/reagent_containers/food/drinks/bottle/small/beer = 1,
		/obj/item/reagent_containers/food/drinks/bottle/small/ale = 1,
		/obj/item/reagent_containers/food/drinks/bottle/orangejuice = 1,
		/obj/item/reagent_containers/food/drinks/bottle/gin = 1,
		/obj/item/reagent_containers/food/drinks/bottle/whiskey = 1,
		/obj/item/reagent_containers/food/drinks/bottle/vodka = 1,
		/obj/item/reagent_containers/food/drinks/bottle/tequilla = 1,
		/obj/item/reagent_containers/food/drinks/bottle/patron = 1,
		/obj/item/reagent_containers/food/drinks/bottle/rum = 1,
		/obj/item/reagent_containers/food/drinks/bottle/vermouth = 1,
		/obj/item/reagent_containers/food/drinks/bottle/wine = 1,
		/obj/item/reagent_containers/food/drinks/bottle/ntcahors = 1,
		/obj/item/reagent_containers/food/drinks/bottle/cola = 1,
		/obj/item/reagent_containers/food/drinks/bottle/space_up = 1,
		/obj/item/storage/deferred/crate/alcohol = 1,
		/obj/item/reagent_containers/food/snacks/liquidfood = 1,
		/obj/item/reagent_containers/food/snacks/tastybread = 1,
		/obj/item/reagent_containers/food/snacks/cheesiehonkers = 1,
		/obj/item/reagent_containers/food/snacks/syndicake = 1,
		/obj/item/reagent_containers/food/snacks/spacetwinkie = 1,
		/obj/item/reagent_containers/food/snacks/no_raisin = 1,
		/obj/item/reagent_containers/food/snacks/sosjerky = 1,
		/obj/item/reagent_containers/food/snacks/mre = 1,
		/obj/item/reagent_containers/food/snacks/mre/can = 1,
		/obj/item/reagent_containers/food/snacks/mre_paste = 1,
		/obj/item/reagent_containers/food/snacks/candy/mre = 1,
		/obj/item/storage/fancy/mre_cracker = 1,
		/obj/item/storage/deferred/rations = 1,
		/obj/item/storage/ration_pack = 1,
		/obj/item/storage/ration_pack/ihr = 1,
		/obj/item/storage/firstaid/regular = 1,
		/obj/item/storage/firstaid/fire = 1,
		/obj/item/storage/firstaid/toxin = 1,
		/obj/item/storage/firstaid/o2 = 1,
		/obj/item/storage/firstaid/adv = 1,
		/obj/item/storage/firstaid/combat = 1,
		/obj/item/storage/firstaid/surgery = 1,
		/obj/item/storage/firstaid/nt = 1
		)
