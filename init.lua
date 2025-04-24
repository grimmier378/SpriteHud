local mq = require('mq')
local ImGui = require 'ImGui'
local Module = {}
if mq.TLO.EverQuest.GameState() ~= "INGAME" then
	printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", Module.Name)
	mq.exit()
end

Module.Name = "SriteHud" -- Name of the module used when loading and unloaing the modules.
Module.IsRunning = false -- Keep track of running state. if not running we can unload it.
Module.ShowGui = false
local myself = mq.TLO.Me
local myName = myself.Name() or "Unknown"
local isFemale = myself.Gender() == 'female'
local hasHoT = false
local cursorX = 0
local cursorY = 0
local debugStatus = false -- set to true to force all status effects to be true for testing
local sortedTbl = {}
local sortedBackground = {}
local sortedCombat = {}

local filePath = nil -- this will be set to the script folder if not loaded externally
local spriteTexture = nil
local efxTexture = nil
local casterTexture = nil
local efx2Texture = nil

-- sprite draw variables
local targetFPS = 6                                   -- Target FPS for the animation
local imgSize = 64                                    -- This is the size to draw the image
local rightOffset = 4                                 -- number of columns to offset to the right to draw the columns 4-7
local spriteSheetSize = 1024                          -- size of the sprite sheet should be Square example 1024x1024 or 512x512
local spriteSheetCols = 8                             -- number of columns in the sprite sheet
local totalFrames = 4                                 -- Total number of frames to animate (4 frames for each direction)
local currentFrame = 0                                -- Current frame to draw start at 0 (0-3) for columns 4-7 use 0-3 and the rightOffset to get the correct column
local efxFrame = 0                                    -- current frame to draw for efx
local frameTime = 1000 / targetFPS                    -- 1second divided by number of images (for number of images per second FPS setting)
local lastSpriteFrameTime = mq.gettime()
local frameWidth = spriteSheetSize / spriteSheetCols  -- total columns (4 male + 4 female)
local frameHeight = spriteSheetSize / spriteSheetCols -- 8 rows for 8 directions
local colPerAnimation = spriteSheetCols / 2
local args = { ..., }

local manualBackground = {
	indoor = false,
	outdoor = false,
	dungeon = false,
	night = false,
	day = false,
	underwater = false,
}

local manualEfx = {
	casting = false,
	cursed = false,
	poisoned = false,
	diseased = false,
	stunned = false,
	mezzed = false,
	hovering = false,
	snared = false,
	rooted = false,
	hot = false,
	feetwet = false,
	underwater = false,
	feigning = false,
	levitate = false,
	invis = false,
	sitting = false,
	silenced = false,
	feared = false,
	looting = false,
}

local manualSprite = {
	skele = false,
	werewolf = false,
	wolf = false,
	bear = false,
	lich = false,
	elemental = false,
	oldcaster = false,
	noarmor = false,
	female = false,
	male = false,
	combat = false,
	caster = false,
	melee = false,
	plate = false,
}

local status = {
	Elemental = false,
	Skele = false,
	Werewolf = false,
	Combat = false,
	Feigning = false,
	Caster = false,
	Sitting = false,
	FeetWet = false,
	UnderWater = false,
	Dungeon = false,
	Outside = false,
	Casting = false,
	Night = false,
	Poisoned = false,
	Diseased = false,
	Cursed = false,
	Mezzed = false,
	Stunned = false,
	Snared = false,
	Rooted = false,
	Hovering = false,
	ResSick = false,
	Bear = false,
	Wolf = false,
	Lich = false,
	Levitate = false,
	Invis = false,
	Silenced = false,
	Feared = false,
	Looting = false,
	Armor = false,
}

-- directions to row mapping for the sprite sheet
local directions = {
	[0] = 3, -- North
	[1] = 7, -- Ne
	[2] = 2, -- East
	[3] = 4, -- SE
	[4] = 0, -- South
	[5] = 5, -- SW
	[6] = 1, -- West
	[7] = 6, -- NW
}

function GetInvisCell(directionVal)
	if directionVal == 3 or directionVal == 0 then
		return 0
	elseif directionVal == 1 then
		return 2
	elseif directionVal == 2 then
		return 1
	elseif directionVal == 4 then
		return 4
	elseif directionVal == 5 then
		return 3
	elseif directionVal == 6 then
		return 5
	elseif directionVal == 7 then
		return 6
	end
