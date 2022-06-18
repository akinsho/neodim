local is_unused = function(diagnostic)
  local diag_info = diagnostic.tags or vim.tbl_get(diagnostic, "user_data", "lsp", "tags") or diagnostic.code
  if type(diag_info) == "table" then
    return diag_info and vim.tbl_contains(diag_info, vim.lsp.protocol.DiagnosticTag.Unnecessary)
  elseif type(diag_info) == "string" then
    return string.find(diag_info, ".*[uU]nused.*") ~= nil
  end
end

local detect_unused = function(diagnostics)
  local is_list = vim.tbl_islist(diagnostics)
  return is_list and vim.tbl_filter(is_unused, diagnostics) or is_unused(diagnostics) or {}
end

local filter_unused = function (diagnostics, invert)
  local is_used = function(d)
    local unused = vim.tbl_islist(d) and not detect_unused(d) or not is_unused(d)
    return unused and d.message or nil
  end

  return vim.tbl_filter(function(d)
    if invert then return not is_used(d) end
    return is_used(d)
  end, diagnostics)
end

return {
  filter_unused = filter_unused,
  is_unused = is_unused,
  detect_unused = detect_unused,
}
