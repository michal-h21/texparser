--
--

-- default actions for control sequences
local texcommands = require "texcommands"

-- function pointers
local get_chars = utf8.codes
local utfchar = utf8.char
local utfcodepoint = utf8.codepoint
local utfoffset = utf8.offset

-- initialize texparser object
local texparser = {
}

local default_catcodes = {}

texparser.__index = texparser

local function getparser(text, filename)
  local filename = filename or "texput" -- default input name is texput
  local self = setmetatable({}, texparser)
  self.filename = filename
  self.texcommands = texcommands -- object with command actions
  self.source = text -- input text
  self.source_pos = 1 -- current position in the input buffer
  self.source_len = utf8.len(text)
  self.line_no = 1 -- current line
  self.column = 1 -- current position on a line
  self.catcodes= {}
  for k,v in pairs(default_catcodes) do self.catcodes[k] = v end
  -- see https://www.overleaf.com/learn/latex/How_TeX_macros_actually_work:_Part_3
  -- for description of these properties
  self.curcs = 0 -- the current control sequence
  self.curchar = 0 -- the current character
  self.curcmd = 0 -- 
  self.curtok = {}
  return self
end


-- declare utf8 values for basic tex categories
function set_type(name, character) 
  default_catcodes[utfcodepoint(character)] = name 
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
local c_ignore = 9
local c_space = 10
local c_letter = 11
local c_other = 12
local c_active = 13
local c_comment = 14
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
set_type(c_letter, "@")
set_type(c_active, "~")
set_type(c_comment,"%")
set_type(c_endline, "\n")
set_type(c_ignore, "\r")

function texparser:get_token_catcode(char)
  local catcode = self.catcodes[char]
  if not catcode then
    catcode = ((char > 64 and char < 91) or (char > 96 and char < 123)) and c_letter or c_other
  end
  return catcode
end

-- convert input characters to tokens
function texparser:tokenize(line, line_no)
  local tokens = {}
  local maxpos = 0
  -- for pos, char in get_chars(line) do
  local char = self:next_char()
  while char do
    local pos = self.source_pos - 1
    self.line_no = line_no
    self.column = pos
    local catcode = self:get_token_catcode(char)
    tokens[#tokens+1] =  self:make_token(utfchar(char), catcode, line_no, pos)
    maxpos = pos -- save highest position, in order to be able to correctly make token for a newline
    char = self:next_char()
  end
  return tokens, maxpos
end

-- 
function texparser:make_token(value, catcode, line_no, col)
  local filename = self.filename -- keep tracks of input files
  return  {
    line = line_no, -- line number where character was parsed 
    file=filename, -- input file
    value = value, -- character at this moment
    catcode = catcode, -- catcode
    column = col -- column where character was placed in the original file
}
end


function texparser:get_raw_tokens(text, filename)
  -- convert text to list of characters with assigned catcode
  -- I know that TeX doesn't tokenize full text at once, we do it for simplicity, 
  -- as we don't intend to support full expansion etc. We may change it in the future if necessary
  local line_no = 0
  local tokens = {}
  for line in  text:gmatch("([^\n]*)") do
    line = line:gsub(" *$", "")  -- remove space characters at the end of line
    self.source = line
    self.source_pos = 1
    self.source_len = utf8.len(line)
    line_no = line_no + 1
    local parsed_tokens, maxpos = self:tokenize(line, line_no)
    for _,token in ipairs(parsed_tokens) do -- process tokens on the current line
      tokens[#tokens+1] = token
    end
    tokens[#tokens+1] = self:make_token("\n", c_endline, line_no, maxpos + 1) -- add new line char
  end
  tokens[#tokens] = nil -- remove last spurious endline
  self.raw_tokens = tokens
  return tokens
end

-- parse next character from the input buffer 
function texparser:next_char()
  local source_pos = self.source_pos
  -- stop parsing when we are at the end of buffer
  if not (source_pos <= self.source_len) then return nil, "end of input buffer" end
  local offset = utfoffset(self.source, source_pos)
  self.source_pos = source_pos + 1
  return utfcodepoint(self.source, offset)
end


-- scan next token from the input buffer
function texparser:scan_token()
  local codepoint, msg = self:next_char()
  if not codepoint then return nil, msg end
  local catcode = self:get_token_catcode(codepoint)
  local token = self:make_token(utfchar(codepoint), catcode, self.line_no, self.column)
  return token
end



function texparser:next_token()
  local pos = self.pos
  self.pos = pos + 1
  local token = self.raw_tokens[pos]
  if token then return token end
  -- return self:scan_token()
end

function texparser:current_token()
  return self.raw_tokens[self.pos]
end

function texparser:prev_token()
  local pos = self.pos - 1
  return self.raw_tokens[pos]
end


function texparser:read_cs(newtokens)
  local function is_part_of_cs(token)
    if token.catcode == c_letter then
      return true
    end
  end
  local current = {}
  local cs_token = self:prev_token() -- the cs starts one character to the left
  local token = self:next_token()
  if token.catcode == c_letter then
    while token and is_part_of_cs(token) do -- loop over characters that are part of cs
      current[#current + 1] = token.value -- concat characters
      token = self:next_token()
    end
    self.pos = self.pos - 1
    cs_token.value = table.concat(current) -- value now contains cs name
  else
    -- save the current token value as cs_name value
    cs_token.value = token.value
  end
  newtokens[#newtokens + 1] = cs_token
  return pos
end

function texparser:read_comment(newtokens)
  local token = self:next_token()
  local current = {}
  while token and token.catcode ~= c_endline do
    current[#current+1] = token.value
    token = self:next_token()
  end
end

-- detect control sequences, math, etc.
function texparser:process(raw_tokens)
  local newtokens = {}
  self.raw_tokens = self.raw_tokens or raw_tokens
  self.pos = 1
  local token = self:next_token() 
  while token do
    if token.catcode == c_escape then
      self:read_cs(newtokens)
    elseif token.catcode == c_comment then
      self:read_comment(newtokens)
    else
      newtokens[#newtokens + 1] = token
    end
    token = self:next_token(raw_tokens, pos)
  end
  return newtokens

end


-- 
function texparser:parse(text, filename)
  local text = text or self.source
  self.filename = filename or self.filename
  local raw_tokens = self:get_raw_tokens(text) -- initial tokenization
  local tokens = self:process(raw_tokens) -- detect commands, environments and groups
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

A samozřejmě $a=\sqrt{a^2 + c}$  inline math.
\test[key=value,
another=anothervalue]{a text}

\begin{verbatim}
Hello verbatim
\end{verbatim}

\makeatletter
\hello@world{something}
\makeatother

Jo a co speciální znaky? \$, \#, \\.

Line % with some content after comment,
but also on another line.

\end{document}
]]

test  = "a\\helo c%b~$\nx"

-- test parsing
local parser = getparser(test, "sample.tex")
local tokens = parser:parse()
for _, token in ipairs(tokens) do
  print(token.line, token.file, 
  token.value:gsub("%s", "") --- don't print newlines
  , token.catcode, token.column)
end

return {
  getparser = getparser,
  tokenprocessor = tokenprocessor
}
