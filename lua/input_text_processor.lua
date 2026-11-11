return function(key_event, env)
    if key_event:repr() ~= "Control+o" then
        return 2
    end

    local ctx = env.engine.context
    local cand = ctx:get_selected_candidate()
    if not cand then
        return 2
    end

    local src = cand.text
    if not src or src == "" then
        return 2
    end

    ctx:set_property("translation_highlighted", src)
    ctx:set_property("translation_triggered", "1")
    ctx:refresh_non_confirmed_composition()
    return 1
end