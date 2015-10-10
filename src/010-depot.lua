Depot = (function()
	
	-- Imports
	local pingDelay = Core.pingDelay
	local setTimeout = Core.setTimeout
	local getWalkableTiles = Core.getWalkableTiles
	local getDirectionTo = Core.getDirectionTo
	local getSelfLookPosition = Core.getSelfLookPosition
	local getPositionFromDirection = Core.getPositionFromDirection
	local warn = Console.warn
	local error = Console.error
	local getLastContainer = Container.getLastContainer
	local getContainerByName = Container.getContainerByName
	local containerMoveItems = Container.containerMoveItems
	local walkerGotoDepot = Walker.walkerGotoDepot

	local function openLocker(callback)
		-- Immediately callback if Locker is already open
		local locker = getContainerByName(CONT_NAME_LOCKER)
		if locker then
			callback(locker)
			return
		end

		-- Depot position (defaults to look pos)
		local depot = getSelfLookPosition(1)

		-- Detect entry, find depot tile from opposite direction
		local pos = xeno.getSelfPosition()
		local tiles = getWalkableTiles(pos, 1)
		if tiles and tiles[1] then
			local entryPos = tiles[1]
			depot = getPositionFromDirection({x=pos.x, y=pos.y}, getDirectionTo(entryPos, pos), 1)
		end
		-- Browse locker field
		xeno.selfBrowseField(depot.x, depot.y, pos.z)
		-- Wait for Browsefield window
		setTimeout(function()
			-- Browsefield window
			local browsefield = getLastContainer()
			-- Open Locker in same window (first slot)
			xeno.containerUseItem(browsefield, 0, true)
			-- Wait for Locker window
			setTimeout(function()
				-- Callback with container list index
				locker = getContainerByName(CONT_NAME_LOCKER)
				callback(locker)
			end, pingDelay(DELAY.CONTAINER_USE_ITEM))
		end, pingDelay(DELAY.BROWSE_FIELD))
	end

	local function openDepot(callback)
		-- Immediately callback if Depot is already open
		local depot = getContainerByName(CONT_NAME_DEPOT)
		if depot then
			callback(depot)
			return
		end

		-- Open Locker first
		openLocker(function(locker)
			-- Unable to open locker
			if not locker then
				callback(false)
				return
			end

			-- Open Depot in same window (first slot)
			xeno.containerUseItem(locker, 0, true)
			-- Wait for Depot window
			setTimeout(function()
				-- Callback with container list index
				depot = getContainerByName(CONT_NAME_DEPOT)
				callback(depot)
			end, pingDelay(DELAY.CONTAINER_USE_ITEM))
		end)
	end

	local function transferToDepot(depot, slot, callback)
		containerMoveItems({
			src = _backpacks['Loot'],
			dest = depot,
			slot = slot,
			openwindow = false,
			ignore = {
				[ITEMID.OBSIDIAN_KNIFE] = true,
				[ITEMID.BLESSED_STAKE] = true,
			},
			filter = function(item)
				if slot == DEPOT.SLOT_STACK and xeno.isItemStackable(item.id) then
					return true
				elseif slot == DEPOT.SLOT_NONSTACK and not xeno.isItemStackable(item.id) then
					return true
				end
				return false
			end
		}, function(success)
			-- Warn player not all their loot was moved
			if not success then
				warn('Some loot was unable to be deposited.')
			end
			-- Return
			callback()
		end)
	end

	local function transferFromDepot(depot, neededSupplies, callback)
		-- Detect items we need to withdraw, and backpacks to withdraw to
		local groups = {}
		local groupIndex = {}
		local mainBP = _backpacks['Main']
		local potionsBP = _backpacks['Potions']
		local runesBP = _backpacks['Runes']
		local ammoBP = _backpacks['Ammo']
		local suppliesBP = _backpacks['Supplies']

		for itemid, supply in pairs(neededSupplies) do
			if supply.group == 'Food' then
				if not groups[mainBP] then groups[mainBP] = {} end
				groups[mainBP][itemid] = supply.needed
			elseif supply.group == 'Potions' then
				if not groups[potionsBP] then groups[potionsBP] = {} end
				groups[potionsBP][itemid] = supply.needed
			elseif supply.group == 'Runes' then
				if not groups[runesBP] then groups[runesBP] = {} end
				groups[runesBP][itemid] = supply.needed
			elseif supply.group == 'Ammo' then
				if not groups[ammoBP] then groups[ammoBP] = {} end
				groups[ammoBP][itemid] = supply.needed
			elseif supply.group == 'Ring' or supply.group == 'Amulet' or supply.group == 'Supplies' then
				if not groups[suppliesBP] then groups[suppliesBP] = {} end
				groups[suppliesBP][itemid] = supply.needed
			end
		end

		-- Turn associate list into something we can iterate easily
		for bp, _ in pairs(groups) do
			groupIndex[#groupIndex+1] = bp
		end

		-- Move each group
		local function transferGroup(index)
			-- Lookup group backpack
			local backpack = groupIndex[index]
			-- No more groups, finished
			if not backpack then
				return callback()
			end
			-- Look group items
			local items = groups[backpack]
			-- Move group
			containerMoveItems({
				src = depot,
				dest = backpack,
				openwindow = false,
				items = items,
			}, function(success)
				-- Warn player not all their loot was moved
				if not success then
					warn('Some loot was unable to be deposited.')
				end
				-- Next group, after short delay
				setTimeout(function()
					transferGroup(index+1)
				end, pingDelay(DELAY.CONTAINER_MOVE_ITEM))
			end)
		end

		-- Open supply slot in depot
		xeno.containerUseItem(depot, DEPOT.SLOT_SUPPLY, true)
		setTimeout(function()
			-- Start transfer
			transferGroup(1)
		end, pingDelay(DELAY.CONTAINER_MOVE_ITEM))
	end

	local function startDepotTransfer(needDeposit, neededSupplies, callback)
		-- Walk to nearest depot
		walkerGotoDepot(function()
			-- Open Depot
			openDepot(function(depot)
				-- Depot not opened, keep looking
				if not depot then
					startDepotTransfer(needDeposit, neededSupplies, callback)
					return
				end

				-- Set depot state
				_script.depotOpen = true

				-- Check slots
				for spot = 0, 2 do
					local item = xeno.getContainerSpotData(depot, spot)
					if not item or not xeno.isItemContainer(item.id) then
						error('The first 3 depot slots must be containers. [non stackables, stackables, supplies]')
						return 
					end
				end

				-- We need to deposit
				if needDeposit then
					-- Deposit stackables
					transferToDepot(depot, DEPOT.SLOT_STACK, function()
						-- Delay
						setTimeout(function()
							-- Deposit non-stackables
							transferToDepot(depot, DEPOT.SLOT_NONSTACK, function()
								-- We need to withdraw, delay and withdraw
								if neededSupplies then
									setTimeout(function()
										-- Withdraw supplies
										transferFromDepot(depot, neededSupplies, function()
											-- Set depot state
											_script.depotOpen = false
											callback()
										end)
									end, DELAY.CONTAINER_MOVE_ITEM)
								-- Nothing left
								else
									-- Set depot state
									_script.depotOpen = false
									callback()
								end
							end)
						end, DELAY.CONTAINER_MOVE_ITEM)
					end)
				-- Only withdraw
				elseif neededSupplies then
					-- Withdraw supplies
					transferFromDepot(depot, neededSupplies, function()
						-- Set depot state
						_script.depotOpen = false
						callback()
					end)
				-- Nothing?
				else
					-- Set depot state
					_script.depotOpen = false
					callback()
				end
			end)
		end)
	end

	-- Export global functions
	return {
		startDepotTransfer = startDepotTransfer
	}
end)()
