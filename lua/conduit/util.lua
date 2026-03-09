local M = {}

-- resolve normalises a polymorphic field — if it's a function, call it with
-- context and return the result. If it's a table, return it directly.
-- Both pod_selector and secret use this pattern.
function M.resolve(field, context)
  if type(field) == "function" then
    return field(context)
  end
  return field
end


-- render substitutes {{key}} tokens in a template string with values from
-- the vars table. Raises an error on missing keys rather than silently
-- producing a broken command string.
function M.render(template, vars)
    return (template:gsub("{{(.-)}}", function(key)
        local val = vars[key]
        if val == nil then
            error("conduit: missing template variable: " .. key)
        end
        return val
    end))
end

return M
