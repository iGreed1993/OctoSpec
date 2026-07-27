-- OctoSpec TalentLogic
-- Next-talent selection, pathfinding, apply next / full build
OctoSpec = OctoSpec or {}

function OctoSpec.BuildDependentsMap(targetMap)
    local dependents = { {}, {}, {} }
    local numTabs = GetNumTalentTabs() or 3
    for tab = 1, numTabs do
        local numTalents = GetNumTalents(tab) or 0
        for index = 1, numTalents do
            local name, icon, tier, column = GetTalentInfo(tab, index)
            local targetRank = (targetMap[tab] and targetMap[tab][index]) or 0
            if targetRank > 0 then
                for otherIndex = 1, numTalents do
                    if otherIndex ~= index then
                        local oname, oicon, otier, ocolumn = GetTalentInfo(tab, otherIndex)
                        if ocolumn == column and otier < tier then
                            dependents[tab][otherIndex] = (dependents[tab][otherIndex] or 0) + 1
                        end
                    end
                end
            end
        end
    end
    return dependents
end

local function TalentIndexAt(tab, tier, column)
    local num = GetNumTalents(tab) or 0
    for i = 1, num do
        local name, icon, t, c = GetTalentInfo(tab, i)
        if t == tier and c == column then
            return i
        end
    end
    return nil
end

-- Prerequisite talent indices (same-row arrows, etc.)
-- GetTalentPrereqs returns: tier, column, isLearnable [, tier, column, isLearnable ...]
local function GetPrereqIndices(tab, index)
    local result = {}
    if not GetTalentPrereqs then return result end
    local a1, b1, c1, a2, b2, c2, a3, b3, c3 = GetTalentPrereqs(tab, index)
    local triples = { {a1, b1}, {a2, b2}, {a3, b3} }
    for _, trip in ipairs(triples) do
        local ptier, pcol = trip[1], trip[2]
        if type(ptier) == "number" and type(pcol) == "number" then
            local pindex = TalentIndexAt(tab, ptier, pcol)
            if pindex then
                table.insert(result, pindex)
            end
        end
    end
    return result
end

-- True only if every arrow-prereq talent has at least 1 rank
local function HasPrereqsMet(tab, index)
    local prereqs = GetPrereqIndices(tab, index)
    if table.getn(prereqs) == 0 then return true end
    for _, pindex in ipairs(prereqs) do
        local _, _, _, _, prank = GetTalentInfo(tab, pindex)
        if (prank or 0) < 1 then
            return false
        end
    end
    return true
end

local function IsLearnable(tab, index)
    -- Vanilla/Turtle GetTalentInfo:
    -- name, icon, tier, column, rank, maxRank, isExceptional, meetsPrereq
    -- (7th is NOT meetsPrereq — treating it as such blocked every normal talent)
    local name, icon, tier, column, rank, maxRank, isExceptional, meetsPrereq = GetTalentInfo(tab, index)
    if not name then return false end
    rank = rank or 0
    maxRank = maxRank or 0
    if maxRank <= 0 then return false end
    if rank >= maxRank then return false end

    -- If the client provides meetsPrereq, honor it; otherwise ignore
    if meetsPrereq == false then return false end

    -- Arrow prereqs: require the prereq talent to actually have ranks
    if not HasPrereqsMet(tab, index) then
        return false
    end

    -- Tier gate: need (tier-1)*5 points in lower tiers of this tree
    local pointsInTree = 0
    local numTalents = GetNumTalents(tab) or 0
    for i = 1, numTalents do
        local _, _, t, _, r = GetTalentInfo(tab, i)
        if t and tier and t < tier then
            pointsInTree = pointsInTree + (r or 0)
        end
    end
    local required = ((tier or 1) - 1) * 5
    return pointsInTree >= required
end

local function ScoreCandidate(tab, index, targetRank, currentRank, dependents, primaryTree)
    local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, index)
    if not name then return -99999 end
    if currentRank >= targetRank then return -99999 end
    if not IsLearnable(tab, index) then return -99999 end

    local score = 0
    if currentRank > 0 then
        score = score + 100000
    end
    if primaryTree and primaryTree > 0 then
        if tab == primaryTree then
            score = score + 50000
        else
            score = score - 20000
        end
    end
    score = score + (6 - (maxRank or 5)) * 80
    local dep = (dependents[tab] and dependents[tab][index]) or 0
    score = score + dep * 40
    score = score + (tier or 1) * 5
    score = score + (targetRank - currentRank) * 3
    return score
end

-- Priority-only target map (no import)
local function BuildPriorityTargetMap()
    local map = { {}, {}, {} }
    local list = OctoSpec.priorityList or {}
    for _, p in ipairs(list) do
        local name, icon, tier, column, rank, maxRank = GetTalentInfo(p.tab, p.index)
        if name and maxRank and maxRank > 0 then
            if not map[p.tab] then map[p.tab] = {} end
            map[p.tab][p.index] = maxRank
        end
    end
    return map
