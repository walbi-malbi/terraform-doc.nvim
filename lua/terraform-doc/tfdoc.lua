local api = require("terraform-doc.api")
local utils = require("terraform-doc.utils")

local M = {}

function M.exec(opts)
	local resource_type, category, err = api.get_resource_info()

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

	local provider_full_name, provider_version, err = api.get_provider_info(provider_name)

	if err ~= nil then
		vim.api.nvim_err_write("an error occurred: " .. err .. "\n")
		return
	end

	if provider_version == "latest" then
		provider_version, err = api.get_provider_latest_version(provider_full_name)
		if err ~= nil then
			vim.api.nvim_err_write("an error occurred: " .. err .. "\n")
			return
		end
	end

	local tempfile, err = api.get_document(provider_full_name, provider_version, category, resource_type)

	if err ~= nil then
		vim.api.nvim_err_write("an error occurred: " .. err .. "\n")
		return
	end

	local open_type = opts.args ~= "" and opts.args or "vsplit" -- floating, split, vsplit, tab (default: vsplit)
	utils.open_doc(tempfile, open_type)
end

return M
