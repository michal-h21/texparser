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

-- input processor states
local s_newline = 1
local s_skipspaces = 2
local s_middle = 3

texparser.__index = texparser

local function getparser(text, filename)
  local filename = filename or "texput" -- default input name is texput
  local self = setmetatable({}, texparser)
  self.filename = filename
  self.texcommands = texcommands -- object with command actions
  self.source = text -- input text
  self.source_pos = 1 -- current position in the input buffer
  self.source_len = utf8.len(text)
  self.line_no = 0 -- current line
  self.column = 1 -- current position on a line
  self.state = s_newline 
  self.grouplevel = 1
  self.catcodes= {}
  for k,v in pairs(default_catcodes) do self.catcodes[k] = v end
  self.endlinechar = "\n" -- hadnle endlinechar
  self.catcodes[self.endlinechar] = c_endline
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
function texparser:tokenize(line)
  local tokens = {}
  local maxpos = 0
  -- for pos, char in get_chars(line) do
  local char = self:next_char()
  self.state = s_newline -- initialize state for each line
  while char do
    local pos = self.source_pos - 1
    self.column = pos
    local catcode = self:get_token_catcode(char)
    tokens[#tokens+1] = self:handle_token(catcode, char)
    -- tokens[#tokens+1] =  self:make_token(utfchar(char), catcode, line_no, pos)
    maxpos = pos -- save highest position, in order to be able to correctly make token for a newline
    char = self:next_char()
  end
  return tokens, maxpos
end


function  texparser:handle_token(catcode, char)
  local state = self.state
  if catcode == c_space then
    if state == s_newline then
      return nil -- space are ignored at new line
    elseif state == s_skipspaces then
      return nil -- ignore double spaces
    end
    self.state = s_skipspaces -- next spaces should be ignored
    return self:make_token(utfchar(char), catcode, self.line_no, self.column)
  elseif catcode==c_escape then
    return self:handle_cs()
  elseif catcode == c_ignore then
    return nil
  elseif  catcode==c_endline then
    if state == s_newline then -- we found paragraph
      return self:make_token("par", c_escape, self.line_no, self.column)
    -- else
    -- TeX converts newlines to spaces, but we may want to keep them
      -- return self:make_token(" ", c_space, self.line_no, self.column) -- convert newline to space
    end
  elseif catcode == c_begin then
    self.grouplevel = self.grouplevel + 1
  elseif catcode == c_end then
    self.grouplevel = self.grouplevel - 1
  elseif catcode == c_comment then
    -- TeX ignores comments, but they can be interesting for our purposes
    -- so we will make a new token that will keep the whole text in the comment
    local offset = utfoffset(self.source, self.source_pos)
    local comment_text = self.source:sub(offset):gsub("\n", "") 
    -- make sure that we will not process rest of the input line 
    self.source_len = 0
    self.source_pos = 1
    return self:make_token(comment_text, catcode, self.line_no, self.column)
  end
  self.state = s_middle -- default state 
  return self:make_token(utfchar(char), catcode, self.line_no, self.column)
end

function texparser:handle_cs()
  local read_next = function()
    local next_char = self:next_char()
    local catcode = self:get_token_catcode(next_char)
    return next_char, catcode
  end
  local name = {}
  local value 
  local next_char, catcode = read_next()
  while catcode == c_letter do
    table.insert(name, utfchar(next_char))
    next_char, catcode = read_next()
  end
  self.state = s_skipspaces
  if #name == 0 then
    if catcode ~= c_space then -- skip spaces by default after control space
      self.state = s_middle -- state after control symbol
    end
    value = next_char
  else
    value = table.concat(name)
    self.source_pos = self.source_pos - 1 -- return the scanner one character back
  end
  return self:make_token(value, c_escape, self.line_no, self.column)
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


function texparser:input_processor(text)
  -- clean lines
  local lines = {}
  for line in  text:gmatch("([^\n]*)") do
    line = line:gsub(" *$", "")  -- remove space characters at the end of line
    line = line .. self.endlinechar -- tokenizer needs to handle endline chars
    lines[#lines + 1] = line
  end
  return lines
end

function texparser:next_line()
  local lines = self.lines or {}
  self.line_no = self.line_no + 1
  local line = lines[self.line_no]
  if not line then return nil, "Line doesn't exits: " .. self.line_no end
  self.source = line 
  self.source_pos = 1
  self.source_len = utf8.len(line)
  return line
end

function texparser:get_raw_tokens()
  -- convert text to list of characters with assigned catcode
  -- I know that TeX doesn't tokenize full text at once, we do it for simplicity, 
  -- as we don't intend to support full expansion etc. We may change it in the future if necessary
  local line_no = 0

  local tokens = {}
  line_no = line_no + 1
  local parsed_tokens, maxpos = self:tokenize(line, line_no)
  for _,token in ipairs(parsed_tokens) do -- process tokens on the current line
    tokens[#tokens+1] = token
  end
  self.raw_tokens = tokens
  return tokens
end

-- parse next character from the input buffer 
function texparser:next_char()
  local source_pos = self.source_pos
  if not self.source then return nil, "end of file" end
  -- stop parsing when we are at the end of buffer
  if not (source_pos <= self.source_len) then 
    local line, msg = self:next_line() 
    if not line then return nil, msg end
    return self:next_char()-- nil, "end of input buffer" 
  end
  local offset = utfoffset(self.source, source_pos)
  self.source_pos = source_pos + 1
  return utfcodepoint(self.source, offset)
end


-- 
function texparser:parse(text, filename)
  local text = text or self.source
  self.filename = filename or self.filename
  self.lines = self:input_processor(text)
  self:next_line() -- initialize first line
  local raw_tokens = self:get_raw_tokens() -- initial tokenization
  -- local tokens = self:process(raw_tokens) -- detect commands and comments
  -- return tokens
  return raw_tokens
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
