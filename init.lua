-- ============================================================
-- Minimizar ao clicar no ícone da Dock (só quando app está em foco)
-- Finder: minimiza imediatamente (sem arrastar)
-- Outras apps: deteta arrastar vs clique (estilo Linux)
-- ============================================================

local menuIsOpen = false
local dragThreshold = 5
local clickStart = nil
local wasDragged = false

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

local function hasVisibleWindows(app)
    for _, win in ipairs(app:allWindows()) do
        if not win:isMinimized() and win:isVisible() and win:title() ~= "" then
            return true
        end
    end
    return false
end

local function findAppByTitle(title)
    -- Primeiro tenta correspondência exata
    for _, a in ipairs(hs.application.runningApplications()) do
        if a:name() == title then
            return a
        end
    end
    -- Depois tenta encontrar se o nome da app contém o título ou vice-versa
    for _, a in ipairs(hs.application.runningApplications()) do
        local appName = a:name()
        if appName and appName ~= "" then
            if string.find(appName, title, 1, true) or string.find(title, appName, 1, true) then
                return a
            end
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
    clickStart = nil
    wasDragged = false
    
    if menuIsOpen then
        menuIsOpen = false
        return false
    end

    local pos = hs.mouse.absolutePosition()
    local screen = hs.screen.mainScreen():frame()
    if pos.y < (screen.y + screen.h - 80) then return false end

    local title = getDockItemTitle(pos)
    if not title then return false end

    if title == "Finder" then
        local finder = hs.application.get("Finder")
        if not finder then return false end
        if not hasVisibleWindows(finder) then return false end
        local frontApp = hs.application.frontmostApplication()
        if frontApp and frontApp:bundleID() == finder:bundleID() then
            local win = getFirstVisibleWindow(finder)
            if win then
                win:minimize()
                return true
            end
        end
        return false
    end

    local clickedApp = findAppByTitle(title)
    
    if not clickedApp then return false end

    local frontApp = hs.application.frontmostApplication()
    if frontApp and frontApp:bundleID() == clickedApp:bundleID() then
        local win = getFirstVisibleWindow(clickedApp)
        if win then
            clickStart = {
                x = pos.x,
                y = pos.y,
                window = win
            }
        end
    end

    return false
end):start()

dockDragWatcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseDragged}, function(event)
    if not clickStart then return false end
    
    local pos = hs.mouse.absolutePosition()
    local dx = math.abs(pos.x - clickStart.x)
    local dy = math.abs(pos.y - clickStart.y)
    
    if dx >= dragThreshold or dy >= dragThreshold then
        wasDragged = true
    end
    
    return false
end):start()

dockMouseUpWatcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseUp}, function(event)
    if not clickStart then return false end

    if not wasDragged then
        local win = clickStart.window
        
        local finder = hs.application.get("Finder")
        if finder then
            finder:activate()
        end
        hs.timer.doAfter(0.05, function()
            win:minimize()
        end)
    end

    clickStart = nil
    wasDragged = false
    return false
end):start()
