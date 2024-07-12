####
## Issues
Offending DLL files in the <install directory>\bin\win64\ directory
libgit2.dll
libssh2.dll

They were renamed to *.backup files, then Mex.jl was re-built, which allows Mex to run successfully.

Renaming these DLL files requires administrator privileges, so this is not a viable solution for corporate IT environments.
######


import Libdl

# the following functions are adapted from the julia-config.jl script and are used to
# determine parameters for the Mex file build process

isDebug() = ccall(:jl_is_debugbuild, Cint, ()) != 0

function shell_escape(str)
    str = replace(str, "'" => "'\''")
    return "\"$str\""
end

function matlab_escape(str)
    str = replace(str, "'" => "''")
    return "'$str'"
end

function libDir()
    return if isDebug() != 0
        dirname(abspath(Libdl.dlpath("libjulia-debug")))
    else
        dirname(abspath(Libdl.dlpath("libjulia")))
    end
end

private_libDir() = abspath(Sys.BINDIR, Base.PRIVATE_LIBDIR)

function includeDir()
    return abspath(Sys.BINDIR, Base.INCLUDEDIR, "julia")
end

function ldflags()
    fl = "-L$(shell_escape(libDir()))"
    if Sys.isunix()
        fl = fl * " -Wl,-rpath $(shell_escape(libDir()))"
    end
    return fl
end
    
function ldlibs()
    libname = if isDebug()
        "julia-debug"
    else
        "julia"
    end
    if Sys.isunix()
        return "-l$libname -ldl"
    else
        return "\'$(normpath(joinpath(libDir(), "..", "lib", "lib$libname.dll.a")))\'"
    end
end
    
function cflags()
    fl = "-I $(shell_escape(includeDir()))"
    if Sys.isunix()
        fl = fl * " -fPIC"
    end
    return fl
end

# the following two functions are taken from the MATLAB.jl build script and are used to
# locate MATLAB and its relevant libraries and commands

function find_matlab_root()
    # Determine MATLAB library path and provide facilities to load libraries with this path
    matlab_root = get(ENV, "MATLAB_ROOT",
                        get(ENV, "MATLAB_HOME", nothing))
    if isnothing(matlab_root)
        matlab_exe = Sys.which("matlab")
        if !isnothing(matlab_exe)
            matlab_exe = islink(matlab_exe) ? readlink(matlab_exe) : matlab_exe
            matlab_root = dirname(dirname(matlab_exe))
        else
            if Sys.isapple()
                default_dir = "/Applications"
                if isdir(default_dir)
                    dirs = readdir(default_dir)
                    filter!(app -> occursin(r"^MATLAB_R[0-9]+[ab]\.app$", app), dirs)
                    if !isempty(dirs)
                        matlab_root = joinpath(default_dir, maximum(dirs))
                    end
                end
            elseif Sys.iswindows()
                default_dir = Sys.WORD_SIZE == 32 ? "C:\\Program Files (x86)\\MATLAB" : "C:\\Program Files\\MATLAB"
                if isdir(default_dir)
                    dirs = readdir(default_dir)
                    filter!(dir -> occursin(r"^R[0-9]+[ab]$", dir), dirs)
                    if !isempty(dirs)
                        matlab_root = joinpath(default_dir, maximum(dirs))
                    end
                end
            elseif Sys.islinux()
                default_dir = "/usr/local/MATLAB"
                if isdir(default_dir)
                    dirs = readdir(default_dir)
                    filter!(dir -> occursin(r"^R[0-9]+[ab]$", dir), dirs)
                    if !isempty(dirs)
                        matlab_root = joinpath(default_dir, maximum(dirs))
                    end
                end
            end
        end
    end
    !isnothing(matlab_root) && isdir(matlab_root) && @info("Detected MATLAB root folder at \"$matlab_root\"")
    return matlab_root
end

function find_matlab_cmd(matlab_root)
    if Sys.iswindows()
        matlab_cmd = joinpath(matlab_root, "bin", (Sys.WORD_SIZE == 32 ? "win32" : "win64"), "matlab.exe")
        isfile(matlab_cmd) && @info("Detected MATLAB executable at \"$matlab_cmd\"")
    else
        matlab_exe = joinpath(matlab_root, "bin", "matlab")
        isfile(matlab_exe) && @info("Detected MATLAB executable at \"$matlab_exe\"")
        matlab_cmd = "$(Base.shell_escape(matlab_exe))"
    end
    return matlab_cmd
end

