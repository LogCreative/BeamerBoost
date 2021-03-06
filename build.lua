#!/usr/bin/env texlua

module           = "beamerboost"

-------------------CONFIGURATION----------------------

-- Specify the main document.
mainfilename     = "beamer.tex"

-- cache dir for frames
-- If you don't depend on a relative path,
-- you could change to another cache directory.

maindir          = "."
-- builddir         = maindir .. "/build"
-- cachedir         = builddir .. "/cache"
cachedir         = "."

-- draft or not               : disable for no numbering
draft            = false
-- total frame number or not  : disable for less changes
totalframe       = false

-- parallel or not            : enable with PowerShell 7
parallel         = true
-- Second pass or not         : enable for TOC rendering
secondpass       = true

------------------------------------------------------

if draft or secondpass then
    totalframe   = false
end

typesetexe       = "pdflatex"
etypesetexe      = "etex"

typesetopts      = "-interaction=nonstopmode"

-- filename
expandedfilename = "expanded"
expandedinputfilename = "expanded.input"
headerfilename   = "header"
framefileprefix  = "frame"
psfilename       = "render"
mergefilename    = "merge"

-- Count the framenumber
framenumber      = -1
totalframenumber = 0

-- l3build clean files
cleanfiles       = {
    expandedfilename .. ".tex",
    headerfilename .. ".tex",
    headerfilename .. ".fmt",
    headerfilename .. ".pdf",
    framefileprefix .. "*.tex",
    framefileprefix .. "*.pdf",
    mergefilename .. ".tex",
    psfilename .. ".ps1",
    "*.dvi",
    "*.fdb_latexmk",
    "*.fls",
    "*.log"
}

-- TODO: Consider use native LaTeX beamer machnism for expanding file.
-- TOOD: Consider tikz externalize like to detect the change.

-- To avoid competing on file I/O
-- close the file before calling the next function
-- then open it with 'a' mode
expandedinputfile = nil

-- Save the code between frames
betweenframes = {}

function expandingFile(file, inpreamble, includeonly, isincludeonly)
    if expandedinputfile == nil then
        expandedinputfile = io.open(cachedir .. "/" .. expandedinputfilename .. ".tex", "w")
    else
        expandedinputfile = io.open(cachedir .. "/" .. expandedinputfilename .. ".tex", "a")
    end

    for line in io.lines(file) do
        if line:find("\\begin{document}") then
            inpreamble = false
        end
        
        local newincludeonly = nil
        if isincludeonly then
            includeonly = includeonly .. line:gsub("%s", ""):gsub("}.*", "") .. ","
            if line:find("}") ~= nil then
                isincludeonly = false
                line = "" -- manually clear
            end
        else
            newincludeonly = line:match("\\includeonly{([^}]*)")
            if newincludeonly ~= nil then
                if includeonly == nil then
                    includeonly = newincludeonly
                else
                    includeonly = includeonly .. newincludeonly
                end
                if inpreamble then
                    if line:find("}") == nil then
                        isincludeonly = true  -- not closed
                    else
                        includeonly = includeonly .. ","
                    end
                else
                    print("! You can only use \\includeonly in preamble")
                    return 1
                end
            end
        end

        function expandFileInput(file)
            expandedinputfile:close()
            expandingFile(file, inpreamble, includeonly, isincludeonly)
            expandedinputfile = io.open(cachedir .. "/" .. expandedinputfilename .. ".tex", "a")
        end

        local fileinput = line:match("\\input{([^}]*)}")
        if fileinput ~= nil then
            if fileinput:find("%.") == nil then
                fileinput = fileinput .. ".tex"
            end
            expandFileInput(fileinput)
        end

        -- TODO: nested include is not allowed
        local fileinclude = line:match("\\include{([^}]*)}")
        if fileinclude ~= nil then
            if includeonly ~= nil then
                if includeonly:find(fileinclude .. ",") ~= nil then
                    if fileinclude:find("%.") == nil then
                        fileinclude = fileinclude .. ".tex"
                    end
                    expandFileInput(fileinclude)
                else
                    print("- " .. fileinclude .. " is not included")
                end
            end
        end

        if fileinput == nil and fileinclude == nil and newincludeonly == nil and isincludeonly == false then
            expandedinputfile:write(line .. "\n")
        end
    end
    expandedinputfile:close()
    return 0
end

function expandFile(file)
    -- Only process \include, \input, \includeonly
    local inpreamble = true
    local includeonly = nil
    local isincludeonly = false
    local errorlevel = expandingFile(file, inpreamble, includeonly, isincludeonly)
    if errorlevel ~= 0 then
        print("! expand " .. file .. " failed")
        return errorlevel
    end
    expandFrame(cachedir .. '/' .. expandedinputfilename .. ".tex")
    return 0
end