end

local casters = {
	['WIZ'] = true,
	['NEC'] = true,
	['ENC'] = true,
	['MAG'] = true,
}

local plateClass = {
	['PAL'] = true,
	['WAR'] = true,
	['CLR'] = true,
	['SHD'] = true,
	['BRD'] = true,
}

local lastTime = mq.gettime()

local function LoadImages()
	spriteTexture = mq.CreateTexture(filePath .. 'sprite_sheet_1k.png')
	efxTexture = mq.CreateTexture(filePath .. 'efx_overlay_sheet_1k.png')
	casterTexture = mq.CreateTexture(filePath .. 'casters_sheet_1k.png')
	efx2Texture = mq.CreateTexture(filePath .. 'efx_overlay_sheet2_1k.png')
end

local function checkArgs()
	if #args == 0 then
		return
	end

	for _, arg in ipairs(args) do
		if tonumber(arg) then
			imgSize = tonumber(arg)
			if imgSize < 1 then
				imgSize = 1
			end
		elseif manualSprite[arg] ~= nil then
			manualSprite[arg] = true
			printf("\aw[\at%s\ax] \aySetting \ax(\at%s\ax) to enabled.\ax", Module.Name, arg)
		elseif manualEfx[arg] ~= nil then
			manualEfx[arg] = true
			printf("\aw[\at%s\ax] \aySetting \ax(\at%s\ax) to enabled.\ax", Module.Name, arg)
		end
		if manualBackground[arg] ~= nil then
			manualBackground[arg] = true
			printf("\aw[\at%s\ax] \aySetting Background \ax(\at%s\ax) to enabled.\ax", Module.Name, arg)
		end
	end
end

local function sortTables()
	sortedTbl = {}
	for k, v in pairs(manualEfx) do
		table.insert(sortedTbl, { name = k, value = v, })
	end
	table.sort(sortedTbl, function(a, b) return a.name < b.name end)
	sortedBackground = {}
	for k, v in pairs(manualBackground) do
		table.insert(sortedBackground, { name = k, value = v, })
	end
	table.sort(sortedBackground, function(a, b) return a.name < b.name end)
	sortedCombat = {}
	for k, v in pairs(manualSprite) do
		table.insert(sortedCombat, { name = k, value = v, })
	end
	table.sort(sortedCombat, function(a, b) return a.name < b.name end)
end



local function Init()
	Module.IsRunning = true

	mq.bind("/spritehud", Module.CommandHandler)
	checkArgs()
	Module.UpdateStatus()
	mq.imgui.init(Module.Name, Module.RenderGUI)

	mq.delay(10) -- delay so we can get our PID from the Lua TLO
	printf("\aw[\at%s\ax] \ayLoading Sprite HUD...\ax", Module.Name)

	if filePath == nil then
		-- get last PID
		local lastPID = mq.TLO.Lua.PIDs():match("(%d+)$")
		local scriptFolder = mq.TLO.Lua.Script(lastPID).Name()
		filePath = string.format("%s/%s/images/", mq.luaDir, scriptFolder)
		LoadImages()
	end
	sortTables()
	printf("\aw[\at%s\ax] \aySprite Size is set to\ax \at%s\ax", Module.Name, imgSize)
	printf("\aw[\at%s\ax] \ay/spritehud size <\atsize\ax>\ax \ayto change the size of the sprite.\ax", Module.Name)
	printf("\aw[\at%s\ax] \ay/spritehud \atclose\ax \ayto close the sprite hud.\ax", Module.Name)
	return true
end

local winFlags = bit32.bor(
	ImGuiWindowFlags.NoCollapse,
	ImGuiWindowFlags.AlwaysAutoResize,
	ImGuiWindowFlags.NoTitleBar
)