end

-- Desired rank for a talent given current targetMap
local function DesiredRank(targetMap, tab, index)
    return (targetMap[tab] and targetMap[tab][index]) or 0
end

-- Map tier/column -> talent index for a tree

local function FindPathToward(tab, index, targetMap, dependents, primaryTree)
    local name, icon, tier = GetTalentInfo(tab, index)
    if not name then return nil end

    local targetRank = DesiredRank(targetMap, tab, index)
    if targetRank <= 0 then
        local _, _, _, _, _, maxRank = GetTalentInfo(tab, index)
        targetRank = maxRank or 1
    end

    local _, _, _, _, currentRank = GetTalentInfo(tab, index)
    currentRank = currentRank or 0
    if currentRank >= targetRank then return nil end

    if IsLearnable(tab, index) then
        return tab, index
    end

    local hasImport = (OctoSpec.targetRanks ~= nil)

    -- Arrow / same-row prerequisites first (must have >=1 before checkpoint)
    local prereqs = GetPrereqIndices(tab, index)
    for _, pindex in ipairs(prereqs) do
        local pname, picon, ptier, pcol, prank, pmax = GetTalentInfo(tab, pindex)
        if pname then
            prank = prank or 0
            pmax = pmax or 1
            -- Always need at least 1 rank to open the arrow
            local want = DesiredRank(targetMap, tab, pindex)
            if want < 1 then want = 1 end
            if want > pmax then want = pmax end
            if prank < want then
                if IsLearnable(tab, pindex) then
                    return tab, pindex
                end
                -- Path into the prereq itself
                local rt, ri = FindPathToward(tab, pindex, targetMap, dependents, primaryTree)
                if rt then return rt, ri end
            end
        end
    end

    -- Lower-tier path (tier gates)
    local best, bestScore = nil, -99999
    local numTalents = GetNumTalents(tab) or 0
    for i = 1, numTalents do
        local n, ic, tt, c, r, mr = GetTalentInfo(tab, i)
        if n and tt and tier and tt < tier then
            local want = DesiredRank(targetMap, tab, i)
            if want <= 0 then
                if hasImport then
                    want = 0
                else
                    want = mr or 0
                end
            end
            r = r or 0
            if want > 0 and r < want and IsLearnable(tab, i) then
                local score = ScoreCandidate(tab, i, want, r, dependents, primaryTree)
                if c then
                    local _, _, _, pcol = GetTalentInfo(tab, index)
                    if pcol and c == pcol then score = score + 500 end
                end
                if score > bestScore then
                    bestScore = score
                    best = { tab = tab, index = i }
                end
            end
        end
    end
    if best then return best.tab, best.index end
    return nil
end

function OctoSpec.GetNextTalent(requireLearnable)
    if requireLearnable == nil then requireLearnable = true end

    local targetMap = OctoSpec.targetRanks
    if not targetMap then
        local list = OctoSpec.priorityList or {}
        if table.getn(list) == 0 then return nil end
        targetMap = BuildPriorityTargetMap()
    end

    local primaryTree = OctoSpec.primaryTree or 0
    local priorityList = OctoSpec.priorityList or {}
    local dependents = OctoSpec.BuildDependentsMap(targetMap)
    local numTabs = GetNumTalentTabs() or 3

    local function CanTake(tab, index)
        if not requireLearnable then return true end
        return IsLearnable(tab, index)
    end

    ------------------------------------------------------------
    -- Pass 0: priority checkpoints (absolute, path-aware)
    ------------------------------------------------------------
    for _, pri in ipairs(priorityList) do
        local ptab, pindex = pri.tab, pri.index
        local want = DesiredRank(targetMap, ptab, pindex)
        if want <= 0 then
            local _, _, _, _, _, maxRank = GetTalentInfo(ptab, pindex)
            want = maxRank or 0
        end
        local _, _, _, _, cur = GetTalentInfo(ptab, pindex)
        cur = cur or 0
        if cur < want then
            if requireLearnable then
                local t, i = FindPathToward(ptab, pindex, targetMap, dependents, primaryTree)
                if t then return t, i end
                break
            else
                -- Display mode: show the checkpoint itself
                return ptab, pindex
            end
        end
    end

    ------------------------------------------------------------
    -- Pass 1: partials (primary first)
    ------------------------------------------------------------
    local function FindBestPartial(onlyPrimary)
        local best, bestScore = nil, -99999
        for tab = 1, numTabs do
            if (not onlyPrimary) or (tab == primaryTree) then
                local numTalents = GetNumTalents(tab) or 0
                for index = 1, numTalents do
                    local want = DesiredRank(targetMap, tab, index)
                    if want > 0 then
                        local _, _, _, _, cur = GetTalentInfo(tab, index)
                        cur = cur or 0
                        if cur > 0 and cur < want and CanTake(tab, index) then
                            local score = 0
                            if requireLearnable then
                                score = ScoreCandidate(tab, index, want, cur, dependents, primaryTree)
                            else
                                score = (want - cur) + (tab == primaryTree and 1000 or 0)
                            end
                            if score > bestScore then
                                bestScore = score
                                best = { tab = tab, index = index }
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    if primaryTree and primaryTree > 0 then
        local p = FindBestPartial(true)
        if p then return p.tab, p.index end
    end
    local anyPartial = FindBestPartial(false)
    if anyPartial then return anyPartial.tab, anyPartial.index end

    ------------------------------------------------------------
    -- Pass 2: global heuristic / first incomplete
    ------------------------------------------------------------
    local best, bestScore = nil, -99999
    for tab = 1, numTabs do
        local numTalents = GetNumTalents(tab) or 0
        for index = 1, numTalents do
            local want = DesiredRank(targetMap, tab, index)
            if want > 0 then
                local _, _, _, _, cur = GetTalentInfo(tab, index)
                cur = cur or 0
                if cur < want and CanTake(tab, index) then
                    local score
                    if requireLearnable then
                        score = ScoreCandidate(tab, index, want, cur, dependents, primaryTree)
                    else
                        score = (6 - tab) * 100 + (want - cur)
                        if primaryTree and tab == primaryTree then score = score + 1000 end
                    end
                    if score > bestScore then
                        bestScore = score
                        best = { tab = tab, index = index }
                    end
                end
            end
        end
    end
    if best then return best.tab, best.index end
    return nil
