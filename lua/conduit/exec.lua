local util = require("conduit.util")
local sec = require("conduit.secret")
local M = {}

function M.run(datasource, context, query, callback)
    local ps = util.resolve(datasource.pod_selector, context)
    sec.get_secret(datasource.secret, context, function(parsed_secret)
        local vars = vim.tbl_extend("force", datasource.vars or {}, parsed_secret)
        local kubectl = {
            "kubectl", "--context", context,
            "exec", "--namespace", ps.namespace, ps.name,
            "-i", "--",
        }
        local stdin
        if datasource.shell_exec then
            vars.query = query
            local cmd_str = util.render(datasource.exec, vars)
            vim.list_extend(kubectl, { "sh", "-c", cmd_str })
        else
            local cmd_str = util.render(datasource.exec, vars)
            vim.list_extend(kubectl, vim.split(cmd_str, "%s+", { trimemtpy = true }))
            stdin = query
        end
        vim.system(
            kubectl,
            { stdin = stdin, text = true },
            function(result)
                callback(result)
            end
        )
    end)
end


return M