---comment
---@param textureMap MQTexture the texture map to draw from
---@param rowNum integer the row number to draw from (0-7)
---@param colNum integer the column number to draw from (0-3) there are 8 columns but we offset to get to the last 4. Any animation uses 4 cells at most.
---@param isOffset boolean|nil If the column is higher than 3 then we will need to offset, mostly used for female animations but also some efx
function DrawAnimatedFrame(textureMap, rowNum, colNum, isOffset)
	local genderOffset = isOffset and rightOffset or 0

	local col = (colNum % colPerAnimation) + genderOffset

	-- Normalize UVs
	local u1 = (col * frameWidth) / spriteSheetSize
	local v1 = (rowNum * frameHeight) / spriteSheetSize
	local u2 = ((col + 1) * frameWidth) / spriteSheetSize
	local v2 = ((rowNum + 1) * frameHeight) / spriteSheetSize

	if textureMap then
		ImGui.Image(textureMap:GetTextureID(), ImVec2(imgSize, imgSize), ImVec2(u1, v1), ImVec2(u2, v2))
	end
	ImGui.SetCursorPos(cursorX, cursorY)
end

function HeadingToRowNum(heading)
	-- Normalize to 0-360 and divide into 8 parts
	local dirIndex = math.floor((heading % 360) / 45 + 0.5) % 8
	return directions[dirIndex] or 0
end

function Module.RenderConfig()
	if not Module.ShowConfig then return end
	local open, show = ImGui.Begin("Sprite HUD Config", Module.ShowConfig)
	if show then
		imgSize = ImGui.DragInt("Sprite Size##SpriteSize", imgSize, 1, 1, 512)
		targetFPS = ImGui.DragInt("Animation Speed##SpriteFPS", targetFPS, 1, 1, 30)
		local cnt = 1
		if ImGui.CollapsingHeader("EFX:") then
			if ImGui.BeginTable("##DebugEfx", 4) then
				ImGui.TableNextRow()
				ImGui.TableNextColumn()
				for _, data in ipairs(sortedTbl) do
					ImGui.PushID(data.name .. "efx")
					ImGui.Text(data.name)
					ImGui.TableNextColumn()
					manualEfx[data.name] = ImGui.Checkbox("##Dbg", manualEfx[data.name])
					ImGui.TableNextColumn()
					ImGui.PopID()
				end
				ImGui.EndTable()
			end
		end
		ImGui.Spacing()
		if ImGui.CollapsingHeader("Background:") then
			if ImGui.BeginTable("##DebugBackground", 4) then
				ImGui.TableNextRow()
				ImGui.TableNextColumn()
				for _, data in ipairs(sortedBackground) do
					ImGui.PushID(data.name .. "bg")
					ImGui.Text(data.name)
					ImGui.TableNextColumn()
					manualBackground[data.name] = ImGui.Checkbox("##Dbg", manualBackground[data.name])
					ImGui.TableNextColumn()
					ImGui.PopID()
				end
				ImGui.EndTable()
			end
		end
		ImGui.Spacing()
		if ImGui.CollapsingHeader("Sprite:") then
			if ImGui.BeginTable("##DebugCombat", 4) then
				ImGui.TableNextRow()
				ImGui.TableNextColumn()
				for _, data in ipairs(sortedCombat) do
					ImGui.PushID(data.name .. 'sprite')
					ImGui.Text(data.name)
					ImGui.TableNextColumn()
					manualSprite[data.name] = ImGui.Checkbox("##Dbg", manualSprite[data.name])
					ImGui.TableNextColumn()
					ImGui.PopID()
				end
				ImGui.EndTable()
			end
		end
	end
	if not open then
		Module.ShowConfig = false
	end
	ImGui.End()
end

function Module.ContextMenu()
	if ImGui.BeginPopupContextWindow("Sprite HUD Context Menu") then
		if ImGui.MenuItem("Config", nil, Module.ShowConfig) then
			Module.ShowConfig = not Module.ShowConfig
		end
		if ImGui.MenuItem("Close", nil, false) then
			Module.ShowGui = false
		end
		ImGui.EndPopup()
	end
end

