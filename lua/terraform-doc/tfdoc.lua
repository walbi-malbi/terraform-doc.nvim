local utils = require("terraform-doc.utils")

local M = {}

function M.exec(opts)
	local resource_type, category, err = M.get_resource_info()

	if err ~= nil then
		vim.api.nvim_err_write("an error occurred: " .. err .. "\n")
		return
	end

	local function extract_provider_name(rt)
		if rt ~= "" or rt ~= nil then
			return rt:match("^(%w+)_"), nil
		else
			return nil, "failed to extract provider name"
		end
	end
	local provider_name, err = extract_provider_name(resource_type)

	if err ~= nil then
		vim.api.nvim_err_write("an error occurred: " .. err .. "\n")
		return
	end

	local provider_namespace, provider_version, err = M.get_provider_info(provider_name)

	if err ~= nil then
		vim.api.nvim_err_write("an error occurred: " .. err .. "\n")
		return
	end

	if provider_version == "latest" then
		provider_version, err = M.get_latest_version(provider_namespace, provider_name)
		if err ~= nil then
			vim.api.nvim_err_write("an error occurred: " .. err .. "\n")
			return
		end
	end

	local open_type = opts.args ~= "" and opts.args or "vsplit" -- floating, split, vsplit, tab (default: vsplit)
	local err = M.open_doc(provider_namespace, provider_name, provider_version, category, resource_type, open_type)

	if err ~= nil then
		vim.api.nvim_err_write("an error occurred: " .. err .. "\n")
		return
	end
end

function M.get_resource_info()
	-- カーソルの位置を取得する
	local row, _ = table.unpack(vim.api.nvim_win_get_cursor(0))
	-- カーソルの位置のリソースタイプを取得する
	local params = vim.lsp.util.make_position_params()

	local response = vim.lsp.buf_request_sync(0, "textDocument/documentSymbol", params)

	if type(response) == "table" and not utils.is_exist_key("result", response) then
		return
	end

	if response == nil then
		return nil, nil, "language server is not ready"
	end

	-- リソースタイプを抽出
	local symbols = response[utils.search_table("result", response)].result
	local category = ""
	local resource_type = ""
	for _, symbol in ipairs(symbols) do
		if symbol.range.start.line < row and symbol.range["end"].line >= row - 1 then
			if symbol.name:match('^resource "(%S+)"') then
				category = "resources"
				resource_type = symbol.name:match('^resource "(%S+)"')
			elseif symbol.name:match('^data "(%S+)"') then
				category = "data-sources"
				resource_type = symbol.name:match('^data "(%S+)"')
			end
			break
		end
	end

	-- resource_typeを取得できなかった場合
	if resource_type ~= "" and category == "" then
		return nil, category, "resource or data-source not found"
	elseif resource_type == "" and category ~= "" then
		return resource_type, category, "category not found"
	elseif resource_type == "" and category == "" then
		return nil, nil, "resource type or data-source and category not found"
	end

	return resource_type, category, nil
end

