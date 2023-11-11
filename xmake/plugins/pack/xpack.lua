--!A cross-platform build utility based on Lua
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Copyright (C) 2015-present, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        xpack.lua
--

-- imports
import("core.base.object")
import("core.base.option")
import("core.base.hashset")
import("core.project.config")
import("core.project.project")
import("lib.detect.find_tool")

-- define module
local xpack = xpack or object {_init = {"_name", "_info"}}

-- get name
function xpack:name()
    return self._name
end

-- get value
function xpack:get(name)
    if self._info then
        return self._info:get(name)
    end
end

-- get the extra configuration
function xpack:extraconf(name, item, key)
    if self._info then
        return self._info:extraconf(name, item, key)
    end
end

-- get the package license
function xpack:license()
    return self:get("license")
end

-- get the package description
function xpack:description()
    return self:get("description")
end

-- get the platform of package
function xpack:plat()
    return config.get("plat") or os.subhost()
end

-- get the architecture of package
function xpack:arch()
    return config.get("arch") or os.subarch()
end

-- the current platform is belong to the given platforms?
function xpack:is_plat(...)
    local plat = self:plat()
    for _, v in ipairs(table.pack(...)) do
        if v and plat == v then
            return true
        end
    end
end

-- the current architecture is belong to the given architectures?
function xpack:is_arch(...)
    local arch = self:arch()
    for _, v in ipairs(table.pack(...)) do
        if v and arch:find("^" .. v:gsub("%-", "%%-") .. "$") then
            return true
        end
    end
end

-- get xxx_script
function xpack:script(name, generic)

    -- get script
    local script = self:get(name)
    local result = nil
    if type(script) == "function" then
        result = script
    elseif type(script) == "table" then

        -- get plat and arch
        local plat = self:plat()
        local arch = self:arch()

        -- match pattern
        --
        -- `@linux`
        -- `@linux|x86_64`
        -- `@macosx,linux`
        -- `android@macosx,linux`
        -- `android|armeabi-v7a@macosx,linux`
        -- `android|armeabi-v7a@macosx,linux|x86_64`
        -- `android|armeabi-v7a@linux|x86_64`
        --
        for _pattern, _script in pairs(script) do
            local hosts = {}
            local hosts_spec = false
            _pattern = _pattern:gsub("@(.+)", function (v)
                for _, host in ipairs(v:split(',')) do
                    hosts[host] = true
                    hosts_spec = true
                end
                return ""
            end)
            if not _pattern:startswith("__") and (not hosts_spec or hosts[os.subhost() .. '|' .. os.subarch()] or hosts[os.subhost()])
            and (_pattern:trim() == "" or (plat .. '|' .. arch):find('^' .. _pattern .. '$') or plat:find('^' .. _pattern .. '$')) then
                result = _script
                break
            end
        end

        -- get generic script
        result = result or script["__generic__"] or generic
    end

    -- only generic script
    return result or generic
end

-- get targets
function xpack:targets()
    local targets = self._targets
    if not targets then
        targets = {}
        local targetnames = self:get("targets")
        if targetnames then
            for _, name in ipairs(targetnames) do
                local target = project.target(name)
                if target then
                    table.insert(targets, target)
                else
                    raise("xpack(%s): target(%s) not found!", self:name(), name)
                end
            end
        end
        self._targets = targets
    end
    return targets
end

-- get formats
function xpack:formats()
    local formats = self._formats
    if not formats then
        formats = hashset.new()
        for _, format in ipairs(self:get("formats")) do
            formats:insert(format)
        end
        self._formats = formats
    end
    return formats
end

-- has the given format?
function xpack:format_has(...)
    local formats = self:formats()
    for _, v in ipairs(table.pack(...)) do
        if v and formats:has(v) then
            return true
        end
    end
end

-- set the current format
function xpack:format_set(format)
    self._FORMAT = format
end

-- get the current format
function xpack:format()
    return self._FORMAT
end

-- get the build directory
function xpack:buildir()
    return path.join(config.buildir(), ".xpack", self:name(), self:format())
