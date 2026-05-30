local exec   = require("conduit.exec")
local format = require("conduit.format")
local M = {}

-- keyed by input buffer handle
local state = {}

local function write_output(s, lines)
    vim.bo[s.out_buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.out_buf, 0, -1, false, lines)
    vim.bo[s.out_buf].modifiable = false
end

local function ensure_out_win(s)
    if vim.api.nvim_win_is_valid(s.out_win or -1) then return end
    -- check if any existing window already holds our out_buf
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == s.out_buf then
            s.out_win = win
            return
        end
    end
    vim.api.nvim_win_call(s.in_win, function()
        if s.layout == "right" then
            vim.cmd("vsplit")
        else
            vim.cmd("belowright split")
        end
        s.out_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(s.out_win, s.out_buf)
        if s.layout == "right" then
            vim.api.nvim_win_set_width(s.out_win, math.floor(vim.o.columns * 0.25))
        else
            vim.api.nvim_win_set_height(s.out_win, math.floor(vim.o.lines * 0.25))
        end
    end)
end

local function do_run(in_buf)
    local s = state[in_buf]
    local lines = vim.api.nvim_buf_get_lines(in_buf, 0, -1, false)
    local query = table.concat(lines, "\n")
    ensure_out_win(s)
    exec.run(s.datasource, s.context, query, function(result)
        vim.schedule(function()
            local raw, formatter
            if result.code ~= 0 then
                raw       = result.stderr or "unknown error"
                formatter = nil
            else
                raw       = result.stdout or ""
                formatter = s.datasource.formatter
            end
            local out_lines, out_ft = format.apply(raw, formatter)
            vim.bo[s.out_buf].filetype = out_ft or ""
            write_output(s, out_lines)
            vim.api.nvim_win_set_cursor(s.out_win, { 1, 0 })
        end)
    end)
end

local function do_save(in_buf, callback)
    local s = state[in_buf]
    local name = vim.api.nvim_buf_get_name(in_buf)
    local lines = vim.api.nvim_buf_get_lines(in_buf, 0, -1, false)

    local function write(filepath)
        vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")
        vim.fn.writefile(lines, filepath)
        vim.api.nvim_buf_set_name(in_buf, filepath)
        vim.bo[in_buf].modified = false
        vim.notify("conduit: saved to " .. filepath, vim.log.levels.INFO)
        if callback then callback() end
    end

    if name == "" then
        local default = os.date("%Y%m%d_%H%M%S")
        local dir = s.query_dir .. "/" .. s.keyname
        vim.ui.input(
            { prompt = "query name: ", default = default },
            function(input)
                if not input or input == "" then return end
                write(dir .. "/" .. input .. "." .. s.datasource.filetype)
            end
        )
    else
        write(name)
    end
end

local function register_autocmds(in_buf)
    local aug = vim.api.nvim_create_augroup("conduit_buf_" .. in_buf, { clear = true })

    vim.api.nvim_create_autocmd("BufDelete", {
        buffer   = in_buf,
        group    = aug,
        callback = function()
            vim.api.nvim_del_augroup_by_id(aug)
            state[in_buf] = nil
        end,
    })
end