function mex_extension()
    if Sys.islinux()
        ext = ".mexa64"
    elseif Sys.isapple()
        ext = ".mexmaci64"
    elseif Sys.iswindows()
        ext = ".mexw"*string(Sys.WORD_SIZE)
    end
    return ext
end

is_ci() = lowercase(get(ENV, "CI", "false")) == "true"

# find matlab root
matlab_root = find_matlab_root()

if !isnothing(matlab_root)

    # get matlab command
    matlab_cmd = find_matlab_cmd(matlab_root)

    # get build parameters
    is_debug = isDebug()
    julia_bin = is_debug ?
        joinpath(unsafe_string(Base.JLOptions().julia_bindir), "julia-debug") :
        joinpath(unsafe_string(Base.JLOptions().julia_bindir), "julia")
    julia_home = unsafe_string(Base.JLOptions().julia_bindir)
    sys_image = unsafe_string(Base.JLOptions().image_file)
    lib_base = is_debug ? "julia-debug" : "julia"
    lib_path = Libdl.dlpath("lib$lib_base")
    lib_dir = Sys.iswindows() ? joinpath(dirname(julia_home), "lib") : dirname(lib_path)
    inc_dir = includeDir()
    build_cflags = cflags()
    build_ldflags = ldflags()
    build_ldlibs = ldlibs()
    build_src = abspath("mexjulia.cpp")
    outdir = normpath(joinpath(pwd(),"..","mexjulia"))
    mex_cmd = "mex -v -largeArrayDims -outdir \'$outdir\' LDFLAGS=\'$(build_ldflags) \$LDFLAGS\' CFLAGS=\'$(build_cflags) \$CFLAGS\' \'$(build_src)\' $(build_ldlibs)"

    # generate Mex-file build script
    dict_file = joinpath(outdir, "jldict.mat")
    build_file = joinpath(pwd(), "build.m")

    open(build_file, "w") do io
        println(io,
            """
            % This file is automatically generated, do not edit.

            % Save build parameters to a .mat file
            is_debug = $is_debug;
            julia_bin = $(matlab_escape(julia_bin));
            julia_home = $(matlab_escape(julia_home));
            sys_image = $(matlab_escape(sys_image));
            lib_base = $(matlab_escape(lib_base));
            lib_path = $(matlab_escape(lib_path));
            lib_dir = $(matlab_escape(lib_dir));
            inc_dir = $(matlab_escape(inc_dir));
            build_cflags = $(matlab_escape(build_cflags));
            build_ldflags = $(matlab_escape(build_ldflags));
            build_ldlibs = $(matlab_escape(build_ldlibs));
            build_src = $(matlab_escape(build_src));
            mex_cmd = $(matlab_escape(mex_cmd));
            save($(matlab_escape(dict_file)), "is_debug", "julia_bin", "julia_home",...
                "sys_image", "lib_base", "lib_path", "lib_dir", "inc_dir", "build_cflags",...
                "build_ldflags", "build_ldlibs", "build_src", "mex_cmd");

            % Run Mex Command
            $mex_cmd;

            """
        )

        if !is_ci()
            println(io,
                """
                % Check if the `mexjulia` directory is already on the path
                path_dirs = regexp(path, pathsep, 'split');
                if ispc
                    on_path = any(strcmpi($(matlab_escape(outdir)), path_dirs));
                else
                    on_path = any(strcmp($(matlab_escape(outdir)), path_dirs));
                end

                % Add the `mexjulia` directory to the path and save the path (if necessary)
                if ~on_path
                    fprintf('%s is not on the MATLAB path. Adding it and saving...\\n\', $(matlab_escape(outdir)));
                    path($(matlab_escape(outdir)), path);
                    savepath;
                end
                """
            )
        end
    end

    # We have to run the build script separately for CI due to licensing issues
    if !is_ci()

        # run the Mex-file build script
        run(`$matlab_cmd -nodesktop -nosplash -r "run('$build_file');exit"`)

        # check that the build information has been saved in the mexjulia directory
        @assert isfile(joinpath(outdir, "jldict.mat"))

        # check that the compiled mexjulia file has been saved in the mexjulia directory
        @assert isfile(joinpath(outdir, "mexjulia" * mex_extension()))

    end

elseif get(ENV, "JULIA_REGISTRYCI_AUTOMERGE", nothing) == "true"
    # We need to be able to install and load this package without error for
    # Julia's registry AutoMerge to work, so we just skip the mex file build process.
else
    error("MATLAB cannot be found. Set the \"MATLAB_ROOT\" environment variable to the MATLAB root directory and re-run Pkg.build(\"Mex\").")
end
