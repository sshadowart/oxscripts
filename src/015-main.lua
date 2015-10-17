--local global = _G
--local env = {}
--setfenv(1, env)

local function init()
	-- Made in Texas with love <3
	xeno.HUDCreateText(65, 33, 'X E N O B O T', 0, 0, 0)
	xeno.HUDCreateText(66, 32, 'X E N O B O T', 255, 255, 255)

	-- Imports
	local loadConfigFile = Ini.loadConfigFile
	local hudInit = Hud.hudInit
	local openConsole = Console.openConsole
	local log = Console.log
	local setupContainers = Container.setupContainers
	local walkerGetTownExit = Walker.walkerGetTownExit
	local walkerGetTownEntrance = Walker.walkerGetTownEntrance
	local loadSettingsFile = Settings.loadSettingsFile
	local setDynamicSettings = Settings.setDynamicSettings
	local resupply = Supply.resupply

	-- Load config.ini
	loadConfigFile(function()
		-- Grab screen dimensions
		if _config['HUD']['Enabled'] then
			hudInit()
		end
		-- Create channel
		openConsole()
		-- Only continue after containers are setup
		setupContainers(function()
			-- Load XBST
			loadSettingsFile(function()
				-- Modify XBST
				setDynamicSettings(function()
					-- Detect town exit
					walkerGetTownExit()
					walkerGetTownEntrance()
					-- Resupply what we need
					resupply()
				end)
			end)
		end)
	end)
end

init()