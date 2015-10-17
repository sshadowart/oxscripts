local _script = {
	start = os.time(),
	baseExp = xeno.getSelfExperience(),
	balance = 0,

	unsafeQueue = 0,

	pingSum = 0,
	pingEntries = 0,
	pingLast = 0,

	theme = 'light',

	name = "{{SCRIPT_NAME}}",
	town = "{{SCRIPT_TOWN}}",
	vocation = "{{SCRIPT_VOCATION}}",

	townexit = nil,
	channel = nil,
	historyChannel = nil,
	disableWithdraw = false,
	firstResupply = true,

	rope = nil,
	shovel = nil,
	pick = nil,

	ropeCode = 0,
	shovelCode = 0,

	state = 'Setting up backpacks',
	route = '--',
	inSpawn = false,
	stuck = false,
	luring = false,
	dynamicLuring = false,
	ignoring = false,

	logoutQueued = false,
	trainingQueued = false,
	returnQueued = false,
	forceLogoutQueued = false,

	alarmInterval = nil,

	wasted = 0,
	looted = 0,
	profit = 0,
	experience = 0,

	doors = {}
}

local _timerIndex = 0
local _eventIndex = 0
local _timers = {}              -- execute callbacks at a specific time
local _events = {               -- execute callbacks on events
	[EVENT_LABEL] = {},
	[EVENT_ERROR] = {},
	[EVENT_BATTLE] = {},
	[EVENT_LOOT] = {},
	[EVENT_NPC] = {},
	[EVENT_COMMAND] = {},
	[EVENT_PATH_END] = {},
	[EVENT_DEPOT_END] = {}
}

local _path = {                 -- current path we're taking
	town = nil,                 -- ex: thais
	route = nil,                -- ex: depot~hunt
	from = nil,                 -- ex: depot
	to = nil,                   -- ex: hunt
	dest = nil                  -- ex: startHunt
}

local _settings = {}
local _config = {}
local _supplies = {}
local _backpacks = {
	['Main'] = 0,
	['Loot'] = 1,
	-- remaining dynamically assigned...
}

local _hud = {
	index = {},
	gamewindow = {x=0, y=0, w=0, h=0},
	leftcolumn = {x=10, y=65, w=200, h=0, panels={}},
	rightcolumn = {x=0, y=10, w=200, h=0, panels={}},
	lootSnapshots = {},
	supplySnapshots = {}
}
