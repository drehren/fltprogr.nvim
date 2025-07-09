---@class fltprogr.broker
local M = {
	---@enum fltprogr.categories
	categories = {
		ANY = '*',
		LSP = 'lsp',
		WORK = 'work',
		BUFFER = 'buffer',
	},
}

---@class fltprogr.progress_event
---@field source fltprogr.source The source id
---@field category string The category this event was sent to
---@field title string Event title, is the same through the event
---@field progress number|true Event progress
---@field message? string Event current state
---@field cancel? function If exists, the progress event is cancellable
---@field [string] any

--- Callbacks required for progress display.
---@class fltprogr.display.set_callbacks
--- Called when a progress event starts.
---@field on_start fun(event: fltprogr.progress_event)
--- Called anytime a progress event gets updated.
---@field on_update fun(event: fltprogr.progress_event)
--- Called when a progress event end. It can still update some data.
---@field on_end fun(event: fltprogr.progress_event)

---@alias fltprogr.source number|string Source identifier
---@alias fltprogr.display number Display identifier
---@alias fltprogr.event number Event identifier

---@private
---@class fltprogr.event_states
---@field started table<integer, boolean>
---@field ended table<integer, boolean>

---@private
---@class fltprogr.srcdef
---@field category string
---@field event_state fltprogr.event_states

---@private
---@class fltprogr.catdef
---@field displays fltprogr.display[]
---@field validate? fun(data: fltprogr.source_progress)

local progr = {
	---@type table<integer|string, fltprogr.srcdef|false>
	sources = {},
	---@type (fltprogr.display.set_callbacks|false)[]
	displays = {},
	---@type table<fltprogr.categories|string, fltprogr.catdef>
	categories = {
		['*'] = { displays = {} },
		work = { displays = {} },
		lsp = {
			displays = {},
			validate = function(data)
				vim.validate('data.client_id', data.client_id, 'number')
			end,
		},
		buffer = {
			displays = {},
			validate = function(data)
				vim.validate('data.buffer', data.buffer, 'number')
			end,
		},
	},
	---@type fltprogr.progress_event[]
	events = {},
}

--- Adds an additional validator for the specified category
---@param category fltprogr.categories|string The category to add/create
---@param validate fun(data: fltprogr.source_progress) The validation function
function M.add_category_validator(category, validate)
	vim.validate('category', category, 'string')
	vim.validate('validate', validate, 'callable')
	if not progr.categories[category] then
		progr.categories[category] = {
			displays = {},
			validate = validate,
		}
		return
	end
	local catdef = progr.categories[category]
	local cur_validate = catdef.validate
	if cur_validate then
		catdef.validate = function(data)
			cur_validate(data)
			validate(data)
		end
	else
		catdef.validate = validate
	end
end

--- Creates a progress display.
---@param callbacks fltprogr.display.set_callbacks
---@return fltprogr.display
function M.create_display(callbacks)
	vim.validate('callbacks', callbacks, 'table')
	vim.validate('callbacks.on_start', callbacks.on_start, 'function')
	vim.validate('callbacks.on_update', callbacks.on_update, 'function')
	vim.validate('callbacks.on_end', callbacks.on_end, 'function')
	table.insert(progr.displays, callbacks)
	return #progr.displays
end

--- Checks if the progress display is valid.
--- @param display fltprogr.display Display id
--- @return boolean
function M.display_is_valid(display)
	vim.validate('display', display, 'number')
	return not not progr.displays[display]
end

---@param category string
---@param ev fltprogr.progress_event
---@param to 'on_start'|'on_update'|'on_end'
local function send_event(category, ev, to)
	local catdef = progr.categories[category]
	local category_displays = {}
	vim.list_extend(category_displays, catdef.displays)
	vim.list_extend(category_displays, progr.categories['*'].displays)
	if #category_displays == 0 then
		vim.notify(
			('No display registered for category "%s"'):format(category),
			vim.log.levels.DEBUG
		)
		return
	end
	for _, display in ipairs(category_displays) do
		if progr.displays[display] then
			progr.displays[display][to](vim.deepcopy(ev))
		end
	end
end

