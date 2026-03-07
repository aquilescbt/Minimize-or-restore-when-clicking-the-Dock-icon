-- ============================================================
-- Minimizar ao clicar no ícone da Dock (só quando app está em foco)
-- Option (⌥) + arrastar = move ícone na Dock normalmente
-- ============================================================

local menuIsOpen = false

local function getDockItemTitle(pos)
    local element = hs.axuielement.systemWideElement():elementAtPosition(pos.x, pos.y)
    if element then
        local role = element:attributeValue("AXRole")
        local title = element:attributeValue("AXTitle")
        if role == "AXDockItem" and title then
            return title
        end
    end
    local dock = hs.axuielement.applicationElement(hs.application.get("Dock"))
    if dock then
        for _, child in ipairs(dock:attributeValue("AXChildren") or {}) do
            for _, item in ipairs(child:attributeValue("AXChildren") or {}) do
                local itemPos = item:attributeValue("AXPosition")
                local itemSize = item:attributeValue("AXSize")
                if itemPos and itemSize then
                    if pos.x >= itemPos.x and pos.x <= itemPos.x + itemSize.w and
                       pos.y >= itemPos.y and pos.y <= itemPos.y + itemSize.h then
                        return item:attributeValue("AXTitle")
                    end
                end
            end
        end
    end
    return nil
end

local function getFirstVisibleWindow(app)
    for _, win in ipairs(app:allWindows()) do
        if not win:isMinimized() and win:isVisible() and win:title() ~= "" then
            return win
        end
    end
    for _, win in ipairs(app:allWindows()) do
        if not win:isMinimized() and win:isVisible() then
            return win
        end
    end
    return nil
end

dockRightClickWatcher = hs.eventtap.new({hs.eventtap.event.types.rightMouseDown}, function(event)
    local pos = hs.mouse.absolutePosition()
    local screen = hs.screen.mainScreen():frame()
    if pos.y >= (screen.y + screen.h - 80) then
        menuIsOpen = true
    end
    return false
end):start()

dockClickWatcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
    local flags = event:getFlags()
    if flags.alt then return false end

    if menuIsOpen then
        menuIsOpen = false
        return false
    end

    local pos = hs.mouse.absolutePosition()
    local screen = hs.screen.mainScreen():frame()
    if pos.y < (screen.y + screen.h - 80) then return false end

    local title = getDockItemTitle(pos)
    if not title then return false end

    local clickedApp = nil
    for _, a in ipairs(hs.application.runningApplications()) do
        if a:name() == title then
            clickedApp = a
            break
        end
    end
    
    if not clickedApp then return false end

    local frontApp = hs.application.frontmostApplication()
    if frontApp and frontApp:bundleID() == clickedApp:bundleID() then
        local win = getFirstVisibleWindow(clickedApp)
        if win then
            win:minimize()
            return true
        end
    end

    return false
end):start()
