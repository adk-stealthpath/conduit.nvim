# conduit.nvim

A Neovim plugin for querying Kubernetes-hosted databases directly from your editor. Datasource-centric configuration, credential injection from k8s secrets, and a clean query/output buffer workflow — no connection managers, no persistent credential storage, no bullshit.

## How it works

1. Pick a datasource from a Telescope picker
2. Plugin resolves the pod and fetches credentials from the configured k8s secret at runtime
3. A query buffer opens with the correct filetype (`sql`, `cypher`, etc.)
4. Execute the buffer or a visual selection — output streams to a split buffer

Credentials live only in the Lua call stack for the duration of the exec call. Nothing is written to disk.

---

## Dependencies

- [Neovim](https://neovim.io/) >= 0.10
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- `kubectl` in `$PATH`, configured and authenticated against your target clusters

---

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "conduit.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("conduit").setup({
      datasources = {
        -- see Configuration below
      }
    })
  end,
}
```

During development, load from a local path:

```lua
{
  dir = "~/projects/conduit.nvim",
  dependencies = { ... },
  config = function() ... end,
}
```

---

## Configuration

All behaviour is driven by the `datasources` table. Each entry is self-describing — it knows its pod, its secret, and how to exec and run a query.

```lua
require("[PLUGIN_NAME]").setup({
  timeout = 30,       -- kubectl exec timeout in seconds (default: 30)
  keymaps = {
    open   = "<leader>do",   -- open datasource picker
    run    = "<leader>dr",   -- execute query buffer / visual selection
    clear  = "<leader>dc",   -- clear output buffer
  },
  datasources = {

    -- Minimal example: Memgraph (Cypher)
    memgraph = {
      type     = "memgraph",
      filetype = "cypher",
      pod_selector = { name = "memgraph-0", namespace = "memgraph" },
      secret   = {
        name      = "memgraph-credentials",
        namespace = "memgraph",
        user_key  = "username",
        pass_key  = "password",
      },
      exec = "mgconsole --username {{username}} --password {{password}}",
    },

    -- Example with static vars: TimescaleDB (SQL)
    timescale = {
      type     = "postgres",
      filetype = "sql",
      pod_selector = { name = "timescaledb-0", namespace = "monitoring" },
      secret   = {
        name      = "ts-credentials",
        namespace = "monitoring",
        user_key  = "username",
        pass_key  = "password",
      },
      exec = "psql postgresql://{{username}}:{{password}}@localhost:{{port}}/{{db}}",
      vars = { port = "5432", db = "sensor_data" },
    },

    -- Example with dynamic pod_selector and secret (multi-environment)
    memgraph_prod = {
      type     = "memgraph",
      filetype = "cypher",
      pod_selector = function(context)
        if context == "prod" then
          return { name = "memgraph-0", namespace = "memgraph-prod" }
        end
        return { name = "memgraph-0", namespace = "memgraph-dev" }
      end,
      secret = function(context)
        if context == "prod" then
          return { name = "memgraph-prod-creds", namespace = "memgraph-prod", user_key = "username", pass_key = "password" }
        end
        return { name = "memgraph-dev-creds", namespace = "memgraph-dev", user_key = "username", pass_key = "password" }
      end,
      exec = "mgconsole --username {{username}} --password {{password}}",
    },

  }
})
```

### Field reference

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `string` | yes | Datasource type identifier (`postgres`, `memgraph`, etc.) |
| `filetype` | `string` | yes | Neovim filetype for the query buffer (`sql`, `cypher`, etc.) |
| `pod_selector` | `table \| function` | yes | Static `{ name, namespace }` or function returning same. Function receives active kubeconfig context name. |
| `secret` | `table \| function` | yes | Static secret reference or function returning same. Function receives active kubeconfig context name. |
| `secret.name` | `string` | yes | k8s secret name |
| `secret.namespace` | `string` | yes | k8s secret namespace |
| `secret.user_key` | `string` | no | Key in secret `.data` for username |
| `secret.pass_key` | `string` | yes | Key in secret `.data` for password |
| `exec` | `string` | yes | Exec command template. `{{username}}`, `{{password}}`, and any keys from `vars` are substituted at runtime. |
| `vars` | `table` | no | Static key/value pairs merged into template render context. Credentials always win on key collision. |

### Template rendering

`exec` strings use `{{key}}` token syntax. At runtime the render context is built from:

1. `datasource.vars` (static, lowest priority)
2. Decoded secret credentials (runtime, highest priority)

Example: `"psql postgresql://{{username}}:{{password}}@localhost:{{port}}/{{db}}"` with `vars = { port = "5432", db = "mydb" }` and credentials `{ username = "admin", password = "secret" }` renders to `"psql postgresql://admin:secret@localhost:5432/mydb"`.

---

## Keymaps

| Keymap | Action |
|---|---|
| `<leader>do` | Open datasource picker |
| `<leader>dr` | Execute query buffer or visual selection |
| `<leader>dc` | Clear output buffer |

All keymaps are buffer-local to the query buffer. Global keymap is only `<leader>do` to open the picker.

---

## TODO

### v0.1 — Core

- [ ] Plugin architecture scaffold (`/lua/[PLUGIN_NAME]/`)
- [ ] Config table validation and merge with defaults
- [ ] `render(template, vars)` utility
- [ ] `resolve(field, context)` polymorphic field normaliser
- [ ] Kubeconfig context picker (Telescope)
- [ ] Datasource picker (Telescope)
- [ ] Secret resolution via `kubectl get secret`
- [ ] base64 decode of secret values
- [ ] Pod selector resolution
- [ ] `kubectl exec` runner via `vim.system` with stdin passthrough
- [ ] Query buffer (`buftype=nofile`, `bufhidden=wipe`, correct filetype)
- [ ] Output buffer (split below, raw stdout/stderr)
- [ ] Error handling: pod not found, kubectl not in PATH, exec timeout, non-zero exit

### v0.2 — Output

- [ ] Pretty-print per datasource type
- [ ] Tabular column alignment for postgres/timescale output
- [ ] JSON node/relationship formatting for Memgraph output
- [ ] Syntax highlighting in output buffer

### v0.3 — Secret handling extensions

- [ ] Connection string secret format
- [ ] TLS cert secret format

---

## Security

Credentials are fetched from k8s secrets at query execution time and exist only in the Lua call stack for the duration of the `kubectl exec` call. They are never written to disk, never stored in Neovim state, never passed as command-line arguments (exec uses stdin), and never logged via `vim.notify`.

The `exec` template string is rendered in memory immediately before execution and the rendered string is not retained after the `vim.system` call returns.

---

## License

MIT
