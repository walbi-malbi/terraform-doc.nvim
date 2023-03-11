local utils = require("terraform-doc.utils")

local M = {}

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

	local provider_full_name = nil
	local provider_version = "latest"

	-- required_providers定義が見つからなかった場合
	if not next(found) then
		url = "https://registry.terraform.io/v1/providers/-/" .. provider_name .. "/versions"

		local handle = io.popen("curl -s " .. url)
		if handle ~= nil then
			local response = handle:read("*a")
			handle:close()
			local response_json = vim.json.decode(response)

			provider_full_name = response_json.moved_to or response_json.id or nil
		else
			return nil, nil, "failed to get provider info request"
		end

		if not provider_full_name then
			return nil, nil, "failed to get provider info"
		end
	end

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
				provider_full_name = required_providers[provider_name].source
			end
			-- ~>で始まるなら指定バージョン、そうでなければlatest
			if required_providers[provider_name].version then
				if required_providers[provider_name].version:match("^>=") then
					provider_version = "latest"
				elseif required_providers[provider_name].version:match("^~>") then
					provider_version = required_providers[provider_name].version:match("^~>%s*(%S+)")
				end
			end
		end
	end

	return provider_full_name, provider_version, nil
end

function M.get_provider_latest_version(provider_full_name)
	local latest_version = nil
	local provider_url = "https://registry.terraform.io/v1/providers/" .. provider_full_name

	local handle = io.popen("curl -s " .. provider_url)
	if handle ~= nil then
		local provider_info = handle:read("*a")
		handle:close()
		latest_version = vim.json.decode(provider_info).version or nil
	else
		return nil, "request failed"
	end

	if not latest_version then
		return nil, "failed to get latest version"
	end

	return latest_version, nil
end

function M.get_document(provider_full_name, provider_version, category, resource_type)
	-- categoryとresource_typeをもとにjsonから要素を取り出し
	local provider_url = "https://registry.terraform.io/v1/providers/" .. provider_full_name .. "/" .. provider_version

	local docs_table
	local docs_table_handle = io.popen("curl -s " .. provider_url)
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

	local doc_url = "https://registry.terraform.io/v1/providers/"
		.. provider_full_name
		.. "/"
		.. provider_version
		.. "/docs?path="
		.. doc_path

	local doc_md

	local doc_md_handle = io.popen("curl -s " .. doc_url)
	if doc_md_handle ~= nil then
		local response = doc_md_handle:read("*a")
		doc_md_handle:close()
		doc_md = vim.json.decode(response).content or nil
	else
		return nil, "request failed"
	end

	if not doc_md then
		return nil, "failed to get markdown document"
	end

	local tempfile = vim.fn.tempname() .. ".md"
	local file = io.open(tempfile, "w")
	file:write(doc_md)
	file:close()

	return tempfile, nil
end

return M
