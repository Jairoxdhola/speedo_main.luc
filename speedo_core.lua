-- =================================================================================================
-- 1. CONFIGURATION & HASHES
-- =================================================================================================
local H_TOGGLE      = Utils.Joaat("Speedo_V10_Toggle")
local H_UNIT        = Utils.Joaat("Speedo_V10_Unit")
local H_SIZE        = Utils.Joaat("Speedo_V10_Size")
local H_COLOR       = Utils.Joaat("Speedo_V10_Color")
local H_TIMER       = Utils.Joaat("Speedo_V10_Timer")
local H_RPM         = Utils.Joaat("Speedo_V10_RPM")

-- Default Settings
local posX, posY    = 0.88, 0.82 -- Un poco más arriba para que se luzca
local currentRadius = 110        -- Más grande por defecto para ver los detalles
local maxSpeed      = 260
local isDragging    = false
local wasInVehicle  = false
local timerRunning, timerStart, timerResult, timerReady = false, 0, 0.0, false

-- Natives
local N_GET_RPM     = 0xAF96695647D0E4C4
local N_GET_GEAR    = 0xB4F4E566C534D753

-- Visual Colors (Glass Theme)
local C_BG          = {10, 10, 15, 240}    -- Fondo casi opaco
local C_SHADOW      = {0, 0, 0, 150}       -- Sombra de caída
local C_TEXT        = {255, 255, 255, 255}
local C_HEALTH_OK   = {0, 255, 100, 220}
local C_HEALTH_BAD  = {255, 0, 0, 220}
local C_GLASS       = {255, 255, 255, 15}  -- Brillo del cristal (muy sutil)

local ANG_START     = 135 
local ANG_END       = 405

-- =================================================================================================
-- 2. HELPER FUNCTIONS
-- =================================================================================================
local function ToRad(deg) return deg * (math.pi / 180) end

local function Notify(title, msg)
    GUI.AddToast(title, msg, 3000, eToastPos.TOP_RIGHT)
end

local function IsMouseHovering(mx, my, cx, cy, r)
    local dx, dy = mx - cx, my - cy
    return (dx*dx + dy*dy) <= (r*r)
end

local function GetVehicleName(veh)
    if veh == nil then return "Vehicle" end
    local modelHash = veh.ModelInfo.Model
    local nameKey = GTA.GetDisplayNameFromHash(modelHash)
    local realName = GTA.GetLabelText(nameKey)
    if realName == "NULL" or realName == nil then return "Unknown Vehicle" end
    return realName
end

local function GetVehicleRPM(veh)
    local handle = GTA.PointerToHandle(veh)
    return Natives.InvokeFloat(N_GET_RPM, handle)
end

local function GetVehicleGear(veh)
    local handle = GTA.PointerToHandle(veh)
    return Natives.InvokeInt(N_GET_GEAR, handle)
end