local function set_keymaps(in_buf, keymaps)
    local opts    = { noremap = true, silent = true, buffer = in_buf }
    local actions = require("telescope.actions")
    local astate  = require("telescope.actions.state")

    vim.keymap.set("n", keymaps.run, function()
        do_run(in_buf)
    end, opts)

    vim.keymap.set("n", keymaps.save, function()
        do_save(in_buf)
    end, opts)

    vim.keymap.set("n", keymaps.save_and_run, function()
        do_save(in_buf, function()
            do_run(in_buf)
        end)
    end, opts)

    vim.keymap.set("n", keymaps.clear, function()
        local s = state[in_buf]
        if vim.api.nvim_win_is_valid(s.out_win or -1) then
            write_output(s, {})
        end
    end, opts)

    vim.keymap.set("n", keymaps.new, function()
        vim.api.nvim_buf_set_lines(in_buf, 0, -1, false, {})
        vim.api.nvim_buf_set_name(in_buf, "")
        vim.bo[in_buf].modified = false
    end, opts)

    vim.keymap.set("n", keymaps.load, function()
        local s = state[in_buf]
        local dir = s.query_dir .. "/" .. s.keyname
        vim.fn.mkdir(dir, "p")

        local function load_into(buf, win)
            local sel = astate.get_selected_entry()
            if not sel then return end
            local lines = vim.fn.readfile(sel.path)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.api.nvim_buf_set_name(buf, sel.path)
            vim.bo[buf].modified = false
            if not state[buf] then
                local parent               = state[in_buf]
                local out_buf              = vim.api.nvim_create_buf(false, true)
                vim.bo[out_buf].buftype    = "nofile"
                vim.bo[out_buf].modifiable = false
                state[buf]                 = {
                    in_win         = win,
                    out_win        = nil,
                    out_buf        = out_buf,
                    datasource     = parent.datasource,
                    context        = parent.context,
                    layout         = parent.layout,
                    query_dir      = parent.query_dir,
                    keyname        = parent.keyname,
                    config_keymaps = parent.config_keymaps,
                }
                set_keymaps(buf, parent.config_keymaps)
                register_autocmds(buf)
            end
        end

        require("telescope.builtin").find_files({
            prompt_title    = "conduit: load query",
            cwd             = dir,
            attach_mappings = function(prompt_buf, map)
                actions.select_default:replace(function()
                    actions.close(prompt_buf)
                    vim.schedule(function()
                        local buf = vim.api.nvim_get_current_buf()
                        local win = vim.api.nvim_get_current_win()
                        load_into(buf, win)
                    end)
                end)

                local action_set = require("telescope.actions.set")

                for _, key in ipairs({ "<C-v>", "<C-x>", "<C-t>" }) do
                    map("i", key, function()
                        local wins_before = vim.api.nvim_list_wins()
                        if key == "<C-v>" then
                            action_set.edit(prompt_buf, "vsplit")
                        elseif key == "<C-x>" then
                            action_set.edit(prompt_buf, "split")
                        elseif key == "<C-t>" then
                            action_set.edit(prompt_buf, "tabedit")
                        end
                        vim.schedule(function()
                            local wins_after = vim.api.nvim_list_wins()
                            local new_win = nil
                            for _, w in ipairs(wins_after) do
                                local found = false
                                for _, wb in ipairs(wins_before) do
                                    if w == wb then
                                        found = true; break
                                    end
                                end
                                if not found then
                                    new_win = w; break
                                end
                            end
                            local win = new_win or vim.api.nvim_get_current_win()
                            local buf = vim.api.nvim_win_get_buf(win)
                            load_into(buf, win)
                        end)
                    end)
                end
                return true
            end,
        })
    end, opts)
end

function M.open(datasource, keyname, context, config)
    vim.cmd("tabnew")

    local in_win = vim.api.nvim_get_current_win()
    local in_buf = vim.api.nvim_create_buf(false, true)
    local out_buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_win_set_buf(in_win, in_buf)
    vim.bo[in_buf].filetype    = datasource.filetype
    vim.bo[in_buf].buftype     = "nofile"
    vim.bo[out_buf].buftype    = "nofile"
    vim.bo[out_buf].modifiable = false

    state[in_buf]              = {
        in_win         = in_win,
        out_win        = nil,
        out_buf        = out_buf,
        datasource     = datasource,
        context        = context,
        layout         = config.layout,
        query_dir      = config.query_dir,
        keyname        = keyname,
        config_keymaps = config.keymaps,
    }

    set_keymaps(in_buf, config.keymaps)
    register_autocmds(in_buf)
end

return M
