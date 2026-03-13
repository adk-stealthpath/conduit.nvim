local exec = require("conduit.exec")
local M = {}

-- keyed by input buffer handle
local state = {}

local function write_output(s, lines)
    local out_buf = s.out_buf
    vim.bo[out_buf].modifiable = true
    vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, lines)
    vim.bo[out_buf].modifiable = false
end

local function ensure_out_win(s)
    if vim.api.nvim_win_is_valid(s.out_win or -1) then return end
    vim.api.nvim_win_call(s.in_win, function()
        vim.cmd("split")
        s.out_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(s.out_win, s.out_buf)
        vim.api.nvim_win_set_height(
            s.out_win,
            math.floor(vim.o.lines * 0.25)
        )
    end)
end

local function set_keymaps(in_buf, keymaps)
    local opts = { noremap = true, silent = true, buffer = in_buf }

    vim.keymap.set("n", keymaps.run, function()
        local s = state[in_buf]
        local lines = vim.api.nvim_buf_get_lines(in_buf, 0, -1, false)
        local query = table.concat(lines, "\n")
        ensure_out_win(s)
        exec.run(s.datasource, s.context, query, function(result)
            vim.schedule(function()
                local out_lines = result.code ~= 0
                    and vim.split(result.stderr or "unknown error", "\n")
                    or  vim.split(result.stdout or "", "\n")
                write_output(s, out_lines)
                vim.api.nvim_win_set_cursor(s.out_win, { 1, 0 })
            end)
        end)
    end, opts)

    vim.keymap.set("n", keymaps.clear, function()
        local s = state[in_buf]
        if vim.api.nvim_win_is_valid(s.out_win or -1) then
            write_output(s, {})
        end
    end, opts)
end

function M.open(datasource, context, keymaps)
    vim.cmd("tabnew")

    local in_win = vim.api.nvim_get_current_win()
    local in_buf = vim.api.nvim_create_buf(false, true)
    local out_buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(in_win, in_buf)
    vim.bo[in_buf].filetype = datasource.filetype
    vim.bo[in_buf].buftype = "nofile"
    vim.bo[out_buf].buftype = "nofile"
    vim.bo[out_buf].modifiable = false

    state[in_buf] = {
        in_win    = in_win,
        out_win   = nil,
        out_buf   = out_buf,
        datasource = datasource,
        context   = context,
    }

    set_keymaps(in_buf, keymaps)

    -- cleanup state when input buffer is wiped
    vim.api.nvim_buf_attach(in_buf, false, {
        on_detach = function()
            state[in_buf] = nil
        end,
    })
end

return M
