-- OctoSpec UI
-- Minimap, main window, priority window, talent hooks, highlight
OctoSpec = OctoSpec or {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function Backdrop()
    return {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }
end

local function EditBackdrop()
    return {
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    }
end

local function MakeButton(parent, width, height, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(height)
    b:SetText(text)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function MakeEditBox(name, parent, width, height)
    local e = CreateFrame("EditBox", name, parent)
    e:SetWidth(width)
    e:SetHeight(height)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlight)
    e:SetBackdrop(EditBackdrop())
    e:SetBackdropColor(0, 0, 0, 0.8)
    e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    return e
end

local function SetButtonTooltip(btn, title, text)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title)
        if text then GameTooltip:AddLine(text, 1, 1, 1, 1) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function GetTreeName(tab)
    local name = GetTalentTabInfo and GetTalentTabInfo(tab)
    if name and name ~= "" then return name end
    return "Tree " .. tostring(tab)
end

------------------------------------------------------------
-- Minimap
------------------------------------------------------------
local function CreateMinimapButton()
    local btn = CreateFrame("Button", "OctoSpecMinimapButton", Minimap)
    btn:SetWidth(32)
    btn:SetHeight(32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetMovable(true)

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    -- Custom icon shipped with the addon (red target reticle)
    icon:SetTexture("Interface\\Icons\\Ability_Marksmanship")
    icon:SetPoint("CENTER", 0, 1)
    btn.icon = icon

    -- Angle-based position around the minimap (same pattern as typical 1.12 minimap buttons)
    local function UpdatePosition()
        local angle = math.rad(OctoSpecDB and OctoSpecDB.minimapAngle or 220)
        local radius = 80
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    btn.UpdatePosition = UpdatePosition

    btn:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            OctoSpec.ToggleMainFrame()
        end
    end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("OctoSpec")
        GameTooltip:AddLine("Left-click: Open OctoSpec window", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move button around minimap", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("/os for slash commands", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnDragStart", function()
        this:LockHighlight()
        this:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            if angle < 0 then angle = angle + 360 end
            if not OctoSpecDB then OctoSpecDB = {} end
            OctoSpecDB.minimapAngle = angle
            this.UpdatePosition()
        end)
    end)
    btn:SetScript("OnDragStop", function()
        this:SetScript("OnUpdate", nil)
        this:UnlockHighlight()
    end)

    UpdatePosition()
    OctoSpec.minimapButton = btn
end

------------------------------------------------------------
-- Primary tree dropdown
------------------------------------------------------------
local primaryDropDown

local function PrimaryDropDown_OnClick()
    local id = this:GetID()
    local n = id - 1
    OctoSpec.primaryTree = n
    if OctoSpecDB then OctoSpecDB.primaryTree = n end
    UIDropDownMenu_SetSelectedID(primaryDropDown, id)
    if n == 0 then
        UIDropDownMenu_SetText("None", primaryDropDown)
    else
        UIDropDownMenu_SetText(GetTreeName(n), primaryDropDown)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Primary tree = " .. (n == 0 and "None" or GetTreeName(n)))
    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
end

local function PrimaryDropDown_Init()
    local info = {}
    info.text = "None"
    info.func = PrimaryDropDown_OnClick
    info.checked = (OctoSpec.primaryTree or 0) == 0
    UIDropDownMenu_AddButton(info)

    local numTabs = GetNumTalentTabs() or 3
    for t = 1, numTabs do
        info = {}
        info.text = GetTreeName(t)
        info.func = PrimaryDropDown_OnClick
        info.checked = (OctoSpec.primaryTree or 0) == t
        UIDropDownMenu_AddButton(info)
    end
end