end

function OctoSpec.ApplyNextTalent()
    local tab, index = OctoSpec.GetNextTalent()
    if not tab then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r No more talents to apply.")
        return false
    end

    local name = GetTalentInfo(tab, index)
    local available = UnitCharacterPoints("player")
    if available < 1 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r No talent points available. Next would be: " .. (name or "?"))
        return false
    end

    LearnTalent(tab, index)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Learned " .. (name or "talent") .. " (tree " .. tab .. ", #" .. index .. ")")
    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    return true
end

-- 1.12 only accepts one LearnTalent per tick; apply full build over time
local fullBuildFrame = nil
local fullBuildPending = false

function OctoSpec.IsFullBuildRunning()
    return fullBuildPending
end

function OctoSpec.StopFullBuild()
    fullBuildPending = false
    if fullBuildFrame then
        fullBuildFrame:SetScript("OnUpdate", nil)
        fullBuildFrame:Hide()
    end
end

function OctoSpec.ApplyFullBuild()
    if not OctoSpec.targetRanks and (not OctoSpec.priorityList or table.getn(OctoSpec.priorityList) == 0) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r No build or priority list loaded.")
        return 0
    end

    if fullBuildPending then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Full build already in progress. Use /os stop if you need to cancel.")
        return 0
    end

    local available = UnitCharacterPoints("player")
    if available < 1 then
        local tab, index = OctoSpec.GetNextTalent(true)
        local name = tab and GetTalentInfo(tab, index)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r No talent points available." .. (name and (" Next would be: " .. name) or ""))
        return 0
    end

    -- Confirm at least one talent is learnable before starting
    local tab0, index0 = OctoSpec.GetNextTalent(true)
    if not tab0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Nothing to apply.")
        return 0
    end

    if not fullBuildFrame then
        fullBuildFrame = CreateFrame("Frame", "OctoSpecFullBuildFrame")
    end

    fullBuildPending = true
    local spent = 0
    local elapsed = 0.5  -- apply first point immediately on first tick
    local interval = 0.5
    local maxPoints = 60

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Applying full build (one point every 0.5s)...")

    fullBuildFrame:Show()
    fullBuildFrame:SetScript("OnUpdate", function()
        if not fullBuildPending then
            this:SetScript("OnUpdate", nil)
            this:Hide()
            return
        end

        elapsed = elapsed + arg1
        if elapsed < interval then return end
        elapsed = 0

        if UnitCharacterPoints("player") < 1 or spent >= maxPoints then
            fullBuildPending = false
            this:SetScript("OnUpdate", nil)
            this:Hide()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Full build finished — applied " .. spent .. " point(s).")
            if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
            if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
            return
        end

        local tab, index = OctoSpec.GetNextTalent(true)
        if not tab then
            fullBuildPending = false
            this:SetScript("OnUpdate", nil)
            this:Hide()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Full build finished — applied " .. spent .. " point(s).")
            if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
            if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
            return
        end

        local name = GetTalentInfo(tab, index)
        LearnTalent(tab, index)
        spent = spent + 1
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r [" .. spent .. "] " .. (name or "talent"))
        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    end)

    return 1
end
