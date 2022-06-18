local fn = vim.fn

local function severity_lsp_to_vim(severity)
  if type(severity) == 'string' then
    severity = vim.lsp.protocol.DiagnosticSeverity[severity]
  end
  return severity
end

local function get_client_id(client_id)
  return client_id == nil and -1 or client_id
end

local function get_buf_lines(bufnr)
  if vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)
  local f = io.open(filename)
  if not f then
    return
  end

  local content = f:read('*a')
  if not content then
    -- Some LSP servers report diagnostics at a directory level, in which case
    -- io.read() returns nil
    f:close()
    return
  end

  local lines = vim.split(content, '\n')
  f:close()
  return lines
end

local function line_byte_from_position(lines, lnum, col, offset_encoding)
  if not lines or offset_encoding == 'utf-8' then return col end
  local line = lines[lnum + 1]
  local ok, result = pcall(vim.str_byteindex, line, col, offset_encoding == 'utf-16')
  if ok then return result end
  return col
end

local function diagnostic_lsp_to_vim(diagnostics, bufnr, client_id)
  local buf_lines = get_buf_lines(bufnr)
  local client = vim.lsp.get_client_by_id(client_id)
  local offset_encoding = client and client.offset_encoding or 'utf-16'
  return vim.tbl_map(function(diagnostic)
    local start = diagnostic.range.start
    local _end = diagnostic.range['end']
    return {
      lnum = start.line,
      col = line_byte_from_position(buf_lines, start.line, start.character, offset_encoding),
      end_lnum = _end.line,
      end_col = line_byte_from_position(buf_lines, _end.line, _end.character, offset_encoding),
      severity = severity_lsp_to_vim(diagnostic.severity),
      message = diagnostic.message,
      source = diagnostic.source,
      code = diagnostic.code,
      user_data = {
        lsp = {
          -- usage of user_data.lsp.code is deprecated in favor of the top-level code field
          code = diagnostic.code,
          codeDescription = diagnostic.codeDescription,
          tags = diagnostic.tags,
          relatedInformation = diagnostic.relatedInformation,
          data = diagnostic.data,
        },
      },
    }
  end, diagnostics)
end

local function on_publish_diagnostics(_, result, ctx, config)
  local client_id = ctx.client_id
  local uri = result.uri
  local fname = vim.uri_to_fname(uri)
  local diagnostics = result.diagnostics
  if #diagnostics == 0 and fn.bufexists(fname) == 0 then return end
  local bufnr = vim.fn.bufadd(fname)
  if not bufnr then return end
  client_id = get_client_id(client_id)
  local namespace = vim.api.nvim_create_namespace(vim.diagnostic.get_namespace(client_id).name)
  local dim_diag_ns = vim.api.nvim_create_namespace("dim_diag")
  if config then
    for _, opt in pairs(config) do
      if type(opt) == 'table' then
        if not opt.severity and opt.severity_limit then
          opt.severity = { min = severity_lsp_to_vim(opt.severity_limit) }
        end
      end
    end
  end
  local vim_diagnostics = diagnostic_lsp_to_vim(diagnostics, bufnr, client_id)
  local is_unused = require("neodim.filter").is_unused
  local unused, non_unused = {}, {}
  for _, d in ipairs(vim_diagnostics) do
    table.insert(is_unused(d) and non_unused or unused, d)
  end
  vim.diagnostic.set(dim_diag_ns, bufnr, non_unused)
  vim.diagnostic.set(namespace, bufnr, non_unused)
end

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
on_publish_diagnostics,{})