local function CreatePrimaryDropDown(parent, anchor)
    local dd = CreateFrame("Frame", "OctoSpecPrimaryDropDown", parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_Initialize(dd, PrimaryDropDown_Init)
    UIDropDownMenu_SetWidth(140, dd)
    UIDropDownMenu_SetButtonWidth(140, dd)
    local cur = OctoSpec.primaryTree or 0
    if cur == 0 then
        UIDropDownMenu_SetText("None", dd)
        UIDropDownMenu_SetSelectedID(dd, 1)
    else
        UIDropDownMenu_SetText(GetTreeName(cur), dd)
        UIDropDownMenu_SetSelectedID(dd, cur + 1)
    end
    primaryDropDown = dd
    return dd
end

------------------------------------------------------------
-- Priority list window (with up/down reorder)
------------------------------------------------------------
local priorityFrame
local PRIORITY_ROWS = 12
local priorityScrollOffset = 0

local function ShowTalentFrame()
    if not TalentFrame and TalentFrame_LoadUI then
        TalentFrame_LoadUI()
    end
    if ToggleTalentFrame then
        -- Open only if hidden
        if not TalentFrame or not TalentFrame:IsShown() then
            ToggleTalentFrame()
        end
    elseif TalentFrame then
        ShowUIPanel(TalentFrame)
    end
end

local function HideTalentFrame()
    if TalentFrame and TalentFrame:IsShown() then
        if ToggleTalentFrame then
            ToggleTalentFrame()
        else
            HideUIPanel(TalentFrame)
        end
    end
end

function OctoSpec.TogglePriorityFrame()
    if not priorityFrame then OctoSpec.CreatePriorityFrame() end
    if priorityFrame:IsShown() then
        priorityFrame:Hide()
        OctoSpec.priorityMode = false
        HideTalentFrame()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Priority click mode OFF (list still used by logic).")
    else
        priorityFrame:Show()
        OctoSpec.priorityMode = true
        priorityScrollOffset = 0
        ShowTalentFrame()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Priority click mode ON - click talents to add them in order.")
        OctoSpec.RefreshPriorityFrame()
    end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
end

function OctoSpec.MovePriority(index, direction)
    local list = OctoSpec.priorityList
    if not list then return end
    local newIndex = index + direction
    if newIndex < 1 or newIndex > table.getn(list) then return end
    local tmp = list[index]
    list[index] = list[newIndex]
    list[newIndex] = tmp
    OctoSpec.RefreshPriorityFrame()
    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
end

function OctoSpec.RemovePriority(index)
    local list = OctoSpec.priorityList
    if not list or not list[index] then return end
    table.remove(list, index)
    OctoSpec.RefreshPriorityFrame()
    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
    if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
end

function OctoSpec.CreatePriorityFrame()
    local f = CreateFrame("Frame", "OctoSpecPriorityFrame", UIParent)
    f:SetWidth(360)
    f:SetHeight(380)
    f:SetPoint("CENTER", 180, 40)
    f:SetBackdrop(Backdrop())
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Priority List")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        f:Hide()
        OctoSpec.priorityMode = false
        HideTalentFrame()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Priority click mode OFF (list still used by logic).")
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -38)
    hint:SetWidth(328)
    hint:SetJustifyH("LEFT")
    hint:SetText("Click talents in the talent frame to add checkpoints. Use arrows to reorder. Closing this window only disables click-to-add - the list still drives selection.")
    f.hint = hint

    f.rows = {}
    for i = 1, PRIORITY_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetWidth(328)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", 16, -90 - (i - 1) * 20)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetWidth(230)
        label:SetJustifyH("LEFT")
        row.label = label

        local up = MakeButton(row, 22, 16, "^", function()
            OctoSpec.MovePriority(row.index, -1)
        end)
        up:SetPoint("LEFT", label, "RIGHT", 4, 0)
        row.up = up

        local down = MakeButton(row, 22, 16, "v", function()
            OctoSpec.MovePriority(row.index, 1)
        end)
        down:SetPoint("LEFT", up, "RIGHT", 2, 0)
        row.down = down

        local rem = MakeButton(row, 22, 16, "X", function()
            OctoSpec.RemovePriority(row.index)
        end)
        rem:SetPoint("LEFT", down, "RIGHT", 2, 0)
        row.rem = rem

        row:Hide()
        f.rows[i] = row
    end

    local scrollHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scrollHint:SetPoint("BOTTOMLEFT", 16, 44)
    scrollHint:SetWidth(320)
    scrollHint:SetJustifyH("LEFT")
    scrollHint:SetText("")
    scrollHint:Hide()
    f.scrollHint = scrollHint

    -- Mouse wheel scrolling
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function()
        local list = OctoSpec.priorityList or {}
        local n = table.getn(list)
        local maxOff = n - PRIORITY_ROWS
        if maxOff < 0 then maxOff = 0 end
        local delta = arg1 or 0  -- 1 = up, -1 = down
        priorityScrollOffset = priorityScrollOffset - delta
        if priorityScrollOffset < 0 then priorityScrollOffset = 0 end
        if priorityScrollOffset > maxOff then priorityScrollOffset = maxOff end
        OctoSpec.RefreshPriorityFrame()
    end)

    local clearBtn = MakeButton(f, 120, 24, "Clear List", function()
        OctoSpec.priorityList = {}
        priorityScrollOffset = 0
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Priority list cleared.")
        OctoSpec.RefreshPriorityFrame()
        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    end)
    clearBtn:SetPoint("BOTTOMLEFT", 16, 16)

    local doneBtn = MakeButton(f, 100, 24, "Done", function()
        f:Hide()
        OctoSpec.priorityMode = false
        HideTalentFrame()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Priority click mode OFF (list still used by logic).")
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    end)
    doneBtn:SetPoint("BOTTOMRIGHT", -16, 16)

    priorityFrame = f
    OctoSpec.priorityFrame = f
end

function OctoSpec.RefreshPriorityFrame()
    if not priorityFrame then return end
    local list = OctoSpec.priorityList or {}
    local n = table.getn(list)

    -- Clamp scroll offset
    local maxOff = n - PRIORITY_ROWS
    if maxOff < 0 then maxOff = 0 end
    if priorityScrollOffset > maxOff then priorityScrollOffset = maxOff end
    if priorityScrollOffset < 0 then priorityScrollOffset = 0 end

    for i = 1, PRIORITY_ROWS do
        local row = priorityFrame.rows[i]
        local listIndex = i + priorityScrollOffset
        if listIndex <= n then
            local p = list[listIndex]
            local name = GetTalentInfo(p.tab, p.index)
            row.index = listIndex  -- real list index for up/down/remove
            row.label:SetText(listIndex .. ". [" .. GetTreeName(p.tab) .. "] " .. (name or "?"))
            row:Show()
        else
            row:Hide()
        end
    end

    if priorityFrame.scrollHint then
        if n > PRIORITY_ROWS then
            priorityFrame.scrollHint:SetText("Showing " .. (priorityScrollOffset + 1) .. "-" .. math.min(priorityScrollOffset + PRIORITY_ROWS, n) .. " of " .. n .. "  (mouse wheel to scroll)")
            priorityFrame.scrollHint:Show()
        else
            priorityFrame.scrollHint:SetText("")
            priorityFrame.scrollHint:Hide()
        end
    end
