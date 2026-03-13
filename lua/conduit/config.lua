local M = {}

local default_config = {
    timeout = 30,
    keymaps = {
        open         = "<leader>co",
        run          = "<leader>cr",
        clear        = "<leader>cc",
        save         = "<leader>cs",
        save_and_run = "<leader>cw",
        load         = "<leader>cl",
        new          = "<leader>cn",
    },
    kubeconfig = vim.fn.expand("~/.kube/config"),
    datasources = {},
    layout = "bottom", -- can be "right"
    query_dir = vim.fn.stdpath("data") .. "/conduit/queries",
}

local function is_empty_table(value)
    if value == nil then
        return true
    end
    return next(value) == nil
end

function M.apply(config)
    assert(not is_empty_table(config.datasources), "conduit: no datasources configured")

    local errs = {}

    for name, ds in pairs(config.datasources) do
        local prefix = name or "<unnamed>"
        if prefix == "<unnamed>" then
            table.insert(errs, prefix .. ": datasources must have a valid name (hint: postgres = {...})")
        end

        local execIsValid = true
        if type(ds.exec) ~= "string" or ds.exec == "" then
            table.insert(errs,
                prefix ..
                ": exec must be a non-empty string (hint: exec = 'psql postgres://{{username}}:{{password}}@localhost:{{port}}/{{db}}')")
            execIsValid = false
        end

        local pstype = type(ds.pod_selector)
        if pstype ~= "table" and pstype ~= "function" then
            table.insert(errs, prefix .. ": pod_selector must be a table or function")
        end

        if pstype == "table" then
            if type(ds.pod_selector.name) ~= "string" or ds.pod_selector.name == "" then
                table.insert(errs, prefix .. ": pod_selector.name must be a non-empty string")
            end

            if type(ds.pod_selector.namespace) ~= "string" or ds.pod_selector.namespace == "" then
                table.insert(errs, prefix .. ": pod_selector.namespace must be a non-empty string")
            end
        end

        local sectype = type(ds.secret)
        if sectype ~= "table" and sectype ~= "function" then
            table.insert(errs, prefix .. ": secret must be a table or function")
        end

        if sectype == "table" then
            if type(ds.secret.name) ~= "string" or ds.secret.name == "" then
                table.insert(errs, prefix .. ": secret.name must be a non-empty string")
            end

            if type(ds.secret.namespace) ~= "string" or ds.secret.namespace == "" then
                table.insert(errs, prefix .. ": secret.namespace must be a non-empty string")
            end

            if type(ds.secret.user_key) ~= "string" or ds.secret.user_key == "" then
                table.insert(errs, prefix .. ": secret.user_key must be a non-empty string")
            end

            if type(ds.secret.pass_key) ~= "string" or ds.secret.pass_key == "" then
                table.insert(errs, prefix .. ": secret.pass_key must be a non-empty string")
            end
        end


        if type(ds.filetype) ~= "string" or ds.filetype == "" then
            table.insert(errs, prefix .. ": filetype must be a non-empty string (hint: filetype = 'sql')")
        end

        if ds.vars ~= nil and execIsValid then
            if next(ds.vars) == nil then
                table.insert(errs, prefix .. ": vars must either be nil or a non-empty table")
            else
                ds.exec:gsub("{{(.-)}}", function(key)
                    if ds.vars[key] == nil then
                        table.insert(errs, prefix .. ": vars is missing expected value " .. key)
                    end
                end)
            end

            if ds.shell_exec and not ds.exec:find("{{query}}") then
                table.insert(errs, prefix .. ": shell_exec = true requires {{query}} in exec template")
            end
        end
    end

    if #errs > 0 then
        error("conduit:\n " .. table.concat(errs, "\n  "))
    end
    return vim.tbl_deep_extend("force", default_config, config)
end

return M
