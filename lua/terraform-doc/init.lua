local tfdoc = require("terraform-doc.tfdoc")

vim.api.nvim_create_user_command("TerraformDoc", function(args)
	tfdoc.exec(args)
end, {
	nargs = "?",
	complete = function(_, _, _)
		return { "floating", "split", "vsplit", "tab" }
	end,
})