end

------------------------------------------------------------
-- Save prompt after import
------------------------------------------------------------
function OctoSpec.PromptSaveBuild()
    if not OctoSpec.savePromptFrame then
        local f = CreateFrame("Frame", "OctoSpecSavePrompt", UIParent)
        f:SetWidth(320)
        f:SetHeight(130)
        f:SetPoint("CENTER", 0, 80)
        f:SetBackdrop(Backdrop())
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:Hide()

        local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOP", 0, -20)
        text:SetWidth(280)
        text:SetText("Build imported. Save it now?")

        local box = MakeEditBox("OctoSpecSavePromptBox", f, 200, 22)
        box:SetPoint("TOP", 0, -48)
        f.box = box

        local yes = MakeButton(f, 100, 24, "Save", function()
            local name = box:GetText()
            if name and name ~= "" then
                OctoSpec.SaveBuild(name)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Enter a name.")
                return
            end
            f:Hide()
            box:SetText("")
            box:ClearFocus()
        end)
        yes:SetPoint("BOTTOMLEFT", 30, 16)

        local no = MakeButton(f, 100, 24, "Skip", function()
            f:Hide()
            box:SetText("")
            box:ClearFocus()
        end)
        no:SetPoint("BOTTOMRIGHT", -30, 16)

        OctoSpec.savePromptFrame = f
    end
    OctoSpec.savePromptFrame.box:SetText("")
    OctoSpec.savePromptFrame:Show()
    OctoSpec.savePromptFrame.box:SetFocus()
end

------------------------------------------------------------
-- Export choice (current vs planned)
------------------------------------------------------------
function OctoSpec.ShowExportChoice()
    if not OctoSpec.exportChoiceFrame then
        local f = CreateFrame("Frame", "OctoSpecExportChoice", UIParent)
        f:SetWidth(320)
        f:SetHeight(130)
        f:SetPoint("CENTER", 0, 60)
        f:SetBackdrop(Backdrop())
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:Hide()

        local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOP", 0, -24)
        text:SetWidth(280)
        text:SetText("Export which build?")

        local cur = MakeButton(f, 130, 24, "Current Talents", function()
            f:Hide()
            local url = OctoSpec.ExportCurrentLink and OctoSpec.ExportCurrentLink() or nil
            if not url then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Could not export current talents.")
                return
            end
            if OctoSpec.CopyToClipboard then
                OctoSpec.CopyToClipboard(url)
            elseif OctoSpec.mainFrame and OctoSpec.mainFrame.importBox then
                OctoSpec.mainFrame.importBox:SetText(url)
                OctoSpec.mainFrame.importBox:HighlightText()
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Current talents exported.")
        end)
        cur:SetPoint("BOTTOMLEFT", 20, 20)

        local plan = MakeButton(f, 130, 24, "Planned Build", function()
            f:Hide()
            local url = OctoSpec.ExportPlannedLink and OctoSpec.ExportPlannedLink() or nil
            if not url then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r No planned build loaded.")
                return
            end
            if OctoSpec.CopyToClipboard then
                OctoSpec.CopyToClipboard(url)
            elseif OctoSpec.mainFrame and OctoSpec.mainFrame.importBox then
                OctoSpec.mainFrame.importBox:SetText(url)
                OctoSpec.mainFrame.importBox:HighlightText()
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Planned build exported.")
        end)
        plan:SetPoint("BOTTOMRIGHT", -20, 20)

        OctoSpec.exportChoiceFrame = f
    end
    OctoSpec.exportChoiceFrame:Show()
end

------------------------------------------------------------
-- Main window
------------------------------------------------------------
local mainFrame
local BUILD_ROWS = 8
local buildsScrollOffset = 0

function OctoSpec.ToggleMainFrame()
    if not mainFrame then OctoSpec.CreateMainFrame() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        OctoSpec.RefreshUI()
    end
end

