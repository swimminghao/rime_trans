-- 不再依赖 simplehttp、sha2，json 保留（librime-lua自带）
local json = require("json")

-- 翻译API配置（原样保留，你不用改）
local config = {
    -- 选择使用的翻译API: "google", "deepl", "microsoft", "deeplx", "niutrans", "youdao", "baidu"
    -- 百度翻译暂时不可用，请勿使用
    default_api = "youdao",
    --default_api = "google",

    -- API密钥配置
    api_keys = {
        deepl = "YOUR_DEEPL_API_KEY", -- DeepL API密钥
        microsoft = {
            key = "YOUR_MS_TRANSLATOR_API_KEY", -- Microsoft Translator API密钥
            region = "global" -- 替换为您的区域
        },
        niutrans = "YOUR_NIUTRANS_API_KEY", -- 小牛云翻译API密钥
        youdao = {
            app_id = "YOUR_API_ID", -- 有道翻译应用ID
            app_key = "YOUR_API_KEY" -- 有道翻译应用密钥
        },
        baidu = {
            app_id = "YOUR_BAIDU_APP_ID", -- 百度翻译应用ID
            app_key = "YOUR_BAIDU_APP_KEY" -- 百度翻译应用密钥
        }
    }
}

-- ===================== 替换实现：curl http + openssl sha256 =====================
local function sha256_hex(s)
    local cmd = string.format([[printf '%s' | openssl dgst -sha256 -r | awk '{print $1}']], s:gsub("'", "'\\''"))
    local f = io.popen(cmd, "r")
    if not f then return nil end
    local res = f:read("*a")
    f:close()
    return res and res:gsub("%s+", "") or nil
end
local function shell_escape(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function http_req(opt)
    local url, method, headers, data
    if type(opt) == "string" then
        url = opt
        method = "GET"
    else
        url = opt.url
        method = opt.method or "GET"
        headers = opt.headers or {}
        data = opt.data
    end

    local cmd = { "curl", "-s", "--connect-timeout", "5" }
    if method == "POST" then
        table.insert(cmd, "-X")
        table.insert(cmd, "POST")
    end
    for k, v in pairs(headers) do
        table.insert(cmd, "-H")
        table.insert(cmd, string.format("%s: %s", k, v))
    end
    if data then
        table.insert(cmd, "-d")
        table.insert(cmd, data)
    end
    table.insert(cmd, url)

    local escaped = {}
    for _, arg in ipairs(cmd) do
        table.insert(escaped, shell_escape(arg))
    end
    local sh_cmd = table.concat(escaped, " ")
    local f = io.popen(sh_cmd, "r")
    if not f then
        return nil
    end
    local ret = f:read("*a")
    f:close()
    return ret
end

-- 模拟 simplehttp 接口，上层代码不用改
local http = {
    request = function(opt)
        return http_req(opt)
    end
}

-- URL编码函数（原样保留）
local function url_encode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w %-%_%.%~])",
            function(c)
                return string.format("%%%02X", string.byte(c))
            end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

-- Google翻译API
local function google(text, from, to)
    local encoded_text = url_encode(text)
    local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl="..from.."&tl="..to.."&dt=t&dt=bd&dt=rm&dt=qca&dt=at&dt=ss&dt=md&dt=ld&dt=ex&dj=1&q=" .. encoded_text

    local reply = http.request(url)
    local success, j = pcall(json.decode, reply)

    if success and j then
        if j.dict and j.dict[1] and j.dict[1].terms and j.dict[1].terms[1] then
            return j.dict[1].terms[1]
        end
        if j.sentences and j.sentences[1] and j.sentences[1].trans then
            return j.sentences[1].trans
        end
    end

    if reply then
        local _, _, terms = string.find(reply, '"terms":%[%"([^"]+)"')
        if terms then
            return terms
        end

        local _, _, translated = string.find(reply, '"trans":"([^"]+)"')
        if translated then
            return translated
        end

        local _, _, translated2 = string.find(reply, '%[%[%["([^"]+)"')
        if translated2 then
            return translated2
        end
    end

    return nil
end

-- DeepL翻译API
local function deepl(text, from, to)
    local api_key = config.api_keys.deepl
    if not api_key then
        return nil
    end
    local url = "https://api-free.deepl.com/v2/translate"
    local body = "auth_key=" .. api_key .. "&text=" .. url_encode(text) .. "&source_lang="..from.."&target_lang="..to
    local headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }
    local reply = http.request{
        url = url,
        method = "POST",
        headers = headers,
        data = body
    }
    local success, j = pcall(json.decode, reply)
    if success and j and j.translations and j.translations[1] and j.translations[1].text then
        return j.translations[1].text
    end
    return nil
end

