local M = {}

-- ---- JSON pretty-printer ----

local function json_pretty(val, depth)
    depth = depth or 0
    local pad = string.rep("  ", depth)
    local inner = pad .. "  "

    if val == vim.NIL then
        return "null"
    end

    local t = type(val)
    if t == "string" then
        return '"'
            .. val
                :gsub('\\', '\\\\')
                :gsub('"', '\\"')
                :gsub('\n', '\\n')
                :gsub('\r', '\\r')
                :gsub('\t', '\\t')
            .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local max_n = #val
        local is_array = max_n > 0
        if is_array then
            local count = 0
            for _ in pairs(val) do count = count + 1 end
            is_array = count == max_n
        end

        if is_array then
            local parts = {}
            for _, v in ipairs(val) do
                table.insert(parts, inner .. json_pretty(v, depth + 1))
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                local key = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
                table.insert(parts, inner .. key .. ": " .. json_pretty(v, depth + 1))
            end
            if #parts == 0 then return "{}" end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        end
    end
    return '"[?]"'
end

local function format_json(stdout)
    local trimmed = vim.trim(stdout)
    local ok, decoded = pcall(vim.fn.json_decode, trimmed)
    if not ok then return nil, nil end
    local pretty = json_pretty(decoded)
    return vim.split(pretty, "\n"), "json"
end

-- ---- Cypher / ASCII table formatter ----

-- Split a props string like: key: val, key2: "v,al", key3: {n: 1}
-- Respects quote context and bracket nesting.
local function split_props(props_str)
    local props = {}
    local depth = 0
    local in_str = false
    local escape = false
    local current = {}

    for i = 1, #props_str do
        local c = props_str:sub(i, i)
        if escape then
            table.insert(current, c)
            escape = false
        elseif c == "\\" and in_str then
            table.insert(current, c)
            escape = true
        elseif c == '"' then
            in_str = not in_str
            table.insert(current, c)
        elseif not in_str then
            if c == "{" or c == "[" or c == "(" then
                depth = depth + 1
                table.insert(current, c)
            elseif c == "}" or c == "]" or c == ")" then
                depth = depth - 1
                table.insert(current, c)
            elseif c == "," and depth == 0 then
                local pair = vim.trim(table.concat(current))
                if pair ~= "" then table.insert(props, pair) end
                current = {}
            else
                table.insert(current, c)
            end
        else
            table.insert(current, c)
        end
    end

    local pair = vim.trim(table.concat(current))
    if pair ~= "" then table.insert(props, pair) end
    return props
end