-- =================================================================================================
-- 3. DRAWING ENGINE (GLASS DESIGN)
-- =================================================================================================
local function DrawGaugeV10(cx, cy, speed, rpm, gear, healthPct, customColor)
    local r = currentRadius
    
    -- 1. DROP SHADOW (Profundidad 3D)
    -- Dibujamos un círculo negro desplazado un poco hacia abajo y derecha
    ImGui.BgAddCircleFilled(cx + 5, cy + 5, r, C_SHADOW[1], C_SHADOW[2], C_SHADOW[3], C_SHADOW[4], 70)

    -- 2. OUTER GLOW (Resplandor del color del tema)
    -- Un círculo más grande, muy transparente, del color elegido
    ImGui.BgAddCircleFilled(cx, cy, r + 10, customColor[1], customColor[2], customColor[3], 40, 50)

    -- 3. MAIN BACKGROUND
    ImGui.BgAddCircleFilled(cx, cy, r, C_BG[1], C_BG[2], C_BG[3], C_BG[4], 80) 
    
    -- 4. DYNAMIC RPM RING
    -- El anillo exterior cambia de opacidad según las RPM
    if FeatureMgr.IsFeatureToggled(H_RPM) then
        local segments = 50
        for i = 0, segments do
            local p1 = i / segments
            local p2 = (i + 1) / segments
            
            local a1 = ToRad(ANG_START + (ANG_END - ANG_START) * p1)
            local a2 = ToRad(ANG_START + (ANG_END - ANG_START) * p2)
            
            local rx1 = cx + (r - 4) * math.cos(a1)
            local ry1 = cy + (r - 4) * math.sin(a1)
            local rx2 = cx + (r - 4) * math.cos(a2)
            local ry2 = cy + (r - 4) * math.sin(a2)
            
            local rR, rG, rB = customColor[1], customColor[2], customColor[3]
            local alpha = 100 -- Base alpha
            
            -- Si las RPM superan este segmento, brillamos más
            if p1 < rpm then 
                alpha = 255
                if p1 > 0.85 then rR, rG, rB = 255, 50, 50 end -- Redline
            else
                rR, rG, rB = 80, 80, 80 -- Apagado
            end

            ImGui.BgAddLine(rx1, ry1, rx2, ry2, rR, rG, rB, alpha, 5.0)
        end
    else
        -- Borde estático si RPM está apagado
        ImGui.BgAddCircle(cx, cy, r, 100, 100, 100, 150, 80, 2.0)
    end

    -- 5. TICKS (Marcas)
    for i = 0, maxSpeed, 20 do
        local pct = i / maxSpeed
        local ang = ToRad(ANG_START + (ANG_END - ANG_START) * pct)
        local cosA, sinA = math.cos(ang), math.sin(ang)
        
        local r1 = r - 15
        local r2 = r - 25
        local x1, y1 = cx + r1*cosA, cy + r1*sinA
        local x2, y2 = cx + r2*cosA, cy + r2*sinA
        
        ImGui.BgAddLine(x1, y1, x2, y2, 255, 255, 255, 220, 2.5)
        
        local tx = cx + (r - 42) * cosA - 7
        local ty = cy + (r - 42) * sinA - 7
        ImGui.BgAddText(tx, ty, tostring(i), 255, 255, 255, 200)
    end

    -- 6. TEXT INFO
    if gear == 0 then gear = "R" elseif gear == 1 then gear = "1" else gear = tostring(gear) end
    ImGui.BgAddText(cx - 5, cy - 25, gear, 180, 180, 180, 255) -- Gear gris arriba
    
    -- Speed Big
    local speedStr = string.format("%d", math.floor(speed))
    ImGui.BgAddText(cx - 15, cy + 15, speedStr, 255, 255, 255, 255) 

    -- 7. NEEDLE (Aguja fina y precisa)
    local sLim = speed > maxSpeed and maxSpeed or speed
    local nAng = ToRad(ANG_START + (ANG_END - ANG_START) * (sLim / maxSpeed))
    local nLen = r - 20
    local nx = cx + nLen * math.cos(nAng)
    local ny = cy + nLen * math.sin(nAng)
    
    -- Dibuja la aguja del color personalizado
    ImGui.BgAddLine(cx, cy, nx, ny, customColor[1], customColor[2], customColor[3], 255, 3.0)
    
    -- Centro metálico
    ImGui.BgAddCircleFilled(cx, cy, 8, 50, 50, 50, 255, 20)
    ImGui.BgAddCircle(cx, cy, 8, 150, 150, 150, 255, 20, 1.5)

    -- 8. HEALTH BAR (Discreta abajo)
    local hW = r * 0.5
    local hX, hY = cx - (hW / 2), cy + (r * 0.6)
    local hColor = (healthPct > 0.4) and C_HEALTH_OK or C_HEALTH_BAD
    ImGui.BgAddRectFilled(hX, hY, hX + hW, hY + 4, 30, 30, 30, 200, 2.0)
    ImGui.BgAddRectFilled(hX, hY, hX + (hW * healthPct), hY + 4, hColor[1], hColor[2], hColor[3], 200, 2.0)

    -- 9. GLASS REFLECTION (Efecto de Cristal)
    -- Un arco blanco semitransparente en la parte superior para simular reflejo
    -- Usamos un círculo recortado visualmente o simplemente un círculo degradado arriba
    ImGui.BgAddCircleFilled(cx, cy - (r * 0.5), r * 1.2, 255, 255, 255, 5, 60) -- Muy sutil
end

