local parser_lib = require "texparser"
local texparser = parser_lib.texparser

-- some helper functions
------------------------------
-- convert tokens to text
local function to_text(tokens)
  local allowed = {[10]=true, [11] = true, [12] = true}
  local text = {}
  for _, x in ipairs(tokens) do
    if allowed[x.type] then
      text[#text+1] = x.value
    end
  end
  return table.concat(text)
end

-- convert TeX source code to text
local function tex_to_text(text)
  local parser = texparser(text)
  return to_text(parser:parse())
end

describe("basic tests", function()
  it("can parse text", function()
    assert.are.equal("a", tex_to_text("a"))
    assert.are.equal("a b", tex_to_text("a b"))
  end)
  it("can handle comments",function()
    assert.are.equal(tex_to_text "hello% world", "hello")
  end)

end)

local test = "příliš žluťoučký kůň úpěl ďábelské ódy"
for i = 1, utf8.len(test) do
  local offset = utf8.offset(test, i)
  local codepoint = utf8.codepoint(test, offset)
  print(codepoint, utf8.char(codepoint))
end
