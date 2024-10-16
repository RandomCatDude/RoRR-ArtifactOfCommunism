------------------------------------------------------------------------------------------------------------------------
-- HERE BE DRAGONS!!!!
-- this code is ancient and crusty, from a time before the toolkit and its conveniences.
-- i would heavily advise against using it for anything other than reflecting on how far RoRR modding has come.
------------------------------------------------------------------------------------------------------------------------

local item_listing = {}
local item_identifier_to_id = {}

local default_blacklist = {
	[1  ] = true,
	[7  ] = true,
	[24 ] = true,
	[25 ] = true,
	[29 ] = true,
	[47 ] = true,
	[48 ] = true,
	[50 ] = true,
	[52 ] = true,
	[57 ] = true,
	[63 ] = true,
	[95 ] = true,
}

local blacklist = {}

local hard_blacklist = {
	[6  ] = true,
	[43 ] = true,
	[54 ] = true,
	[77 ] = true,
	[79 ] = true,
	[86 ] = true,
	[113] = true,
	[114] = true,
}

local blacklist_search = ""

local cfg_path = _ENV["!config_mod_folder_path"]
local cfg_file = path.combine(cfg_path, "communism_blacklist.toml")

function reset_blacklist()
	blacklist = {}
	for k, v in pairs(default_blacklist) do
		blacklist[k] = v
	end
end

function save_blacklist()
    local dirs = path.get_directories(cfg_path)
    local create = true
    for _,v in pairs(dirs) do
        if v == cfg_path then create = false end
    end
    if create then
		path.create_directory(cfg_path)
    end

	local serialize = {}
	for id, blacklisted in pairs(blacklist) do
		serialize[item_listing[id+1].config_key] = blacklisted
	end
	local succeeded, result = pcall(toml.encodeToFile, serialize, { file = cfg_file, overwrite = true })
end

function load_blacklist()
	local succeeded, table = pcall(toml.decodeFromFile, cfg_file)
	if succeeded then
		blacklist = {}
		for k, v in pairs(table) do
			if item_identifier_to_id[k] then
				blacklist[ item_identifier_to_id[k] ] = v
			end
		end
	else
		reset_blacklist()
	end
end

gui.add_imgui(function()
	if ImGui.Begin("(Communism) Enemy Item Blacklist") then
		if #item_listing == 0 then
			ImGui.TextWrapped("...")
			return
		end

		ImGui.TextWrapped("Tick the checkmarks of items to blacklist from distribution to enemies.\nYou have to be the host for this to apply.")
		if ImGui.Button("Reset to defaults") then
			reset_blacklist()
			save_blacklist()
		end

		ImGui.Separator()
		blacklist_search = ImGui.InputText("Filter", blacklist_search, 100)
		ImGui.Separator()
		for _, item in pairs(item_listing) do
			local show = true
			if show and blacklist_search ~= "" then
				local rawmatch = string.find(string.lower(item.printname), string.lower(blacklist_search))
				if not rawmatch then
					show = false
				end
			end

			if show and hard_blacklist[item.id] then
				show = false
			end

			if show then
				local id = item.id
				local val, pressed = ImGui.Checkbox(item.printname, blacklist[id] or false)
				if pressed then
					blacklist[id] = val
					if blacklist[id] then
						log.info("added item "..item.identifier.." (id: "..id..") to blacklist")
					else
						log.info("removed item "..item.identifier.." (id: "..id..") from blacklist")
					end
					save_blacklist()
				end
			end
		end
		ImGui.End()
	end
end)

local forbidden = {
	[gm.constants.oEngiTurret] = true,
	[gm.constants.oEngiTurretB] = true,
	[gm.constants.oLizardF] = true,
	[gm.constants.oLizardFG] = true,
}

function is_valid_object_id(id)
	if forbidden[id] then return false end
	return gm.object_is_ancestor(id, gm.constants.pFriend) == 1.0 or gm.object_is_ancestor(id, gm.constants.pEnemy) == 1.0
end
function is_actor_id_allowed_item(id, item_id)
	if id ~= gm.constants.oP and hard_blacklist[item_id] then return end
	return not (gm.object_is_ancestor(id, gm.constants.pEnemy) == 1.0 and blacklist[item_id] )
end

local enemy_items = {}
local enable_communism = true
local uwu_id

gm.post_script_hook(gm.constants.run_create, function(self, other, result, args)
	local artifacts = gm.variable_global_get("class_artifact")
	local communism = gm.array_get(artifacts, uwu_id)

	enable_communism = gm.array_get(communism, 8)

	if enable_communism then
		log.info("new run -- resetting item pool")
		enemy_items = {}
	end
end)