function OctoSpec.CreateMainFrame()
    local f = CreateFrame("Frame", "OctoSpecMainFrame", UIParent)
    f:SetWidth(380)
    f:SetHeight(480)
    f:SetPoint("CENTER", 0, 0)
    f:SetBackdrop(Backdrop())
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("OctoSpec")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local importLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importLabel:SetPoint("TOPLEFT", 18, -42)
    importLabel:SetText("Import calculator link / points:")

    local importBox = MakeEditBox("OctoSpecImportBox", f, 300, 22)
    importBox:SetPoint("TOPLEFT", 18, -60)
    importBox:SetScript("OnEnterPressed", function()
        OctoSpec.Import(this:GetText())
        this:ClearFocus()
    end)
    f.importBox = importBox

    local clearBoxBtn = MakeButton(f, 50, 22, "Clear", function()
        local box = OctoSpec.mainFrame and OctoSpec.mainFrame.importBox
        if not box then return end
        box:SetText("")
        box:ClearFocus()
    end)
    clearBoxBtn:SetPoint("LEFT", importBox, "RIGHT", 4, 0)
    SetButtonTooltip(clearBoxBtn, "Clear", "Clear the import/export text box.")

    local importBtn = MakeButton(f, 80, 22, "Import", function()
        OctoSpec.Import(importBox:GetText())
    end)
    importBtn:SetPoint("TOPLEFT", 18, -88)
    SetButtonTooltip(importBtn, "Import", "Load a talent build from an OctoWoW calculator link or points string.")

    local exportBtn = MakeButton(f, 80, 22, "Export", function()
        OctoSpec.ShowExportChoice()
    end)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 6, 0)
    SetButtonTooltip(exportBtn, "Export", "Copy a calculator link for your current talents or the planned build.")

    local resetBtn = MakeButton(f, 80, 22, "Reset", function()
        OctoSpec.targetRanks = nil
        OctoSpec.targetPointsString = nil
        OctoSpec.priorityList = {}
        OctoSpec.nextTalent = nil
        if OctoSpec.RememberActiveBuild then OctoSpec.RememberActiveBuild(nil) end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r Target build and priority list cleared.")
        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
        OctoSpec.RefreshUI()
        if OctoSpec.RefreshPriorityFrame then OctoSpec.RefreshPriorityFrame() end
    end)
    resetBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)
    SetButtonTooltip(resetBtn, "Reset", "Clear the imported build and priority list.")

    local primLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    primLabel:SetPoint("TOPLEFT", 18, -120)
    primLabel:SetText("Primary tree:")
    CreatePrimaryDropDown(f, primLabel)

    local priBtn = MakeButton(f, 160, 22, "Priority List...", function()
        OctoSpec.TogglePriorityFrame()
    end)
    priBtn:SetPoint("TOPLEFT", 18, -165)
    f.priorityBtn = priBtn
    SetButtonTooltip(priBtn, "Priority List", "Open the priority checkpoint list. While open, click talents to add them in order. Closing only disables click-to-add — the list still drives selection.")

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", 18, -198)
    status:SetWidth(340)
    status:SetJustifyH("LEFT")
    status:SetText("No build loaded.")
    f.statusText = status

    local activeBuild = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeBuild:SetPoint("TOPLEFT", 18, -216)
    activeBuild:SetWidth(340)
    activeBuild:SetJustifyH("LEFT")
    activeBuild:SetText("Active: |cffffffffNone|r")
    f.activeBuildText = activeBuild

    local applyBtn = MakeButton(f, 120, 24, "Apply Next", function()
        OctoSpec.ApplyNextTalent()
        OctoSpec.RefreshUI()
    end)
    applyBtn:SetPoint("TOPLEFT", 18, -242)
    SetButtonTooltip(applyBtn, "Apply Next", "Spend one talent point on the next suggested talent (if you have points and it is unlockable).")

    local applyFullBtn = MakeButton(f, 140, 24, "Apply Full Build", function()
        OctoSpec.ConfirmApplyFull()
    end)
    applyFullBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    SetButtonTooltip(applyFullBtn, "Apply Full Build", "Spend all available talent points following the plan (asks for confirmation first).")

    local autoBtn = MakeButton(f, 170, 22, "Auto on Level-up: OFF", function()
        if not OctoSpecDB.autoApply then OctoSpecDB.autoApply = { enabled = false, mode = "levelup" } end
        OctoSpecDB.autoApply.enabled = not OctoSpecDB.autoApply.enabled
        this:SetText(OctoSpecDB.autoApply.enabled and "Auto on Level-up: ON" or "Auto on Level-up: OFF")
    end)
    autoBtn:SetPoint("TOPLEFT", 18, -264)
    f.autoBtn = autoBtn
    SetButtonTooltip(autoBtn, "Auto on Level-up", "When ON, automatically learns the next suggested talent each time you level up.")

    local saveLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    saveLabel:SetPoint("TOPLEFT", 18, -300)
    saveLabel:SetText("Saved Builds:")

    local saveNameBox = MakeEditBox("OctoSpecSaveNameBox", f, 150, 20)
    saveNameBox:SetPoint("TOPLEFT", 18, -320)
    f.saveNameBox = saveNameBox

    local saveBtn = MakeButton(f, 55, 20, "Save", function()
        OctoSpec.SaveBuild(saveNameBox:GetText())
    end)
    saveBtn:SetPoint("LEFT", saveNameBox, "RIGHT", 4, 0)
    SetButtonTooltip(saveBtn, "Save", "Save the current plan under the name in the box.")

    local loadBtn = MakeButton(f, 55, 20, "Load", function()
        OctoSpec.LoadBuild(saveNameBox:GetText())
    end)
    loadBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
    SetButtonTooltip(loadBtn, "Load", "Load a saved build. Priority Only only deactivates the current target — it does not delete any saved builds.")

    local delBtn = MakeButton(f, 55, 20, "Delete", function()
        OctoSpec.DeleteBuild(saveNameBox:GetText())
    end)
    delBtn:SetPoint("LEFT", loadBtn, "RIGHT", 4, 0)
    SetButtonTooltip(delBtn, "Delete", "Delete the named saved build. Cannot delete Priority Only.")

    f.buildButtons = {}
    for i = 1, BUILD_ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(340)
        b:SetHeight(16)
        b:SetPoint("TOPLEFT", 18, -348 - (i - 1) * 16)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetAllPoints()
        fs:SetJustifyH("LEFT")
        b.text = fs
        b:SetScript("OnClick", function()
            if this.buildName then
                saveNameBox:SetText(this.buildName)
                saveNameBox:HighlightText()
            end
        end)
        b:SetScript("OnEnter", function()
            if this.buildName then this.text:SetTextColor(1, 1, 0) end
        end)
        b:SetScript("OnLeave", function()
            this.text:SetTextColor(1, 1, 1)
        end)
        b:Hide()
        f.buildButtons[i] = b
    end

    local buildsHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buildsHint:SetPoint("TOPLEFT", 18, -348 - BUILD_ROWS * 16 - 2)
    buildsHint:SetWidth(340)
    buildsHint:SetJustifyH("LEFT")
    buildsHint:SetText("")
    f.buildsHint = buildsHint

    -- Mouse wheel over main window scrolls saved builds when many exist
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function()
        local names = OctoSpec.GetSavedBuildNames and OctoSpec.GetSavedBuildNames() or {}
        local n = table.getn(names)
        local maxOff = n - BUILD_ROWS
        if maxOff < 0 then maxOff = 0 end
        local delta = arg1 or 0
        buildsScrollOffset = buildsScrollOffset - delta
        if buildsScrollOffset < 0 then buildsScrollOffset = 0 end
        if buildsScrollOffset > maxOff then buildsScrollOffset = maxOff end
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    end)

    mainFrame = f
    OctoSpec.mainFrame = f
