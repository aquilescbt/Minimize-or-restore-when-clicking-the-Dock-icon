-- ============================================================
-- Minimizar/restaurar ao clicar no ícone da Dock
-- Option (⌥) + arrastar = move ícone na Dock normalmente
-- ============================================================

local menuIsOpen = false

-- LIFO: rastreia ordem de minimização para restaurar a última janela minimizada
local isScriptMinimizing = false
local isScriptUnminimizing = false
local minimizeOrder = {}

local function trackMinimizedWindow(app, win)
    local appName = app:name()
    if not minimizeOrder[appName] then minimizeOrder[appName] = {} end
    local winId = win:id()
    for _, id in ipairs(minimizeOrder[appName]) do
        if id == winId then return end
    end
    table.insert(minimizeOrder[appName], winId)
end

local function getLastMinimizedWindow(app)
    local appName = app:name()
    if not minimizeOrder[appName] or #minimizeOrder[appName] == 0 then return nil end
    for i = #minimizeOrder[appName], 1, -1 do
        local winId = minimizeOrder[appName][i]
        for _, win in ipairs(app:allWindows()) do
            if win:id() == winId then
                table.remove(minimizeOrder[appName], i)
                if win:isMinimized() then return win end
                break
            end
        end
    end
    return nil
end

local function isOnlyUnnamedWindows(app)
    local total = 0
    local unnamed = 0
    for _, win in ipairs(app:allWindows()) do
        total = total + 1
        if win:title() == "" then unnamed = unnamed + 1 end
    end
    return total > 0 and total == unnamed
end

local function getFirstVisibleWindow(app)
    for _, win in ipairs(app:allWindows()) do
        if not win:isMinimized() and win:isVisible() and win:title() ~= "" then
            return win
        end
    end
    if isOnlyUnnamedWindows(app) then
        for _, win in ipairs(app:allWindows()) do
            if not win:isMinimized() and win:isVisible() then
                return win
            end
        end
    end
    return nil
end

local function minimizeApp(app)
    local win = getFirstVisibleWindow(app)
    if win then
        isScriptMinimizing = true
        trackMinimizedWindow(app, win)
        win:minimize()
        hs.timer.doAfter(0.3, function() isScriptMinimizing = false end)
    else
        app:activate()
        hs.timer.doAfter(0.15, function()
            local w = getFirstVisibleWindow(app)
            if w then
                isScriptMinimizing = true
                trackMinimizedWindow(app, w)
                w:minimize()
                hs.timer.doAfter(0.3, function() isScriptMinimizing = false end)
            end
        end)
    end
end

local function unminimizeWindow(win)
    isScriptUnminimizing = true
    win:unminimize()
    hs.timer.doAfter(0.3, function() isScriptUnminimizing = false end)
end

local function openNewWindow(app)
    if app:name() == "Finder" then
        hs.osascript.applescript('tell application "Finder" to make new Finder window to home')
        hs.timer.doAfter(0.3, function()
            hs.application.get("Finder"):activate()
        end)
    else
        app:activate()
        hs.timer.doAfter(0.1, function()
            hs.eventtap.keyStroke({"cmd"}, "n")
        end)
    end
end

local function getDockItemTitle(pos)
    -- Método primário: AXDockItem direto
    local element = hs.axuielement.systemWideElement():elementAtPosition(pos.x, pos.y)
    if element then
        local role = element:attributeValue("AXRole")
        local title = element:attributeValue("AXTitle")
        if role == "AXDockItem" and title then
            return title
        end
    end
    -- Fallback: percorrer os filhos da Dock manualmente
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

local function handleFinder()
    local finder = hs.application.get("Finder")
    if not finder then
        hs.application.launchOrFocus("Finder")
        return true
    end

    -- Oculto → unhide sem abrir nova janela
    if finder:isHidden() then
        finder:unhide()
        finder:activate()
        return true
    end

    local hasVisible = false
    local lastMinimized = nil

    for _, win in ipairs(finder:allWindows()) do
        if win:title() == "" then goto continue end
        if win:isMinimized() then lastMinimized = win end
        if not win:isMinimized() and win:isVisible() then hasVisible = true end
        ::continue::
    end

    -- Só janelas minimizadas → restaurar a última (LIFO)
    if not hasVisible then
        local lifoWin = getLastMinimizedWindow(finder)
        local winToRestore = lifoWin or lastMinimized
        if winToRestore then
            unminimizeWindow(winToRestore)
            finder:activate()
        else
            openNewWindow(finder)
        end
        return true
    end

    -- Tem janelas visíveis → só minimiza se já estiver em foco, senão traz para a frente
    local frontApp = hs.application.frontmostApplication()
    if frontApp and frontApp:bundleID() == finder:bundleID() then
        minimizeApp(finder)
    else
        finder:activate()
    end
    return true