function Module.RenderGUI()
	ImGui.SetNextWindowPos((ImGui.GetIO().DisplaySize.x / 2) - 64, 0, ImGuiCond.FirstUseEver)
	ImGui.SetNextWindowSize(ImVec2(500, 770), ImGuiCond.FirstUseEver)
	if Module.ShowGui and filePath ~= nil then
		ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.1, 0.1, 0.1, 0.0))
		ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 0.0)
		local open, show = ImGui.Begin("Sprite HUD##" .. myName, true, winFlags)
		if not open then
			show = false
			Module.ShowGui = false
		end
		if show and efxTexture ~= nil and spriteTexture ~= nil and casterTexture ~= nil and efx2Texture ~= nil then
			-------- Sprite Animation Style
			local heading = myself.Heading.Degrees() or 0
			local rowNum = HeadingToRowNum(heading)
			local drawFrame = currentFrame

			if not status.Moving then
				drawFrame = 0
			end

			cursorX, cursorY = ImGui.GetCursorPos()

			-- draw background
			if status.UnderWater then
				DrawAnimatedFrame(efxTexture, 3, 3, false)
			elseif status.Indoor or status.Outside and not manualBackground.dungeon then
				if status.Night then
					DrawAnimatedFrame(efxTexture, 3, 2, true)
				else
					DrawAnimatedFrame(efxTexture, 3, 1, true)
				end
				if status.Indoor then
					DrawAnimatedFrame(efxTexture, 3, 0, true)
				end
			elseif status.Dungeon then
				DrawAnimatedFrame(efxTexture, 3, 3, true)
			end

			-- draw background efx


			-- Draw the sprite
			if status.Invis then
				local invisCol = GetInvisCell(rowNum)
				local invisOffset = invisCol > 3
				if invisCol > 3 then
					invisCol = invisCol - rightOffset
				end
				if not status.Sitting then
					DrawAnimatedFrame(efxTexture, 6, invisCol, invisOffset)
				else
					DrawAnimatedFrame(efxTexture, 6, 3, true)
				end
			elseif status.Looting then
				DrawAnimatedFrame(efxTexture, 7, 3, false)
			elseif status.Sitting then
				local colIdx = isFemale and 3 or 2
				if status.Caster then
					DrawAnimatedFrame(efx2Texture, 3, colIdx, false)
				else
					DrawAnimatedFrame(efx2Texture, 3, colIdx, true)
				end
			elseif status.Feigning then
				local colIdx = isFemale and 1 or 0
				if status.Caster then
					DrawAnimatedFrame(efx2Texture, 3, colIdx, false)
				else
					DrawAnimatedFrame(efx2Texture, 3, colIdx, true)
				end
			else
				if status.Combat then
					if status.Werewolf then
						DrawAnimatedFrame(efx2Texture, 0, efxFrame, false)
					elseif status.Skele then
						DrawAnimatedFrame(efx2Texture, 0, efxFrame, true)
					elseif status.Wolf then
						DrawAnimatedFrame(efx2Texture, 2, efxFrame, true)
					elseif status.Bear then
						DrawAnimatedFrame(efx2Texture, 1, efxFrame, true)
					elseif status.Lich then
						DrawAnimatedFrame(efx2Texture, 1, efxFrame, false)
					elseif status.Elemental then
						DrawAnimatedFrame(efx2Texture, 2, efxFrame, false)
					elseif status.Caster then
						if manualSprite.oldcaster then
							DrawAnimatedFrame(efx2Texture, 6, currentFrame, isFemale)
						else
							DrawAnimatedFrame(efx2Texture, 5, currentFrame, isFemale)
						end
					elseif status.Armor then
						if manualSprite.noarmor then
							DrawAnimatedFrame(efx2Texture, 7, currentFrame, isFemale)
						else
							DrawAnimatedFrame(efx2Texture, 4, currentFrame, isFemale)
						end
					else
						DrawAnimatedFrame(efx2Texture, 7, currentFrame, isFemale)
					end
				elseif status.ResSick or status.Hovering then
					DrawAnimatedFrame(efxTexture, 0, 0, true)
				elseif status.Caster then
					DrawAnimatedFrame(casterTexture, rowNum, drawFrame, isFemale)
				else
					DrawAnimatedFrame(spriteTexture, rowNum, drawFrame, isFemale)
				end
			end

			-- Draw the efx overlay
			if status.Diseased then
				DrawAnimatedFrame(efxTexture, 1, efxFrame, true)
			end

			if status.Poisoned then
				DrawAnimatedFrame(efxTexture, 1, efxFrame, false)
			end

			if status.Cursed then
				DrawAnimatedFrame(efxTexture, 2, efxFrame, false)
			end

			if hasHoT then
				DrawAnimatedFrame(efxTexture, 0, efxFrame, false)
			end

			if status.Casting then
				if manualEfx.casting then
					DrawAnimatedFrame(efxTexture, 5, efxFrame, true)
				elseif mq.TLO.Spell(myself.Casting()).Category() == 'Create Item' or mq.TLO.Spell(myself.Casting()).Category() == 'Pet' then
					DrawAnimatedFrame(efxTexture, 7, efxFrame, true)
				elseif mq.TLO.Spell(myself.Casting()).Beneficial() then
					DrawAnimatedFrame(efxTexture, 5, efxFrame, true)
				else
					DrawAnimatedFrame(efxTexture, 5, efxFrame, false)
				end
			end

			if status.Mezzed then
				DrawAnimatedFrame(efxTexture, 4, efxFrame, true)
			elseif status.Stunned then
				DrawAnimatedFrame(efxTexture, 4, efxFrame, false)
			end

			if status.Silenced then
				DrawAnimatedFrame(efxTexture, 0, 2, true)
			end

			if status.Feared then
				DrawAnimatedFrame(efxTexture, 0, 1, true)
			end

			if status.FeetWet and not status.UnderWater then
				DrawAnimatedFrame(efxTexture, 3, 1, false)
			elseif (status.FeetWet and status.UnderWater) or manualEfx.underwater then
				DrawAnimatedFrame(efxTexture, 3, 2, false)
			end

			if status.Levitate then
				DrawAnimatedFrame(efxTexture, 3, 0, false)
			end

			-- draw the border
			if status.Snared then
				DrawAnimatedFrame(efxTexture, 7, 2, false)
			elseif status.Rooted then
				DrawAnimatedFrame(efxTexture, 7, 1, false)
			else
				DrawAnimatedFrame(efxTexture, 7, 0, false)
			end

			Module.ContextMenu()
		end
		ImGui.PopStyleColor()
		ImGui.PopStyleVar()
		ImGui.End()
	end

	Module.RenderConfig()
