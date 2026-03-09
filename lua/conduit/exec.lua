local util = require("conduit.util")
local sec = requrie("conduit.secret")
local M = {}

function M.run(datasource, context, query, callback)
    local ps = util.resolve(datasource.pod_selector)
    sec.get_secret(datasource.secret, context, function(parsed_secret) end)
ens
