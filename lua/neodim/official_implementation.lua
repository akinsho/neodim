local bufnr_and_namespace_cacher_mt = {
  __index = function(t, bufnr)
    assert(bufnr > 0, "Invalid buffer number")
    t[bufnr] = {}
    return t[bufnr]
  end,
}

local diagnostic_cache = setmetatable({}, {
  __index = function(t, bufnr)
    assert(bufnr > 0, "Invalid buffer number")
    vim.api.nvim_buf_attach(bufnr, false, {
      on_detach = function()
        rawset(t, bufnr, nil) -- clear cache
      end
    })
    t[bufnr] = {}
    return t[bufnr]
  end,
})

local diagnostic_cache_extmarks = setmetatable({}, bufnr_and_namespace_cacher_mt)
local diagnostic_attached_buffers = {}
local diagnostic_disabled = {}
local bufs_waiting_to_update = setmetatable({}, bufnr_and_namespace_cacher_mt)

local function restore_extmarks(bufnr, last)
  for ns, extmarks in pairs(diagnostic_cache_extmarks[bufnr]) do
    local extmarks_current = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {details = true})
    local found = {}
    for _, extmark in ipairs(extmarks_current) do
      -- nvim_buf_set_lines will move any extmark to the line after the last
      -- nvim_buf_set_text will move any extmark to the last line
      if extmark[2] ~= last + 1 then
        found[extmark[1]] = true
      end
    end
    for _, extmark in ipairs(extmarks) do
      if not found[extmark[1]] then
        local opts = extmark[4]
        opts.id = extmark[1]
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, extmark[2], extmark[3], opts)
      end
    end
  end
end

local function save_extmarks(namespace, bufnr)
  if not diagnostic_attached_buffers[bufnr] then
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = function(_, _, _, _, _, last)
        restore_extmarks(bufnr, last - 1)
      end,
      on_detach = function()
        diagnostic_cache_extmarks[bufnr] = nil
      end})
    diagnostic_attached_buffers[bufnr] = true
  end
  diagnostic_cache_extmarks[bufnr][namespace] = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {details = true})
end

M = {}

M.ignore_vtext = function(diagnostic)
  return not diagnostic.severity == vim.diagnostic.HINT
end

M.setup = function ()
  local dim_ns = vim.api.nvim_create_namespace("dim")
  vim.api.nvim_set_hl(0, "Unused", {fg="#000022"})
  vim.diagnostic.handlers["dim/unused"] = {
    show = function(namespace, bufnr, diagnostics, opts)
      diagnostics = vim.tbl_filter(function(t)
        if t.severity == vim.diagnostic.severity.HINT then
          local tags = t.tags or t.user_data.lsp.tags
          return tags and vim.tbl_contains(tags, vim.lsp.protocol.DiagnosticTag.Unnecessary)
        end
        return false
      end, diagnostics)
      for _, diagnostic in ipairs(diagnostics) do
        local higroup = "Unused"
        vim.highlight.range(
          bufnr,
          dim_ns,
          higroup,
          { diagnostic.lnum, diagnostic.col },
          { diagnostic.end_lnum, diagnostic.end_col },
          { priority = 200 }
        )
      end
      save_extmarks(dim_ns, bufnr)
    end,
    hide = function(namespace, bufnr)
      if dim_ns then
        diagnostic_cache_extmarks[bufnr][dim_ns] = {}
        vim.api.nvim_buf_clear_namespace(bufnr, dim_ns, 0, -1)
      end
    end
  }
end

return M
