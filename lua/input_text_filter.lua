local translation = require("translate_all")

local function strip_quotes(s)
    if type(s) ~= "string" then return s end
    s = s:gsub('^["“]', '')
    s = s:gsub('[”"]$', '')
    return s
end

local function is_chinese_text(s)
    local c = utf8.codepoint(s, 1)
    return c >= 0x4E00 and c <= 0x9FFF
end

local function is_english_text(s)
    local c = utf8.codepoint(s, 1)
    return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)
end

local function trans(text)
    local api = translation.config.default_api
    local from, to

    if is_chinese_text(text) then
        if api == "google" then from, to = "zh-CN", "en"
        elseif api == "youdao" then from, to = "zh-CHS", "en"
        else from, to = "zh", "en" end
    elseif is_english_text(text) then
        if api == "google" then from, to = "en", "zh-CN"
        elseif api == "youdao" then from, to = "en", "zh-CHS"
        else from, to = "en", "zh" end
    else
        if api == "google" then from, to = "zh-CN", "en"
        elseif api == "youdao" then from, to = "zh-CHS", "en"
        else from, to = "zh", "en" end
    end

    local fn = translation[api]
    if type(fn) ~= "function" then return nil end
    return fn(text, from, to)
end

return function(input, env)
    local ctx = env.engine.context
    local input_text = ctx.input

    -- 仅在 Ctrl+O 标记存在时处理
    if ctx:get_property("translation_triggered") == "1" then
        ctx:set_property("translation_triggered", "")
        local highlighted = ctx:get_property("translation_highlighted") or ""
        ctx:set_property("translation_highlighted", "")

        if highlighted == "" then
            yield(Candidate("error", 0, 0, "[无高亮候选项]", "请先高亮候选词"))
            for cand in input:iter() do yield(cand) end
            return
        end

        local res = trans(highlighted)
        if not res then
            yield(Candidate("error", 0, #input_text, "[翻译失败]", "请检查网络或API配置"))
            for cand in input:iter() do yield(cand) end
            return
        end

        yield(Candidate("translation", 0, #input_text, strip_quotes(res), "[译] " .. highlighted))
        for cand in input:iter() do yield(cand) end
        return
    end

    -- 非触发状态，原样输出候选
    for cand in input:iter() do
        yield(cand)
    end
end