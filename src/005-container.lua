Container = (function()
	
	-- Imports
	local pingDelay = Core.pingDelay
	local clearTimeout = Core.clearTimeout
	local clearWhen = Core.clearWhen
	local setTimeout = Core.setTimeout
	local setInterval = Core.setInterval
	local when = Core.when
	local log = Console.log
	local prompt = Console.prompt

	local function getLastContainer()
		local last = 0
		for i = 0, 16 do
			if xeno.getContainerOpen(i) then
				last = i
			end
		end
		return last
	end

	local function getContainerByName(name)
		for i = 0, 16 do
			if xeno.getContainerName(i) == name and xeno.getContainerOpen(i) then
				return i
			end
		end
		return false
	end

	local function compareContainers(a, b)
		-- Different item count, return false
		local itemcount = xeno.getContainerItemCount(a)
		local compcount = xeno.getContainerItemCount(b)
		if itemcount ~= compcount then
			return false
		end
		-- Different name, return false
		if xeno.getContainerName(a) ~= xeno.getContainerName(b) then
			return false
		end
		-- Different slot data, return false
		for spot = 0, itemcount do
			local item = xeno.getContainerSpotData(a, spot)
			local compitem = xeno.getContainerSpotData(b, spot)
			if item.id ~= compitem.id or item.count ~= compitem.count then
				return false
			end
		end
		-- Containers are similar (shallow comparison)
		return true
	end

	local function fixContainerDepth(container, spot, depth, callback)
		local item = xeno.getContainerSpotData(container, spot)
		-- Cascade backpack, last slot of backpack
		if xeno.isItemContainer(item.id) then 
			xeno.containerUseItem(container, spot, true)
		end
		-- Wait for the container to open
		setTimeout(function()
			callback()
		end, pingDelay(DELAY.CONTAINER_USE_ITEM))
	end

	local function resetContainerDepths(source, destination, sDepth, dDepth, callback)
		-- DEBUG: print(source .. ', ' .. destination .. ', ' .. sDepth .. ', ' .. dDepth)
		
		-- Main backpack containers
		local mainItemCount = xeno.getContainerItemCount(0)
		local backpacks = {}
		for spot = 0, mainItemCount - 1 do
			local item = xeno.getContainerSpotData(0, spot)
			if xeno.isItemContainer(item.id) then
				backpacks[#backpacks+1] = spot
			end
		end

		-- Fail-safe for source containers
		-- checks if container matches main backpack (contents, name, not id)
		local sourceBackpack = backpacks[source]
		if source ~= 0 and sourceBackpack and sDepth ~= -1 and compareContainers(0, source) then
			fixContainerDepth(source, sourceBackpack, sDepth, function()
				resetContainerDepths(source, destination, -1, dDepth, callback)
			end)
			return
		end

		-- Fail-safe for destination containers
		-- checks if container matches main backpack (contents, name, not id)
		local destBackpack = backpacks[destination]
		if destination ~= 0 and destBackpack and dDepth ~= -1 and compareContainers(0, destination) then
			fixContainerDepth(destination, destBackpack, dDepth, function()
				resetContainerDepths(source, destination, sDepth, -1, callback)
			end)
			return
		end

		-- Go back in source container
		if sDepth > 0 then
			xeno.containerBack(source)
			setTimeout(function()
				resetContainerDepths(source, destination, sDepth-1, dDepth, callback)
			end, pingDelay(DELAY.CONTAINER_BACK))

		-- Go back in destination container
		elseif dDepth > 0 then
			xeno.containerBack(destination)
			setTimeout(function()
				resetContainerDepths(source, destination, sDepth, dDepth-1, callback)
			end, pingDelay(DELAY.CONTAINER_BACK))

		-- Return
		elseif callback then
			callback()
		end
	end

	local function containerMoveItems(options, callback)
		local fromContainer = options.src
		local toContainer = options.dest
		local toSlot = options.slot or 0

		local whiteList = options.items
		local blackList = options.ignore
		local itemFilter = options.filter

		local disableSourceCascade = options.disableSourceCascade
		local openWindow = options.openwindow -- open first destination cascade in new window

		local spotOffset = 0
		local sourceDepth = 0
		local destDepth = 0

		local moveItem = nil
		local watchContainerFullError = nil
		local onContainerFull = nil
		local moveInterval = nil
		local fullEvent = nil

		local moveCounts = {}
		local lastMove = {
			itemid = nil,
			count = nil
		}

		-- Registers the error watcher
		watchContainerFullError = function()
			return when(EVENT_ERROR, ERROR_CONTAINER_FULL, onContainerFull)
		end

		-- Called to trigger a single item move
		moveItem = function(self)

			-- Amount of this stack to move (defaults to all)
			local moveStackCount = -1

			-- Remaining items
			local itemCount = xeno.getContainerItemCount(fromContainer)

			-- No items and cascade OR skipped all filled spots, stop entirely
			if itemCount == 0 or spotOffset >= itemCount then
				-- Kill moveInterval & fullEvent
				clearTimeout(self)
				clearWhen(EVENT_ERROR, fullEvent)
				-- Reset depths and finish
				resetContainerDepths(fromContainer, toContainer, sourceDepth, destDepth, function()
					callback(true)
				end)
				return
			end

			-- Das item
			local item = xeno.getContainerSpotData(fromContainer, spotOffset)

			-- Cascade backpack, last slot of backpack
			if xeno.isItemContainer(item.id) and (spotOffset + 1 >= itemCount) then 
				-- Cascade source enabled, open it, update source depth, reset spot offset
				if not disableSourceCascade then
					sourceDepth = sourceDepth + 1
					spotOffset = 0
					xeno.containerUseItem(fromContainer, itemCount-1, true)
				else
					spotOffset = spotOffset + 1
				end
				return
			end

			-- Item is in blacklist, try next spot
			if blackList and blackList[item.id] then
				spotOffset = spotOffset + 1
				return
			end

			-- Item not in filter list, try next spot
			if whiteList and not whiteList[item.id] then
				spotOffset = spotOffset + 1
				return
			end

			-- Item filter is set, run function to test validity
			if itemFilter and not itemFilter(item) then
				spotOffset = spotOffset + 1
				return
			end

			-- Item list, and entry has a number (count) value
			if whiteList and whiteList[item.id] and type(whiteList[item.id]) == 'number' then
				-- Check if we've moved any of this item yet
				if not moveCounts[item.id] then
					moveCounts[item.id] = whiteList[item.id]
				end

				-- We don't need anymore of this item, skip
				if moveCounts[item.id] <= 0 then
					spotOffset = spotOffset + 1
					return
				end

				-- Now we know how much to move, don't go over the needed (smallest value)
				moveStackCount = math.min(item.count, moveCounts[item.id])

				-- Decrease needed (we'll reverse this if we fail)
				moveCounts[item.id] = moveCounts[item.id] - moveStackCount
			end

			-- Track last move
			lastMove.itemid = item.id
			lastMove.count = moveStackCount
			-- Move item to destination
			xeno.containerMoveItemToContainer(fromContainer, spotOffset, toContainer, toSlot, moveStackCount)
		end

		-- Triggered when the destination fills up
		onContainerFull = function()
			-- Check if we need to reverse a needed count
			if whiteList and lastMove.itemid and lastMove.count > -1 and moveCounts[lastMove.itemid] then
				moveCounts[item.id] = moveCounts[item.id] + lastMove.count
			end

			-- Pause moving items
			-- No need to kill fullEvent, it dies after one use
			clearTimeout(moveInterval)

			setTimeout(function()
				-- We weren't depositing into a backpack, no cascade available
				if not xeno.isItemContainer(xeno.getContainerSpotData(toContainer, toSlot).id) then
					-- Reset depths and finish
					resetContainerDepths(fromContainer, toContainer, sourceDepth, destDepth, function()
						callback(false)
					end)
					return
				end
				-- Open destination container
				xeno.containerUseItem(toContainer, toSlot, not openWindow)
				setTimeout(function()
					-- Update toContainer index if we opened in a new window
					if openWindow then
						toContainer = getLastContainer()
						-- Reset destination depth, since we're in a new destination
						destDepth = 0
					end

					-- Check if last item is a container
					local lastSlot = xeno.getContainerItemCount(toContainer) - 1
					local cascadeID = xeno.getContainerSpotData(toContainer, lastSlot).id
					if xeno.isItemContainer(cascadeID) then
						-- Found cascade backpack, update slot, update destination depth
						openWindow = false
						destDepth = destDepth + 1
						toSlot = lastSlot

						-- Re-register events
						moveInterval = setInterval(moveItem, DELAY.CONTAINER_MOVE_ITEM)
						fullEvent = watchContainerFullError()
						return
					end
					-- No cascade backpack, stop entirely
					-- Reset depths and finish
					resetContainerDepths(fromContainer, toContainer, sourceDepth, destDepth, function()
						callback(false)
					end)
					return
				end, pingDelay(DELAY.CONTAINER_USE_ITEM))
			end, DELAY.CONTAINER_MOVE_ITEM)
		end

		-- Begin moving
		moveInterval = setInterval(moveItem, DELAY.CONTAINER_MOVE_ITEM)
		-- Start watching for container full errors
		fullEvent = watchContainerFullError()
	end

	local function moveItems(containers, options, callback)
		local source = table.remove(containers)
		containerMoveItems({
			src = source,
			dest = options.dest,
			slot = options.slot,
			items = options.items,
			disableSourceCascade = options.disableSourceCascade,
			openwindow = options.openwindow
		}, function(success)
			-- Last container, finish
			if #containers == 0 then 
				callback()
			-- Recurse
			else
				moveItems(containers, options, callback)
			end
		end)
	end

	local function openMainBackpack(callback)
		-- Open
		local opened = xeno.slotUseItem(3)

		-- Wait for Main Backpack
		setTimeout(function()
			-- Success
			if opened > 0 then
				if _config['General']['Minimize-Main-BP'] then
					xeno.minimizeContainer(0)
				end
				callback(opened)
			-- Fail, recurse
			else
				openMainBackpack(callback)
			end
		end, pingDelay(DELAY.USE_EQUIPMENT))
	end

	local function resetContainers(minimize, callback)
		-- Close all containers
		for i = 0, 15 do
			xeno.closeContainer(i)
		end

		openMainBackpack(function()
			local backpacks = {}
			local function openChild(index)
				local spot = backpacks[index]
				local freeslot = getLastContainer() + 1
				-- Open child backpack
				xeno.containerUseItem(0, spot)
				-- Wait for child to open
				setTimeout(function()
					-- Minimize backpack
					xeno.minimizeContainer(freeslot)
					-- Open next child
					if #backpacks > index then
						openChild(index+1)
					-- Complete, main callback
					else
						callback()
					end
				end, pingDelay(DELAY.CONTAINER_USE_ITEM))
			end

			-- Loop through all items, add containers to list
			local itemcount = xeno.getContainerItemCount(0)
			for spot = 0, itemcount - 1 do
				local item = xeno.getContainerSpotData(0, spot)
				if xeno.isItemContainer(item.id) then
					backpacks[#backpacks+1] = spot
				end
			end

			-- Call openChild for every backpack
			openChild(1)
		end)
	end

	local function setupContainers(callback)
		local needGoldContainer = false
		local needPotionContainer = false
		local needRuneContainer = false
		local needAmmoContainer = false
		local needSuppliesContainer = false

		log('Automatically setting up your backpacks. Please wait...')
		local backpackList = {}
		local function finishSetup()
			-- TODO: Display backpack order
			log('Done. Your backpacks have been setup.')
			callback()
		end

		-- Move items in main backpack to the correct backpacks
		local function organizeMainBackpack()
			local moveList = {}
			local moveBackpacks = {}
			local mainbp = _backpacks['Main']

			-- Populate the list of items to move to their respective backpacks
			for spot = 0, xeno.getContainerItemCount(mainbp) - 1 do
				local item = xeno.getContainerSpotData(mainbp, spot)
				local supply = _supplies[item.id]
				-- This item is a supply
				if supply then
					-- Backpack name of the supply group
					local backpackName = supply.group
					if backpackName == 'Amulet' or backpackName == 'Ring' then
						backpackName = 'Supplies'
					end
					-- The group has a dedicated container
					local backpack = _backpacks[backpackName]
					if backpack and backpack ~= mainbp then
						-- Create or update existing movelist for this backpack
						if not moveList[backpack] then
							moveList[backpack] = {}
							-- Add backpack to index for easy iteration
							moveBackpacks[#moveBackpacks+1] = backpack
						end
						-- Add item to movelist
						moveList[backpack][item.id] = true
					end
				end
			end

			local function moveItems(index)
				local destination = moveBackpacks[index]

				-- Check if destination exists (no items to move)
				if not destination then
					finishSetup()
					return
				end

				-- Move the all the items for this destination
				local itemList = moveList[destination]

				containerMoveItems({
					src = _backpacks['Main'],
					dest = destination,
					slot = 0,
					items = itemList,
					disableSourceCascade = true,
					openwindow = false
				}, function(success)
					-- Proceed to next destination
					moveItems(index+1)
				end)
			end

			-- Move items to proper backpack, then finish
			if #moveBackpacks > 0 then
				moveItems(1)
			-- None to move, finish up
			else
				finishSetup()
			end
		end

		-- Assign backpacks
		local function assignBackpacks()
			-- Setup containers (start at index 2 since Main = 0, Loot = 1)
			local index = 2

			if needGoldContainer then
				_backpacks['Gold'] = index
				backpackList[#backpackList+1] = 'gold'
				index = index + 1
			else
				_backpacks['Gold'] = 0
			end

			if needPotionContainer then
				_backpacks['Potions'] = index
				backpackList[#backpackList+1] = 'potions'
				index = index + 1
			else
				_backpacks['Potions'] = 0
			end

			if needRuneContainer then
				_backpacks['Runes'] = index
				backpackList[#backpackList+1] = 'runes'
				index = index + 1
			else
				_backpacks['Runes'] = 0
			end

			if needAmmoContainer then
				_backpacks['Ammo'] = index
				backpackList[#backpackList+1] = 'ammo'
				index = index + 1
			else
				_backpacks['Ammo'] = 0
			end

			if needSuppliesContainer then
				_backpacks['Supplies'] = index
				backpackList[#backpackList+1] = 'supplies'
				index = index + 1
			else
				_backpacks['Supplies'] = 0
			end

			organizeMainBackpack()
		end

		-- Open main bp and children
		resetContainers(true, function()
			-- Count how many are open (excluding main bp)
			-- Determine how many we need
			-- If we have enough, continue
			-- If not, prompt user, wait for response, recheck

			-- Loop through supplies, flag each "type" of container we will need
			local neededContainers = 0
			local runeCount = 0
			local potionCount = 0
			local ammoCount = 0
			local supplyCount = 0

			if _config['Loot']['Loot-Gold'] then
			   neededContainers = neededContainers + 1
			   needGoldContainer = true 
			end

			for supplyId, supply in pairs(_supplies) do
				if supply.group == 'Potions' and not needPotionContainer then
					potionCount = potionCount + supply.max
					if potionCount > 100 then
						neededContainers = neededContainers + 1
						needPotionContainer = true
					end
				elseif supply.group == 'Runes' and not needRuneContainer then
					runeCount = runeCount + supply.max
					if runeCount > 100 then
						neededContainers = neededContainers + 1
						needRuneContainer = true
					end
				elseif supply.group == 'Ammo' and not needAmmoContainer then
					ammoCount = ammoCount + supply.max
					if ammoCount > 100 then
						neededContainers = neededContainers + 1
						needAmmoContainer = true
					end
				elseif (supply.group == 'Ring' or supply.group == 'Amulet') and not needSuppliesContainer then
					supplyCount = supplyCount + supply.max
					if supplyCount > 5 then
						neededContainers = neededContainers + 1
						needSuppliesContainer = true
					end
				end
			end

			-- Backpacks inside main bp we can use (ignore mainbp and loot bp)
			local availableContainers = getLastContainer() - 1

			-- Make sure we have enough, if not prompt, then retry
			if availableContainers < neededContainers then
				-- prompt user, then assignBackpacks
				local missingCount = (neededContainers - availableContainers)
				local singularMsg = 'Not enough backpacks. Add one more backpack to your main backpack. Type "retry" to continue.'
				local pluralMsg = 'Not enough backpacks. Add ' .. missingCount .. ' more backpacks to your main backpack. Type "retry" to continue.'
				local message = missingCount > 1 and pluralMsg or singularMsg
				local function promptBackpacks()
					prompt(message, function(response)
						if string.find(string.lower(response), 'retry') then
							setupContainers(callback)
						else
							promptBackpacks()
						end
					end)
				end
				promptBackpacks()
				return
			end

			-- All is well, start setup
			assignBackpacks()
		end)
	end

	local function getContainerItemCounts(index, callback, deep, start, depth)
		-- Log incase this function takes awhile
		if depth and not _depths[depth] then
			log('Determining the depth of your ' .. depth .. ' backpack. Please wait...')
		end

		local items = nil
		local function countLevel(level)
			-- Iterate through container spots
			for spot = 0, xeno.getContainerItemCount(index) - 1 do
				local item = xeno.getContainerSpotData(index, spot)
				-- Create table and entries on-demand
				if not items then
					items = {}
				end
				if not items[item.id] then
					items[item.id] = 0
				end
				-- Increment count
				items[item.id] = items[item.id] + math.max(item.count, 1)
			end
			-- Only counting the current container level OR reached top level
			if not deep or level <= 1 then
				callback(items)
			else
				-- Go back one level
				xeno.containerBack(index)
				-- Count new level
				setTimeout(function()
					countLevel(level-1)
				end, pingDelay(DELAY.CONTAINER_BACK))
			end
		end
		local function gotoBottom(level, func)
			local lastSlot = xeno.getContainerItemCount(index) - 1
			local cascadeID = xeno.getContainerSpotData(index, lastSlot).id
			-- Another cascade, go deeper
			if xeno.isItemContainer(cascadeID) then
				xeno.containerUseItem(index, lastSlot, true)
				setTimeout(function()
					gotoBottom(level+1, func)
				end, pingDelay(DELAY.CONTAINER_USE_ITEM))
				return
			end
			-- No entry for this depth yet, record the depth we just saw
			if not _depths[depth] then
				_depths[depth] = level
				-- Log the depth we found
				log('Done. Your ' .. depth .. ' backpack is ' .. level .. ' level' .. (level > 1 and 's' or '') .. ' deep.')
			end
			-- At the last level, start counting items
			countLevel(_depths[depth])
		end
		-- Deep count specified, start at last level
		if deep then
			gotoBottom(start or 1)
		-- Start at the current level
		else
			countLevel(start or 1)
		end
	end

	local function cleanContainers()
		-- Check all backpacks except for loot
		-- for items you get from skinning
		-- and move them to the loot backpack
		local containers = {}
		for i = 0, 15 do
			if i ~= _backpacks['Loot'] and xeno.getContainerOpen(i) then
				containers[#containers+1] = i
			end
		end
		moveItems(containers, {
			dest = _backpacks['Loot'],
			slot = 0,
			items = {
				[281] = true,
				[282] = true,
				[3026] = true,
				[3029] = true,
				[3032] = true,
				[5876] = true,
				[5877] = true,
				[5878] = true,
				[5893] = true,
				[5905] = true,
				[5906] = true,
				[5925] = true,
				[5948] = true,
				[9303] = true
			},
			disableSourceCascade = true,
			openwindow = false
		}, function(success)
			-- TODO: nothing needs a callback for this yet?
		end)
	end

	local function unrustLoot(callback)
		-- Make sure a corpse is not currently open
		-- Loop through each slot in the loot container
		-- If loot is a "rusty" item, use oil on it.
		-- Wait x delay and look at the same slot.
		-- If loot is shitty, toss it out. (offset slot in loop)
		-- If loot is good, continue (add to supplies)
		-- Remove rusty armor from supplies (HUD)
		-- Add oil as supply waste (HUD)
	end

	-- Export global functions
	return {
		getLastContainer = getLastContainer,
		getContainerByName = getContainerByName,
		containerMoveItems = containerMoveItems,
		setupContainers = setupContainers,
		getContainerItemCounts = getContainerItemCounts,
		cleanContainers = cleanContainers
	}
end)()
