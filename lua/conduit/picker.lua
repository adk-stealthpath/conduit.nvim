local pickers   = require("telescope.pickers")
local finders   = require("telescope.finders")
local conf      = require("telescope.config").values
local actions   = require("telescope.actions")
local astate    = require("telescope.actions.state")
local buffer    = require("conduit.buffer")
local M         = {}

local function get_contexts(callback)
    vim.system(
        { "kubectl", "config", "get-contexts", "-o", "name" },
        { text = true },
        function(result)
            vim.schedule(function()
                if result.code ~= 0 then
                    vim.notify("conduit: failed to get contexts - " .. (result.stderr or "unknown error"), vim.log.levels.ERROR)
                    return
                end
                local contexts = vim.split(result.stdout, "\n", { trimempty = true })
                callback(contexts)
            end)
        end
    )
end

function M.open(config)
    local names = vim.tbl_keys(config.datasources)
    table.sort(names)

    get_contexts(function(contexts)
        if vim.tbl_isempty(contexts) then
            vim.notify(
                "conduit: no kube contexts found — check KUBECONFIG (`kubectl config get-contexts`)",
                vim.log.levels.WARN)
            return
        end
        pickers.new({}, {
            prompt_title = "conduit: select context",
            finder       = finders.new_table({ results = contexts }),
            sorter       = conf.generic_sorter({}),
            attach_mappings = function(prompt_buf, map)
                actions.select_default:replace(function()
                    actions.close(prompt_buf)
                    local ctx_entry = astate.get_selected_entry()
                    if not ctx_entry then return end
                    local ctx = ctx_entry[1]
                    pickers.new({}, {
                        prompt_title = "conduit: select datasource",
                        finder       = finders.new_table({ results = names }),
                        sorter       = conf.generic_sorter({}),
                        attach_mappings = function(prompt_buf2, _)
                            actions.select_default:replace(function()
                                actions.close(prompt_buf2)
                                local ds_entry = astate.get_selected_entry()
                                if not ds_entry then return end
                                local name = ds_entry[1]
                                buffer.open(config.datasources[name], name, ctx, config)
                            end)
                            return true
                        end,
                    }):find()
                end)
                return true
            end,
        }):find()
    end)
end

return M
