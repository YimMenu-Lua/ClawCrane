-- Inspired by https://gtaforums.com/topic/941626-shiny-claw-machine-mechanics/?do=findComment&comment=1072121836

local claw_crane_state = 0
local collided_plushie = 0
local rng_result       = 0
local sweet_spot       = 0.0
local plushie_spot     = vec3:new(0, 0, 0)
local claw_spot        = vec3:new(0, 0, 0)
local swk_pos_fixed    = false

-- Replace SWK's Y grab offset (-0.03463f) with PRB's Y grab offset (0.00628f) in little-endian format
-- This apparently breaks the plushie if the user tries to re-grab it after winning (shapetest fails). Re-entering the arcade fixes it.
fix_swk_y_offset = scr_patch:new("am_mp_arcade_claw_crane", "FSWKYO", "29 30 D8 0D BD", 1, {0x75, 0xC8, 0xCD, 0x3B}) -- Replace PUSH_CONST_F -0.03463 with PUSH_CONST_F 0.00628

-- Store distance result variable into a local so that we can read or modify it at runtime however the fuck we want
distance_result_store = scr_patch:new("am_mp_arcade_claw_crane", "DRS", "39 12 38 0A", 0, {0x3C, 0x1E}) -- Replace LOCAL_U8_STORE 18 with STATIC_U8_STORE 30
distance_result_load  = scr_patch:new("am_mp_arcade_claw_crane", "DRL", "38 12 29", 0, {0x3B, 0x1E}) -- Replace LOCAL_U8_LOAD 18 with STATIC_U8_LOAD 30

-- Can't use a script function or patch for these
local function GET_COLLIDED_PLUSHIE_SPOT()
    local plushie_coords  = ENTITY.GET_ENTITY_COORDS(collided_plushie, true)
    local plushie_heading = ENTITY.GET_ENTITY_HEADING(collided_plushie)
    return OBJECT.GET_OFFSET_FROM_COORD_AND_HEADING_IN_WORLD_COORDS(plushie_coords.x, plushie_coords.y, plushie_coords.z, plushie_heading, 0.0, 0.0, 0.0)
end

local function GET_CLAW_CRANE_SPOT()
    local claw_entity  = locals.get_int("am_mp_arcade_claw_crane", 262 + 25 + 3)
    local claw_coords  = ENTITY.GET_ENTITY_COORDS(claw_entity, true)
    local claw_heading = ENTITY.GET_ENTITY_HEADING(claw_entity)
    local grab_offset  = scr_function.call_script_function("am_mp_arcade_claw_crane", 0x6655F, "vector3", {
        { "int", collided_plushie }
    })
    return OBJECT.GET_OFFSET_FROM_COORD_AND_HEADING_IN_WORLD_COORDS(claw_coords.x, claw_coords.y, claw_coords.z, claw_heading, grab_offset.x, grab_offset.y, grab_offset.z)
end

-- This will fail if the user changes the cabinet location, but I don't care.
local function FIX_SWK_POSITION()
    if not swk_pos_fixed then
        local swk_entity = locals.get_int("am_mp_arcade_claw_crane", 262 + 25 + 12)
        if ENTITY.DOES_ENTITY_EXIST(swk_entity) then
            local swk_offset = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(swk_entity, 0.0, 0.020, 0.0)
            ENTITY.SET_ENTITY_COORDS(swk_entity, swk_offset.x, swk_offset.y, swk_offset.z, true, false, false, true)
            swk_pos_fixed = true
    	end
    end
end

local function RESTORE_SWK_POSITION()
    local swk_entity = locals.get_int("am_mp_arcade_claw_crane", 262 + 25 + 12)
    if ENTITY.DOES_ENTITY_EXIST(swk_entity) then
        local swk_offset = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(swk_entity, 0.0, -0.020, 0.0)
        ENTITY.SET_ENTITY_COORDS(swk_entity, swk_offset.x, swk_offset.y, swk_offset.z, true, false, false, true)
    end
end

local function DRAW_CLAW_CRANE_ESP()
    local c_screen_x = 0.0
    local c_screen_y = 0.0
    local p_screen_x = 0.0
    local p_screen_y = 0.0
    _, c_screen_x, c_screen_y = GRAPHICS.GET_SCREEN_COORD_FROM_WORLD_COORD(claw_spot.x, claw_spot.y, claw_spot.z, c_screen_x, c_screen_y)
    _, p_screen_x, p_screen_y = GRAPHICS.GET_SCREEN_COORD_FROM_WORLD_COORD(plushie_spot.x, plushie_spot.y, plushie_spot.z, p_screen_x, p_screen_y)
    
    local text = ""
    if claw_crane_state == 4 then
    	text = string.format("Distance: %.3f\nRNG: %d", distance_result, rng_result)
    else
        text = string.format("Distance: N/A\nRNG: N/A")
    end
    HUD.BEGIN_TEXT_COMMAND_DISPLAY_TEXT("STRING")
    HUD.ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME(text)
    HUD.SET_TEXT_RENDER_ID(1)
    HUD.SET_TEXT_OUTLINE()
    HUD.SET_TEXT_CENTRE(true)
    HUD.SET_TEXT_DROP_SHADOW()
    HUD.SET_TEXT_SCALE(0, 0.3)
    HUD.SET_TEXT_FONT(4)
    HUD.SET_TEXT_COLOUR(255, 255, 255, 240)
    HUD.END_TEXT_COMMAND_DISPLAY_TEXT(p_screen_x, p_screen_y, 0)
    
    GRAPHICS.REQUEST_STREAMED_TEXTURE_DICT("CommonMenu", false)
    GRAPHICS.DRAW_LINE(claw_spot.x, claw_spot.y, claw_spot.z, plushie_spot.x, plushie_spot.y, plushie_spot.z, 255, 0, 0, 255)
    GRAPHICS.DRAW_SPRITE("CommonMenu", "common_medal", c_screen_x, c_screen_y, 0.02, 0.04, 0.0, 255, 0, 0, 255, false, 0)
    GRAPHICS.DRAW_SPRITE("CommonMenu", "common_medal", p_screen_x, p_screen_y, 0.02, 0.04, 0.0, 255, 0, 0, 255, false, 0)
end

event.register_handler(menu_event.ScriptsReloaded, function()
    fix_swk_y_offset:disable_patch()
    distance_result_store:disable_patch()
    distance_result_load:disable_patch()
    RESTORE_SWK_POSITION()
end)

script.register_looped("Claw Crane", function()
    if script.is_active("am_mp_arcade_claw_crane") then
        claw_crane_state = locals.get_int("am_mp_arcade_claw_crane", 262 + 43)
        collided_plushie = locals.get_int("am_mp_arcade_claw_crane", 122 + (1 + (self.get_id() * 4)) + 2)
        if collided_plushie ~= 0 then
            rng_result      = locals.get_int("am_mp_arcade_claw_crane", 262 + 10)
            distance_result = locals.get_float("am_mp_arcade_claw_crane", 30)
            plushie_spot    = GET_COLLIDED_PLUSHIE_SPOT()
            claw_spot       = GET_CLAW_CRANE_SPOT()
            
            DRAW_CLAW_CRANE_ESP()
        end
        FIX_SWK_POSITION()
    end
end)