--- Registers a display to be used with the specified categories.
---@param display fltprogr.display Display id
---@param categories string|fltprogr.categories|(string|fltprogr.categories)[] Categories to display progress from
function M.display_register(display, categories)
	vim.validate('display', display, 'number')
	if not progr.displays[display] then
		error(('Invalid display id: %d'):format(display))
	end
	vim.validate('categories', categories, { 'table', 'string' })

	if type(categories) ~= 'table' then
		categories = { categories }
	end

	for _, category in ipairs(categories) do
		if not progr.categories[category] then
			progr.categories[category] = { displays = {} }
		end
		local catdef = progr.categories[category]
		if not vim.list_contains(catdef.displays, display) then
			table.insert(catdef.displays, display)
		end
	end

	-- Send all event currently in progress to the new display
	for _, srcdef in pairs(progr.sources) do
		if srcdef and vim.list_contains(categories, srcdef.category) then
			for evid, started in pairs(srcdef.event_state.started) do
				if started and not srcdef.event_state.ended[evid] then
					-- send_event(srcdef.category, progr.events[evid], 'on_start')
					progr.displays[display].on_start(
						vim.deepcopy(progr.events[evid])
					)
				end
			end
		end
	end
end

--- Unregisters and removes a progress display.
---@param display fltprogr.display Display id
function M.display_delete(display)
	vim.validate('display', display, 'number')
	if not progr.displays[display] then
		error(('Invalid display id: %d'):format(display))
	end

	for _, catdef in pairs(progr.categories) do
		for i = 1, #catdef.displays do
			if catdef.displays[i] == display then
				table.remove(catdef.displays, i)
				break
			end
		end
	end

	progr.displays[display] = false
end

--- Creates a new progress source.
---@param category fltprogr.categories|string Progress source category
---@return fltprogr.source
function M.create_source(category)
	vim.validate('category', category, 'string')
	---@type fltprogr.srcdef
	local srcdef = {
		category = category,
		events = {},
		event_state = {
			created = {},
			ended = {},
			started = {},
		},
	}
	table.insert(progr.sources, srcdef)
	return #progr.sources
end

--- Checks if the given source is valid.
---@param source fltprogr.source Source id
---@return boolean
function M.source_is_valid(source)
	vim.validate('source', source, 'number')
	return not not progr.sources[source]
end

---@class fltprogr.source_progress
---@field title string The progress event title
---@field message string? A progress message
---@field progress? number The progress value
---@field cancel? function If exists, the progress event is cancellable
---@field [string] any Additional event data, which may be required by the specified category

