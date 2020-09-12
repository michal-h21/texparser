local parser_lib = require "texparser"
local texparser = parser_lib.getparser

-- some helper functions
------------------------------
-- convert tokens to text
local function to_text(tokens)
  local allowed = {[10]=true, [11] = true, [12] = true}
  local text = {}
  for _, x in ipairs(tokens) do
    if allowed[x.catcode] then
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

describe("token scanning", function()
  local scanparser = texparser("ab")
  it("can parse characters", function()
    assert.are.equal("a", utf8.char(scanparser:next_char()))
    assert.are.equal("b", utf8.char(scanparser:next_char()))
    assert.are.equal(nil, scanparser:next_char())
  end)
  it("can scan tokens", function()
    scanparser.source_pos = 1
    local first = scanparser:scan_token()
    local second = scanparser:scan_token()
    local third = scanparser:scan_token()
    assert.Table(second)
    assert.Nil(third)
  end)
end)


describe("basic tests", function()
  it("can parse text", function()
    assert.are.equal("a", tex_to_text("a"))
    assert.are.equal("a b", tex_to_text("a b"))
  end)
  it("can handle comments",function()
    assert.are.equal(tex_to_text "hello% world", "hello")
  end)
  it("removes  cs sequences", function()
    assert.are.equal(tex_to_text "hello \\textit{world}", "hello world")
    assert.are.equal(tex_to_text "hello \\textit@at{world}", "hello world")
  end)

end)

describe("catcode updates", function()
  local text = "\\hello@world{???}"
  local special_parser = texparser(text) -- this one will have different catcode for @
  special_parser.catcodes[utf8.codepoint("@")] = 12
  local normal_parser = texparser(text)
  it("normal parser should see @ char as part of command", function()
    assert.are.equal("???", to_text(normal_parser:parse()))
    assert.are.equal("@world???", to_text(special_parser:parse()))
  end)


end)

