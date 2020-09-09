--
--

-- default actions for control sequences
local texcommands = require "texcommands"

-- function pointers
local get_chars = utf8.codes
local utfchar = utf8.char

-- initialize texparser object
local texparser = {
  types={}
}

texparser.__index = texparser

local function getparser(text, filename)
  local filename = filename or "texput"
  local self = setmetatable({}, texparser)
  self.filename = filename
  self.texcommands = texcommands
  self.source = text
  return self
end


-- declare utf8 values for basic tex categories
function set_type(name, character) 
  texparser.types[string.byte(character)] = name -- interesting characters are ASCII, no need for unicode here
end

-- initialize catcodes
local c_escape = 0
local c_begin = 1
local c_end = 2
local c_math = 3
local c_alignment = 4
local c_endline = 5
local c_parameter = 6
local c_superscript = 7
local c_subscript = 8
local c_space = 10
local c_letter = 11
local c_other = 12
set_type(c_escape,'\\')
set_type(c_begin, "{")
set_type(c_end, "}")
set_type(c_math, "$")
set_type(c_alignment, "&")
set_type(c_parameter, "#")
set_type(c_superscript, "^")
set_type(c_subscript, "_")
set_type(c_space, " ")
set_type(c_space, "\t")
set_type(c_space, "~")
set_type(c_comment,"%")



function texparser:tokenize(line, line_no)
  local tokens = {}
  for _, char in get_chars(line) do
    local typ = self.types[char]
    if not typ then
      typ = ((char > 64 and char < 91) or (char > 96 and char < 123)) and c_letter or c_other
    end
    tokens[#tokens+1] =  self:make_token(utfchar(char), typ, line_no)
  end
  return tokens
end

function texparser:raw_tokens(text, filename)
  -- convert text to list of characters with assigned catcode
  local line_no = 0
  local tokens = {}
  for line in  text:gmatch("([^\n]*)") do
    line_no = line_no + 1
    for _,token in ipairs(self:tokenize(line, line_no)) do -- process tokens on the current line
      tokens[#tokens+1] = token
    end
    tokens[#tokens+1] = self:make_token("\n", c_endline, line_no) -- add new line char
  end
  self.raw_tokens = tokens
  return tokens
end

function texparser:read_cs(tokens,pos, newtokens)
  local function is_part_of_cs(token)
    if token.type == c_letter then
      return true
    elseif token.type == c_other then
      if token.value == "@" then return true end -- support internal commands
    end
  end
  local current = {}
  local token = tokens[pos]
  local cs_token = tokens[pos-1] -- the cs starts one character to the left
  while is_part_of_cs(token) do -- loop over characters that are part of cs
    current[#current + 1] = token.value -- concat characters
    pos = pos + 1
    token = tokens[pos]
  end
  cs_token.value = table.concat(current) -- value now contains cs name
  newtokens[#newtokens + 1] = cs_token
  return pos
end

function texparser:read_token(raw_tokens, pos)
  return raw_tokens[pos]
end

function texparser:parse_cs(raw_tokens)
  local newtokens = {}
  local pos = 1
  local token = self:read_token(raw_tokens, pos) 
  while token do
    if token.type == c_escape then
      pos = self:read_cs(raw_tokens, pos + 1, newtokens)
    else
      newtokens[#newtokens + 1] = token
      pos = pos + 1
    end
    token = self:read_token(raw_tokens, pos)
  end
  return newtokens

end

function texparser:make_token(value, typ, line_no)
  local filename = self.filename
  return  {line = line_no, file=filename, value = value, type = typ}
end

-- 
function texparser:parse(text, filename)
  local text = text or self.source
  self.filename = filename or self.filename
  local raw_tokens = self:raw_tokens(text) -- initial tokenization
  local tokens = self:parse_cs(raw_tokens) -- detect commands, environments and groups
  return tokens
end

local test = [[
\documentclass{article}
\begin{document}
\section[test]{test}
\subsection*{Hello subsection}
\begin{tabular}{ll}
ahoj & svete\\
nazdar & svete
\end{tabular}

Příliš žluťoučký kůň \textit{přes
dva řádky, i~to je pěkné}. Nějaký \verb|inline verb|.

Jo a co speciální znaky? \$, \#.

A samozřejmě $a=\sqrt{a^2 + c}$  inline math.
\test[key=value,
another=anothervalue]{a text}

\begin{verbtatim}
Hello verbatim
\end{verbatim}

\makeatletter
\hello@world{something}
\makeatother

\end{document}
]]

-- test parsing
local parser = getparser(test, "sample.tex")
local tokens = parser:parse()
for _, token in ipairs(tokens) do
  print(token.line, token.file, 
  token.value:gsub("%s", "") --- don't print newlines
  , token.type)
end

return getparser
