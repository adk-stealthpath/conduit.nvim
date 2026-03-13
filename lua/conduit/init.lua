local config = require("conduit.config")
local picker = require("conduit.picker")
local M = {}

function M.setup(user_config)
    local cfg = config.apply(user_config)

    vim.keymap.set("n", cfg.keymaps.open, function()
        picker.open(cfg)
    end, { noremap = true, silent = true, desc = "conduit: open picker" })
end

return M
