if not arg[1] then
   print("Usage: " .. arg[0] .. [[ PATH [--dump]

PATH should point to the base of the pgf distribution (so that PATH/doc exists)
]])
   return
end

extract_text = false --or true
make_keys = false --or true

lpeg = require "lpeg"
lpeg.locale(lpeg)
P, V, R, S, B = lpeg.P, lpeg.V, lpeg.R, lpeg.S, lpeg.B
C, Cp, Cs, Cmt, Cf, Ct = lpeg.C, lpeg.Cp, lpeg.Cs, lpeg.Cmt, lpeg.Cf, lpeg.Ct
Cc, Cg = lpeg.Cc, lpeg.Cg

save_from_table = require"luarocks.persist".save_from_table
load_into_table = require"luarocks.persist".load_into_table

util = require "digestif.util"
lfs = require "lfs"
ser = require "serpent".block
dump = require "serpent".dump
see = require "see"
concat = table.concat
merge = util.merge
search, gobble_until, case_fold = util.search, util.gobble_until, util.case_fold
split, replace = util.split, util.replace
trim = util.trim()

tmpout = os.tmpname()
tmperr = os.tmpname()

pandoc_cmd = "pandoc --reference-links --verbose -f latex -t markdown_strict+tex_math_dollars-raw_html+simple_tables -o" .. tmpout .. " 2> " .. tmperr
preamble =[[
\def\meta#1{⟨#1⟩}
\def\cs#1{\\texttt{\\textbackslash #1}}
\def\marg#1{\texttt{\{#1\}}}
\def\oarg#1{\texttt{[#1]}}
\def\declare#1{#1}
\def\pageref#1{??}
\def\opt#1{#1}
\def\text#1{#1}
\def\mvar#1{#1}
\def\declareandlabel#1{\verb|#1|}
\def\example{}
\def\pgfname{PGF}
\def\pdf{PDF}
\def\makeatletter{}
\def\tikzname{TikZ}
\def\noindent{}
\def\medskip{}
\def\keyalias#1{}

]]

function pandockify(s)
  local pd = io.popen(pandoc_cmd, "w")
  pd:write(preamble)
  pd:write(s)
  local exit = pd:close()
  local ef = io.open(tmperr)
  local err = ef:read"all"
--  if err ~= "" then print(err) end
  ef:close()
  return exit and io.open(tmpout):read"all", (err ~= "") and err
end

function deverbify(s)
  s = replace("\\", "\\textbackslash ")(s)
  s = replace("&", "\\& ")(s)
  s = replace("_", "\\_ ")(s)
  s = replace("#", "\\# ")(s)
  s = replace("{", "\\{")(s)
  s = replace("}", "\\}")(s)
  return "\\texttt{" .. s .. "}"
end

function cs(s)
  return P("\\") * s * -Pletter * S(" \t")^0 * P"\n"^-1 * P(" ")^0 
end
function surrounded(l, r)
  if not r then r = l end
  return P(l) * C((1 - P(r))^0) * P(r)
end
Pletter = R'AZ' + R'az'
Pgroup = util.between_balanced("{", "}", "\\" * S"{}" + P(1))

----------------------------------------------------------------------
-- Read main parts of the book

local lpeg_add = getmetatable(P(1)).__add
local lpeg_mul = getmetatable(P(1)).__mul
function choice(p, q, ...)
  if q == nil then
    return P(p)
  else
    return choice(lpeg_add(p, q), ...)
  end
end
function sequence(p, q, ...)
  if q == nil then
    return P(p)
  else
    return sequence(lpeg_mul(p, q), ...)
  end
end
function map(fun, source)
  local target = {}
  for key, val in pairs(source) do
    local new_val, new_key = fun(key, val)
    if new_key == nil then
      new_key = key
    end
    target[new_key] = new_val
  end
  return target
