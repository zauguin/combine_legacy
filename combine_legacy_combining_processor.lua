local traverse = node.direct.traverse
local is_char = node.direct.is_char
local uses_font = node.direct.is_char
local getprev = node.direct.getprev
local getwhd = node.direct.getwhd
local newnode = node.direct.new
local setchar = node.direct.setchar
local setkern = node.direct.setkern
local setlink = node.direct.setlink
local getoffsets = node.direct.getoffsets
local setoffsets = node.direct.setoffsets
local getdisc = node.direct.getdisc
local setdisc = node.direct.setdisc

local glyph_id = node.id'glyph'
local disc_id = node.id'disc'
local kern_id = node.id'kern'
local accent_kern = 2

local tonode = node.direct.tonode
local todirect = node.direct.todirect
local function print_nodes(head)
  head = tonode(head)
  for n in node.traverse(head) do
    print(n)
  end
end

local parse = require'lua-uni-parse'

local combining_no_height = {
  [0x0327] = true,
}

local entries = lpeg.Cf(lpeg.Ct'' * (lpeg.Cg(parse.fields(
  parse.codepoint,
  parse.ignore_field,
  parse.ignore_field,
  parse.ignore_field,
  parse.ignore_field,
  '<compat> 0020 ' * parse.codepoint,
  parse.ignore_line
)) + parse.ignore_line)^0, rawset) * -1
local spacing_to_combining = assert(parse.parse_file('UnicodeData', entries))

print(string.format('U+%04X', spacing_to_combining[0xB8]))

return function(characters, parameters)
  local x_height = assert(parameters.x_height)
  local slant = assert(parameters.slant)
  local process_list = {}
  for spacing, combining in next, spacing_to_combining do
    if not characters[combining] and characters[spacing] then
      process_list[combining] = spacing
    end
  end
  if next(process_list) then
    local function process(head, font, attr, direction, count)
      local saved_n, saved_xoff, saved_yoff
      for n, id, sub in traverse(head) do
        if id == glyph_id then
          local char = is_char(n, font)
          if char then
            local spacing = process_list[char]
            if spacing and head ~= n then
              local prev = getprev(n)
              if is_char(prev, font) then
                setchar(n, spacing)
                local prev_w, prev_h = getwhd(prev)
                local prev_xoff, prev_yoff
                if prev == saved_n then
                  prev_xoff, prev_yoff = saved_xoff, saved_yoff -- This doesn't restore the slant shift since we add that again
                else
                  prev_xoff, prev_yoff = getoffsets(prev)
                end
                local this_w, this_h = getwhd(n)
                local kern = newnode(kern_id, accent_kern)
                setkern(kern, -this_w)
                setlink(prev, kern, n)
                if combining_no_height[char] then
                  saved_n, saved_xoff, saved_yoff = n, prev_xoff + (this_w - prev_w) // 2, -this_h + prev_h + prev_yoff
                  setoffsets(n, saved_xoff)
                else
                  local height_diff = prev_h + prev_yoff - x_height
                  saved_n, saved_xoff, saved_yoff = n, prev_xoff + (this_w - prev_w) // 2, height_diff
                  setoffsets(n, saved_xoff + (height_diff * slant >> 16), saved_yoff)
                end
                saved_n = n
              end
            end
          end
        elseif id == disc_id then
          local pre, post, rep = getdisc(n)
          process(pre, font, attr, direction, count)
          process(post, font, attr, direction, count)
          process(rep, font, attr, direction, count)
        end
      end
    end
    return process
  end
end
