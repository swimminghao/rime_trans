local translation = require("trans-all")

local function strip_quotes(s)
    if type(s) ~= "string" then return s end
    s = s:gsub('^["“]', '')
    s = s:gsub('[”"]$', '')
    return s
end

-- 判断是否中文
local function is_chinese_text(s)
    local c = utf8.codepoint(s, 1)
    return c >= 0x4E00 and c <= 0x9FFF
end
-- 判断是否英文字母
local function is_english_text(s)
    local c = utf8.codepoint(s, 1)
    return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)
end

-- 自动选语种 + 调用对应API
local function trans(text)
    local api = translation.config.default_api
    local from, to

    if is_chinese_text(text) then
        -- 中文 → 英文
        if api == "google" then
            from, to = "zh-CN", "en"
        elseif api == "youdao" then
            from, to = "zh-CHS", "en"
        else
            from, to = "zh", "en"
        end
    elseif is_english_text(text) then
        -- 英文 → 中文
        if api == "google" then
            from, to = "en", "zh-CN"
        elseif api == "youdao" then
            from, to = "en", "zh-CHS"
        else
            from, to = "en", "zh"
        end
    else
        -- 分不清，默认中译英
        if api == "google" then
            from, to = "zh-CN", "en"
        elseif api == "youdao" then
            from, to = "zh-CHS", "en"
        else
            from, to = "zh", "en"
        end
    end

    local fn = translation[api]
    if type(fn) ~= "function" then
        return nil
    end
    return fn(text, from, to)
end

local function is_chinese_character(char)
    local code = utf8.codepoint(char)
    return code >= 0x4E00 and code <= 0x9FFF
end

-- 处理器模块
local processor = {}

-- 按键处理函数
function processor.func(key_event, env)
    local context = env.engine.context
    if key_event:repr() == "Control+o" then
        local selected_candidate = context:get_selected_candidate()
        if selected_candidate then
            context:set_property("translation_highlighted", selected_candidate.text)
        end
        context:set_property("translation_triggered", "1")
        context:refresh_non_confirmed_composition()
        return 1
    end
    return 2
end

-- 过滤器模块
local filter = {}

function filter.func(input, env)
    local context = env.engine.context
    local input_text = context.input

    -- 模式1：Ctrl+o 快捷键触发
    local triggered = context:get_property("translation_triggered") == "1"
    if triggered then
        context:set_property("translation_triggered", "")
        local highlighted = context:get_property("translation_highlighted") or ""
        context:set_property("translation_highlighted", "")
        if highlighted == "" then
            yield(Candidate("error", 0, 0, "[无高亮候选项]", "请先高亮候选词"))
            for cand in input:iter() do yield(cand) end
            return
        end
        local translated_text = trans(highlighted)
        translated_text = strip_quotes(translated_text)
        if not translated_text then
            yield(Candidate("error", 0, #input_text, "[翻译失败]", "请检查网络或API配置"))
            for cand in input:iter() do yield(cand) end
            return
        end
        yield(Candidate("translation", 0, #input_text, translated_text, "[译] "..highlighted))
        for cand in input:iter() do yield(cand) end
        return
    end

    -- 模式2：后缀 '' 自动翻译
    if input_text:sub(-2) == "''" then
        local raw_input = {}
        local count = 0
        for cand in input:iter() do
            if not cand.text then
                goto continue
            end
            local first_char
            local success = pcall(function()
                first_char = utf8.char(utf8.codepoint(cand.text))
            end)
            if not success then
                goto continue
            end
            if is_chinese_character(first_char) then
                if count < 6 then
                    count = count + 1
                    table.insert(raw_input, cand.text)
                else
                    break
                end
            end
            ::continue::
        end
        if #raw_input == 0 then
            for cand in input:iter() do yield(cand) end
            return
        end
        local translated_text = trans(raw_input[1])
        translated_text = strip_quotes(translated_text)
        if not translated_text then
            yield(Candidate("error", 0, #input_text, "[翻译失败]", "请检查网络或API配置"))
            for cand in input:iter() do yield(cand) end
            return
        end
        yield(Candidate("translation", 0, #input_text, translated_text, "[译] " .. raw_input[1]))
        for cand in input:iter() do yield(cand) end
    else
        for cand in input:iter() do yield(cand) end
    end
end

function filter.fini(env)
    local ctx = env.engine.context
    ctx:set_property("translation_triggered", "")
    ctx:set_property("translation_highlighted", "")
end

return { processor = processor, filter = filter }