end

function OctoSpec.RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    -- Active build label
    if mainFrame.activeBuildText then
        local label = OctoSpec.currentBuildName
        if label == "Priority Only" then
            local extra = ""
            if OctoSpec.suspendedBuildName then
                extra = " |cffaaaaaa(saved: " .. OctoSpec.suspendedBuildName .. " still available)|r"
            end
            mainFrame.activeBuildText:SetText("Active: |cffffd700Priority Only|r" .. extra)
        elseif label and label ~= "" then
            mainFrame.activeBuildText:SetText("Active: |cffffd700" .. label .. "|r")
        elseif OctoSpec.targetRanks then
            mainFrame.activeBuildText:SetText("Active: |cffffd700Imported (unsaved)|r")
        elseif OctoSpec.priorityList and table.getn(OctoSpec.priorityList) > 0 then
            mainFrame.activeBuildText:SetText("Active: |cffffd700Priority Only|r")
        else
            mainFrame.activeBuildText:SetText("Active: |cffffffffNone|r")
        end
    end

    local hasTarget = OctoSpec.targetRanks or (OctoSpec.priorityList and table.getn(OctoSpec.priorityList) > 0)
    if not hasTarget then
        mainFrame.statusText:SetText("No build loaded. Import a link or set a priority list.")
    else
        -- Prefer a learnable talent; if none, show the next desired (locked) talent
        local tab, index = OctoSpec.GetNextTalent(true)
        local locked = false
        if not tab then
            tab, index = OctoSpec.GetNextTalent(false)
            locked = (tab ~= nil)
        end
        if tab then
            local name = GetTalentInfo(tab, index)
            local pts = UnitCharacterPoints("player") or 0
            local extra = ""
            if locked then
                extra = "  |cffffaa00(not unlockable yet)|r"
            elseif pts < 1 then
                extra = "  |cffaaaaaa(no points yet)|r"
            end
            mainFrame.statusText:SetText("Next: |cff00ff00" .. (name or "?") .. "|r  [" .. GetTreeName(tab) .. "]" .. extra)
        else
            mainFrame.statusText:SetText("Build complete - nothing left to learn.")
        end
    end

    if primaryDropDown then
        local cur = OctoSpec.primaryTree or 0
        if cur == 0 then
            UIDropDownMenu_SetText("None", primaryDropDown)
        else
            UIDropDownMenu_SetText(GetTreeName(cur), primaryDropDown)
        end
    end

    if mainFrame.autoBtn and OctoSpecDB and OctoSpecDB.autoApply then
        mainFrame.autoBtn:SetText(OctoSpecDB.autoApply.enabled and "Auto on Level-up: ON" or "Auto on Level-up: OFF")
    end

    if mainFrame.priorityBtn then
        local n = OctoSpec.priorityList and table.getn(OctoSpec.priorityList) or 0
        if OctoSpec.priorityMode then
            mainFrame.priorityBtn:SetText("Priority: ON (" .. n .. ")")
        else
            mainFrame.priorityBtn:SetText("Priority List... (" .. n .. ")")
        end
    end

    local names = OctoSpec.GetSavedBuildNames and OctoSpec.GetSavedBuildNames() or {}
    local n = table.getn(names)
    local maxOff = n - BUILD_ROWS
    if maxOff < 0 then maxOff = 0 end
    if buildsScrollOffset > maxOff then buildsScrollOffset = maxOff end
    if buildsScrollOffset < 0 then buildsScrollOffset = 0 end

    for i = 1, BUILD_ROWS do
        local b = mainFrame.buildButtons[i]
        local listIndex = i + buildsScrollOffset
        if listIndex <= n and names[listIndex] then
            b.buildName = names[listIndex]
            b.text:SetText(names[listIndex])
            b.text:SetTextColor(1, 1, 1)
            b:Show()
        else
            b.buildName = nil
            b:Hide()
        end
    end

    if mainFrame.buildsHint then
        if n > BUILD_ROWS then
            mainFrame.buildsHint:SetText("Showing " .. (buildsScrollOffset + 1) .. "-" .. math.min(buildsScrollOffset + BUILD_ROWS, n) .. " of " .. n .. "  (mouse wheel to scroll)")
            mainFrame.buildsHint:Show()
        else
            mainFrame.buildsHint:SetText("")
            mainFrame.buildsHint:Hide()
        end
    end
