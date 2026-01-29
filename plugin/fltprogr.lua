if vim.g.fltprogr_loaded then
	return
end

vim.g.fltprogr_loaded = true

if not package.loaded.lazy then
	require('fltprogr').setup()
end