function expandFrame(file)

    local inpreamble = true

    local atbeginpart = ""
    local isatbeginpart = false
    local atbeginsection = ""
    local isatbeginsection = false
    local atbeginsubsection = ""
    local isatbeginsubsection = false
    local atbeginsubsubsection = ""
    local isatbeginsubsubsection = false

    local expandedfile = io.open(cachedir .. "/" .. expandedfilename .. ".tex", "w")
    for line in io.lines(file) do
        if line:sub(1, 1) ~= "%" then
            line = line:gsub("([^\\])%%.*", "%1")
            if inpreamble then
                if line:find("\\begin{document}") then
                    inpreamble = false
                    expandedfile:write(line .. "\n")
                elseif isatbeginpart then
                    if line:gsub("%s","") == "}" then
                        isatbeginpart = false
                    else
                        atbeginpart = atbeginpart .. line .. "\n"
                    end
                elseif line:find("\\AtBeginPart") ~= nil then
                    atbeginpart = ""
                    isatbeginpart = true
                elseif isatbeginsection then
                    if line:gsub("%s","") == "}" then
                        isatbeginsection = false
                    else
                        atbeginsection = atbeginsection .. line .. "\n"
                    end
                elseif line:find("\\AtBeginSection") ~= nil then
                    atbeginsection = ""
                    isatbeginsection = true
                elseif isatbeginsubsection then
                    if line:gsub("%s","") == "}" then
                        isatbeginsubsection = false
                    else
                        atbeginsubsection = atbeginsubsection .. line .. "\n"
                    end
                elseif line:find("\\AtBeginSubsection") ~= nil then
                    atbeginsubsection = ""
                    isatbeginsubsection = true
                elseif isatbeginsubsubsection then
                    if line:gsub("%s","") == "}" then
                        isatbeginsubsubsection = false
                    else
                        atbeginsubsubsection = atbeginsubsubsection .. line .. "\n"
                    end
                elseif line:find("\\AtBeginSubsubsection") ~= nil then
                    atbeginsubsubsection = ""
                    isatbeginsubsubsection = true
                else
                    expandedfile:write(line .. "\n")
                end
            else
                if line:find("\\maketitle") ~= nil then
                    expandedfile:write("\\begin{frame}\n\\titlepage\n\\end{frame}\n")
                elseif line:find("\\part{") then
                    expandedfile:write(line .. "\n")
                    expandedfile:write(atbeginpart)
                elseif line:find("\\section{") then
                    expandedfile:write(line .. "\n")
                    expandedfile:write(atbeginsection)
                elseif line:find("\\subsection{") then
                    expandedfile:write(line .. "\n")
                    expandedfile:write(atbeginsubsection)
                elseif line:find("\\subsubsection{") then
                    expandedfile:write(line .. "\n")
                    expandedfile:write(atbeginsubsubsection)
                else
                    expandedfile:write(line .. "\n")
                end
            end
        end
    end
    expandedfile:close()

    -- Count the total framenumber and save the preamble.
    local inpreamble = true
    local inframe = false

    for line in io.lines(cachedir .. "/" .. expandedfilename .. ".tex") do
        if inpreamble == false and line:find("\\begin{frame}") ~= nil then
            inframe = true
            totalframenumber = totalframenumber + 1
        elseif inpreamble == false and line:find("\\end{frame}") ~= nil then
            inframe = false
        elseif inpreamble and line:find("\\begin{document}") ~= nil then
            inpreamble = false
        else
            lineenter = line .. "\n"
            if inpreamble == false and inframe == false and lineenter ~= "\n" and lineenter:match("%s*\n") ~= nil then
                table.insert(betweenframes,line)
            end
        end
    end
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
    local betweenpast = 1
    local framepreamble = "" -- accumulated preamble
    for line in io.lines(file) do
        if inpreamble == false and line:find("\\begin{frame}") ~= nil then
            framenumber  = framenumber + 1
            inframe = true
            framefile = io.open(cachedir .. "/" .. framefileprefix .. "." .. framenumber .. ".tex", "w")
            framefile:write("%&" .. headerfilename .. "\n")
            framefile:write("\\begin{document}\n")
            framefile:write(framepreamble)
            framefile:write("\\setcounter{framenumber}{" .. framenumber .. "}\n")
            if totalframe then
                framefile:write("\\gdef\\inserttotalframenumber{" .. totalframenumber ..  "}\n")
            else
                framefile:write("\\gdef\\inserttotalframenumber{?}\n")
            end
            
            framefile:write(line .. "\n")

        elseif inpreamble == false and line:find("\\end{frame}") ~= nil then
            inframe = false
            framefile:write(line .. "\n")
            for i=betweenpast,#betweenframes do
                framefile:write(betweenframes[i] .. "\n")
            end
            framefile:close()
        elseif inpreamble and line:find("\\begin{document}") ~= nil then
            headerfile:write("\\AtBeginPart{}\n\\AtBeginSection{}\n\\AtBeginSubsection{}\n") -- Override the original automatic definitions on sectioning appending.
            headerfile:write("\\begin{document}\n\\end{document}\n")
            headerfile:close()
            inpreamble = false
        else
            if inpreamble then
                headerfile:write(line .. "\n")
            elseif inframe then
                framefile:write(line .. "\n")
            else
                line = line .. "\n"
                if line ~= "\n" and line:match("%s*\n") ~= nil then
                    framepreamble = framepreamble .. line
                    betweenpast = betweenpast + 1
                end
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
        local errlv = tex("\"\"\"" .. headerfilename .. ".tex\"\"\"", cachedir, etypesetcommand)
        if errlv ~= 0 then
            print("! precompile header failed")
            return 2
        end
        return errorlevel
    else return errorlevel
    end
