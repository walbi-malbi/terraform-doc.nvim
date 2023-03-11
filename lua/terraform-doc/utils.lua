local M = {}

-- テーブル内に指定したキーが含まれているか確認
function M.is_exist_key(key, tbl)
	for k, v in pairs(tbl) do
		if k == key then
			return true
		elseif type(v) == "table" and M.is_exist_key(key, v) then
			return true
		end
	end
	return false
end

-- テーブル内の指定したキーが格納されている要素番号を返す
function M.search_table(key, tbl)
	for i, v in pairs(tbl) do
		if type(v) == "table" and v[key] ~= nil then
			return i
		elseif type(v) == "table" then
			local result = M.search_table(v)
			if result ~= nil then
				return result
			end
		end
	end
	return nil
end

-- glowでmarkdownを表示
function M.open_doc(tempfile, open_type)
	local cmd = string.format("%s -c 'glow %s; sleep 0.2'", vim.env.SHELL, tempfile)
	local bufnr = vim.api.nvim_create_buf(false, true)

	if open_type ~= "floating" and open_type ~= "split" and open_type ~= "vsplit" and open_type ~= "tab" then
		open_type = "vsplit"
	end

	if open_type == "floating" then
		-- Floating windowを作成してバッファを設定
		local win_width = math.ceil(vim.o.columns * 0.8)
		local win_height = math.ceil(vim.o.lines * 0.8)
		local row = math.ceil((vim.o.lines - win_height) / 2 - 1)
		local col = math.ceil((vim.o.columns - win_width) / 2)
		local win_id = vim.api.nvim_open_win(bufnr, true, {
			relative = "editor",
			row = row,
			col = col,
			width = win_width,
			height = win_height,
			style = "minimal",
			focusable = false,
			border = "single",
		})
	elseif open_type == "split" then
		-- スプリットウィンドウを作成して、バッファを設定
		vim.api.nvim_command("split")
		local winid = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(winid, bufnr)
	elseif open_type == "vsplit" then
		-- Vスプリットウィンドウを作成して、バッファを設定（デフォルト）
		vim.api.nvim_command("vsplit")
		local winid = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(winid, bufnr)
	elseif open_type == "tab" then
		-- 新規タブを作成して、バッファを設定
		vim.api.nvim_command("tabnew")
		local winid = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(winid, bufnr)
	end

	vim.fn.termopen(cmd, {
		detach = 0,
		on_exit = function(_, _)
			os.remove(tempfile)
		end,
	})

	-- バッファローカルなマップを設定
	local map_buf_opts = { noremap = true, silent = true, nowait = true }
	vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<Cmd>bdelete<CR>", map_buf_opts)

	return nil
end

return M
