Npc = (function()
	
	-- Imports
	local pingDelay = Core.pingDelay
	local setTimeout = Core.setTimeout
	local talk = Core.talk
	local checkSoftBoots = Core.checkSoftBoots
	local error = Console.error
	local getTotalItemCount = Container.getTotalItemCount
	local containerMoveItems = Container.containerMoveItems
	local getMoney = Container.getMoney
	local getFlasks = Container.getFlasks

	local function moveTransactionGoldChange(container, callback)
		-- Move loose gold change from container to gold backpack
		-- uses main bp if gold backpack isn't assigned.
		containerMoveItems({
			src = container,
			dest = _backpacks['Gold'] or _backpacks['Main'],
			items = {
				[3031] = true
			},
			disableSourceCascade = true,
			openwindow = false
		}, function(success)
			callback()
		end)
	end

	local function bankDepositGold(callback)
		-- Deposit everything (skip deposit if no money)
		talk(getMoney() <= 0 and {'hi'} or {'hi', 'deposit all', 'yes'}, function(responses)
			-- TODO: verify funds deposited
			callback()
		end)
	end

	local function bankGetBalance(callback, nodialog)
		local dialog = not nodialog and {'hi', 'balance'} or {'balance'}
		talk(dialog, function(responses)
			-- Search for balance in dialog
			if responses then
				for i = 1, #responses do
					local response = responses[i]
					if response then
						local balanceText = response:gsub(',', '')
						local balance = balanceText:match('account balance is (%d+) gold')
						if balance then
							_script.balance = tonumber(balance) or 0
							-- Callback
							callback()
							return true
						end
					end
				end
			end
			-- Failure callback
			callback(false)
		end)
	end

	local function bankWithdrawGold(amount, callback, nodialog)
		local dialog = not nodialog and {'hi', 'withdraw', amount, 'yes'} or {'withdraw', amount, 'yes'}
		local prevMoney = getMoney()
		local tries = 3
		local function interact()
			-- TODO: use npc proxy to verify withdraw
			setTimeout(function()
				if getMoney() > prevMoney then
					callback()
				else
					tries = tries - 1
					if tries <= 0 then
						error('Unable to withdraw ' .. amount .. ' gold. Make sure you have sufficient funds.')
					else
						talk(dialog, interact)
					end
				end
			end, pingDelay(DELAY.RANGE_TALK))
		end

		talk(dialog, interact)
	end

	local function shopSellableCount(itemid, includeEq)
		local countWithEq = xeno.shopGetItemSaleCountByID(itemid)
		if includeEq then
			return countWithEq
		end

		local slots = {"getHeadSlotData", "getArmorSlotData", "getLegsSlotData", "getFeetSlotData", "getAmuletSlotData", "getWeaponSlotData", 
					   "getRingSlotData", "getBackpackSlotData", "getShieldSlotData", "getAmmoSlotData"}

		local count = countWithEq
		for _, slot in ipairs(slots) do
			local itemInSlot = xeno[slot]()
			if itemInSlot.id == itemid then
				count = count - math.max(itemInSlot.count, 1)
			end
		end

		return count
	end

	local function shopSellItem(itemid, callback, neededCount, tries)
		tries = tries or 10

		-- Sell specific amount or "all"
		local remaining = neededCount or 100000

		local function sellItem()
			-- Item doesn't exist, ignore
			local amount = shopSellableCount(itemid)

			-- No more to sell
			if amount <= 0 then
				callback()
				return
			end

			-- Sell 100x at a time
			local neededStackCount = math.min(remaining, amount)

			-- Successfully sold the stack
			if xeno.shopSellItemByID(itemid, neededStackCount) > 0 then
				-- Reduce remaining by sold stack count, reset tries
				remaining = remaining - neededStackCount
				setTimeout(function()
					-- Remaining count to sell, recurse
					if remaining > 0 then
						sellItem()
					-- Sold all items, callback
					else
						callback()
					end
				end, pingDelay(DELAY.TRADE_TRANSACTION))
			-- Failed to sell, retrying
			elseif tries > 0 then
				shopSellItem(itemid, callback, neededCount, tries-1)
			-- Out of tries. Failed to sell stack.
			else
				error('Failed to sell ' .. xeno.getItemNameByID(itemid) .. ' (' .. neededStackCount .. 'x).')
			end
			return
		end
		-- Start recursive selling
		sellItem()
	end

	local function shopSellLoot(sellList, callback, nodialog)
		-- Add key, value array to flat list
		local itemlist = {}
		for itemid, _ in pairs(sellList) do
			itemlist[#itemlist+1] = itemid
		end
		local itemcount = #itemlist

		function sell(index)
			local itemid = itemlist[index]

			-- No more items, finish
			if not itemid then
				-- Move change to gold
				moveTransactionGoldChange(0, function()
					callback()
				end)
				return
			end

			local amount = shopSellableCount(itemid)

			if amount > 0 then
				shopSellItem(itemid, function()
					-- Recurse to next item in list
					setTimeout(function()
						sell(index + 1)
					end, pingDelay(DELAY.TRADE_TRANSACTION))
				end)
			else
				-- If we don't have the item, recurse without a wait.
				sell(index + 1)
			end
		end

		if nodialog then
			sell(1)
			return
		end

		talk({'hi', 'trade'}, function()
			-- Todo: use NPC proxy to verify trade window
			setTimeout(function()
				sell(1)
			end, pingDelay(DELAY.RANGE_TALK))
		end)
	end

	local function shopSellFlasks(callback)
		shopSellLoot(ITEM_LIST_FLASKS, callback, true)
	end

	local function shopRefillSoftboots(callback)
		local tries = 10
		function repair()
			talk({'repair', 'yes'}, function()
				-- Wait for this bitch to shine our boots
				setTimeout(function()
					-- Move change to gold
					moveTransactionGoldChange(0, function()
						-- No more boots, or failed too much
						if getTotalItemCount(ITEMID.SOFTBOOTS_WORN) <= 0 or tries <= 0 then
							-- Equip softboots if needed
							checkSoftBoots()
							callback()
						else
							tries = tries - 1
							repair()
						end
					end)
				end, pingDelay(DELAY.TRADE_TRANSACTION))
			end)
		end

		talk({'hi'}, function()
			repair()
		end)
	end

	local function shopBuyItemUpToCount(itemid, neededCount, destination, callback, tries)
		destination = destination or 0
		tries = tries or 10
		local remaining = neededCount

		local function buyItem()
			-- Item doesn't exist, ignore
			local price = xeno.shopGetItemBuyPriceByID(itemid)
			local neededStackCount = math.min(remaining, 100)

			-- Price not found
			if price <= 0 then
				callback()
				return
			end

			-- Successfully bought stack
			if xeno.shopBuyItemByID(itemid, neededStackCount) > 0 then
				-- Reduce remaining by bought stack count, reset tries
				remaining = remaining - neededStackCount
				-- TODO: possibly randomize this (move after x stacks bought)
				setTimeout(function()
					-- Only move if intended destination isn't main backpack
					if destination > 0 then
						-- Move to destination after buying stack
						containerMoveItems({
							src = _backpacks['Main'],
							dest = destination,
							items = {[itemid] = true},
							disableSourceCascade = true,
							openwindow = false
						}, function(success)
							-- Remaining count to buy, continue
							if remaining > 0 then
								buyItem()
							-- Bought all items, callback
							else
								callback()
							end
						end)
					else
						-- Remaining count to buy, continue
						if remaining > 0 then
							buyItem()
						-- Bought all items, callback
						else
							callback()
						end
					end
				end, pingDelay(DELAY.TRADE_TRANSACTION))
			-- Failed to buy, retrying
			elseif tries > 0 then
				shopBuyItemUpToCount(itemid, neededCount, destination, callback, tries-1)
			-- Out of tries. Failed to buy stack.
			else
				error('Failed to buy ' .. xeno.getItemNameByID(itemid) .. ' (' .. neededStackCount .. 'x). ' .. 'Make sure you have enough capacity and gold.')
			end
			return
		end
		-- Start recursive buying
		buyItem()
	end

	local function shopBuySupplies(group, callback)
		local items = {}
		local backpack = _backpacks[group] and _backpacks[group] or nil
		local function buyListItem(index)
			-- Reached end of list, callback
			if index > #items then
				callback()
				return
			end

			-- Lookup current item
			local item = items[index]

			-- Item doesn't exist or not needed
			if not item or not item.needed or item.needed < 1 then
				buyListItem(index + 1)
				return
			end

			-- Buy item
			shopBuyItemUpToCount(item.id, item.needed, backpack, function()
				buyListItem(index + 1)
			end)
		end

		-- Whether we need to greet npc
		local greetNPC = true

		-- Populate items
		for itemid, supply in pairs(_supplies) do
			-- Belongs to the correct group
			if supply.group == group then
				-- Minimum is expected to be checked and is below expected
				if supply.needed and supply.needed > 0 then
					items[#items+1] = supply
					-- Check if item is in trade window (if open)
					if xeno.shopGetItemBuyPriceByID(itemid) > 0 then
						greetNPC = false
					end
				end
			end
		end

		if greetNPC then
			talk({'hi'}, function()
				-- Try to sell flasks if we may be at the magic shop
				if group == 'Potions' then
					talk({'trade'}, function()
						shopSellFlasks(function()
							buyListItem(1)
						end)
					end)
				else
					talk({'trade'}, function()
						buyListItem(1)
					end)
				end
			end)
		else
			-- Try to sell flasks if we may be at the magic shop
			if group == 'Potions' then
				shopSellFlasks(function()
					buyListItem(1)
				end)
			else
				buyListItem(1)
			end
		end
	end

	-- Export global functions
	return {
		bankDepositGold = bankDepositGold,
		bankGetBalance = bankGetBalance,
		bankWithdrawGold = bankWithdrawGold,
		shopSellLoot = shopSellLoot,
		shopRefillSoftboots = shopRefillSoftboots,
		shopBuySupplies = shopBuySupplies
	}
end)()
