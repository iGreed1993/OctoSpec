-- OctoSpec
-- Events, slash commands, import/export, saved builds
OctoSpec = OctoSpec or {}

function OctoSpec.CharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName and GetRealmName() or "Realm"
    return realm .. "-" .. name
end

-- Per-character build table (this class defaults + this character's saves only)
function OctoSpec.GetCharBuilds()
    if not OctoSpecDB then return {} end
    if not OctoSpecDB.charBuilds then OctoSpecDB.charBuilds = {} end
    local key = OctoSpec.CharKey()
    if not OctoSpecDB.charBuilds[key] then
        OctoSpecDB.charBuilds[key] = {}
    end
    return OctoSpecDB.charBuilds[key]
end

-- One-time: copy class-matching entries from old account-wide OctoSpecDB.builds
function OctoSpec.MigrateLegacyBuilds()
    if not OctoSpecDB or not OctoSpecDB.builds then return end
    if not OctoSpecDB._legacyBuildMigrated then
        OctoSpecDB._legacyBuildMigrated = {}
    end
    local key = OctoSpec.CharKey()
    if OctoSpecDB._legacyBuildMigrated[key] then return end
    OctoSpecDB._legacyBuildMigrated[key] = true

    local class = UnitClass("player")
    if not class then return end
    local builds = OctoSpec.GetCharBuilds()
    local moved = 0
    for name, data in pairs(OctoSpecDB.builds) do
        if type(data) == "table" and not builds[name] then
            local matches = false
            if data.class and data.class == class then
                matches = true
            elseif data.isDefault and OctoSpecDefaultBuilds and OctoSpecDefaultBuilds[class] and OctoSpecDefaultBuilds[class][name] then
                matches = true
            end
            if matches then
                builds[name] = {
                    points = data.points or "",
                    primaryTree = data.primaryTree or 0,
                    priority = data.priority or {},
                    class = class,
                    isDefault = data.isDefault and true or false,
                }
                moved = moved + 1
            end
        end
    end
    if moved > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Migrated " .. moved .. " build(s) for this character from the old shared list.")
    end
end


local function InitDB()
    if not OctoSpecDB then
        OctoSpecDB = {}
    end
    if OctoSpecDefaults then
        for k, v in pairs(OctoSpecDefaults) do
            if OctoSpecDB[k] == nil then
                if type(v) == "table" then
                    OctoSpecDB[k] = {}
                    for kk, vv in pairs(v) do
                        OctoSpecDB[k][kk] = vv
                    end
                else
                    OctoSpecDB[k] = v
                end
            end
        end
    end
    if not OctoSpecDB.charBuilds then OctoSpecDB.charBuilds = {} end
    if not OctoSpecDB.deletedDefaults then OctoSpecDB.deletedDefaults = {} end
end

local function OnLoad()
    InitDB()
    OctoSpec.primaryTree = OctoSpecDB.primaryTree or 0
    OctoSpec.priorityList = {}
    OctoSpec._restoredThisSession = false
    OctoSpec._restoreDone = false
    OctoSpec._restoreFrame = nil
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec|r v" .. (OctoSpec.version or "1.2.0") .. " loaded. Type /os for help.")
end

local function OnEvent()
    if event == "ADDON_LOADED" and arg1 == "OctoSpec" then
        OnLoad()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not OctoSpec._restoredThisSession then
            OctoSpec._restoredThisSession = true
            if OctoSpec.MigrateLegacyBuilds then
                OctoSpec.MigrateLegacyBuilds()
            end
            if OctoSpec.SeedDefaultBuilds then
                OctoSpec.SeedDefaultBuilds()
            end
            if OctoSpec.RestoreCharacterBuild then
                OctoSpec.RestoreCharacterBuild()
            end
        end
    elseif event == "PLAYER_LEVEL_UP" then
        -- Point is not granted yet on this event in 1.12 — mark pending and apply shortly after
        if OctoSpecDB and OctoSpecDB.autoApply and OctoSpecDB.autoApply.enabled then
            OctoSpec._autoApplyPending = true
            if not OctoSpec._autoApplyFrame then
                OctoSpec._autoApplyFrame = CreateFrame("Frame", "OctoSpecAutoApplyFrame")
            end
            local f = OctoSpec._autoApplyFrame
            local elapsed = 0
            local tries = 0
            f:SetScript("OnUpdate", function()
                elapsed = elapsed + arg1
                if elapsed < 0.3 then return end
                elapsed = 0
                tries = tries + 1
                if not (OctoSpecDB and OctoSpecDB.autoApply and OctoSpecDB.autoApply.enabled) then
                    OctoSpec._autoApplyPending = nil
                    this:SetScript("OnUpdate", nil)
                    return
                end
                local pts = UnitCharacterPoints("player") or 0
                if pts >= 1 then
                    OctoSpec._autoApplyPending = nil
                    this:SetScript("OnUpdate", nil)
                    if OctoSpec.ApplyNextTalent then
                        OctoSpec.ApplyNextTalent()
                    end
                elseif tries >= 20 then
                    -- ~6s — give up quietly
                    OctoSpec._autoApplyPending = nil
                    this:SetScript("OnUpdate", nil)
                end
            end)
        end
    elseif event == "CHARACTER_POINTS_CHANGED" then
        -- If we were waiting on a level-up point, try to apply as soon as points change
        if OctoSpec._autoApplyPending and OctoSpecDB and OctoSpecDB.autoApply and OctoSpecDB.autoApply.enabled then
            local pts = UnitCharacterPoints("player") or 0
            if pts >= 1 then
                OctoSpec._autoApplyPending = nil
                if OctoSpec._autoApplyFrame then
                    OctoSpec._autoApplyFrame:SetScript("OnUpdate", nil)
                end
                if OctoSpec.ApplyNextTalent then
                    OctoSpec.ApplyNextTalent()
                end
            end
        end
        if OctoSpec.UpdateHighlight then
            OctoSpec.UpdateHighlight()
        end
        if OctoSpec.RefreshUI then
            OctoSpec.RefreshUI()
        end
    end
end

local eventFrame = CreateFrame("Frame", "OctoSpecEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
eventFrame:SetScript("OnEvent", OnEvent)

SLASH_OCTOSPEC1 = "/os"
SLASH_OCTOSPEC2 = "/octospec"
SlashCmdList["OCTOSPEC"] = function(msg)
    msg = string.lower(string.gsub(msg or "", "^%s+", ""))
    msg = string.gsub(msg, "%s+$", "")

    if msg == "" or msg == "show" or msg == "ui" then
        if OctoSpec.ToggleMainFrame then OctoSpec.ToggleMainFrame() end
    elseif msg == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  /os                  - open the main window")
        DEFAULT_CHAT_FRAME:AddMessage("  /os next             - learn the next suggested talent")
        DEFAULT_CHAT_FRAME:AddMessage("  /os stop             - cancel an in-progress full build apply")
        DEFAULT_CHAT_FRAME:AddMessage("  /os prio             - toggle priority list UI / click mode")
        DEFAULT_CHAT_FRAME:AddMessage("  /os clearprio        - clear the priority list")
        DEFAULT_CHAT_FRAME:AddMessage("  /os primary 1-3      - set primary tree (0 = none)")
        DEFAULT_CHAT_FRAME:AddMessage("  /os reset            - clear target build and priority")
        DEFAULT_CHAT_FRAME:AddMessage("  /os export           - export current talents")
        DEFAULT_CHAT_FRAME:AddMessage("  /os redef            - restore deleted default builds for this character")
        DEFAULT_CHAT_FRAME:AddMessage("  /os help             - this help")
    elseif msg == "next" then
        if OctoSpec.ApplyNextTalent then OctoSpec.ApplyNextTalent() end
    elseif msg == "stop" then
        if OctoSpec.StopFullBuild then OctoSpec.StopFullBuild() end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Full build apply cancelled.")
    elseif msg == "prio" or msg == "priority" then
        if OctoSpec.TogglePriorityFrame then OctoSpec.TogglePriorityFrame() end
    elseif msg == "clearprio" or msg == "clear priority" then
        OctoSpec.priorityList = {}
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Priority list cleared.")
        if OctoSpec.RefreshPriorityFrame then OctoSpec.RefreshPriorityFrame() end
        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    elseif string.find(msg, "^primary") then
        local _, _, n = string.find(msg, "primary%s+(%d+)")
        n = tonumber(n)
        if n and n >= 0 and n <= 3 then
            OctoSpec.primaryTree = n
            if OctoSpecDB then OctoSpecDB.primaryTree = n end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Primary tree set to " .. n)
            if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
            if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Usage: /os primary 1-3 (0 = none)")
        end
    elseif msg == "reset" then
        OctoSpec.targetRanks = nil
        OctoSpec.targetPointsString = nil
        OctoSpec.priorityList = {}
        OctoSpec.nextTalent = nil
        OctoSpec.currentBuildName = nil
        if OctoSpecDB and OctoSpecDB.charState then
            OctoSpecDB.charState[OctoSpec.CharKey()] = nil
        end
        if OctoSpec.RememberActiveBuild then OctoSpec.RememberActiveBuild(nil) end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Target build cleared.")
        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    elseif msg == "export" then
        local url = OctoSpec.ExportCurrentLink and OctoSpec.ExportCurrentLink() or nil
        if not url then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Export failed.")
            return
        end
        if OctoSpec.CopyToClipboard then
            OctoSpec.CopyToClipboard(url)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Current talents exported.")
    elseif msg == "redef" or msg == "restoredefaults" or msg == "restore defaults" then
        if OctoSpec.RestoreDefaultBuilds then
            OctoSpec.RestoreDefaultBuilds()
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Unknown command. Type /os help")
    end
end







function OctoSpec.IsClassDefaultBuild(name)
    if not name or not OctoSpecDefaultBuilds then return false end
    local class = UnitClass("player")
    if not class or not OctoSpecDefaultBuilds[class] then return false end
    return OctoSpecDefaultBuilds[class][name] ~= nil
end

function OctoSpec.SeedDefaultBuilds()
    if not OctoSpecDB or not OctoSpecDefaultBuilds then return 0 end
    local class = UnitClass("player")
    if not class or not OctoSpecDefaultBuilds[class] then return 0 end

    local builds = OctoSpec.GetCharBuilds()
    if not OctoSpecDB.deletedDefaults then OctoSpecDB.deletedDefaults = {} end
    local key = OctoSpec.CharKey()
    if not OctoSpecDB.deletedDefaults[key] then
        OctoSpecDB.deletedDefaults[key] = {}
    end
    local deleted = OctoSpecDB.deletedDefaults[key]

    local added = 0
    for name, data in pairs(OctoSpecDefaultBuilds[class]) do
        local points = data and data.points
        if points and points ~= "" and not deleted[name] and not builds[name] then
            builds[name] = {
                points = points,
                primaryTree = data.primaryTree or 0,
                priority = {},
                class = class,
                isDefault = true,
            }
            added = added + 1
        end
    end
    return added
end

function OctoSpec.RestoreDefaultBuilds()
    if not OctoSpecDB then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Database not ready.")
        return
    end
    if not OctoSpecDefaultBuilds then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r No default builds table loaded.")
        return
    end
    local class = UnitClass("player")
    if not class or not OctoSpecDefaultBuilds[class] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r No defaults defined for " .. tostring(class) .. ".")
        return
    end

    local builds = OctoSpec.GetCharBuilds()
    if not OctoSpecDB.deletedDefaults then OctoSpecDB.deletedDefaults = {} end
    local key = OctoSpec.CharKey()
    OctoSpecDB.deletedDefaults[key] = {}

    local restored = 0
    local skipped = 0
    for name, data in pairs(OctoSpecDefaultBuilds[class]) do
        local points = data and data.points
        if points and points ~= "" then
            builds[name] = {
                points = points,
                primaryTree = data.primaryTree or 0,
                priority = {},
                class = class,
                isDefault = true,
            }
            restored = restored + 1
        else
            skipped = skipped + 1
        end
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Restored " .. restored .. " default build(s) for " .. class .. "."
        .. (skipped > 0 and (" (" .. skipped .. " still empty in DefaultBuilds.lua)") or ""))
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
end

function OctoSpec.RememberActiveBuild(buildName)
    if not OctoSpecDB then return end
    if not OctoSpecDB.charState then OctoSpecDB.charState = {} end
    -- Only tracks the ACTIVE plan for this character. Never writes OctoSpecDB.builds.
    OctoSpec.currentBuildName = buildName
    local key = OctoSpec.CharKey()
    local state = {
        buildName = buildName,
        points = OctoSpec.targetPointsString,
        primaryTree = OctoSpec.primaryTree or 0,
        suspendedBuildName = OctoSpec.suspendedBuildName,
        priority = {},
    }
    for i, p in ipairs(OctoSpec.priorityList or {}) do
        state.priority[i] = { tab = p.tab, index = p.index }
    end
    if (not state.points or state.points == "") and OctoSpec.targetRanks and OctoSpec.BuildGridRanks and OctoSpec.BitPack then
        state.points = OctoSpec.BitPack(OctoSpec.BuildGridRanks(OctoSpec.targetRanks))
    end
    OctoSpecDB.charState[key] = state
end

function OctoSpec.RestoreCharacterBuild()
    if not OctoSpecDB or not OctoSpecDB.charState then return end
    local state = OctoSpecDB.charState[OctoSpec.CharKey()]
    if not state then return end
    if OctoSpec._restoreDone then return end

    -- Talent info is often not ready at PLAYER_ENTERING_WORLD.
    -- Retry until GetNumTalents works (or give up after ~10s).
    local function TalentsReady()
        local tabs = GetNumTalentTabs and GetNumTalentTabs() or 0
        if tabs < 1 then return false end
        local n = GetNumTalents and GetNumTalents(1) or 0
        return n > 0
    end

    local function ApplyState()
        local announce = state.buildName or "last plan"

        if state.buildName == "Priority Only" then
            OctoSpec.targetRanks = nil
            OctoSpec.targetPointsString = nil
            OctoSpec.priorityList = {}
            for i, pr in ipairs(state.priority or {}) do
                OctoSpec.priorityList[i] = { tab = pr.tab, index = pr.index }
            end
            OctoSpec.currentBuildName = "Priority Only"
            OctoSpec.primaryTree = state.primaryTree or 0
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Loaded build: |cffffd700Priority Only|r")
            if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
            if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
            OctoSpec._pendingTalentHighlight = true
            return true
        end

        if state.buildName then
            local charBuilds = OctoSpec.GetCharBuilds()
            local data = charBuilds and charBuilds[state.buildName]
        if data then
            local points = data.points or ""
            OctoSpec.targetPointsString = points
            local ranks = OctoSpec.BitUnpack(points)
            OctoSpec.targetRanks = OctoSpec.RanksToMap(ranks)
            OctoSpec.primaryTree = data.primaryTree or state.primaryTree or 0
            if OctoSpecDB then OctoSpecDB.primaryTree = OctoSpec.primaryTree end
            OctoSpec.priorityList = {}
            local src = data.priority or state.priority or {}
            for i, pr in ipairs(src) do
                OctoSpec.priorityList[i] = { tab = pr.tab, index = pr.index }
            end
            OctoSpec.currentBuildName = state.buildName
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Loaded build: |cffffd700" .. state.buildName .. "|r")
            if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
            if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
            OctoSpec._pendingTalentHighlight = true
            return true
        end

        -- Fall back: raw points + priority from charState
        if state.points and state.points ~= "" then
            OctoSpec.targetPointsString = state.points
            local ranks = OctoSpec.BitUnpack(state.points)
            OctoSpec.targetRanks = OctoSpec.RanksToMap(ranks)
        else
            OctoSpec.targetRanks = nil
            OctoSpec.targetPointsString = nil
        end
        OctoSpec.primaryTree = state.primaryTree or 0
        if OctoSpecDB then OctoSpecDB.primaryTree = OctoSpec.primaryTree end
        OctoSpec.priorityList = {}
        for i, pr in ipairs(state.priority or {}) do
            OctoSpec.priorityList[i] = { tab = pr.tab, index = pr.index }
        end
        if OctoSpec.targetRanks or (OctoSpec.priorityList and table.getn(OctoSpec.priorityList) > 0) then
            OctoSpec.currentBuildName = state.buildName or "Imported (unsaved)"
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Loaded build: |cffffd700" .. tostring(OctoSpec.currentBuildName) .. "|r")
            if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
            if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
            OctoSpec._pendingTalentHighlight = true
            return true
        end
        return false
    end

    if TalentsReady() then
        OctoSpec._restoreDone = true
        ApplyState()
        return
    end

    -- Defer until talent data is available
    if OctoSpec._restoreFrame then return end
    local f = CreateFrame("Frame", "OctoSpecRestoreFrame")
    local elapsed = 0
    local tries = 0
    f:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < 0.25 then return end
        elapsed = 0
        tries = tries + 1
        if TalentsReady() then
            OctoSpec._restoreDone = true
            this:SetScript("OnUpdate", nil)
            this:Hide()
            ApplyState()
        elseif tries >= 40 then
            -- ~10 seconds — apply anyway so the player at least has points string
            OctoSpec._restoreDone = true
            this:SetScript("OnUpdate", nil)
            this:Hide()
            ApplyState()
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Talent data was slow to load; if the build looks empty, use Load again.")
        end
    end)
    f:Show()
    OctoSpec._restoreFrame = f
