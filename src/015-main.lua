--local global = _G
--local env = {}
--setfenv(1, env)

local function init()
    xeno.setWalkerEnabled(false)

    -- Made in Texas with love <3
    xeno.HUDCreateText(65, 33, 'X E N O B O T', 0, 0, 0)
    xeno.HUDCreateText(66, 32, 'X E N O B O T', 255, 255, 255)

    -- Imports
    local loadConfigFile = Ini.loadConfigFile
    local hudInit = Hud.hudInit
    local checkSoftBoots = Core.checkSoftBoots
    local isXenoBotBinary = Core.isXenoBotBinary
    local getXenoVersion = Core.getXenoVersion
    local openConsole = Console.openConsole
    local sortPositionsByDistance = Core.sortPositionsByDistance
    local log = Console.log
    local setupContainers = Container.setupContainers
    local walkerGetTownExit = Walker.walkerGetTownExit
    local walkerGetTownEntrance = Walker.walkerGetTownEntrance
    local loadSettingsFile = Settings.loadSettingsFile
    local setDynamicSettings = Settings.setDynamicSettings
    local resupply = Supply.resupply
    local walkerGetClosestLabel = Walker.walkerGetClosestLabel

    -- Only allow XenoBot Binary
    if not isXenoBotBinary() then
        print('You are using an older version of XenoBot. Update to XenoBot Binary to run this script.')
        return
    end

    -- Create channel
    openConsole()
        
    -- Load config.ini
    loadConfigFile(function()
        -- Grab screen dimensions
        if _config['HUD']['Enabled'] then
            hudInit()
        end
        -- Ready for events
        _script.ready = true
        -- Only continue after containers are setup
        setupContainers(function()
            -- Check EQ related stuff
            checkSoftBoots()

            -- Load XBST
            loadSettingsFile(function()
                -- Modify XBST
                setDynamicSettings(function()
                    -- Detect town exit
                    walkerGetTownExit()
                    walkerGetTownEntrance()

                    -- Check if we're in the spawn or in town
                    local position = xeno.getSelfPosition()
                    local townPositions = sortPositionsByDistance(xeno.getSelfPosition(), TOWN_POSITIONS)
                    local town = townPositions[1].name
                    local startLabel = walkerGetClosestLabel(true, town:lower())
                    local huntStart = false
                    if not startLabel or getDistanceBetween(position, startLabel) > 30 then
                        startLabel = walkerGetClosestLabel(false, 'huntstart')
                        huntStart = true
                        if not startLabel or getDistanceBetween(position, startLabel) > 30 then
                            error('Too far from any start point. Restart the script closer to a town.')
                            return
                        end
                    end

                    if huntStart then
                        xeno.gotoLabel(startLabel.name)
                    else
                        resupply()
                    end
                end)
            end)
        end)
    end)
end

init()