end

local function handleApp(app)
    -- App oculta (hide) → mostrar sem abrir nova janela
    if app:isHidden() then
        app:unhide()
        app:activate()
        return true
    end

    local hasVisible = false
    local pwa = isOnlyUnnamedWindows(app)

    for _, win in ipairs(app:allWindows()) do
        if not pwa and win:title() == "" then goto continue end
        if not win:isMinimized() and win:isVisible() then hasVisible = true end
        ::continue::
    end

    -- Sem janelas visíveis → restaurar a última minimizada (LIFO)
    if not hasVisible then
        local lastMinimized = getLastMinimizedWindow(app)
        if lastMinimized then
            unminimizeWindow(lastMinimized)
            app:activate()
        else
            openNewWindow(app)
        end
        return true
    end

    -- Tem janelas visíveis → só minimiza se já estiver em foco, senão traz para a frente
    local frontApp = hs.application.frontmostApplication()
    if frontApp and frontApp:bundleID() == app:bundleID() then
        minimizeApp(app)
    else
        app:activate()
    end
    return true
end

local hideOnlyApps = {
    ["System Preferences"] = true,
    ["System Settings"] = true,
    ["Definições do Sistema"] = true,
}

local function handleHideOnlyApp(app)
    local hasVisible = false
    local lastMinimized = nil
    local pwa = isOnlyUnnamedWindows(app)

    for _, win in ipairs(app:allWindows()) do
        if not pwa and win:title() == "" then goto continue end
        if win:isMinimized() then lastMinimized = win end
        if not win:isMinimized() and win:isVisible() then hasVisible = true end
        ::continue::
    end

    if hasVisible then
        local frontApp = hs.application.frontmostApplication()
        if frontApp and frontApp:bundleID() == app:bundleID() then
            minimizeApp(app)
        else
            app:activate()
        end
        return true
    elseif lastMinimized then
        local lifoWin = getLastMinimizedWindow(app)
        unminimizeWindow(lifoWin or lastMinimized)
        app:activate()
        return true
    else
        if app:isHidden() then
            app:unhide()
            app:activate()
        else
            app:hide()
        end
        return true
    end
end

-- ============================================================
-- Watchers
-- ============================================================

-- Rastreia minimizações externas (botão amarelo, ⌘M, etc.)
windowWatcher = hs.window.filter.new(nil)
windowWatcher:subscribe(hs.window.filter.windowMinimized, function(win)
    if isScriptMinimizing then return end
    local app = win:application()
    if app then trackMinimizedWindow(app, win) end
end)

-- Remove da lista quando restaurado externamente
windowWatcher:subscribe(hs.window.filter.windowUnminimized, function(win)
    if isScriptUnminimizing then return end
    local app = win:application()
    if not app then return end
    local appName = app:name()
    if not minimizeOrder[appName] then return end
    local winId = win:id()
    for i = #minimizeOrder[appName], 1, -1 do
        if minimizeOrder[appName][i] == winId then
            table.remove(minimizeOrder[appName], i)
            break
        end
    end
end)

windowWatcher:subscribe(hs.window.filter.windowDestroyed, function(win)
    local winId = win:id()
    for _, list in pairs(minimizeOrder) do
        for i = #list, 1, -1 do
            if list[i] == winId then table.remove(list, i) end
        end
    end
end)

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

    if title == "Finder" then return handleFinder() end

    -- Procura a app pelo nome exato entre todos os processos em execução.
    -- Mais robusto que hs.application.get() que falha quando o nome do processo
    -- difere do título da Dock (ex: Stremio, apps Electron, etc.)
    local clickedApp = nil
    for _, a in ipairs(hs.application.runningApplications()) do
        if a:name() == title then
            clickedApp = a
            break
        end
    end
    if not clickedApp then return false end

    if hideOnlyApps[title] then return handleHideOnlyApp(clickedApp) end

    return handleApp(clickedApp)
end):start()
