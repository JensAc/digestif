package = "digestif"
version = "scm-1"
source = {
   url = "git://github.com/astoff/digestif",
   branch = "master"
}
description = {
   summary = "Code analyzer for TeX.",
   detailed = [[
      A code analyzer for LaTeX documents (and eventually perhaps also
      plain TeX and ConTeXt).  It includes a Language Server Protocol
      implementation, so it can run on many different text editors.
    ]],
   homepage = "https://github.com/astoff/digestif/",
   license = "MIT"
}
dependencies = {
   "lua >= 5.3",
   "lpeg >= 1.0",
   "dkjson >= 2.1.0",
}

build = {
   type = "builtin",
   modules = {
      ["digestif.FileCache"] = "digestif/FileCache.lua",
      ["digestif.Manuscript"] = "digestif/Manuscript.lua",
      ["digestif.ManuscriptLaTeX"] = "digestif/ManuscriptLaTeX.lua",
      ["digestif.Parser"] = "digestif/Parser.lua",
      ["digestif.config"] = "digestif/config.lua",
      ["digestif.data"] = "digestif/data.lua",
      ["digestif.langserver"] = "digestif/langserver.lua",
      ["digestif.util"] = "digestif/util.lua",
   },
   copy_directories = {
      "digestif-data"
   },
   install = {
      bin = {
         ["digestif"] = "bin/digestif.lua"
      }
   }
}