end
local function format_args(args)
  if not args then return nil end
  local t = {}
  for i, arg in ipairs(args) do
    local l, r
    if arg.literal then
      l, r = "", ""
    elseif arg.delims == false then
      l, r = "〈", "〉"
    elseif arg.delims then
      l, r = arg.delims[1] or "{", arg.delims[2] or "}"
    else
      l, r = "{", "}"
    end
    if l == "" or r == "" then
      l, r = l .."⟨", "⟩" .. r
    end
    t[#t+1] = l .. (arg.literal or arg.meta or "#" .. i) .. r
  end
  return concat(t)
end

interesting_envs = {"key", "command", "stylekey", "shape"}
Pinteresting_envs = choice(unpack(interesting_envs))
Pitem = Cp()*P"\\begin{" * C(Pinteresting_envs) * P"}" * Pgroup
Pitems = Ct(search(Ct(Pitem))^0)
skipping_examples = surrounded("\\begin{codeexample}", "\\end{codeexample}") + 1

Penv = util.between_balanced("\\begin{"*Pinteresting_envs*"}"*Pgroup/0, "\\end{"*Pinteresting_envs*"}")
Penvs = Ct(search(Ct(Penv))^0)

items = map(function(i,v)return {},v end, interesting_envs)
result = map(function(i,v)return {},v end, interesting_envs)
excerpts = {}


for f in lfs.dir(arg[1] .. "doc/text-en") do
  if f:match("%.tex$") then
    local s = io.open(arg[1] .. "/doc/text-en/" .. f):read"all"
    for _, v in ipairs(Pitems:match(s)) do
      local text = Penv:match(s,v[1])
      items[v[2]][v[3]]=text

      if extract_text then
        text = replace(surrounded("|","|"), deverbify, skipping_examples)(text)
        text = replace(C(cs"tikz" * Pgroup), "[PICTURE]", skipping_examples)(text)
        text = replace(surrounded("\\tikz" * (1-Pletter), ";"), "[PICTURE]", skipping_examples)(text)
        text = replace("\\begin{codeexample}" * surrounded("[","]"), "\\begin{verbatim}")(text)
        text = replace("\\end{codeexample}", "\\end{verbatim}")(text)
        text = replace("\\" * C(P"begin" + "end") * "{" * Pinteresting_envs * "}", "\\%1{comment}")(text)
        local ntext, err = pandockify(text)
        --if not ntext then print(err) end
        if ntext and err then ntext = ntext .. "\n" .. err end
        if ntext then
          key = v[3]:gsub("\n", "")
          excerpts[key]=ntext
        end
      end
    end
  end
end

if extract_text then
  save_from_table('pgftext.lua', {data=excerpts})
else
  excerpts = load_into_table("pgftext.lua").data
end

--print(ser(excerpts))

white = S' \n\t%'
sentence_end = P(-1) + P'\n' + white^0 * (R'AZ' + P'\\begin')
first_sentence = white^0
  * C(search(
        '.' * #sentence_end)/0)

-- for _, things in pairs(items) do
--   for _, thing in pairs(things) do
--     local s = first_sentence:match(thing)
--     print (s)
--     --if not s then print(ser(thing))end
--     print'-------------'
--   end
-- end


-- treat commands

commands = {}

Poarg = Cg(Cc(true), "optional") * Cg(Cc({"[","]"}),"delims")
Pparg = Cg(Cc({"(",")"}),"delims")

sigpatt = "\\"*C((lpeg.alpha+'@')^1)*Ct(Ct(P" "^0 * choice(
  Cg(surrounded("\\opt{\\oarg{", "}}"), "meta") *Poarg,
  Cg(surrounded("{\\marg{", "}}"), "meta"),
  Cg(cs"oarg"*Pgroup, "meta") *Poarg,
  Cg("|(|"*cs"meta"*Pgroup*"|)|", "meta")*Pparg,
  Cg(surrounded("|", "|"), "literal"),
  Cg(C'=', "literal"),
  Cg(cs"marg"*Pgroup, "meta"),
  Cg(cs"meta"*Pgroup, "meta")))^0) 

for sig, text in pairs(items.command) do
  sig = util.clean("%"*S" \n"^0 + S" \n")(sig)
  sig = replace("{\\ttfamily\\char`\\\\}", "|\\|")(sig)
  sig = replace("{\\ttfamily\\char`\\}}", "|}|")(sig)
  sig = replace(surrounded("\\opt{", "}"), "%1")(sig)
  sig = replace("{\\ttfamily\\char`\\{}", "|{|")(sig)
  sig = replace("\\\\","")(sig)
  sig = replace("{}","")(sig)
  sig = replace(surrounded('(initially', ')'*P(-1)),"")(sig)
  local csname, args = sigpatt:match(sig)
  if not csname then print(sig)
  else
    --if args then print(csname .. format_args(args) .. "\n" .. sig .. "\n") end
    if csname then commands[csname] = {} end
    if args and #args>0 then commands[csname].arguments = args end
    commands[csname].documentation = "texdoc:generic/pgf/pgfmanual.pdf#pgf.<CS>" .. csname
    commands[csname].details = excerpts[sig:gsub("\n", "")]
    -- if not args then print(sig)end
  end
end

-- problematic commands:
-- \pgfsettransformnonlinearflatness\marg{dimension} 
-- \spy \oarg{options} |on| \meta{coordinate} \texttt{in node} \meta{node options}|;|
-- \pgfoosuper|(|\meta{class},\meta{object handle}|).|\meta{method name}|(|\meta{arguments}|)|
-- \rule|{|\meta{head}{\ttfamily->}\meta{body}|}|
-- \pgfmathdeclarerandomlist\marg{list name}\{\marg{item-1}\marg{item 2}...\}
-- \pgfextra \meta{code} \texttt{\char`endpgfextra}
-- \foreach| |\meta{variables}| |{\ttfamily[\meta{options}{\ttfamily]}}| in |\meta{list} \meta{commands}
-- \tikzmath\texttt{\\meta{statements}\texttt{\}}
-- \pgfsysanimkeyrepeat{number of times}
-- \pgfprofilesetrel\marg{profiler entry name} 

save_from_table('pgfcommands.lua', {commands=commands})

-- treat keys

for k,v in pairs(items.stylekey) do
  if items.key[k] then error(k..'don\'t do this!') end
  items.key[k]=v
end

keypatt = (
  C(gobble_until(P"=" + P' '^1 * "("))
    * (('=' * C(gobble_until(P' '^1 * (P"(init"+P'(defa'))))^-1 + Cc(nil))
    * (P' '^0 * P'('*C(gobble_until')'))^-1
)

keypatt = (
  C(gobble_until(P"=" + P' '^1 * "("))
    * (('=' * C(gobble_until(P' '^1 * P(-1))))^-1 + Cc(nil))
)


if make_keys then
keys = {}

for a,b in pairs(items.key) do
  local c = a
  a = replace(P'%\n', '')(a)
  a = replace(cs'space', ' ')(a)
  a = replace(cs'\\', ' ')(a)
  a = replace("\\char`\\}", "|}|")(a)
  a = replace("\\char`\\{", "|{|")(a)
  a = replace(surrounded("|","|"), deverbify)(a)
  a = replace(surrounded('(initially', ')'*P(-1)),"")(a)
  a = replace(surrounded('(default', ')'*P(-1)),"")(a)
  a = util.clean()(a)
  local k, v, rmk = keypatt:match(a)
  --  if rmk then print(k,v,rmk)end
  pandoc_cmd = "pandoc --wrap=none --verbose -f latex -t plain -o" .. tmpout .. " 2> " .. tmperr
  local w = {}
  if v then
    w.meta = trim(pandockify(v) or "??")
  end
  w.documentation = "texdoc:generic/pgf/pgfmanual.pdf#pgf." .. k:gsub(" ", ":")
  w.details = excerpts[c:gsub("\n", "")]
  keys[k] = w
end

save_from_table('pgfkeys.lua', {keys=keys})

else

keys = load_into_table('pgfkeys.lua').keys

end

tikzcommands = {
    coordinate = {} --[[max]],
    graph = {} --[[max]],
    matrix = {} --[[max]],
    node = {} --[[max]],
    nodepart = {} --[[max]],
    pic = {} --[[max]],
    scoped = {} --[[max]], p={},x={},y={},n={},chainin={}
}

tikzpathcommands = {
   path = {},
   clip = {} --[[max]],
   draw = {} --[[max]],
   graph={},
   datavisualization={},
   fill = {} --[[max]],
   filldraw = {} --[[max]],
   path = {} --[[max]],
   pattern = {} --[[max]],
   shade = {} --[[max]],
   shadedraw = {} --[[max]],
   useasboundingbox = {},
}

tikzenvironments={
   scope = {} --[[max]],
   tikzfadingfrompicture = {} --[[max]],
   tikzpicture = {} --[[max]]
}

tikz = {commands = {}, keys = {tikz ={}, ['data visualization'] ={}, ['graphs'] = {}}}
pgf = {commands = {}, keys = {pgf ={}}}

for k, _ in pairs(tikzcommands) do
  tikz.commands[k] = commands[k]
  commands[k] = nil
end
commands.graph={}
for k, _ in pairs(tikzpathcommands) do
  tikz.commands[k] = commands[k]
  commands[k] = nil
  tikz.commands[k].arguments = {{meta='options', delims={"[","]"}, optional=true},
    {meta="specification", delims={"", ";"}, optional = false}}
  tikz.commands[k].action = 'tikzpath'
end
for k, _ in pairs(commands) do
  if k:match'tikz' then
    tikz.commands[k] = commands[k]
    commands[k] = nil
  end
end
pgf.commands = commands

for k,v in pairs(keys) do
  if k:match'^/tikz/data visualization' then
    tikz.keys['data visualization'][k:gsub('^/tikz/data visualization/', '')] = v
    keys[k]=nil
  elseif k:match'^/tikz/graphs' then
    tikz.keys['graphs'][k:gsub('^/tikz/graphs/','')] = v
    keys[k]=nil
  elseif k:match'^/tikz' then
    tikz.keys['tikz'][k:gsub('/tikz/','')] = v
    keys[k]=nil
  elseif k:match'^/pgf' then
    pgf.keys.pgf[k:gsub('/pgf/','')] = v
    keys[k] = nil
  else
    print(k)
  end
end

for k,v in pairs(pgf.commands) do
  for _, v in ipairs(v.arguments or {}) do
    if v.meta == "options" then v.keys = "$DIGESTIFDATA/pgf/keys/pgf" end
  end
end

for k,v in pairs(tikz.commands) do
  for _, w in ipairs(v.arguments or {}) do
    if w.meta == "options" then w.keys = "$DIGESTIFDATA/tikz/keys/tikz";print(k) end
  end
end

tikz.commands.datavisualization.arguments[1].keys="$DIGESTIFDATA/tikz/keys/data visualization"
tikz.commands.tikzgraphsset.arguments[1].keys="$DIGESTIFDATA/tikz/keys/data visualization"
--tikz.commands.graph.arguments[1].keys="$DIGESTIFDATA/tikz/keys/data visualization"
  

save_from_table('tikz.lua', tikz)
save_from_table('pgf.lua', pgf)

os.remove(tmpout)
os.remove(tmperr)
