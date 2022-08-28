local default_encoding_provider = 'lua'

local encoding_providers = {
  cmap = function()
    local parse_cmap = require'combine_legacy_parse_cmap'
    return setmetatable({}, {__index = function(t, enc)
      local mapping = parse_cmap(enc) or false
      t[enc] = mapping
      return mapping
    end})
  end,
  lua = function()
    return require'combine_legacy_luamapping'
  end,
  ucsmapping_file = function()
    local parse_ucsmapping = require'combine_legacy_parse_ucsmapping'.file
    return setmetatable({}, {__index = function(t, enc)
      local mapping = parse_ucsmapping(enc) or false
      t[enc] = mapping
      return mapping
    end})
  end,
  ucsmapping_http = function()
    local parse_ucsmapping = require'combine_legacy_parse_ucsmapping'.http
    return setmetatable({}, {__index = function(t, enc)
      local mapping = parse_ucsmapping(enc) or false
      t[enc] = mapping
      return mapping
    end})
  end,
}
local encoding_mappings = setmetatable({}, {__index = function(t, provider)
  local mapping = assert(encoding_providers[provider], 'Unknown encoding provider')()t[provider] = mapping
  return mapping
end})

function encoding_providers.ucsmapping()
  if kpse.find_file'bx-t1.txt' then
    return encoding_mappings.ucsmapping_file
  else
    return encoding_mappings.ucsmapping_http
  end
end

local lpeg = lpeg

local ws = lpeg.S' \n\t\f'^0
local name = (lpeg.R('09', 'az', 'AZ') + lpeg.S'-_.')^1
local keyval = ws * lpeg.C(name) * ws * '=' * ws * lpeg.C(name) * ws * ','
local keyvals = lpeg.Ct(lpeg.Ct(keyval)^0) * ws * lpeg.P','^-1 * -1

return function(spec)
  local encodings = spec.features.raw.encodings
  if not encodings then return end
  local provider = spec.features.raw.encoding_provider or default_encoding_provider
  local enc_mappings = encoding_mappings[provider]
  if not enc_mappings then return end

  local parsed = keyvals:match(encodings .. ',')
  if not parsed then return end
  local new_font = {
    name = spec.specification,
    fonts = {},
    characters = {},
  }
  local parameters
  local private = 0x100000
  for fontnum, pair in ipairs(parsed) do
    local enc_mapping = enc_mappings[pair[1]:lower()]
    if not enc_mapping then
      error(string.format('Unsupported encoding %s', pair[1]))
    end
    -- new_font.fonts[fontnum] = {name = pair[2], size = spec.size}
    local loaded = assert(font.read_tfm(pair[2], fontnum == 1 and spec.size or new_font.size))
    if fontnum == 1 then
      new_font.parameters = loaded.parameters
      new_font.designsize = loaded.designsize
      new_font.size = loaded.size
    end
    new_font.fonts[fontnum] = {id = font.define(loaded)}
      
    local font_mapping = {}
    for i, glyph in pairs(loaded.characters) do
      local mapped = enc_mapping[i]
      if not mapped then
        mapped = private
        private = private + 1
      end
      font_mapping[i] = mapped
    end
    for i, glyph in pairs(loaded.characters) do
      local mapped = font_mapping[i]
      local new_glyph = new_font.characters[mapped]
      if new_glyph then
        -- TODO: Transfer kerns/ligatures
      else
        local extensible
        if glyph.extensible then
          extensible = {}
          for i, part in pairs(glyph.extensible) do
            extensible[i] = font_mapping[part]
          end
        end
        local kerns
        if glyph.kerns then
          kerns = {}
          for i, kern in pairs(glyph.kerns) do
            kerns[font_mapping[i]] = kern
          end
        end
        local ligatures
        if glyph.ligatures then
          ligatures = {}
          for i, lig in pairs(glyph.ligatures) do
            ligatures[font_mapping[i]] = { char = font_mapping[lig.char], type = lig.type }
          end
        end
        new_glyph = {
          width = glyph.width,
          height = glyph.height,
          depth = glyph.depth,
          next = font_mapping[glyph.next],
          extensible = extensible,
          kerns = kerns,
          ligatures = ligatures,
          commands = {{'slot', fontnum, i}},
        }
        new_font.characters[mapped] = new_glyph
      end
    end
  end
  return new_font
end