end


function OctoSpec.CopyToClipboard(text)
    if not text or text == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Nothing to copy.")
        return
    end
    if OctoSpec.mainFrame and OctoSpec.mainFrame.importBox then
        OctoSpec.mainFrame.importBox:SetText(text)
        OctoSpec.mainFrame.importBox:SetFocus()
        OctoSpec.mainFrame.importBox:HighlightText(0, string.len(text))
    end
    if ChatFrameEditBox then
        ChatFrameEditBox:Show()
        ChatFrameEditBox:SetText(text)
        ChatFrameEditBox:HighlightText()
        ChatFrameEditBox:SetFocus()
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Press |cffffffffCtrl+C|r to copy.")
end

function OctoSpec.ExportCurrentLink()
    local ranks = OctoSpec.BuildGridRanks("current")
    return OctoSpec.BuildExportLink(ranks)
end

function OctoSpec.ExportPlannedLink()
    -- 1) Exact imported/saved points string when available
    if OctoSpec.targetPointsString and OctoSpec.targetPointsString ~= "" then
        local classToken = string.lower(UnitClass("player") or "")
        local classMap = {
            warrior = "warrior", paladin = "paladin", hunter = "hunter",
            rogue = "rogue", priest = "priest", shaman = "shaman",
            mage = "mage", warlock = "warlock", druid = "druid",
        }
        local cls = classMap[classToken] or classToken
        return "https://octowow.st/talents/" .. cls .. "/?points=" .. OctoSpec.targetPointsString
    end
    -- 2) Re-encode from targetRanks
    if OctoSpec.targetRanks then
        return OctoSpec.BuildExportLink(OctoSpec.BuildGridRanks(OctoSpec.targetRanks))
    end
    -- 3) Priority-only: current ranks + checkpoints at maxRank
    if OctoSpec.priorityList and table.getn(OctoSpec.priorityList) > 0 then
        local map = { {}, {}, {} }
        local numTabs = GetNumTalentTabs() or 3
        for tab = 1, numTabs do
            map[tab] = {}
            local num = GetNumTalents(tab) or 0
            for index = 1, num do
                local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, index)
                if rank and rank > 0 then
                    map[tab][index] = rank
                end
            end
        end
        for _, pri in ipairs(OctoSpec.priorityList) do
            local name, icon, tier, column, rank, maxRank = GetTalentInfo(pri.tab, pri.index)
            if name and maxRank and maxRank > 0 then
                local cur = map[pri.tab][pri.index] or 0
                if maxRank > cur then
                    map[pri.tab][pri.index] = maxRank
                end
            end
        end
        return OctoSpec.BuildExportLink(OctoSpec.BuildGridRanks(map))
    end

    return nil
