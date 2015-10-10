Walker = (function()
	
	-- Imports
	local pingDelay = Core.pingDelay
	local setTimeout = Core.setTimeout
	local when = Core.when
	local split = Core.split
	local getPosFromString = Core.getPosFromString
	local cleanLabel = Core.cleanLabel
	local sortPositionsByDistance = Core.sortPositionsByDistance
	local getPositionFromDirection = Core.getPositionFromDirection
	local getDistanceBetween = Core.getDistanceBetween
	local talk = Core.talk
	local log = Console.log
	local warn = Console.warn
	local error = Console.error
	local prompt = Console.prompt
	local bankWithdrawGold = Npc.bankWithdrawGold
	local getMoney = Container.getMoney

	local function walkerLabelExists(label)
		local waypoints = _settings['Walker']['WaypointList']
		for i = 1, #waypoints do
			if cleanLabel(waypoints[i].text) == label then
				return true
			end
		end
		return false
	end

	local function walkerGetTownExit()
		if _script.townexit then
			return _script.townexit
		end
		local waypoints = _settings['Walker']['WaypointList']
		for i = 1, #waypoints do
			if string.find(waypoints[i].text, '~spawn:') then
				local label = cleanLabel(waypoints[i].text)
				_script.townexit = split(split(label, '|')[2], '~')[1]
				return
			end
		end
	end

	local function walkerGetTownEntrance()
		if _script.townentrance then
			return _script.townentrance
		end
		local waypoints = _settings['Walker']['WaypointList']
		for i = 1, #waypoints do
			if string.find(waypoints[i].text, 'spawn~') then
				local label = cleanLabel(waypoints[i].text)
				_script.townentrance = split(split(label, '|')[2], '~')[2]
				return
			end
		end
	end

	local function walkerStartPath(town, source, destination, callback)
		-- DISABLED, we should have depot~depot and similar paths.
		-- Already at destination, return success
		--if source == destination then
		--    callback()
		--    return
		--end

		local function walkTo(label, walkCallback)
			xeno.gotoLabel(label)
			xeno.setWalkerEnabled(true)
			when(EVENT_PATH_END, nil, function()
				walkCallback()
			end)
		end

		-- Label doesn't exist, try walking to depot, then destination from there
		local label = string.lower(town) .. '|' .. source .. '~' .. destination
		if not walkerLabelExists(label) then
			local depotLabel = string.lower(town) .. '|' .. source .. '~depot'
			
			-- Depot doesn't exist, error out, this should never happen (path missing)
			if not walkerLabelExists(depotLabel) then
				-- Check if we're starting the script in spawn
				if source == 'spawn' then
					error('Unable to walk to ' .. destination .. ' from here. Please start the script near ' .. town .. '.')
				else	
					error('Missing route: ' .. town .. ' ' .. source .. ' to ' .. destination .. '. Please contact support.')
				end
				return
			end
			
			-- Depot path exist, take detour
			walkTo(depotLabel, function()
				-- Walk from depot to destination
				walkTo(string.lower(town) .. '|depot~' .. destination, callback)
			end)
			return
		end

		-- Path exists, take direct path
		walkTo(label, callback)
	end

	local function walkerGetPosAfterLabel(label, index)
		local waypoints = _settings['Walker']['WaypointList']
		local foundLabel = index and true or false
		local startIndex = index or 1
		for i = startIndex, #waypoints do
			waypoint = waypoints[i]
			-- Find the starting position if we haven't already
			if not foundLabel and cleanLabel(waypoint.text) == label then
				foundLabel = true
			end
			-- Find the related stand position after we find the label
			if foundLabel and tonumber(waypoint.tag) < 10 then
				local pos = getPosFromString(waypoint.text)
				return pos.x > 0 and pos or false
			end
		end
		return false
	end

	local function walkerGetClosestLabel(multiFloor, prefix)
		local waypoints = _settings['Walker']['WaypointList']
		local positions = {}
		local selfPos = xeno.getSelfPosition()
		for i = 1, #waypoints do
			if waypoints[i].tag == '255' then
				local label = cleanLabel(waypoints[i].text)
				-- Prefix filter
				if not prefix or string.lower(split(label, '|')[1]) == string.lower(prefix) then
					-- Floor filter
					local pos = walkerGetPosAfterLabel(nil, i)
					if pos and (multiFloor or selfPos.z == pos.z) then
						pos.name = label
						table.insert(positions, pos)
					end
				end
			end
		end
		positions = sortPositionsByDistance(selfPos, positions, 10)
		return positions[1]
	end

	local function walkerVerifyPosition(label, option)
		local pos = walkerGetPosAfterLabel(label)
		local selfPos = xeno.getSelfPosition()
		local distance = getDistanceBetween(selfPos, pos)
		if pos then
			-- no option specified, compare exact position
			if not option and distance < 1 and selfPos.z == pos.z then
				return true
			-- option (=) specified, check for higher z axis.
			elseif option == '=' and selfPos.z == pos.z then
				return true
			-- option (-) specified, check for higher z axis.
			elseif option == '-' and selfPos.z > pos.z then
				return true
			-- option (+) specified, check for lower z axis.
			elseif option == '+' and selfPos.z < pos.z then
				return true
			-- other long option specified, probably range.
			elseif option and #option > 1 then
				local operator = string.sub(option, 1, 1)
				local value = tonumber(string.sub(option, 2))
				-- if value is a number
				if value then
					local meetsRange = false
					if operator == '>' then
						meetsRange = (distance > value)
					elseif operator == '<' then
						meetsRange = (distance < value)
					elseif operator == '=' then
						meetsRange = (distance == value)
					end
					if meetsRange then
						return true
					end
				end
			end
		end

		warn('Failed label ' .. label .. ', trying again.')
		xeno.gotoLabel(label)
		return false
	end

	local function walkerGetNeededTools()
		local tools = {pick=false, shovel=false, rope=false}
		local needsTools = false
		local waypoints = _settings['Walker']['WaypointList']
		for i = 1, #waypoints do
			if not tools.rope and waypoints[i].tag == '3' then
				tools.rope = true
				needsTools = true
			elseif not tools.shovel and waypoints[i].tag == '4' then
				tools.shovel = true
				needsTools = true
			elseif not tools.pick and waypoints[i].tag == '255' and waypoints[i].tag == '255' and split(waypoints[i].text, '|')[1] == 'pick' then
				tools.pick = true
				needsTools = true
			end
		end
		return needsTools and tools or false
	end

	local function walkerReachNPC(name, callback, tries)
		tries = tries ~= nil and tries or 5
		local index = nil
		-- Loop through battle list
		for i = 1, 1300 do
			local creaturePos = xeno.getCreaturePosition(i)
			local distance = getDistanceBetween(xeno.getSelfPosition(), creaturePos)
			-- NPC we are looking for
			if string.lower(xeno.getCreatureName(i)) == string.lower(name) and distance < 7 then
				-- We need to walk to it
				if distance > 2 then
					index = i
					xeno.doSelfWalkTo(creaturePos.x, creaturePos.y, creaturePos.z)
				-- We are close enough
				else
					callback()
					return
				end
				break
			end
		end
		setTimeout(function()
			-- In range, finish with callback
			if getDistanceBetween(xeno.getSelfPosition(), xeno.getCreaturePosition(index)) <= 2 then
				callback()
			elseif tries <= 0 then
				error('Unable to reach ' .. name .. '. Please contact support.')
			else
				walkerReachNPC(name, callback, tries - 1)
			end
		end, pingDelay(DELAY.FOLLOW_WAIT))
	end

	local function walkerGotoTown(targetTown, callback)
		local townPositions = sortPositionsByDistance(xeno.getSelfPosition(), TOWN_POSITIONS)
		local town = townPositions[1].name

		-- In town, return success
		if (string.lower(town) == string.lower(targetTown)) then
			callback()
			return
		end

		-- Out of town, detect travel costs
		local travelInfo = TRAVEL_ROUTES[string.lower(town) .. '~' .. string.lower(targetTown)]

		-- Travel path doesn't exist, prompt user to walk manually
		if not travelInfo then
			local function travelPrompt()
				prompt('Unable to travel to ' .. _script.town .. '. When you are in town type "retry" to continue.', function(response)
					if string.find(response, 'retry') then
						walkerGotoTown(targetTown, callback)
					else
						travelPrompt()
					end
				end)
			end
			travelPrompt()
			return
		end

		local travelCost = travelInfo.cost
		local travelMethod = travelInfo.route or 'boat'

		-- When we have travel money
		local function gotoBoat(startLocation)
			-- Walk to boat
			-- Wait for us to get to the boat
			walkerStartPath(town, startLocation, travelMethod, function(path)
				-- Loop through all spectators on screen
				local spectators = {xeno.getCreatureSpectators(0)}
				-- Break when/if we find an npc with a transcript
				for _, listIndex in ipairs(spectators) do
					local name = xeno.getCreatureName(listIndex)
					local transcript = travelInfo.transcript[name]
					-- Found transcript
					if transcript then
						-- Follow NPC
						walkerReachNPC(name, function()
							-- Start talking
							talk(transcript, function()
								-- TODO: compare position to see if we moved
								-- We're in the correct town now
								callback()
							end)
						end)
						break
					end
				end
			end)
		end

		-- Find out where we are in town
		local closestLabel = walkerGetClosestLabel(false, town)
		local closestRoute = split(closestLabel.name, '|')
		local closestPath = split(closestRoute[2], '~')
		local location = closestPath[1]
		local destination = closestPath[2]

		-- Tell the user what we're doing
		log('You are near the ' .. town:lower() .. ' ' .. location .. ', traveling to ' .. targetTown .. '.')

		-- Needs gold to travel, go to bank from here
		local travelCostDifference = travelCost - getMoney()
		if travelCostDifference > 0 then
			-- Tell the user we need to go to the bank
			local bankMessage = 'Traveling to ' .. targetTown .. ' requires an additional ' .. travelCostDifference .. ' gold.'
			if location ~= 'bank' then
				bankMessage = bankMessage .. ' Heading to the ' .. town .. ' bank.'    
			end
			log(bankMessage)

			-- Go to local bank
			-- Wait for us to get to the bank
			walkerStartPath(town, location, 'bank', function()
				-- Withdraw travel funds (round up to nearest hundred)
				local roundedCost = math.ceil(travelCostDifference / 100) * 100
				bankWithdrawGold(roundedCost, function()
					gotoBoat('bank')
				end)
			end)
			return
		end

		-- Has travel money, head to boat
		-- Go to travel label once at boat
		-- If no path from here to boat / bank, go to depot first
		gotoBoat(location)
	end

	local function walkerGotoLocation(town, destination, callback)
		-- Make sure we're in the right town
		walkerGotoTown(town, function()
			-- Find out where we are
			local closestLabel = walkerGetClosestLabel(false, string.lower(town))
			local closestRoute = split(closestLabel.name, '|')
			local closestPath = split(closestRoute[2], '~')
			local location = closestPath[1]
			-- Walk to path
			walkerStartPath(town, location, destination, function(path)
				callback(path)
			end)
		end)
	end

	local function walkerGotoDepot(callback)
		-- Go to the first town depot
		xeno.gotoLabel('depot|' .. _script.town .. '|1')
		-- Tell if-stuck monitor to try next depot if we get stuck
		_script.findingDepot = 1
		xeno.setWalkerEnabled(true)
		when(EVENT_DEPOT_END, nil, function()
			-- Do not try anymore depots if-stuck
			_script.findingDepot = nil
			callback()
		end)
	end

	local function walkerGetDoorDetails(doorID)
		-- Cached details
		if _script.doors[doorID] then
			return _script.doors[doorID]
		end

		-- Determine door details
		-- get position of the stand before the label
		local doorPos = nil
		local posLabel = nil
		local direction = nil
		local startLabel = 'door|'..doorID..'|START'
		local standPos = walkerGetPosAfterLabel(startLabel)
		local directions = {['NORTH']=NORTH, ['SOUTH']=SOUTH, ['EAST']=EAST, ['WEST']=WEST}
		for dirName, dirCode in pairs(directions) do
			-- Look for the corresponding door label
			posLabel = 'door|'..doorID..'|'..dirName
			if walkerLabelExists(posLabel) then
				-- Determine position of the door
				doorPos = getPositionFromDirection(standPos, dirCode, 1)
				direction = dirCode
				break
			end
		end

		if not doorPos then
			return error('Missing door position for Door #' .. doorID ..'. Please contact support.')
		end

		_script.doors[doorID] = {
			doorPos = doorPos,
			standPos = standPos,
			posLabel = posLabel,
			startLabel = startLabel,
			direction = direction
		}

		return _script.doors[doorID]
	end

	local function walkerUseTrainer()
		local skill = _config['Logout']['Train-Skill']
		local statues = {
			sword = 16198,
			axe = 16199,
			club = 16200,
			spear = 16201,
			magic = 16202
		}

		local itemid = statues[skill]

		-- Skill statue does not exist
		if not itemid then
			error('Invalid skill type, valid options: sword, axe, club, spear, magic.')
			return
		end

		-- Find statue on map
		local pos = xeno.getSelfPosition()
		for x = -7, 7 do
			for y = -7, 7 do
				local posX = pos.x + x
				local posY = pos.y + y
				if xeno.getTileUseID(posX, posY, pos.z).id == itemid then
					xeno.selfUseItemFromGround(posX, posY, pos.z)
					return
				end
			end
		end

		error('Unable to locate the "'.. skill ..'" training statue.')
	end

	local function walkerCapacityDrop()
		if not _config['Capacity'] then
			return
		end
		local flaskDropCap = _config['Capacity']['Drop-Flasks']
		local goldDropCap = _config['Capacity']['Drop-Gold']
		if (goldDropCap and goldDropCap > 0) or (flaskDropCap and flaskDropCap > 0) then
			local cap = xeno.getSelfCap()
			local pos = xeno.getSelfPosition()
			-- Check if we need to drop flasks
			if flaskDropCap and flaskDropCap > 0 and cap <= flaskDropCap then
				local flasks = ITEM_LIST_FLASKS
				-- Potion Backpack
				for spot = 0, xeno.getContainerItemCount(_backpacks['Potions']) - 1 do
					local item = xeno.getContainerSpotData(_backpacks['Potions'], spot)
					-- Item is a flask
					if flasks[item.id] then
						-- Drop this stack of flasks
						xeno.containerMoveItemToGround(_backpacks['Potions'], spot, pos.x, pos.y, pos.z, -1)
						setTimeout(function()
							walkerCapacityDrop()
						end, pingDelay(DELAY.CONTAINER_MOVE_ITEM))
						return
					end
				end
				-- Main Backpack (if different than Potion)
				if _backpacks['Potions'] ~= _backpacks['Main'] then
					for spot = 0, xeno.getContainerItemCount(_backpacks['Main']) - 1 do
						local item = xeno.getContainerSpotData(_backpacks['Main'], spot)
						-- Item is a flask
						if flasks[item.id] then
							-- Drop this stack of flasks
							xeno.containerMoveItemToGround(_backpacks['Main'], spot, pos.x, pos.y, pos.z, -1)
							setTimeout(function()
								walkerCapacityDrop()
							end, pingDelay(DELAY.CONTAINER_MOVE_ITEM))
							return
						end
					end
				end
			end

			-- Check if we need to drop gold
			if goldDropCap and goldDropCap > 0 and cap <= goldDropCap then
				for spot = 0, xeno.getContainerItemCount(_backpacks['Gold']) - 1 do
					local item = xeno.getContainerSpotData(_backpacks['Gold'], spot)
					-- Item is gold
					if item.id == 3031 then
						-- Drop this stack of gold
						xeno.containerMoveItemToGround(_backpacks['Gold'], spot, pos.x, pos.y, pos.z, -1)
						setTimeout(function()
							walkerCapacityDrop()
						end, pingDelay(DELAY.CONTAINER_MOVE_ITEM))
						return
					end
				end
				-- Main Backpack (if different than Gold)
				if _backpacks['Gold'] ~= _backpacks['Main'] then
					for spot = 0, xeno.getContainerItemCount(_backpacks['Main']) - 1 do
						local item = xeno.getContainerSpotData(_backpacks['Main'], spot)
						-- Item is gold
						if item.id == 3031 then
							-- Drop this stack of gold
							xeno.containerMoveItemToGround(_backpacks['Main'], spot, pos.x, pos.y, pos.z, -1)
							setTimeout(function()
								walkerCapacityDrop()
							end, pingDelay(DELAY.CONTAINER_MOVE_ITEM))
							return
						end
					end
				end
			end
		end
	end

	local function walkerRestoreMana(potionid, manaRestorePercent, callback)
		local selfid = xeno.getSelfID()
		local function pump()
			-- Stop if creature onscreen
			local pos = xeno.getSelfPosition()
			for i = CREATURES_LOW, CREATURES_HIGH do
				local cpos = xeno.getCreaturePosition(i)
				if cpos and pos.z == cpos.z and getDistanceBetween(pos, cpos) <= 7 then
					if xeno.getCreatureVisible(i) and xeno.getCreatureHealthPercent(i) > 0 and xeno.isCreatureMonster(i) then
						callback()
						return
					end
				end
			end
			-- Stop if we're above threshold
			if math.abs((xeno.getSelfMana() / xeno.getSelfMaxMana()) * 100) >= manaRestorePercent then
				callback()
				return
			end
			-- Use potion
			xeno.selfUseItemWithCreature(potionid, selfid)
			-- Recurse
			setTimeout(function()
				pump()
			end, 100)
		end
		pump()
	end

	-- Export global functions
	return {
		walkerLabelExists = walkerLabelExists,
		walkerGetTownExit = walkerGetTownExit,
		walkerGetTownEntrance = walkerGetTownEntrance,
		walkerStartPath = walkerStartPath,
		walkerGetPosAfterLabel = walkerGetPosAfterLabel,
		walkerGetClosestLabel = walkerGetClosestLabel,
		walkerGetNeededTools = walkerGetNeededTools,
		walkerReachNPC = walkerReachNPC,
		walkerGotoLocation = walkerGotoLocation,
		walkerGotoDepot = walkerGotoDepot,
		walkerGetDoorDetails = walkerGetDoorDetails,
		walkerUseTrainer = walkerUseTrainer,
		walkerCapacityDrop = walkerCapacityDrop,
		walkerRestoreMana = walkerRestoreMana
	}
end)()