end

------------------------------------------------------------
-- Talent hooks + highlight
------------------------------------------------------------

-- Talent UI compatibility (Blizzard TalentFrame + DFRL BLF_TalentFrame)
local TALENT_BTN_PREFIXES = {
    "TalentFrameTalent",
    "PlayerTalentFrameTalent",
}

local function GetActiveTalentFrame()
    -- Prefer whichever is actually shown. Check default first if both exist.
    local blf = getglobal("BLF_TalentFrame")
    local tf = getglobal("TalentFrame")
    local ptf = getglobal("PlayerTalentFrame")
    if tf and tf.IsShown and tf:IsShown() then return tf end
    if blf and blf.IsShown and blf:IsShown() then return blf end
    if ptf and ptf.IsShown and ptf:IsShown() then return ptf end
    return nil
end

local function IsDFRLTalentUI(frame)
    frame = frame or GetActiveTalentFrame()
    if not frame or not frame.GetName then return false end
    return frame:GetName() == "BLF_TalentFrame"
end

local function GetSelectedTalentTab(frame)
    frame = frame or GetActiveTalentFrame()
    if IsDFRLTalentUI(frame) then
        return nil
    end
    if frame and PanelTemplates_GetSelectedTab then
        local selected = PanelTemplates_GetSelectedTab(frame)
        if selected then return selected end
    end
    if TalentFrame and TalentFrame.IsShown and TalentFrame:IsShown() and PanelTemplates_GetSelectedTab then
        return PanelTemplates_GetSelectedTab(TalentFrame)
    end
    return nil
end

local function FindTalentButton(tab, index)
    if not tab or not index then return nil end

    local frame = GetActiveTalentFrame()
    local isDFRL = IsDFRLTalentUI(frame)

    -- Default Blizzard talent buttons (named TalentFrameTalentN)
    if not isDFRL then
        for _, prefix in ipairs(TALENT_BTN_PREFIXES) do
            local btn = getglobal(prefix .. index)
            if btn and ((btn.IsShown and btn:IsShown()) or (btn.IsVisible and btn:IsVisible())) then
                return btn
            end
        end
    end

    if not frame then return nil end

    -- DFRL / generic: scan for tabIndex+talentIndex or GetID
    local function Scan(f, depth)
        if not f or depth > 10 then return nil end
        if f.GetObjectType and f:GetObjectType() == "Button" then
            local shown = (f.IsShown and f:IsShown()) or (f.IsVisible and f:IsVisible())
            if shown then
                if f.tabIndex and f.talentIndex then
                    if f.tabIndex == tab and f.talentIndex == index then
                        return f
                    end
                elseif (not isDFRL) and f.GetID and f:GetID() == index then
                    return f
                end
            end
        end
        if f.GetChildren then
            local children = { f:GetChildren() }
            for _, child in ipairs(children) do
                local found = Scan(child, depth + 1)
                if found then return found end
            end
        end
        return nil
    end
    return Scan(frame, 0)
end

local function IsTalentUIShown()
    return GetActiveTalentFrame() ~= nil
end