end

function OctoSpec.Import(input)
    if not input or input == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Paste a full calculator URL or the points= string.")
        return
    end

    -- Class from URL path: /talents/warlock/?points=...
    local linkClass = nil
    local _, _, clsFromUrl = string.find(input, "talents/([a-zA-Z]+)")
    if clsFromUrl then
        linkClass = string.lower(clsFromUrl)
    end
    local playerClass = string.lower(UnitClass("player") or "")
    local classMap = {
        warrior = "warrior", paladin = "paladin", hunter = "hunter",
        rogue = "rogue", priest = "priest", shaman = "shaman",
        mage = "mage", warlock = "warlock", druid = "druid",
    }
    playerClass = classMap[playerClass] or playerClass
    if linkClass and classMap[linkClass] then
        linkClass = classMap[linkClass]
        if linkClass ~= playerClass then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Link is for |cffffffff" .. linkClass .. "|r but you are a |cffffffff" .. playerClass .. "|r. Import aborted.")
            return
        end
    end

    local points = input
    -- Take everything after points= up to whitespace, &, or #
    local pos = string.find(input, "points=", 1, true)
    if pos then
        local rest = string.sub(input, pos + 7)
        local stop = string.find(rest, "[%s&#]")
        if stop then
            points = string.sub(rest, 1, stop - 1)
        else
            points = rest
        end
    end
    OctoSpec.targetPointsString = points

    local ranks = OctoSpec.BitUnpack(points)

    -- Raw decoded point sum (before mapping)
    local rawTotal = 0
    local rawLens = {}
    for t = 1, 3 do
        local n = 0
        local list = ranks[t] or {}
        for _, r in ipairs(list) do
            rawTotal = rawTotal + (r or 0)
            n = n + 1
        end
        rawLens[t] = n
    end

    -- Prefer live-client GRID map (1.18.1 layout). Fall back to sequential if grid loses too many points.
    local mapGrid = OctoSpec.RanksToMap(ranks)
    local mapSeq = OctoSpec.RanksToMapSequential and OctoSpec.RanksToMapSequential(ranks) or mapGrid

    local function SumMap(m)
        local total = 0
        for t = 1, 3 do
            for _, r in pairs(m[t] or {}) do
                total = total + r
            end
        end
        return total
    end
    local gridTotal = SumMap(mapGrid)
    local seqTotal = SumMap(mapSeq)

    local map = mapGrid
    local used = "grid"
    -- If sequential recovers more of the raw points, use it
    if seqTotal > gridTotal then
        map = mapSeq
        used = "sequential"
    end

    local total = SumMap(map)
    if total == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Could not decode any talent points. Check the string.")
        return
    end

    OctoSpec.targetRanks = map
    OctoSpec.priorityList = {}
    OctoSpec.currentBuildName = "Imported (unsaved)"
    if OctoSpec.RememberActiveBuild then OctoSpec.RememberActiveBuild(nil) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Build imported (" .. total .. " points).")

    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end

    if OctoSpec.mainFrame and OctoSpec.mainFrame.importBox then
        OctoSpec.mainFrame.importBox:SetText("")
        OctoSpec.mainFrame.importBox:ClearFocus()
    end
    if OctoSpec.PromptSaveBuild then
        OctoSpec.PromptSaveBuild()
    end