end

function Module.Unload()
	mq.unbind("/spritehud")
end

function Module.CommandHandler(...)
	local args = { ..., }
	if args[1] == 'exit' or args[1] == 'close' then
		Module.ShowGui = false
		return
	elseif args[1] == 'config' then
		Module.ShowConfig = not Module.ShowConfig
	elseif args[1] == 'debug' then
		if manualEfx[args[2]] ~= nil then
			manualEfx[args[2]] = not manualEfx[args[2]]
		end
		local found = false
		for k, v in pairs(manualEfx) do
			if v then
				found = true
				break
			end
		end
		debugStatus = found
		if debugStatus then
			printf("\aw[\at%s\ax] \ayDebugging \ax(\at%s\ax) is enabled.\ax", Module.Name, args[2])
		else
			printf("\aw[\at%s\ax] \ayDebugging \ax(\at%s\ax) is disabled.\ax", Module.Name, args[2])
		end
	elseif #args == 2 and args[1] == 'size' then
		local size = tonumber(args[2])
		if size and size > 0 then
			printf("\aw[\at%s\ax] \aoChanging Sprite Size from\ax (\at%s\ax) \aoto \ax(\ay%s\ax). ", Module.Name, imgSize, size)
			imgSize = size
		end
	elseif #args == 2 and args[1] == 'speed' then
		if args[2] == 'up' then
			targetFPS = targetFPS + 1
			if targetFPS > 15 then
				targetFPS = 15
			end
			printf("\aw[\at%s\ax] \ayIncreasing FPS to\ax \at%s\ax", Module.Name, targetFPS)
		elseif args[2] == 'down' then
			targetFPS = targetFPS - 1
			if targetFPS < 1 then
				targetFPS = 1
			end
			printf("\aw[\at%s\ax] \ayDecreasing FPS to\ax \at%s\ax", Module.Name, targetFPS)
		elseif args[2] == 'reset' then
			targetFPS = 6
			printf("\aw[\at%s\ax] \ayResetting FPS to\ax \at%s\ax", Module.Name, targetFPS)
		elseif tonumber(args[2]) then
			targetFPS = tonumber(args[2])
			if targetFPS < 1 then
				targetFPS = 1
			end
			printf("\aw[\at%s\ax] \aySetting FPS to\ax \at%s\ax", Module.Name, targetFPS)
		end
	end
end

