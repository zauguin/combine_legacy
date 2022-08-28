-- kpse.set_program_name('lualatex', 'lualatex')

local operators = {
  beginbfrange = function(scanner, info)
    assert(not info.bfrange and not info.bfchar)
    info.bfrange = scanner:popnumber()
  end,
  endbfrange = function(scanner, info)
    local mapping = info.mapping

    local count = assert(info.bfrange)
    info.bfrange = nil
    for i = 1, count do
      local mapped = scanner:popstring()
      local final = scanner:popstring()
      local start = scanner:popstring()
      if #start ~= 1 or #final ~= 1 then
        error'Unsupported'
      end
      start = start:byte(1)
      final = final:byte(1)
      for source = start, final do
        local last = mapped:byte(-1) + source - start
        if last >= 0x100 then error'Invalid' end
        mapping[source] = mapped:sub(1, -2) .. string.char(last)
      end
    end
  end,
  beginbfchar = function(scanner, info)
    assert(not info.bfrange and not info.bfchar)
    info.bfchar = scanner:popnumber()
  end,
  endbfchar = function(scanner, info)
    local mapping = info.mapping

    local count = assert(info.bfchar)
    info.bfchar = nil
    for i = 1, count do
      local mapped = scanner:popstring()
      local source = scanner:popstring()
      if #source ~= 1 then error'Unsupported' end
      source = source:byte(1)
      mapping[source] = mapped
    end
  end,
}

local u16_to_u8 = setmetatable({}, {__index = function(t, k)
  local recoded = ''
  local surrogate
  for first, second in k:bytepairs() do
    local cp = first << 8 | second
    local marker = cp & 0xFC00
    if marker == 0xD800 then
      assert(not surrogate)
      surrogate = cp & 0x3FF
    else
      if marker == 0xDC00 then
        cp = ((assert(surrogate) << 10) | (cp & 0x3FF)) + 0x10000
        surrogate = nil
      else
        assert(not surrogate)
      end
      recoded = recoded .. utf8.char(cp)
    end
  end
  assert(not surrogate)
  t[k] = recoded
  return recoded
end})

local new_codepoint = setmetatable({
  ff = 0xFB00,
  fi = 0xFB01,
  fl = 0xFB02,
  ffi = 0xFB03,
  ffl = 0xFB04,
  SS = 0x1E9E,
}, {__index = function(t, k)
  local cp
  if utf8.len(k) == 1 then
    cp = utf8.codepoint(k, 1)
  else
    error('Unknown ' .. k)
  end
  t[k] = cp
  return cp
end})

local function from_name(name)
  local filename = kpse.find_file(name .. '.cmap', 'tex')
  if not filename then return end
  local f = assert(io.open(filename, 'r'))
  local cmap = f:read'a'
  f:close()

  local data = {mapping = {}}
  pdfscanner.scan(cmap, operators, data)
  for k, v in pairs(data.mapping) do
    data.mapping[k] = new_codepoint[u16_to_u8[v]]
  end
  return data.mapping
end

-- print(require'inspect'(from_name(arg[1])))
return from_name
