local util = require("conduit.util")
local M = {}

-- get_secret takes a context and a datasources secret after resolving the given field
-- it runs kubectl --context {{context}} get secret -n {{namespace}} {{name}} -o jsonpath='{.data}'
-- and returns the resulting table
function M.get_secret(field, context, callback)
    local secret_tbl = util.resolve(field, context)
    vim.system(
        {"kubectl", "--context", context, "get", "secret", "-n", secret_tbl.namespace, secret_tbl.name, "-o", "jsonpath={.data}"},
        {text = true},
        function(result)
            vim.schedule(function()
                if result.code ~= 0 then
                    vim.notify("conduit: " .. (result.stderr or "unknown error"), vim.log.levels.ERROR)
                    return
                end
                -- got result. do stuff
                local retval = {}

                local raw_secret = vim.fn.json_decode(result.stdout)
                if raw_secret[secret_tbl.pass_key] ~= nil then
                    retval.password = vim.base64.decode(raw_secret[secret_tbl.pass_key])
                else
                    vim.notify("conduit: secret does not have given pass_key - " .. secret_tbl.pass_key, vim.log.levels.ERROR)
                end

                if secret_tbl.user_key ~= nil then
                    if raw_secret[secret_tbl.user_key] ~= nil then
                        retval.username = vim.base64.decode(raw_secret[secret_tbl.user_key])
                    else
                        vim.notify("conduit: secret does not have given user_key - " .. secret_tbl.user_key, vim.log.levels.WARN)
                    end
                end
                callback(retval)
            end)
        end
    )
end

return M