-- =================================================================================================
-- 4. MAIN LOGIC
-- =================================================================================================
local function OnPresentCallback()
    if not FeatureMgr.IsFeatureToggled(H_TOGGLE) then return end

    local veh = GTA.GetLocalVehicle()
    local isInVehicle = (veh ~= nil and veh:IsVehicle())

    -- Notification Logic
    if isInVehicle and not wasInVehicle then
        local vehName = GetVehicleName(veh)
        Notify("Dashboard V10", "Connected: " .. vehName)
        timerResult = 0.0
    elseif not isInVehicle and wasInVehicle then
        Notify("Dashboard V10", "Disconnected")
    end
    wasInVehicle = isInVehicle

    if isInVehicle then
        currentRadius = FeatureMgr.GetFeatureInt(H_SIZE)
        local r, g, b, a = FeatureMgr.GetFeatureColor(H_COLOR)
        local userColor = {r, g, b, a}

        local vel = veh:GetVelocity()
        local speedMs = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
        local speedVal = speedMs * 3.6
        local targetSpeed = 100.0
        
        if FeatureMgr.GetFeatureListIndex(H_UNIT) == 1 then 
            speedVal = speedMs * 2.23694; targetSpeed = 60.0
        end

        local rpm = GetVehicleRPM(veh)
        local gear = GetVehicleGear(veh)
        local health = veh.BodyHealth / 1000.0

        if FeatureMgr.IsFeatureToggled(H_TIMER) then
            if speedVal < 1.0 then
                timerReady = true; timerRunning = false
            elseif timerReady and speedVal > 1.0 and not timerRunning then
                timerRunning = true; timerReady = false; timerStart = Time.Get(); timerResult = 0.0
            elseif timerRunning then
                if speedVal >= targetSpeed then
                    timerRunning = false; timerResult = Time.Get() - timerStart
                    Notify("0-100 Record", string.format("Time: %.2fs", timerResult))
                end
            end
        end

        local dw, dh = ImGui.GetDisplaySize()
        local cx, cy = dw * posX, dh * posY

        if GUI.IsOpen() then
            local mx, my = ImGui.GetMousePos()
            if ImGui.IsMouseDown(0) then
                if not isDragging and IsMouseHovering(mx, my, cx, cy, currentRadius) then
                    isDragging = true
                elseif isDragging then
                    posX = mx / dw; posY = my / dh
                end
            else
                isDragging = false
            end
        end

        DrawGaugeV10(cx, cy, speedVal, rpm, gear, health, userColor)
        
        if FeatureMgr.IsFeatureToggled(H_TIMER) then
            local text = string.format("0-100: %.2fs", timerResult)
            if timerRunning then text = string.format("%.1f...", Time.Get() - timerStart) end
            ImGui.BgAddText(cx - 30, cy + currentRadius + 10, text, 255, 255, 255, 200)
        end
    end
end

-- =================================================================================================
-- 5. MENU REGISTRATION (WITH DESCRIPTIONS)
-- =================================================================================================

-- Toggle
FeatureMgr.AddFeature(H_TOGGLE, "Enable Glass HUD", eFeatureType.Toggle, 
    "Toggles the visual speedometer overlay on/off.", -- Description
    function(f) if f:IsToggled() then Notify("System", "HUD On") else Notify("System", "HUD Off") end end
)

-- RPM
FeatureMgr.AddFeature(H_RPM, "Dynamic RPM Ring", eFeatureType.Toggle, 
    "Enables the outer ring that lights up based on engine revs.")

-- Timer
FeatureMgr.AddFeature(H_TIMER, "0-100 Performance", eFeatureType.Toggle, 
    "Automatically tracks acceleration time from stop to 100km/h.")

-- Size
local fSize = FeatureMgr.AddFeature(H_SIZE, "Interface Scale", eFeatureType.SliderInt, 
    "Adjust the size of the gauge (Pixels).")
fSize:SetLimitValues(80, 250):SetValue(110)

-- Unit
local fUnit = FeatureMgr.AddFeature(H_UNIT, "Measurement Unit", eFeatureType.Combo, 
    "Choose between Metric (KM/H) and Imperial (MPH).")
fUnit:SetList({[0]="KM/H", [1]="MPH"})

-- Color
local fColor = FeatureMgr.AddFeature(H_COLOR, "Glow Color", eFeatureType.InputColor3, 
    "Pick the color for the needle and background glow.")
fColor:SetColor(0, 190, 255, 255) -- Default Cyan

-- Register Loop
EventMgr.RegisterHandler(eLuaEvent.ON_PRESENT, OnPresentCallback)

-- Menu Tab
ClickGUI.AddTab("Glass HUD V10", function()
    if ClickGUI.BeginCustomChildWindow("Settings") then
        
        ClickGUI.RenderFeature(H_TOGGLE)
        ImGui.Separator()
        
        ImGui.Text("Features")
        ClickGUI.RenderFeature(H_RPM)
        ClickGUI.RenderFeature(H_TIMER)
        ImGui.Separator()
        
        ImGui.Text("Style")
        ClickGUI.RenderFeature(H_SIZE)
        ClickGUI.RenderFeature(H_UNIT)
        ClickGUI.RenderFeature(H_COLOR)

        ImGui.TextDisabled("Tip: Drag gauge with mouse to move.")

        ClickGUI.EndCustomChildWindow()
    end
end)

Notify("System", "Glass HUD V10 Loaded")