end

------------------------------------------------------------
-- Saved Builds
------------------------------------------------------------
function OctoSpec.SaveBuild(name)
    if not name or name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Enter a name for the build.")
        return
    end
    if name == "Priority Only" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r \"Priority Only\" is a built-in entry and cannot be overwritten. Choose another name.")
        return
    end
    if not OctoSpec.targetRanks and (not OctoSpec.priorityList or table.getn(OctoSpec.priorityList) == 0) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Import a build or set a priority list first.")
        return
    end

    local points
    if OctoSpec.targetPointsString and OctoSpec.targetPointsString ~= "" then
        -- Prefer exact website string when we imported one
        points = OctoSpec.targetPointsString
    elseif OctoSpec.targetRanks then
        points = OctoSpec.BitPack(OctoSpec.BuildGridRanks(OctoSpec.targetRanks))
    else
        -- Priority-only: current ranks + checkpoints at maxRank
        local map = { {}, {}, {} }
        local numTabs = GetNumTalentTabs() or 3
        for tab = 1, numTabs do
            map[tab] = {}
            local num = GetNumTalents(tab) or 0
            for index = 1, num do
                local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, index)
                if rank and rank > 0 then
                    map[tab][index] = rank
                end
            end
        end
        for _, pri in ipairs(OctoSpec.priorityList or {}) do
            local name, icon, tier, column, rank, maxRank = GetTalentInfo(pri.tab, pri.index)
            if name and maxRank and maxRank > 0 then
                local cur = map[pri.tab][pri.index] or 0
                if maxRank > cur then
                    map[pri.tab][pri.index] = maxRank
                end
            end
        end
        points = OctoSpec.BitPack(OctoSpec.BuildGridRanks(map))
    end

    local builds = OctoSpec.GetCharBuilds()
    builds[name] = {
        points = points,
        primaryTree = OctoSpec.primaryTree or 0,
        priority = OctoSpec.priorityList or {},
        class = UnitClass("player"),
        isDefault = false,
    }
    if OctoSpecDB.deletedDefaults then
        local key = OctoSpec.CharKey()
        if OctoSpecDB.deletedDefaults[key] then
            OctoSpecDB.deletedDefaults[key][name] = nil
        end
    end
    if OctoSpec.RememberActiveBuild then OctoSpec.RememberActiveBuild(name) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Saved build \"" .. name .. "\".")
    if OctoSpec.mainFrame and OctoSpec.mainFrame.saveNameBox then
        OctoSpec.mainFrame.saveNameBox:SetText("")
        OctoSpec.mainFrame.saveNameBox:ClearFocus()
    end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