local function HookTalentButtons()
    local function OnTalentClickFromButton(btn)
        if not OctoSpec.priorityMode then return end
        if not btn then return end

        local tab = btn.tabIndex
        local index = btn.talentIndex
        if not tab or not index then
            -- Blizzard-style
            tab = GetSelectedTalentTab() or (TalentFrame and PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(TalentFrame))
            index = btn.GetID and btn:GetID() or nil
        end
        if not tab or not index then return end

        local name = GetTalentInfo(tab, index)
        if not name then return end

        if OctoSpec.targetRanks then
            local targetRank = (OctoSpec.targetRanks[tab] and OctoSpec.targetRanks[tab][index]) or 0
            if targetRank <= 0 then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r That talent is not part of the imported build.")
                return
            end
        end

        for _, p in ipairs(OctoSpec.priorityList or {}) do
            if p.tab == tab and p.index == index then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r Already in the priority list.")
                return
            end
        end

        if not OctoSpec.priorityList then OctoSpec.priorityList = {} end
        table.insert(OctoSpec.priorityList, { tab = tab, index = index })
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r #" .. table.getn(OctoSpec.priorityList) .. " " .. name)
        local n = table.getn(OctoSpec.priorityList)
        local maxOff = n - PRIORITY_ROWS
        if maxOff < 0 then maxOff = 0 end
        priorityScrollOffset = maxOff
        OctoSpec.RefreshPriorityFrame()
        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
        if OctoSpec.RefreshUI then OctoSpec.RefreshUI() end
    end

    local function TryHookButton(btn)
        if not btn or btn.octoSpecHooked then return end
        local old = btn:GetScript("OnClick")
        btn:SetScript("OnClick", function()
            if OctoSpec.priorityMode then
                OnTalentClickFromButton(this)
            elseif old then
                old()
            end
        end)
        btn.octoSpecHooked = true
    end

    local function TryHook()
        -- Named Blizzard buttons
        for i = 1, 40 do
            for _, prefix in ipairs(TALENT_BTN_PREFIXES) do
                TryHookButton(getglobal(prefix .. i))
            end
        end
        -- Scan active UI (covers DFRL unnamed buttons)
        local frame = GetActiveTalentFrame()
        if frame and frame.GetChildren then
            local function Scan(f, depth)
                if not f or depth > 10 then return end
                if f.GetObjectType and f:GetObjectType() == "Button" then
                    if f.tabIndex and f.talentIndex then
                        TryHookButton(f)
                    elseif f.GetID and f:GetID() and f:GetID() >= 1 and f:GetID() <= 40 then
                        TryHookButton(f)
                    end
                end
                if f.GetChildren then
                    local children = { f:GetChildren() }
                    for _, child in ipairs(children) do
                        Scan(child, depth + 1)
                    end
                end
            end
            Scan(frame, 0)
        end
    end

    TryHook()

    -- Hook OnShow on known talent frames
    local roots = { "BLF_TalentFrame", "TalentFrame", "PlayerTalentFrame" }
    for _, name in ipairs(roots) do
        local f = getglobal(name)
        if f and not f.octoSpecShowHooked then
            local oldShow = f:GetScript("OnShow")
            f:SetScript("OnShow", function()
                if oldShow then oldShow() end
                TryHook()
                if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                -- Buttons/layout may not be ready this frame
                local d = CreateFrame("Frame")
                local e = 0
                d:SetScript("OnUpdate", function()
                    e = e + arg1
                    if e < 0.1 then return end
                    this:SetScript("OnUpdate", nil)
                    TryHook()
                    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                end)
            end)
            f.octoSpecShowHooked = true
        end
    end

    -- DFRL creates BLF_TalentFrame lazily on first ToggleTalentFrame — poll briefly
    if not OctoSpec._talentHookTimer then
        local tf = CreateFrame("Frame", "OctoSpecTalentHookTimer")
        local elapsed = 0
        tf:SetScript("OnUpdate", function()
            elapsed = elapsed + arg1
            if elapsed < 0.5 then return end
            elapsed = 0

            -- Re-wrap ToggleTalentFrame if another addon replaced it (e.g. DFRL)
            if ToggleTalentFrame and OctoSpec._wrappedToggle ~= ToggleTalentFrame then
                local previous = ToggleTalentFrame
                local function wrapper()
                    previous()
                    TryHook()
                    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                    local d = CreateFrame("Frame")
                    local e = 0
                    d:SetScript("OnUpdate", function()
                        e = e + arg1
                        if e < 0.2 then return end
                        this:SetScript("OnUpdate", nil)
                        TryHook()
                        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                    end)
                end
                ToggleTalentFrame = wrapper
                OctoSpec._wrappedToggle = wrapper
            end

            -- Catch late-created BLF_TalentFrame
            local blf = getglobal("BLF_TalentFrame")
            if blf and not blf.octoSpecShowHooked then
                local oldShow = blf:GetScript("OnShow")
                blf:SetScript("OnShow", function()
                    if oldShow then oldShow() end
                    TryHook()
                    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                    local d = CreateFrame("Frame")
                    local e = 0
                    d:SetScript("OnUpdate", function()
                        e = e + arg1
                        if e < 0.15 then return end
                        this:SetScript("OnUpdate", nil)
                        TryHook()
                        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                    end)
                end)
                blf.octoSpecShowHooked = true
            end

            local tf2 = getglobal("TalentFrame")
            if tf2 and not tf2.octoSpecShowHooked then
                local oldShow = tf2:GetScript("OnShow")
                tf2:SetScript("OnShow", function()
                    if oldShow then oldShow() end
                    TryHook()
                    if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                    local d = CreateFrame("Frame")
                    local e = 0
                    d:SetScript("OnUpdate", function()
                        e = e + arg1
                        if e < 0.15 then return end
                        this:SetScript("OnUpdate", nil)
                        TryHook()
                        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                    end)
                end)
                tf2.octoSpecShowHooked = true
            end

            if IsTalentUIShown() then
                TryHook()
                if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
                OctoSpec._pendingTalentHighlight = nil
            end
        end)
        OctoSpec._talentHookTimer = tf
    end
end