function M.get_provider_info(provider_name)
	local default_namespace = "hashicorp"
	local default_version = "latest"

	-- バッファのtfファイルと同じディレクトリ内のtfファイル内をgrep
	local function search_files(dir_path, pattern, search_text)
		local match_files = vim.fn.globpath(dir_path, pattern, true, true)
		local files = {}
		for _, file_path in ipairs(match_files) do
			local file = io.open(file_path, "r")
			if file then
				for line in file:lines() do
					if line:find(search_text) and not line:match("^%s*#") then
						table.insert(files, file_path)
						goto continue
					end
				end
				::continue::
				file:close()
			end
		end
		return files
	end

	local current_file_path = vim.fn.expand("%:p")
	local directory = vim.fn.fnamemodify(current_file_path, ":h")
	local pattern = "*.tf"
	local search_text = "required_providers"
	local found = search_files(directory, pattern, search_text)

	-- required_providers定義が見つからなかった場合
	if not next(found) then
		return default_namespace, default_version, nil
	end

	local source = default_namespace
	local version = default_version

	-- required_providersからsourceとversionを抽出
	for _, v in pairs(found) do
		local handle = io.popen("hcl2json " .. v)
		local get_required_providers = function()
			if handle ~= nil then
				local required_providers = handle:read("*a")
				handle:close()
				return vim.json.decode(required_providers).terraform[1].required_providers[1] or {}
			else
				return {}
			end
		end
		local required_providers = get_required_providers()

		if required_providers and required_providers[provider_name] then
			-- sourceがあれば抽出、なければそのまま
			if required_providers[provider_name].source then
				source = required_providers[provider_name].source:match("([^/]+)")
			end
			-- ~>で始まるなら指定バージョン、そうでなければlatest
			if required_providers[provider_name].version then
				if required_providers[provider_name].version:match("^>=") then
					version = "latest"
				elseif required_providers[provider_name].version:match("^~>") then
					version = required_providers[provider_name].version:match("^~>%s*(%S+)")
				end
			end
		end
	end

	return source, version, nil
end

function M.get_latest_version(provider_namespace, provider_name)
	local latest_version = nil
	local provider_url = "https://registry.terraform.io/v1/providers/" .. provider_namespace .. "/" .. provider_name

	local handle = io.popen("curl -s " .. provider_url .. " | jq . -c")
	if handle ~= nil then
		local provider_info = handle:read("*a")
		handle:close()
		latest_version = vim.json.decode(provider_info).version or nil
	else
		return nil, "failed to get latest version"
	end

	if not latest_version then
		return nil, "failed to get latest version"
	end

	return latest_version, nil
end

function M.open_doc(provider_namespace, provider_name, provider_version, category, resource_type, open_type)
	-- categoryとresource_typeをもとにjsonから要素を取り出し
	local provider_url = "https://registry.terraform.io/v1/providers/"
		.. provider_namespace
		.. "/"
		.. provider_name
		.. "/"
		.. provider_version

	local docs_table
	local docs_table_handle = io.popen("curl -s " .. provider_url .. " | jq . -c")
	if docs_table_handle ~= nil then
		local provider_info = docs_table_handle:read("*a")
		docs_table_handle:close()
		docs_table = vim.json.decode(provider_info).docs or nil
	else
		return "failed to get docs response"
	end

	-- ドキュメントリストが取得できなかったら終了
	if not docs_table then
		return "failed to get docs"
	end

	local resource_title = resource_type:match("^[a-z1-9]+_(.*)")
	local doc_path = nil

	for _, item in pairs(docs_table) do
		if item.title == resource_title and item.category == category then
			doc_path = item.path
			break
		end
	end

	-- ドキュメントパスが取得できなかったら終了
	if not doc_path then
		return "failed to get document path"
	end

	-- 該当リソースのmarkdownドキュメント取得
	local doc_url = "https://registry.terraform.io/v1/providers/"
		.. provider_namespace
		.. "/"
		.. provider_name
		.. "/"
		.. provider_version
		.. "/docs?path="
		.. doc_path

	local doc_md

	local doc_handle = io.popen("curl -s " .. doc_url .. " | jq . -c")
	if doc_handle ~= nil then
		local doc = doc_handle:read("*a")
		doc_handle:close()
		doc_md = vim.json.decode(doc).content or nil
	else
		return "failed to get markdown document"
	end

	if not doc_md then
		return "failed to get markdown document"
	end

	-- Prototype
	local tempfile = vim.fn.tempname() .. ".md"
	local file = io.open(tempfile, "w")
	file:write(doc_md)
	file:close()

	local cmd = string.format("glow %s", tempfile)
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

	-- バッファローカルなマップを設定する
	local map_buf_opts = { noremap = true, silent = true, nowait = true }
	vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<Cmd>bdelete<CR>", map_buf_opts)

	return nil
end

return M