end

function OctoSpec.LoadBuild(name)
    if not name or name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Enter a build name.")
        return
    end

    -- Priority Only: deactivate target only. NEVER deletes OctoSpecDB.builds entries.
    if name == "Priority Only" then
        local suspended = OctoSpec.currentBuildName
        if suspended and suspended ~= "" and suspended ~= "Priority Only" and suspended ~= "Imported (unsaved)" then
            OctoSpec.suspendedBuildName = suspended
        elseif OctoSpec.currentBuildName == "Imported (unsaved)" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00OctoSpec:|r Unsaved import deactivated. Use Save next time if you want to keep an import.")
        end

        OctoSpec.targetRanks = nil
        OctoSpec.targetPointsString = nil
        OctoSpec.currentBuildName = "Priority Only"
        if OctoSpec.RememberActiveBuild then OctoSpec.RememberActiveBuild("Priority Only") end

        local msg = "|cff00ff00OctoSpec:|r Priority Only mode — target deactivated (saved builds are NOT deleted)."
        if OctoSpec.suspendedBuildName then
            msg = msg .. " Load |cffffd700" .. OctoSpec.suspendedBuildName .. "|r from the list to return."
        end
        DEFAULT_CHAT_FRAME:AddMessage(msg)

        if OctoSpec.mainFrame and OctoSpec.mainFrame.saveNameBox then
            OctoSpec.mainFrame.saveNameBox:SetText("")
            OctoSpec.mainFrame.saveNameBox:ClearFocus()
        end
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
        return
    end

    local builds = OctoSpec.GetCharBuilds()
    if not builds or not builds[name] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Build "" .. tostring(name) .. "" not found on this character.")
        return
    end
    local data = builds[name]
    local points = data.points or ""
    OctoSpec.targetPointsString = points
    local ranks = OctoSpec.BitUnpack(points)
    OctoSpec.targetRanks = OctoSpec.RanksToMap(ranks)
    OctoSpec.primaryTree = data.primaryTree or 0
    if OctoSpecDB then OctoSpecDB.primaryTree = OctoSpec.primaryTree end

    OctoSpec.priorityList = {}
    if data.priority then
        for idx, pr in ipairs(data.priority) do
            OctoSpec.priorityList[idx] = { tab = pr.tab, index = pr.index }
        end
    end

    OctoSpec.currentBuildName = name
    OctoSpec.suspendedBuildName = nil
    if OctoSpec.RememberActiveBuild then OctoSpec.RememberActiveBuild(name) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Loaded build \"" .. name .. "\".")
    if OctoSpec.mainFrame and OctoSpec.mainFrame.saveNameBox then
        OctoSpec.mainFrame.saveNameBox:SetText("")
        OctoSpec.mainFrame.saveNameBox:ClearFocus()
    end
    if OctoSpec.mainFrame and OctoSpec.mainFrame.importBox then
        OctoSpec.mainFrame.importBox:SetText("")
        OctoSpec.mainFrame.importBox:ClearFocus()
    end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
