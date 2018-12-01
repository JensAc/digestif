local lpeg = require "lpeg"
local util = require "digestif.util"

local P = lpeg.P
local C, Cc = lpeg.C, lpeg.Cc

local DATA_DIR = util.config.data_dir

local data = {loaded = {}}

local token = P(1)
local xparse_patt = (P" "^0 * P"+"^-1 *
   (  "m" * Cc{optional = false}
    + "r" * C(token) * C(token)
          / function (tok1, tok2) return {delims = {tok1, tok2}} end
    + "u{"* C((token - "}")^0) * "}"
          / function (toks) return {delims = {"", toks}} end
    + "v" * Cc{type = "verbatim"}
    + "o" * Cc{optional = true, delims = {"[", "]"}}
    + "d" * C(token) * C(token)
          / function (tok1, tok2) return {optonal = true, delims = {tok1, tok2}} end
    + "s" * Cc{type = "literal", literal = "*", optional = true, delims = false}
    + "t" * C(token)
          / function (tok) return {type = "literal", literal = tok, optional = true} end
    + "g" * Cc{optional = true, delims = {"{", "}"}}))^0

function data.signature(sig, ...)
   local args = {...}
   for i, arg in ipairs({xparse_patt:match(sig)}) do
      if type(args[i]) ~= "table" then
         args[i] = {meta = args[i] or "#" .. i}
      end
      util.update(args[i], arg)
   end
   return args
end

local load_env = {merge = util.merge, data = data, signature = data.signature}

function data.load_data(name)
   if type(name) ~= "string" then return nil end
   -- need to check this forms a reasonable file name
   name = util.path_join(DATA_DIR, name .. ".lua")
   local f = io.open(name)
   local result, err
   if f then
      result, err = util.eval_with_env(f:read("*all"), load_env)
      f:close()
      if not result then util.log(err) end
   end
   data.loaded[name] = result
   return result
end

local function get_data(_, name)
   return data.loaded[name] or data.load_data(name)
end

return setmetatable(data, {__call = get_data})
