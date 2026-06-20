-- Register lsp progress messages source

local augid =
	vim.api.nvim_create_augroup('fltprogr.source.lsp', { clear = true })

---@private
---@alias fltprogr.lsp_srcev { source: fltprogr.source, event: fltprogr.event[], evprog: boolean[] }

---@type table<integer, fltprogr.lsp_srcev>
local lspsources = {}

---@param client vim.lsp.Client
---@return fltprogr.lsp_srcev
local function create_lsp_source(client)
	if not lspsources[client.id] then
		local progress = require('fltprogr')
		local source = progress.create_source(progress.categories.LSP)
		lspsources[client.id] = {
			source = source,
			event = {},
			evprog = {},
		}
	end
	return lspsources[client.id]
end

vim.api.nvim_create_autocmd('LspProgress', {
	group = augid,
	pattern = 'begin',
	callback = function(ev)
		local client = vim.lsp.get_client_by_id(ev.data.client_id)
		if not client then
			return
		end
		local lspprog = create_lsp_source(client)
		local progress = require('fltprogr')
		local token = ev.data.params.token
		if lspprog.event[token] then
			vim.notify(
				'fltprogr lsp begin: server reusing token',
				vim.log.levels.ERROR
			)
			-- lsp server reusing token?
			progress.source_event_end(lspprog.source, lspprog.event[token])
		end
		---@type lsp.WorkDoneProgressBegin
		local value = ev.data.params.value
		local evdata = {
			title = value.title,
			message = value.message,
			client_id = ev.data.client_id,
		}
		if value.cancellable == true then
			function ev.data.cancel()
				client:notify('window/workDoneProgress/cancel', {
					token = token,
				})
			end
		end
		if value.percentage then
			evdata.progress = value.percentage / 100
			lspprog.evprog[token] = true
		end
		evdata = vim.tbl_extend('keep', evdata, value)
		lspprog.event[token] =
			progress.source_create_event(lspprog.source, true, evdata)
	end,
})

vim.api.nvim_create_autocmd('LspProgress', {
	group = augid,
	pattern = 'report',
	callback = function(ev)
		local client = vim.lsp.get_client_by_id(ev.data.client_id)
		if not client then
			return
		end
		local lspprog = create_lsp_source(client)
		local token = ev.data.params.token
		local event =
			assert(lspprog.event[token], 'fltprogr lsp report: no event')
		---@type lsp.WorkDoneProgressReport
		local value = ev.data.params.value
		local evdata = {
			message = value.message,
		}
		if value.percentage then
			evdata.progress = value.percentage / 100
			lspprog.evprog[token] = true
		end
		local progress = require('fltprogr')
		progress.source_event_update(lspprog.source, event, evdata)
	end,
})

vim.api.nvim_create_autocmd('LspProgress', {
	group = augid,
	pattern = 'end',
	callback = function(ev)
		local client = vim.lsp.get_client_by_id(ev.data.client_id)
		if not client then
			return
		end
		local lspprog = create_lsp_source(client)
		local token = ev.data.params.token
		local event = assert(lspprog.event[token], 'fltprogr lsp end: no event')
		---@type lsp.WorkDoneProgressEnd
		local value = ev.data.params.value
		local progress = require('fltprogr')
		progress.source_event_end(lspprog.source, event, {
			message = value.message or false,
			progress = lspprog.evprog[token] and 1 or nil,
		})
		lspprog.event[token] = nil
	end,
})