end

function OctoSpec.DeleteBuild(name)
    if not name or name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Enter a build name to delete.")
        return
    end
    if name == "Priority Only" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Cannot delete the built-in Priority Only entry.")
        return
    end
    local builds = OctoSpec.GetCharBuilds()
    if not builds or not builds[name] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Build not found on this character.")
        return
    end

    local wasDefault = false
    if builds[name].isDefault then
        wasDefault = true
    elseif OctoSpec.IsClassDefaultBuild and OctoSpec.IsClassDefaultBuild(name) then
        wasDefault = true
    end

    builds[name] = nil

    if wasDefault then
        if not OctoSpecDB.deletedDefaults then OctoSpecDB.deletedDefaults = {} end
        local key = OctoSpec.CharKey()
        if not OctoSpecDB.deletedDefaults[key] then
            OctoSpecDB.deletedDefaults[key] = {}
        end
        OctoSpecDB.deletedDefaults[key][name] = true
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Deleted default \"" .. name .. "\" for this character. Use /os redef to restore defaults.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Deleted build \"" .. name .. "\".")
    end

    if OctoSpec.currentBuildName == name then
        OctoSpec.currentBuildName = nil
    end
    if OctoSpec.suspendedBuildName == name then
        OctoSpec.suspendedBuildName = nil
    end
    if OctoSpec.mainFrame and OctoSpec.mainFrame.saveNameBox then
        OctoSpec.mainFrame.saveNameBox:SetText("")
        OctoSpec.mainFrame.saveNameBox:ClearFocus()
    end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
end

function OctoSpec.GetSavedBuildNames()
    local names = { "Priority Only" }
    if not OctoSpecDB then
        return names
    end
    local builds = OctoSpec.GetCharBuilds()
    if not builds then
        return names
    end

    local defaults = {}
    local custom = {}
    for name, data in pairs(builds) do
        if name ~= "Priority Only" then
            if data and data.isDefault then
                table.insert(defaults, name)
            else
                table.insert(custom, name)
            end
        end
    end
    table.sort(defaults)
    table.sort(custom)
    for _, name in ipairs(defaults) do
        table.insert(names, name)
    end
    for _, name in ipairs(custom) do
        table.insert(names, name)
    end
    return names
end