-- Microsoft翻译API
local function microsoft(text, from, to)
    local api_key = config.api_keys.microsoft.key
    local region = config.api_keys.microsoft.region
    if not api_key then
        return nil
    end
    local url = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from="..from.."&to="..to
    local body = json.encode({{["Text"] = text}})
    local headers = {
        ["Content-Type"] = "application/json",
        ["Ocp-Apim-Subscription-Key"] = api_key,
        ["Ocp-Apim-Subscription-Region"] = region
    }
    local reply = http.request{
        url = url,
        method = "POST",
        headers = headers,
        data = body
    }
    local success, j = pcall(json.decode, reply)
    if success and j and j[1] and j[1].translations and j[1].translations[1] and j[1].translations[1].text then
        return j[1].translations[1].text
    end
    return nil
end

-- 小牛云翻译API
local function niutrans(text, from, to)
    local api_key = config.api_keys.niutrans
    if not api_key then
        return nil
    end
    local url = "https://api.niutrans.com/NiuTransServer/translation"
    local body = json.encode({
        from = from,
        to = to,
        apikey = api_key,
        src_text = text
    })
    local headers = {
        ["Content-Type"] = "application/json"
    }
    local reply = http.request{
        url = url,
        method = "POST",
        headers = headers,
        data = body
    }
    if not reply or reply == "" then
        return nil
    end
    local success, j = pcall(json.decode, reply)
    if not success then
        return nil
    end
    if j.tgt_text then
        if type(j.tgt_text) == "string" then
            local inner_success, inner_json = pcall(json.decode, j.tgt_text)
            if inner_success and type(inner_json) == "table" then
                return inner_json.content
            else
                return j.tgt_text
            end
        elseif type(j.tgt_text) == "table" then
            if j.tgt_text.content then
                return j.tgt_text.content
            else
                for k, v in pairs(j.tgt_text) do
                    if type(v) == "string" then return v end
                end
                return nil
            end
        else
            return nil
        end
    elseif j.translation then
        return j.translation
    elseif j.result and j.result.translatedText then
        return j.result.translatedText
    else
        return nil
    end
end

-- 有道翻译API（sha256改用openssl子进程）
local function youdao(text, from, to)
    local log = require("log")
    local app_id = config.api_keys.youdao.app_id
    local app_key = config.api_keys.youdao.app_key
    if not app_id or not app_key then
        return nil
    end
    local salt = tostring(math.random(32768, 65536))
    local curtime = tostring(os.time())
    local function get_input(q)
        if #q <= 20 then return q end
        return q:sub(1,10) .. tostring(#q) .. q:sub(-10)
    end
    local input = get_input(text)
    local sign_str = app_id .. input .. salt .. curtime .. app_key
    local sign = sha256_hex(sign_str)
    if not sign then return nil end

    local url = "https://openapi.youdao.com/api"
    local body = "q=" .. url_encode(text)
        .. "&from="..from.."&to="..to
        .. "&appKey=" .. app_id
        .. "&salt=" .. salt
        .. "&sign=" .. sign
        .. "&signType=v3"
        .. "&curtime=" .. curtime

    local headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }
    local reply = http.request{
        url = url,
        method = "POST",
        headers = headers,
        data = body
    }
    if not reply or reply == "" then
        return nil
    end
    local success, j = pcall(json.decode, reply)
    if not success then
        return nil
    end
    if j and j.translation and j.translation[1] then
        return j.translation[1]
    elseif j and j.basic and j.basic.explains and j.basic.explains[1] then
        return j.basic.explains[1]
    else
        return nil
    end
end

-- 百度翻译API
local function baidu(text, from, to)
    local app_id = config.api_keys.baidu.app_id
    local app_key = config.api_keys.baidu.app_key
    if not app_id or not app_key then
        return nil
    end
    local salt = tostring(math.random(32768, 65536))
    local sign_src = app_id .. text .. salt .. app_key
    local cmd = string.format([[printf '%s' | openssl dgst -md5 -r | awk '{print tolower($1)}']], sign_src:gsub("'", "'\\''"))
    local f = io.popen(cmd, "r")
    local sign = nil
    if f then
        sign = f:read("*a"):gsub("%s+", "")
        f:close()
    end
    if not sign then return nil end

    local url = "https://fanyi-api.baidu.com/api/trans/vip/translate"
    local body = "q=" .. url_encode(text)
        .. "&from="..from.."&to="..to
        .. "&appid=" .. app_id
        .. "&salt=" .. salt
        .. "&sign=" .. sign
    local headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded"
    }
    local reply = http.request{
        url = url,
        method = "POST",
        headers = headers,
        data = body
    }
    if not reply or reply == "" then
        return nil
    end
    local success, j = pcall(json.decode, reply)
    if not success then
        return nil
    end
    if j and j.trans_result and j.trans_result[1] and j.trans_result[1].dst then
        return j.trans_result[1].dst
    else
        return nil
    end
end

-- 导出模块
return {
    google = google,
    deepl = deepl,
    microsoft = microsoft,
    niutrans = niutrans,
    youdao = youdao,
    baidu = baidu,
    config = config
}