function OctoSpec.UpdateHighlight()
    if OctoSpec.highlightFrame then
        OctoSpec.highlightFrame:Hide()
        OctoSpec.highlightFrame:SetParent(UIParent)
    end

    if not OctoSpecDB or OctoSpecDB.highlightNext == false then return end
    if not IsTalentUIShown() then return end

    local learnable = true
    local tab, index = OctoSpec.GetNextTalent(true)
    if not tab then
        tab, index = OctoSpec.GetNextTalent(false)
        learnable = false
    end
    if not tab or not index then return end

    -- Blizzard UI: only highlight on the selected tree tab.
    -- DFRL shows all three trees — always allow.
    local selected = GetSelectedTalentTab()
    if selected and selected ~= tab then
        -- Still try to find a DFRL-style button for this tab (all trees visible)
        if not IsDFRLTalentUI() then
            return
        end
    end

    local btn = FindTalentButton(tab, index)
    if not btn then return end

    if not OctoSpec.highlightFrame then
        local h = CreateFrame("Frame", "OctoSpecHighlightFrame", UIParent)
        h:SetFrameStrata("HIGH")
        h:SetFrameLevel(100)

        -- Outer ring around the talent (visible but not covering the icon art)
        local outer = h:CreateTexture(nil, "BACKGROUND")
        outer:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        outer:SetBlendMode("ADD")
        outer:SetPoint("TOPLEFT", h, "TOPLEFT", -6, 6)
        outer:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 6, -6)
        h.outer = outer

        local border = h:CreateTexture(nil, "BORDER")
        border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        border:SetBlendMode("ADD")
        border:SetPoint("TOPLEFT", h, "TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 2, -2)
        h.border = border

        -- Marker glow behind the small icon
        local glow = h:CreateTexture(nil, "ARTWORK")
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetWidth(32)
        glow:SetHeight(32)
        glow:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", -6, -6)
        h.glow = glow

        -- Marker icon bottom-left (keeps rank numbers clear on the bottom-right)
        local marker = h:CreateTexture(nil, "OVERLAY")
        marker:SetTexture("Interface\\Icons\\Ability_Marksmanship")
        marker:SetWidth(18)
        marker:SetHeight(18)
        marker:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
        h.marker = marker

        OctoSpec.highlightFrame = h
    end

    local h = OctoSpec.highlightFrame
    if learnable then
        h.outer:SetVertexColor(0, 1, 0, 0.85)
        h.border:SetVertexColor(0.3, 1, 0.3, 0.9)
        h.glow:SetVertexColor(0, 1, 0, 1)
        h.marker:SetVertexColor(1, 1, 1, 1)
    else
        h.outer:SetVertexColor(1, 0.85, 0, 0.8)
        h.border:SetVertexColor(1, 0.75, 0, 0.85)
        h.glow:SetVertexColor(1, 0.85, 0, 1)
        h.marker:SetVertexColor(1, 1, 1, 1)
    end
    h:SetParent(btn)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    h:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    h:SetFrameLevel(btn:GetFrameLevel() + 5)
    h:Show()
end

function OctoSpec.UpdatePriorityVisuals() end

------------------------------------------------------------
-- Full-build confirmation
------------------------------------------------------------
function OctoSpec.ConfirmApplyFull()
    if not OctoSpec.targetRanks and (not OctoSpec.priorityList or table.getn(OctoSpec.priorityList) == 0) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OctoSpec:|r No build or priority list loaded.")
        return
    end
    local available = UnitCharacterPoints("player")
    if available < 1 then
        local tab, index = OctoSpec.GetNextTalent()
        local name = tab and GetTalentInfo(tab, index)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OctoSpec:|r No talent points available." .. (name and (" Next would be: " .. name) or ""))
        return
    end

    if not OctoSpec.confirmFrame then
        local f = CreateFrame("Frame", "OctoSpecConfirmFrame", UIParent)
        f:SetWidth(320)
        f:SetHeight(120)
        f:SetPoint("CENTER", 0, 100)
        f:SetBackdrop(Backdrop())
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:Hide()

        local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOP", 0, -24)
        text:SetWidth(280)
        text:SetText("Apply the full remaining build?\nThis spends all available talent points.")

        local yes = MakeButton(f, 100, 24, "Yes", function()
            f:Hide()
            OctoSpec.ApplyFullBuild()
        end)
        yes:SetPoint("BOTTOMLEFT", 30, 20)

        local no = MakeButton(f, 100, 24, "Cancel", function() f:Hide() end)
        no:SetPoint("BOTTOMRIGHT", -30, 20)

        OctoSpec.confirmFrame = f
    end
    OctoSpec.confirmFrame:Show()
end

------------------------------------------------------------
-- Init
------------------------------------------------------------
local function ScheduleHighlightRefresh()
    local f = CreateFrame("Frame")
    local elapsed = 0
    f:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < 0.15 then return end
        this:SetScript("OnUpdate", nil)
        if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
    end)
end

local function HookToggleTalentFrame()
    if not ToggleTalentFrame then return end
    -- DFRL (and others) may replace ToggleTalentFrame after we load — re-wrap if needed
    if OctoSpec._wrappedToggle == ToggleTalentFrame then return end
    local previous = ToggleTalentFrame
    local function wrapper()
        previous()
        HookTalentButtons()
        ScheduleHighlightRefresh()
        local d = CreateFrame("Frame")
        local e = 0
        d:SetScript("OnUpdate", function()
            e = e + arg1
            if e < 0.2 then return end
            this:SetScript("OnUpdate", nil)
            HookTalentButtons()
            if OctoSpec.UpdateHighlight then OctoSpec.UpdateHighlight() end
        end)
    end
    ToggleTalentFrame = wrapper
    OctoSpec._wrappedToggle = wrapper
end

local uiFrame = CreateFrame("Frame")
uiFrame:RegisterEvent("PLAYER_LOGIN")
uiFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
uiFrame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        CreateMinimapButton()
        HookTalentButtons()
        HookToggleTalentFrame()
    elseif event == "PLAYER_ENTERING_WORLD" then
        HookTalentButtons()
        HookToggleTalentFrame()
    end
end)
