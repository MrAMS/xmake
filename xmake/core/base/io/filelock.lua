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
-- Copyright (C) 2015 - 2019, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        filelock.lua
--

-- define module
local io        = io or {}
local _filelock = _filelock or {}

-- load modules
local path   = require("base/path")
local table  = require("base/table")
local string = require("base/string")

-- new a filelock
function _filelock.new(lockpath, lock)
    local filelock = table.inherit(_filelock)
    filelock._NAME = path.filename(lockpath)
    filelock._PATH = path.absolute(lockpath)
    filelock._LOCK = lock
    filelock._LOCKED_NUM = 0
    setmetatable(filelock, _filelock)
    return filelock
end

-- get the filelock name 
function _filelock:name()
    return self._NAME
end

-- get the filelock path 
function _filelock:path()
    return self._PATH
end

-- is locked?
function _filelock:islocked()
    return self._LOCKED_NUM > 0
end

-- lock file
--
-- @param opt       the argument option, {shared = true}
--
-- @return          ok, errors
--
function _filelock:lock(opt)

    -- ensure opened
    local ok, errors = self:_ensure_opened()
    if not ok then
        return false, errors
    end

    -- lock it
    if self._LOCKED_NUM > 0 or io.filelock_lock(self._LOCK, opt) then
        self._LOCKED_NUM = self._LOCKED_NUM + 1
        return true
    else
        return false, string.format("%s: lock failed!", self)
    end
end

-- try to lock file
--
-- @param opt       the argument option, {shared = true}
--
-- @return          ok, errors
--
function _filelock:trylock(opt)

    -- ensure opened
    local ok, errors = self:_ensure_opened()
    if not ok then
        return false, errors
    end

    -- unlock it
    if self._LOCKED_NUM > 0 or io.filelock_trylock(self._LOCK, opt) then
        self._LOCKED_NUM = self._LOCKED_NUM + 1
        return true
    else
        return false, string.format("%s: trylock failed!", self)
    end
end

-- unlock file
function _filelock:unlock(opt)

    -- ensure opened
    local ok, errors = self:_ensure_opened()
    if not ok then
        return false, errors
    end

    -- unlock it
    if self._LOCKED_NUM > 1 or (self._LOCKED_NUM > 0 and io.filelock_unlock(self._LOCK)) then
        if self._LOCKED_NUM > 0 then
            self._LOCKED_NUM = self._LOCKED_NUM - 1
        else 
            self._LOCKED_NUM = 0
        end
        return true
    else
        return false, string.format("%s: unlock failed!", self)
    end
end

-- close filelock
function _filelock:close()

    -- ensure opened
    local ok, errors = self:_ensure_opened()
    if not ok then
        return false, errors
    end

    -- close filelock
    ok = io.filelock_close(self._LOCK)
    if ok then
        self._LOCK = nil
        self._LOCKED_NUM = 0
    end
    return ok
end

-- ensure the filelock is opened
function _filelock:_ensure_opened()
    if not self._LOCK then
        return false, string.format("%s: has been closed!", self)
    end
    return true
end

-- tostring(filelock)
function _filelock:__tostring()
    local name = self:path()
    if not name or #name > 16 then
        name = self:name()
    end
    return "<filelock: " .. name .. ">"
end

-- gc(filelock)
function _filelock:__gc()
    if self._LOCK and io.filelock_close(self._LOCK) then
        self._LOCK = nil
        self._LOCKED_NUM = 0
    end
end

-- open a filelock
function io.openlock(filepath)

    -- check
    assert(filepath)

    -- open it
    local lock = io.filelock_open(filepath)
    if lock then
        return _filelock.new(filepath, lock)
    else
        return nil, string.format("failed to open lock: %s", filepath)
    end
end