-- Returns expanded lines for a node/relationship cell, or nil if the cell
-- is a plain scalar that should be inlined.
local function expand_cell(cell)
    -- Node with properties: (:Labels {props})
    local node_pre, node_props = cell:match("^(%(:[^{]*){(.*)}%)$")
    if node_pre and node_props and node_props ~= "" then
        local prop_list = split_props(node_props)
        if #prop_list > 0 then
            local lines = { node_pre .. " {" }
            for i, p in ipairs(prop_list) do
                table.insert(lines, "  " .. p .. (i < #prop_list and "," or ""))
            end
            table.insert(lines, "})")
            return lines
        end
    end

    -- Relationship with properties: [:TYPE {props}]
    local rel_pre, rel_props = cell:match("^(%[:[^{]*){(.*)}%]$")
    if rel_pre and rel_props and rel_props ~= "" then
        local prop_list = split_props(rel_props)
        if #prop_list > 0 then
            local lines = { rel_pre .. " {" }
            for i, p in ipairs(prop_list) do
                table.insert(lines, "  " .. p .. (i < #prop_list and "," or ""))
            end
            table.insert(lines, "}]")
            return lines
        end
    end

    return nil
end

-- Parse a raw mgconsole ASCII table into { headers, rows, extras }.
-- extras: banner / summary lines that appear outside the table borders.
local function parse_mgconsole(stdout)
    local headers = nil
    local rows    = {}
    local extras  = {}
    local in_table = false

    for _, line in ipairs(vim.split(stdout, "\n")) do
        if line:match("^%+[-+]+%+") then
            in_table = true
        elseif in_table and line:match("^|") then
            local cells = {}
            for cell in line:gmatch("|([^|]+)") do
                table.insert(cells, vim.trim(cell))
            end
            if not headers then
                headers = cells
            else
                table.insert(rows, cells)
            end
        elseif line ~= "" then
            table.insert(extras, line)
        end
    end

    return { headers = headers, rows = rows, extras = extras }
end

local COL_SEP = "  │  "

-- Expanded lines for one cell: label on its own line + indented properties
-- for nodes/rels, or a single inline "label: value" for scalars.
local function cell_block(label, cell)
    local expanded = expand_cell(cell)
    if expanded then
        local lines = { label .. ":" }
        for _, el in ipairs(expanded) do
            table.insert(lines, "  " .. el)
        end
        return lines
    end
    return { label .. ": " .. cell }
end

-- Each result row is rendered with its SELECT columns placed side-by-side,
-- properties expanded vertically within each column. Rows stack downward.
-- Column widths are divided evenly across the terminal width.
local function format_records(stdout)
    local parsed = parse_mgconsole(stdout)
    if not parsed.headers or #parsed.rows == 0 then
        local out = {}
        for _, l in ipairs(parsed.extras) do table.insert(out, l) end
        return out
    end

    local ncols     = #parsed.headers
    local col_width = math.max(10, math.floor((vim.o.columns - (ncols - 1) * #COL_SEP) / ncols))
    local output    = {}

    for _, cells in ipairs(parsed.rows) do
        local blocks = {}
        local max_h  = 0
        for i, cell in ipairs(cells) do
            local block = cell_block(parsed.headers[i] or ("col" .. i), cell)
            table.insert(blocks, block)
            max_h = math.max(max_h, #block)
        end

        for row = 1, max_h do
            local parts = {}
            for ci, block in ipairs(blocks) do
                local line = block[row] or ""
                if #line > col_width then line = line:sub(1, col_width - 1) .. "~" end
                if ci < ncols then
                    table.insert(parts, line .. string.rep(" ", col_width - #line))
                else
                    table.insert(parts, line)
                end
            end
            table.insert(output, table.concat(parts, COL_SEP))
        end

        table.insert(output, "")
    end

    for _, line in ipairs(parsed.extras) do
        table.insert(output, line)
    end

    return output
end

-- Horizontal table view: one line per row, columns space-aligned.
-- Cells wider than MAX_COL are truncated with a trailing ellipsis.
local MAX_COL = 60

local function truncate(s, max)
    if #s <= max then return s end
    return s:sub(1, max - 1) .. "~"
end

local function format_grid(stdout)
    local parsed  = parse_mgconsole(stdout)
    local headers = parsed.headers
    if not headers then
        return parsed.extras
    end

    -- compute column widths (capped)
    local widths = {}
    for i, h in ipairs(headers) do
        widths[i] = math.min(#h, MAX_COL)
    end
    for _, row in ipairs(parsed.rows) do
        for i, cell in ipairs(row) do
            widths[i] = math.max(widths[i] or 0, math.min(#cell, MAX_COL))
        end
    end

    local function sep()
        local parts = {}
        for _, w in ipairs(widths) do
            table.insert(parts, string.rep("-", w + 2))
        end
        return "+" .. table.concat(parts, "+") .. "+"
    end

    local function row_line(cells)
        local parts = {}
        for i, w in ipairs(widths) do
            local cell = truncate(cells[i] or "", w)
            table.insert(parts, " " .. cell .. string.rep(" ", w - #cell) .. " ")
        end
        return "|" .. table.concat(parts, "|") .. "|"
    end

    local output = {}
    table.insert(output, sep())
    table.insert(output, row_line(headers))
    table.insert(output, sep())
    for _, row in ipairs(parsed.rows) do
        table.insert(output, row_line(row))
    end
    table.insert(output, sep())

    for _, line in ipairs(parsed.extras) do
        table.insert(output, line)
    end

    return output
end

local function format_cypher(stdout)
    local trimmed = vim.trim(stdout)
    if trimmed:sub(1, 1) == "{" or trimmed:sub(1, 1) == "[" then
        local lines, ft = format_json(stdout)
        if lines then return lines, ft end
    end
    return format_records(stdout), nil
end

local function format_cypher_table(stdout)
    local trimmed = vim.trim(stdout)
    if trimmed:sub(1, 1) == "{" or trimmed:sub(1, 1) == "[" then
        local lines, ft = format_json(stdout)
        if lines then return lines, ft end
    end
    return format_grid(stdout), nil
end

-- ---- Built-in registry & dispatch ----

local builtins = {
    cypher       = format_cypher,
    cypher_table = format_cypher_table,
    json         = format_json,
}

-- Apply formatter to raw stdout. Returns lines[], filetype?.
-- formatter may be nil (pass-through), a builtin name string, or a function.
function M.apply(stdout, formatter)
    local raw = stdout or ""
    if formatter == nil then
        return vim.split(raw, "\n"), nil
    end

    local fn
    if type(formatter) == "string" then
        fn = builtins[formatter]
        if not fn then
            vim.notify("conduit: unknown formatter '" .. formatter .. "'", vim.log.levels.WARN)
            return vim.split(raw, "\n"), nil
        end
    elseif type(formatter) == "function" then
        fn = formatter
    else
        return vim.split(raw, "\n"), nil
    end

    local ok, lines, ft = pcall(fn, raw)
    if not ok then
        vim.notify("conduit: formatter error: " .. tostring(lines), vim.log.levels.WARN)
        return vim.split(raw, "\n"), nil
    end
    return lines or {}, ft
end

return M
