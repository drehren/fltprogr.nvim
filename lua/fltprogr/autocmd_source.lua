--- Listen to Progress autocommand

---@class fltprogr.vim_progress
---@field id integer|string
---@field text string[]
---@field title? string
---@field source string
---@field status 'running'|'success'|'failed'|'cancel'
---@field percent? integer
---@field data any

---@type fltprogr.api2
local progr

local events = {}

---@type table<string, fun(ev: fltprogr.event, data?: fltprogr.event_update, id: integer|string)>
local status_handlers = {
	running = function(ev, data)
		if not progr.event_running(ev) then
			progr.event_start(ev)
		else
			progr.event_update(ev, data)
		end
	end,
	success = function(ev, data, id)
		---@cast data fltprogr.event_end
		data.end_state = 'success'
		progr.event_end(ev, data)
		events[id] = nil
	end,
	failed = function(ev, data, id)
		---@cast data fltprogr.event_end
		data.end_state = 'failed'
		progr.event_end(ev, data)
		events[id] = nil
	end,
}
local group =
	vim.api.nvim_create_augroup('fltprogr.source.au', { clear = true })

vim.api.nvim_create_autocmd('Progress', {
	group = group,
	callback = function(args)
		if not progr then
			progr = require('fltprogr').api2
			status_handlers.cancel = progr.event_cancel
		end
		---@type fltprogr.vim_progress
		local data = args.data

		local evid = events[data.id]
		local evdata = {
			title = data.title,
			message = table.concat(data.text),
		}
		if data.percent then
			evdata.progress = data.percent / 100
		end
		if not evid then
			evid = progr.create_event('aucmd', data.source, evdata)
			events[data.id] = evid
			evdata = nil
		end

		status_handlers[data.status](evid, evdata, data.id)
	end,
})