local everlasting_head = false
gm.post_script_hook(gm.constants.item_give, function(self, other, result, args)
	if everlasting_head then return end
	if not enable_communism then return end

	local actor = args[1].value

	if actor.object_index == gm.constants.oP then
		local item_id = args[2].value
		local count = args[3].value
		local stack_kind = args[4].value

		-- don't add temp items to the pool because they'll stick around forever and be obnoxious
		-- also don't add it to the pool if its in the hard blacklist cause players'
		if stack_kind == 0 or hard_blacklist[item_id] then
			enemy_items[item_id] = (enemy_items[item_id] or 0) + count
		end

		everlasting_head = true
		for i = 1, #gm.CInstance.instances_active do
			local instance = gm.CInstance.instances_active[i]
			if is_valid_object_id(instance.object_index) and instance ~= actor and is_actor_id_allowed_item(instance.object_index, item_id) then
				gm.item_give(instance, item_id, count, stack_kind)
			end
		end
		everlasting_head = false
	end
end)

gm.post_script_hook(gm.constants.init_actor_late, function(self, other, result, args)
	if not enable_communism then return end

	if not is_valid_object_id(self.object_index) then return end

	everlasting_head = true
	for item, count in pairs(enemy_items) do
		if is_actor_id_allowed_item(self.object_index, item) then
			gm.item_give(self, item, count, 0)
		end
	end
	everlasting_head = false
end)

-- remove items from the pool when players consume items like dios
gm.post_script_hook(gm.constants.item_take, function(self, other, result, args)
	if not enable_communism then return end
	if args[1].value.object_index == gm.constants.oP then
		local item_id = args[2].value
		local count = args[3].value
		local stack_kind = args[4].value

		if stack_kind == 0 and enemy_items[item_id] > 0 then
			enemy_items[item_id] = enemy_items[item_id] - 1
		end
	end
end)

local sprite = nil
local hooks = {}

local init = false
gm.post_script_hook(gm.constants.__input_system_tick, function(self, other, result, args)
	if init then return end
    init = true

    uwu_id = gm.artifact_find("kitty-communism")
	if not uwu_id then
		uwu_id = gm.artifact_create("kitty",
									"communism",
									nil,
									7,
									0,
									0)
	end
	if not sprite then
		sprite = addsprite()
	end

	local artifacts = gm.variable_global_get("class_artifact")
	local communism = gm.array_get(artifacts, uwu_id)

	gm.array_set(communism, 2, "Communism")
	gm.array_set(communism, 3, "Artifact of Communism")
	gm.array_set(communism, 4, "Items are shared with everyone, ally and enemy alike.")
	gm.array_set(communism, 5, sprite)
	gm.array_set(communism, 6, 0)
	gm.array_set(communism, 7, 0)

	--local langmap = gm.variable_global_get("_language_map")
	--gm.ds_map_set(langmap, "artifact.communism.name", "Communism")
	--gm.ds_map_set(langmap, "artifact.communism.description", "Items are shared with everyone, ally and enemy alike.")

	generate_item_mapping()
	load_blacklist()
end)

function generate_item_mapping()
	local langmap = gm.variable_global_get("_language_map")
	local items = gm.variable_global_get("class_item")
	log.info("Item listing generating")
	for i = 1, #items do
		local item = items[i]
		local namespace = item[1]
		local identifier = item[2]
		local token = item[3]
		local config_key = namespace.."."..identifier
		local name = tostring(gm.ds_map_find_value(langmap, token))
		if name ~= "nil" and not hard_blacklist[i - 1] then
			item_listing[i] = {
				printname = "ID "..i-1 ..': '..name.." ("..identifier..')',
				identifier = identifier,
				id = i - 1,
				config_key = config_key,
			}
		end
		item_identifier_to_id[config_key] = i - 1
	end
	log.info("Item listing generated -- "..#item_listing.." entries")
end

function addsprite()
	local path = _ENV._PLUGIN.plugins_mod_folder_path .. "/ArtifactCommunism.png"
	return gm.sprite_add(path, 3, false, false, 16, 16)
end

-- hack to prevent drones with mocha from crashing
gm.pre_script_hook(gm.constants.actor_skin_skinnable_set_skin, function(self, other, result, args)
	if enable_communism and gm.object_is_ancestor(args[1].value.object_index, gm.constants.pDrone) then
		return false
	end
end)
