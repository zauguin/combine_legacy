-- kpse.set_program_name('lualatex', 'lualatex')

local tonumber = tonumber

local l = lpeg or require'lpeg'
local hex = '0' * l.S'xX' * (l.R('09', 'af', 'AF')^1 / function(s) return tonumber(s, 16) end)
local comment = '#' * (1-l.P'\n')^0

local line = l.Cg(hex * '\t' * hex * '\t')^-1 * comment * '\n'
local file = l.Cf(l.Ct'' * line^0 * -1, rawset)

local function from_http(name)
  local unparsed, status = socket.http.request(string.format('http://gitcdn.link/cdn/zr-tex8r/texucsmapping/master/bx-%s.txt', name))

  return file:match(unparsed)
end

local function from_file(name)
  local filename = kpse.find_file(string.format('bx-%s.txt', name), 'tex')
  if not filename then return end
  local f = assert(io.open(filename, 'r'))
  local unparsed = f:read'a'
  f:close()

  return file:match(unparsed)
end

return {
  file = from_file,
  http = from_http,
}