function Module.UpdateStatus()
	if not Module.ShowGui then return end
	local myClass = myself.Class.ShortName() or "Unknown"
	local zoneType = mq.TLO.Zone.Type() or 0
	status.Combat = manualSprite.combat or myself.Combat()
	status.Sitting = manualEfx.sitting or myself.Sitting()
	status.FeetWet = manualEfx.feetwet or myself.FeetWet()
	status.UnderWater = manualBackground.underwater or myself.Underwater()
	status.Dungeon = manualBackground.dungeon or mq.TLO.Zone.Dungeon()
	status.Outside = manualBackground.outside or mq.TLO.Zone.Outdoor()
	status.Casting = manualEfx.casting or myself.Casting()
	status.Night = manualBackground.night or mq.TLO.GameTime.Night()
	status.Poisoned = manualEfx.poisoned or myself.Poisoned()
	status.Diseased = manualEfx.diseased or myself.Diseased()
	status.Cursed = manualEfx.cursed or myself.Cursed()
	status.Mezzed = manualEfx.mezzed or myself.Mezzed()
	status.Stunned = manualEfx.stunned or myself.Stunned()
	status.Snared = manualEfx.snared or myself.Snared()
	status.Rooted = manualEfx.rooted or myself.Rooted()
	status.Hovering = manualEfx.hovering or myself.Hovering()
	status.ResSick = manualEfx.ressick or myself.Buff("Resurrection Sickness")() ~= nil
	status.Indoor = manualBackground.indoor or (zoneType == 3 or zoneType == 4)
	status.Feigning = manualEfx.feigning or myself.Feigning()
	status.Skele = manualSprite.skele or myself.Race() == 'Skeleton'
	status.Werewolf = manualSprite.werewolf or myself.Race() == 'Werewolf'
	status.Wolf = manualSprite.wolf or myself.Race() == 'Wolf'
	status.Bear = manualSprite.bear or myself.Race() == 'Bear'
	status.Lich = manualSprite.lich or myself.Race() == 'Spectre'
	status.Elemental = manualSprite.elemental or myself.Race() == 'Elemental'
	status.Levitate = manualEfx.levitate or myself.Levitating()
	status.Invis = manualEfx.invis or myself.Invis()
	status.Silenced = manualEfx.silenced or myself.Silenced()
	status.Feared = manualEfx.feared or (myself.Feared() or false)
	status.Looting = manualEfx.looting or mq.TLO.Corpse() ~= 'FALSE'

	if casters[myClass] ~= nil then
		status.Caster = true
	else
		status.Caster = false
	end

	if plateClass[myClass] ~= nil then
		status.Armor = true
	else
		status.Armor = false
	end

	if manualSprite.caster then
		status.Caster = true
		status.Armor = false
	end

	if manualSprite.plate then
		status.Armor = true
		status.Caster = false
	end

	if manualSprite.melee then
		status.Caster = false
		status.Armor = false
	end


	if manualBackground.day then
		status.Night = false
	end

	local speed = myself.Speed() or 0
	if speed <= 5 and speed >= -5 then
		status.Moving = false
	else
		status.Moving = true
	end

	local buffCount = myself.BuffCount() or 0
	local songCount = myself.CountSongs() or 0

	isFemale = manualSprite.female or myself.Gender() == 'female'
	if manualSprite.male then
		isFemale = false
	end

	local checkHot = false
	if buffCount > 0 then
		for i = 1, buffCount do
			local buff = myself.Buff(i)
			if buff() then
				if buff.HasSPA(100)() then
					checkHot = true
					break
				end
			end
		end
	end
	if songCount > 0 then
		for i = 1, songCount do
			local song = myself.Song(i)
			if song() then
				if song.HasSPA(100)() then
					checkHot = true
					break
				end
			end
		end
	end
	hasHoT = checkHot or manualEfx.hot
end

function Module.MainLoop()
	while Module.ShowGui do
		local nowTime = mq.gettime()

		-- update status every 100ms to reduce CPU usage
		if nowTime - lastTime > 100 then
			Module.UpdateStatus()
		end

		-- update sprite frame every frameTime so we can target the FPS we want
		frameTime = 1000 / targetFPS
		if nowTime - lastSpriteFrameTime > frameTime then
			currentFrame = (currentFrame + 1) % totalFrames
			efxFrame = (efxFrame + 1) % totalFrames
			lastSpriteFrameTime = nowTime
		end
		mq.delay(1)
	end
	Module.Unload()
end

function Module.LocalLoop()

end

-- Init the module
Module.ShowGui = Init()

Module.MainLoop()

return Module