--- Creates and optionally starts a new event for the given source.
---@param source fltprogr.source Source id
---@param start boolean Indicate whether to start/signal this event right away
---@param data fltprogr.source_progress Source event data
function M.source_create_event(source, start, data)
	vim.validate('source', source, { 'number', 'string' })

	local srcdef = progr.sources[source]
	if not srcdef then
		error(('Invalid source id: %d'):format(source))
	end

	vim.validate('data', data, 'table')
	vim.validate('data.title', data.title, 'string')
	vim.validate('data.progress', data.progress, 'number', true)
	vim.validate('data.message', data.message, 'string', true)
	vim.validate('data.cancel', data.cancel, 'callable', true)

	-- Validate that the event contains required category data
	local catdef = progr.categories[srcdef.category]
	if catdef.validate then
		catdef.validate(data)
	end

	---@type fltprogr.progress_event
	local event = {
		title = data.title,
		message = data.message,
		progress = data.progress or true,
		source = source,
		category = srcdef.category,
	}
	if data.cancel then
		event.cancel = function(...)
			data.cancel(...)
			M.source_event_end(source, event.id)
		end
	end
	-- copy additional data into event
	event = vim.tbl_extend('keep', event, data)
	table.insert(progr.events, event)

	if start then
		M.source_event_start(source, #progr.events)
	end

	return #progr.events
end

--- Starts an event
---@param source fltprogr.source Source id
---@param event fltprogr.event Event id
function M.source_event_start(source, event)
	vim.validate('source', source, 'number')
	local srcdef = progr.sources[source]
	if not srcdef then
		error(('Invalid source id: %d'):format(source))
	end

	vim.validate('event', event, 'number')
	local ev = progr.events[event]
	if not ev then
		error(('Invalid event id (%d) for source: %d'):format(source, event))
	end

	if srcdef.event_state.started[event] then
		error(('Event already started: %d'):format(event))
	end
	if srcdef.event_state.ended[event] then
		error(('Event already ended: %d'):format(event))
	end
	srcdef.event_state.started[event] = true

	send_event(srcdef.category, ev, 'on_start')
end

---@class fltprogr.event_update
---@field message? string|false Detail message. Use `false` remove
---@field progress? number Progress
---@field [string] any Additional data

--- Updates progress data for the started event.
---@param source fltprogr.source Source id
---@param event fltprogr.event Event id
---@param data fltprogr.event_update Event update data
function M.source_event_update(source, event, data)
	vim.validate('source', source, 'number')
	local srcdef = progr.sources[source]
	if not srcdef then
		error(('Invalid source id: %d'):format(source))
	end

	vim.validate('event', event, 'number')
	local ev = progr.events[event]
	if not ev then
		error(('Invalid event id (%d) for source: %d'):format(source, event))
	end

	if not srcdef.event_state.started[event] then
		error(('Event not started: %d'):format(event))
	end
	if srcdef.event_state.ended[event] then
		error(('Event already ended: %d'):format(event))
	end

	vim.validate('data', data, 'table')

	do
		local evtmp = vim.tbl_extend('force', ev, data)
		evtmp.id = ev.id
		evtmp.title = ev.title
		evtmp.source = ev.source
		evtmp.category = ev.category
		ev = evtmp
	end

	send_event(srcdef.category, ev, 'on_update')
end

--- Signals the end of a source event.
---
--- It can update some data for an ending message, displays can then decide
--- what to do if the data changed or not.
---@param source fltprogr.source Source id
---@param event fltprogr.event Event id
---@param data fltprogr.event_update? Update data for end event
function M.source_event_end(source, event, data)
	vim.validate('source', source, 'number')
	local srcdef = progr.sources[source]
	if not srcdef then
		error(('Invalid source id: %d'):format(source))
	end

	vim.validate('event', event, 'number')
	local ev = progr.events[event]
	if not ev then
		error(('Invalid event id (%d) for source: %d'):format(source, event))
	end

	if not srcdef.event_state.started[event] then
		error(('Event not started: %d'):format(event))
	end
	if srcdef.event_state.ended[event] then
		error(('Event already ended: %d'):format(event))
	end
	srcdef.event_state.ended[event] = true

	vim.validate('data', data, 'table', true)

	if data then
		local evtmp = vim.tbl_extend('force', ev, data or {})
		evtmp.id = ev.id
		evtmp.title = ev.title
		evtmp.source = ev.source
		evtmp.category = ev.category
		ev = evtmp
	end

	send_event(srcdef.category, ev, 'on_end')
end

--- Removes a source
---@param source fltprogr.source Source id
function M.source_delete(source)
	vim.validate('source', source, 'number')
	local srcdef = progr.sources[source]
	if not srcdef then
		error(('Invalid source id: %d'):format(source))
	end

	progr.sources[source] = false
end

function M.setup(opts)
	local cfg = vim.tbl_extend(
		'force',
		{ autoregister = true },
		opts or { autoregister = vim.g.fltprogr_autoregister == 1 or nil }
	)

	if cfg.autoregister then
		require('fltprogr.lsp_source')
	end
end

--- Modified api to resemble what was posted to neovim #32537
---@class fltprogr.api2
M.api2 = {}

local progr2 = {
	---@type table<integer, integer|string>
	events = {},
}

---Creates and registers a progress display for the specified categories.
---@param categories string|fltprogr.categories|(string|fltprogr.categories)[]
---@param callbacks fltprogr.display.set_callbacks
---@return fltprogr.display
function M.api2.create_display(categories, callbacks)
	vim.validate('categories', categories, { 'table', 'string' })
	vim.validate('callbacks', callbacks, 'table')
	local id = M.create_display(callbacks)
	M.display_register(id, categories)
	return id
end

--- Creates a progress event
---@param srcid number|string Source identifier
---@param category string|fltprogr.categories Progress event category
---@param event fltprogr.source_progress Event data
---@return fltprogr.event event Event id
function M.api2.create_event(srcid, category, event)
	if not M.source_is_valid(srcid) then
		local source = M.create_source(category)
		progr.sources[srcid] = progr.sources[source]
		progr.sources[source] = nil
	end
	local eventid = M.source_create_event(srcid, false, event)
	progr2.events[eventid] = srcid
	return eventid
end

--- Starts a created progress event
---@param event fltprogr.event Event id
function M.api2.event_start(event)
	vim.validate('event', event, 'number')
	local source = assert(progr2.events[event], 'invalid event')
	M.source_event_start(source, event)
end

--- Updates an ongoing progress event
---@param event fltprogr.event Event id
---@param data fltprogr.event_update Update event data
function M.api2.event_update(event, data)
	vim.validate('event', event, 'number')
	local source = assert(progr2.events[event], 'invalid event')
	M.source_event_update(source, event, data)
end

--- Signals the end of the progress event
---@param event fltprogr.event Event id
---@param data? fltprogr.event_update Update event data
function M.api2.event_end(event, data)
	vim.validate('event', event, 'number')
	local source = assert(progr2.events[event], 'invalid event')
	M.source_event_end(source, event, data)
end

M.api2.add_category_validator = M.add_category_validator

return M
