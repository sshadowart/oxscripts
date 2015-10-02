Targeter = (function()
	
	-- Imports
	local clearTimeout = Core.clearTimeout
	local setInterval = Core.setInterval
	
	local function targetingGetCreatureThreshold(list, range, amount, multifloor)
		local targets = {}
		local count = 0
		local pos = xeno.getSelfPosition()
		for i = CREATURES_LOW, CREATURES_HIGH do
			local name = xeno.getCreatureName(i)
			-- Is this creature invited to die?
			if list[string.lower(name)] then
				-- Position & Distance
				local cpos = xeno.getCreaturePosition(i)
				local distance = xeno.getDistanceBetween(pos, cpos)
				if (pos.z == cpos.z or multifloor) and distance <= range then
					-- Normal creature checks
					if xeno.getCreatureVisible(i) and xeno.getCreatureHealthPercent(i) > 0 and xeno.isCreatureMonster(i) then
						targets[#targets+1] = xeno.getCreatureIDFromIndex(i)
						count = count + 1
					end
				end
			end
		end
		return {count >= amount, targets}
	end

	local function targetingInitDynamicLure()
		-- Clear previously running dynamic lure
		if _script.dynamicLureInterval then
			clearTimeout(_script.dynamicLureInterval)
		end

		if _config['Lure']['Creatures'] and _config['Lure']['Amount'] and _config['Lure']['Amount'] > 0 then
			-- Targets of each lure,
			-- do not allow luring until targets are dead or time has elapsed
			local targets = {}
			_script.dynamicLureInterval = setInterval(function()
				-- We're in normal ifstuck mode, not lure mode, do nothing.
				if _script.ignoring or (_script.stuck and not _script.dynamicLuring) then
					return
				end

				-- Ready to attack?
				local status = targetingGetCreatureThreshold(_config['Lure']['Creatures'], _config['Lure']['Range'], _config['Lure']['Amount'], true)
				local attackReady = status[1]
				local newTargets = status[2]

				-- Normal attack mode, look for victims
				if not _script.dynamicLuring then

					-- Append new targets to list with current time (if they are new)
					for _, newTargetCID in ipairs(newTargets) do
						if not targets[newTargetCID] then
							targets[newTargetCID] = os.time()
						end
					end

					-- Are we still under the deadline for at least the threshold
					local attackStillReady = false
					local pos = xeno.getSelfPosition()
					for targetCID, targetTime in pairs(targets) do
						local index = xeno.getCreatureListIndex(targetCID)
						local cpos = xeno.getCreaturePosition(index)
						if pos.z == cpos.z and xeno.getDistanceBetween(pos, cpos) <= 7 then
							if xeno.getCreatureHealthPercent(index) > 0 and os.time() - targetTime < _config['Lure']['Kill-Time'] then
								attackStillReady = true
								break
							end
						end
					end

					-- Still going strong, keep killing 'em
					if attackStillReady then
						return
					end

					-- No victims, start luring them, turn targeter OFF
					targets = {}
					_script.dynamicLuring = true
					xeno.setTargetingEnabled(false)
					return
				end

				-- We have enough victims, stop luring, turn targeter ON
				if attackReady then
					_script.dynamicLuring = false
					xeno.setTargetingEnabled(true)
				end
			end, 100)
		end
	end

	-- Export global functions
	return {
		targetingGetCreatureThreshold = targetingGetCreatureThreshold,
		targetingInitDynamicLure = targetingInitDynamicLure
	}
end)()