end

-- get the output directory
function xpack:outputdir()
    local outputdir = option.get("outputdir")
    if outputdir == nil then
        outputdir = path.join(config.buildir(), "xpack", self:name(), self:format())
    end
    return outputdir
end

-- get the basename
function xpack:basename()
    return self:get("basename") or self:name()
end

-- get the spec variables
function xpack:specvars()
    local specvars = self._specvars
    if specvars == nil then
        specvars = {
            ARCH  = self:arch()
        ,   PLAT  = self:plat()
        ,   HOST  = os.host()
        ,   MODE  = config.get("mode") or "release"
        }

        -- get version
        local version, version_build = self:version()
        if version then
            specvars.VERSION = version
            try {function ()
                local v = semver.new(version)
                if v then
                    specvars.VERSION_MAJOR = v:major()
                    specvars.VERSION_MINOR = v:minor()
                    specvars.VERSION_ALTER = v:patch()
                end
            end}
            if version_build then
                specvars.VERSION_BUILD = version_build
            end
        end

        -- get git information
        local cmds =
        {
            GIT_TAG         = {"describe", "--tags"},
            GIT_TAG_LONG    = {"describe", "--tags", "--long"},
            GIT_BRANCH      = {"rev-parse", "--abbrev-ref", "HEAD"},
            GIT_COMMIT      = {"rev-parse", "--short", "HEAD"},
            GIT_COMMIT_LONG = {"rev-parse", "HEAD"},
            GIT_COMMIT_DATE = {"log", "-1", "--date=format:%Y%m%d%H%M%S", "--format=%ad"}
        }
        for name, argv in pairs(cmds) do
            specvars[name] = function ()
                local result
                local git = find_tool("git")
                if git then
                    result = try {function ()
                        return os.iorunv(git.program, argv)
                    end}
                end
                if not result then
                    result = "none"
                end
                return result:trim()
            end
        end

        -- get user variables
        local vars = self:get("specvar")
        if vars then
            table.join2(specvars, vars)
        end
        self._specvars = specvars
    end
    return specvars
end

-- get the specfile path
function xpack:specfile()
    local extensions = {
        nsis = ".nsi"
    }
    local extension = extensions[self:format()] or ".spec"
    return self:get("specfile") or path.join(self:buildir(), self:basename() .. extension)
end

-- get the output filename
function xpack:filename()
    local extensions = {
        nsis = ".exe"
    }
    local extension = extensions[self:format()] or ""
    return self:basename() .. extension
end

-- get the output file
function xpack:outputfile()
    return path.join(self:outputdir(), self:filename())
end

-- get the package version
function xpack:version()
    local version = self:get("version")
    local version_build
    if version == nil then
        for _, target in ipairs(self:targets()) do
            version, version_build = target:version()
            if version then
                break
            end
        end
        if version == nil then
            version, version_build = project.version()
        end
    else
        version_build = self:extraconf("version", version, "build")
        if type(version_build) == "string" then
            version_build = os.date(version_build, os.time())
        end
    end
    return version, version_build
end

-- new a xpack
function _new(name, info)
    return xpack {name, info}
end

-- get xpack packages
function packages()
    local packages = _g.packages
    if not packages then
        packages = {}
        local packages_need = option.get("packages")
        if packages_need then
            packages_need = hashset.from(packages_need)
        end
        local formats_need = option.get("formats")
        if formats_need then
            formats_need = formats_need:split(",")
            if formats_need[1] == "all" then
                formats_need = nil
            end
        end
        local xpack_scope = project.scope("xpack")
        for name, scope in pairs(xpack_scope) do
            local need = false
            if packages_need then
                if packages_need:has(name) then
                    need = true
                end
            else
                need = true
            end
            if need then
                local instance = _new(name, scope)
                if not formats_need or instance:format_has(table.unpack(formats_need)) then
                    packages[name] = instance
                end
            end
        end
        _g.packages = packages
    end
    return packages
end

-- get the given package
function package(name)
    return packages()[name]
end