end

function cleanExtraFrames()
    local extra = framenumber + 1
    local errorlevel = 0
    while fileexists(cachedir .. "/" .. framefileprefix .. extra .. ".tex") do
        rm(cachedir, framefileprefix .. extra .. ".tex")
        rm(cachedir, framefileprefix .. extra .. ".pdf")
        extra = extra + 1
        errorlevel = 1 -- Has less files.
    end
    return errorlevel
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

    if parallel then
        -- Check whether pwsh exists.
        local errorlevel = os.execute("pwsh --version")
        if errorlevel ~= 0 then
            print("! PowerShell 7 is not installed or in PATH.")
            parallel = false
        end 
    end

    if parallel then

        psfile = io.open(cachedir .. "/" .. psfilename .. ".ps1", "w")
        psfile:write("#!/usr/bin/env pwsh\n")

        psfile:write(table.concat(dirty, ", ") .. " | ForEach-Object -Parallel {\n")
        psfile:write("\t" .. typesetexe .. " " .. framefileprefix .. "$_" .. ".tex" .. " " .. typesetopts .. "\n")
        if secondpass then
            psfile:write("\t" .. typesetexe .. " " .. framefileprefix .. "$_" .. ".tex" .. " " .. typesetopts .. "\n")
        end
        psfile:write("}\n")
        
        psfile:close()

        return os.execute("cd " .. cachedir .. " && pwsh -f " .. psfilename .. ".ps1")
    else
        for _,v in ipairs(dirty) do
            errorlevel = run(cachedir, typesetexe .. " " .. framefileprefix .. v .. ".tex " .. typesetopts)
            if secondpass then
                errorlevel = run(cachedir, typesetexe .. " " .. framefileprefix .. v .. ".tex " .. typesetopts)
            end
            if errorlevel ~= 0 then
                print("! render frame " .. v .. " failed")
                return 1
            end
        end
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

    local starttime = os.time()

    if not direxists(cachedir) then
        mkdir(cachedir)
    end
    
    local errorlevel = expandFile(maindir .. "/" .. mainfilename)
    if errorlevel ~= 0 then
        return errorlevel
    end

    splitFile(cachedir .. "/" .. expandedfilename .. ".tex")

    errorlevel = precompile(headerfilename)
    if errorlevel == 2 then
        return 1
    end
    
    local lessframelv = cleanExtraFrames()

    local dirty = dirtyFrames()
    if errorlevel ~= 0 then
        dirty = {}
        for i=0, framenumber do
            table.insert(dirty,i)  -- All restart since header is changed.
        end
        print(' header changing causes a full restart.')
    elseif #dirty == 0 then
        print(" No dirty frames.")
        if lessframelv == 0 then
            print(" Nothing to do.")
            return 0
        end
    end
    
    errorlevel = renderFrames(dirty)
    if errorlevel ~= 0 then
        -- clean frames and pdfs
        rm(cachedir, framefileprefix .. "*.tex")
        rm(cachedir, framefileprefix .. "*.pdf")
        return errorlevel
    end

    local framerenderedtime = os.time()
    
    if #dirty > 0 or lessframelv ~= 0 then
        errorlevel = mergeFrames()
        if errorlevel ~= 0 then
            return errorlevel
        end

        -- Copy file back to the main directory.
        local pdfname = mainfilename:gsub("%.tex$", ".pdf")
        if cachedir ~= maindir then
            cp(mergefilename .. ".pdf", cachedir, maindir) 
        end
        rm(maindir, pdfname)
        ren(maindir, mergefilename .. ".pdf", pdfname)
    end

    -- Clean up
    cleansuffixs = {
        ".aux",
        ".log",
        ".nav",
        ".snm",
        ".toc",
        ".vrb",
        ".out"
    }
    for _, suffix in ipairs(cleansuffixs) do
        rm(cachedir, "*" .. suffix)
    end

    local finishedtime = os.time()

    print("Frame rendering finished at (s): " .. framerenderedtime - starttime)
    print("Merge finished at (s): " .. finishedtime - starttime)

    return 0
end
