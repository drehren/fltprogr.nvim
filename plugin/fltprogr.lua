if vim.g.fltprogr_loaded then
	return
end

vim.g.fltprogr_loaded = true

if vim.g.fltprogr_autoregister then
	if vim.version.ge(vim.version(), { 0, 12, 0 }) then
		require('fltprogr.autocmd_source')
	end

	require('fltprogr.lsp_source')
end
