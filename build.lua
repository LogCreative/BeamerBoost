#!/usr/bin/env texlua

module           = "beamerboost"

-- Specify the main document.
mainfilename     = "beamer.tex"

typesetexe       = "pdflatex"
etypesetexe      = "etex"

typesetopts      = "-interaction=nonstopmode"

-- cache dir for frames
maindir          = "."
builddir         = maindir .. "/build"
cachedir         = builddir .. "/cache"

-- filename
headerfilename   = "header"
framefileprefix  = "frame"
psfilename       = "render"
mergefilename    = "merge"

-- Count the framenumber
framenumber      = -1

-- draft or not
draft            = false

function parseOption(line)
    local options = line:match("\\begin{frame}%[([,%s%a]*)%]")
    if options ~= nil then
        for option in options:gmatch("[^,%s]+") do
            print(option)
        end
    end
end

function expandFile(file)
    -- Since usually you cannot define frames directly normally.
    -- Expand the page command and include/input command directly.
    -- maketitle, partpage ...
end

function splitFile(file)
    -- Due to the capacity of lua on processing strings,
    -- The program is limited to the source code with proper line spliting.
    local inpreamble = true
    local inframe = false
    local headerfile = io.open(cachedir .. "/" .. headerfilename .. ".new.tex", "w")
    headerfile:write("\\RequirePackage[OT1]{fontenc}\n")       -- for beamer caching
    if draft then
        headerfile:write("\\PassOptionsToClass{draft}{beamer}\n")  -- for quick beamer previewing.
    end
    local framefile = nil
    local framepreamble = "" -- accumulated preamble
    for line in io.lines(file) do
        if line:find("\\begin{frame}") ~= nil then
            framenumber  = framenumber + 1
            inframe = true
            -- parseOption(line)
            framefile = io.open(cachedir .. "/" .. framefileprefix .. "." .. framenumber .. ".tex", "w")
            framefile:write("%&" .. headerfilename .. "\n")
            framefile:write("\\begin{document}\n")
            framefile:write(framepreamble)
            framefile:write(line .. "\n")

        elseif line:find("\\end{frame}") ~= nil then
            inframe = false
            framefile:write(line .. "\n")
            framefile:write("\\end{document}\n")
            framefile:close()
        elseif line:find("\\begin{document}") ~= nil then
            headerfile:write("\\begin{document}\n\\end{document}\n")
            headerfile:close()
            inpreamble = false
        else
            if inpreamble then
                headerfile:write(line .. "\n")
            elseif inframe then
                framefile:write(line .. "\n")
            elseif line:match("%s*\n") ~= nil then
                framepreamble = framepreamble .. line .. "\n"
            end
        end
    end
end

function compareFile(dir, old, new)
    -- Compare the old and new files.
    -- If the old file doesn't exist,
    -- then rename and return for recompiling.
    -- If they are same remove the new one,
    -- Otherwise, rename the new one to old name.

    if fileexists(dir .. "/" .. old) == false then
        ren(dir, new, old)
        return 1
    end

    local errorlevel = os.execute("cd " .. dir .. " && " .. os_diffexe .. " " .. normalize_path(old .. " " .. new))
    if errorlevel == 0 then
        rm(dir, new)
    else
        rm(dir, old)
        ren(dir, new, old)
    end
    return errorlevel
end

function precompile(file)
    local etypesetcommand = etypesetexe .. "  -ini -interaction=nonstopmode -jobname=" .. headerfilename .. " \"&" .. typesetexe .. "\" mylatexformat.ltx "

    -- Check if header is dirty.
    local errorlevel = compareFile(cachedir, headerfilename .. ".tex", headerfilename .. ".new.tex")

    if errorlevel ~= 0 then
        -- If dirty, recompile.
        errorlevel = tex("\"\"\"" .. headerfilename .. ".tex\"\"\"", cachedir, etypesetcommand)
        if errorlevel ~= 0 then
            print("! precompile header failed")
            return 2
        end
    else return errorlevel
    end
end

function dirtyFrames()
    local dirty = {}
    for i=0,framenumber do
        if compareFile(cachedir, framefileprefix .. i .. ".tex", framefileprefix .. "." .. i .. ".tex") ~= 0 then
            table.insert(dirty, i)
        end
    end
    return dirty
end

function renderFrames(dirty)
    -- Write Script to PowerShell for parallel rendering
    -- Or sequencial rendering without.
    
    local parallel = true

    -- Check whether pwsh exists.
    local errorlevel = os.execute("pwsh --version")
    if errorlevel ~= 0 then
        print("! PowerShell 7 is not installed or in PATH.")
        parallel = false
    end

    if parallel then
        psfile = io.open(cachedir .. "/" .. psfilename .. ".ps1", "w")
        psfile:write("#!/usr/bin/env pwsh\n")

        psfile:write(table.concat(dirty, ", ") .. " | ForEach-Object -Parallel {\n")
        psfile:write("\t" .. typesetexe .. " " .. framefileprefix .. "$_" .. ".tex" .. " " .. typesetopts .. "\n")
        psfile:write("}\n")
        
        psfile:close()

        errorlevel = os.execute("cd " .. cachedir .. " && pwsh -f " .. psfilename .. ".ps1")
    end

    return 0
end

function mergeFrames()
    local mergefile = io.open(cachedir .. "/" .. mergefilename .. ".tex", "w")
    mergefile:write("\\documentclass{article}\n")
    mergefile:write("\\usepackage{pdfpages}\n")
    mergefile:write("\\includepdfset{fitpaper=true,pages=1-last}\n")
    mergefile:write("\\begin{document}\n")
    for i=0,framenumber do
        mergefile:write("\\includepdf{" .. framefileprefix .. i .. ".pdf}\n")
    end
    mergefile:write("\\end{document}\n")
    mergefile:close()
    return tex(mergefilename, cachedir, typesetexe .. " " ..typesetopts)
end


-- Main function
function typeset_demo_tasks()
    if not direxists(cachedir) then
        mkdir(cachedir)
    end
    expandFile(mainfilename)
    splitFile(mainfilename)

    local errorlevel = precompile(headerfilename)
    if preelv == 2 then
        return 1
    end
    
    dirty = dirtyFrames()
    if errorlevel == 0 and #dirty == 0 then
        print(" Nothing to do.")
        return 0
    end

    errorlevel = renderFrames(dirty)
    if errorlevel ~= 0 then
        return errorlevel
    end

    errorlevel = mergeFrames()
    if errorlevel ~= 0 then
        return errorlevel
    end

    -- Copy file back to the main directory.
    local pdfname = mainfilename:gsub("%.tex$", ".pdf")
    cp(mergefilename .. ".pdf", cachedir, maindir)
    rm(maindir, pdfname)
    ren(maindir, mergefilename .. ".pdf", pdfname)

    return 0
end
