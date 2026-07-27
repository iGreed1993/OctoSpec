-- OctoSpec Encode / Decode
-- OctoWoW points= : 3-bit ranks, 6-bit Base64 chars, trees joined by "-"
OctoSpec = OctoSpec or {}

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function trimTrailingZeros(t)
    local copy = {}
    for i, v in ipairs(t) do
        copy[i] = v
    end
    while table.getn(copy) > 0 and copy[table.getn(copy)] == 0 do
        table.remove(copy)
    end
    return copy
end

function OctoSpec.BitPack(ranks)
    local parts = {}
    for tree = 1, 3 do
        local treeRanks = ranks[tree] or {}
        local trimmed = trimTrailingZeros(treeRanks)

        if table.getn(trimmed) == 0 then
            parts[tree] = ""
        else
            local bits = ""
            for _, rank in ipairs(trimmed) do
                local r = math.max(0, math.min(7, rank or 0))
                for i = 2, 0, -1 do
                    local bit = math.mod(math.floor(r / (2^i)), 2)
                    bits = bits .. tostring(bit)
                end
            end

            -- Pad trailing zeros to multiple of 6
            local pad = math.mod(6 - math.mod(string.len(bits), 6), 6)
            bits = bits .. string.rep("0", pad)

            local result = ""
            for i = 1, string.len(bits), 6 do
                local group = string.sub(bits, i, i + 5)
                local val = 0
                for j = 1, 6 do
                    if string.sub(group, j, j) == "1" then
                        val = val + (2^(6 - j))
                    end
                end
                result = result .. string.sub(b64chars, val + 1, val + 1)
            end
            parts[tree] = result
        end
    end
    return table.concat(parts, "-")
end

function OctoSpec.BitUnpack(raw)
    if not raw or raw == "" then
        return { {}, {}, {} }
    end

    local trees = {}
    for part in string.gfind(raw .. "-", "([^-]*)-") do
        table.insert(trees, part)
    end
    while table.getn(trees) < 3 do
        table.insert(trees, "")
    end
    if table.getn(trees) > 3 then
        trees = { trees[1], trees[2], trees[3] }
    end

    local b64lookup = {}
    for i = 1, 64 do
        b64lookup[string.sub(b64chars, i, i)] = i - 1
    end

    local ranks = {}
    for t = 1, 3 do
        local treeStr = trees[t] or ""
        ranks[t] = {}
        if treeStr ~= "" then
            -- Each char -> 6 bits (NOT standard base64 byte decode)
            local bits = ""
            for i = 1, string.len(treeStr) do
                local c = string.sub(treeStr, i, i)
                local v = b64lookup[c] or 0
                for b = 5, 0, -1 do
                    local bit = math.mod(math.floor(v / (2^b)), 2)
                    bits = bits .. tostring(bit)
                end
            end

            -- 3-bit ranks
            local temp = {}
            for i = 1, string.len(bits), 3 do
                local group = string.sub(bits, i, i + 2)
                if string.len(group) == 3 then
                    local val = 0
                    for j = 1, 3 do
                        if string.sub(group, j, j) == "1" then
                            val = val + (2^(3 - j))
                        end
                    end
                    table.insert(temp, val)
                end
            end

            -- Strip ONLY trailing zeros (bit padding). Keep leading and middle zeros.
            while table.getn(temp) > 0 and temp[table.getn(temp)] == 0 do
                table.remove(temp)
            end

            ranks[t] = temp
        end
    end

    return ranks
end

function OctoSpec.RanksToMap(ranks)
    -- Live client grid (tier x column) = actual Turtle/Octo 1.18.1 layout
    local map = {}
    for tab = 1, 3 do
        map[tab] = {}
        local list = ranks[tab] or {}
        if table.getn(list) > 0 then
            local talentAt = {}
            local maxTier, maxCol = 0, 0
            local num = GetNumTalents(tab) or 0
            for i = 1, num do
                local name, icon, tier, column = GetTalentInfo(tab, i)
                if tier and column then
                    if not talentAt[tier] then talentAt[tier] = {} end
                    talentAt[tier][column] = i
                    if tier > maxTier then maxTier = tier end
                    if column > maxCol then maxCol = column end
                end
            end
            if maxCol < 4 then maxCol = 4 end

            local gridOrder = {}
            for tier = 1, maxTier do
                for col = 1, maxCol do
                    table.insert(gridOrder, talentAt[tier] and talentAt[tier][col] or nil)
                end
            end

            for i, rank in ipairs(list) do
                local talentIndex = gridOrder[i]
                if talentIndex and rank and rank > 0 then
                    local name, icon, tier, column, cur, maxRank = GetTalentInfo(tab, talentIndex)
                    if maxRank and rank > maxRank then rank = maxRank end
                    map[tab][talentIndex] = rank
                end
            end
        end
    end
    return map
end

function OctoSpec.RanksToMapSequential(ranks)
    local map = {}
    for tab = 1, 3 do
        map[tab] = {}
        local list = ranks[tab] or {}
        local num = GetNumTalents(tab) or 0
        for index, rank in ipairs(list) do
            if index > num then break end
            if rank and rank > 0 then
                local name, icon, tier, column, cur, maxRank = GetTalentInfo(tab, index)
                if maxRank and rank > maxRank then rank = maxRank end
                map[tab][index] = rank
            end
        end
    end
    return map
end

-- Build a rank list in WEBSITE grid order (tier x column, empties as 0)
-- source = "current"  -> live ranks from GetTalentInfo
-- source = map table  -> targetRanks-style map[tab][talentIndex] = rank
function OctoSpec.BuildGridRanks(source)
    local ranks = { {}, {}, {} }
    local numTabs = GetNumTalentTabs() or 3
    for tab = 1, numTabs do
        local talentAt = {}
        local maxTier, maxCol = 0, 0
        local num = GetNumTalents(tab) or 0
        for i = 1, num do
            local name, icon, tier, column, rank = GetTalentInfo(tab, i)
            if tier and column then
                if not talentAt[tier] then talentAt[tier] = {} end
                talentAt[tier][column] = { index = i, rank = rank or 0 }
                if tier > maxTier then maxTier = tier end
                if column > maxCol then maxCol = column end
            end
        end
        if maxCol < 4 then maxCol = 4 end

        local list = {}
        for tier = 1, maxTier do
            for col = 1, maxCol do
                local cell = talentAt[tier] and talentAt[tier][col]
                if cell then
                    if source == "current" then
                        table.insert(list, cell.rank or 0)
                    else
                        -- source is target map
                        local r = 0
                        if source and source[tab] and source[tab][cell.index] then
                            r = source[tab][cell.index] or 0
                        end
                        table.insert(list, r)
                    end
                else
                    table.insert(list, 0)  -- empty grid cell
                end
            end
        end
        ranks[tab] = list
    end
    return ranks
end

function OctoSpec.GetCurrentRanks()
    return OctoSpec.BuildGridRanks("current")
end

function OctoSpec.BuildExportLink(ranks, classToken)
    classToken = classToken or string.lower(UnitClass("player"))
    local classMap = {
        warrior = "warrior", paladin = "paladin", hunter = "hunter",
        rogue = "rogue", priest = "priest", shaman = "shaman",
        mage = "mage", warlock = "warlock", druid = "druid",
    }
    local cls = classMap[classToken] or classToken
    local points = OctoSpec.BitPack(ranks)
    return "https://octowow.st/talents/" .. cls .. "/?points=" .. points
end
