# terraform-doc.nvim

This plugin displays the documentation of the resource or data-source under the cursor.

[![asciicast](https://asciinema.org/a/566290.svg)](https://asciinema.org/a/566290)

## Get Started

Install with lazy

```lua
{
	"walbi-malbi/terraform-doc.nvim",
	config = function()
		require("terraform-doc")
	end,
},
```

## Require

- curl
- [terraform-ls](https://github.com/hashicorp/terraform-ls)
- [hcl2json](https://github.com/tmccombs/hcl2json)
- [glow](https://github.com/charmbracelet/glow)

## Usage

```
:TerraformDoc
:TerraformDoc floating
:TerraformDoc vsplit
:TerraformDoc split
:TerraformDoc tab
```
