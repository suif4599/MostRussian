local function open_rime_file(rel_path)
    local pathsep = (package.config or "/"):sub(1, 1)
    local base = rime_api.get_user_data_dir()
    local path = base .. pathsep .. rel_path
    local file, err = io.open(path)
    if not file then
        log.error("most_translator: failed to open " .. path .. ", error: " .. tostring(err))
    end
    return file
end

local function load_csv_dict()
    local dict = {}
    local prefix_dict = {}
    local lower2upper = {}
    local max_code_len = 0
    local file = open_rime_file("most_letter.mapping")
    if not file then
        return dict, prefix_dict, max_code_len
    end

    for line in file:lines() do
        line = line:match("[^\r\n]+")
        if line and line ~= "" and not line:match("^%s*#") then
            local upper, lower, code = line:match("^%s*([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)%s*$")
            if lower and code then
                local code_key = code:lower()
                if not dict[code_key] then
                    dict[code_key] = lower
                    lower2upper[lower] = upper
                    if #code_key > max_code_len then
                        max_code_len = #code_key
                    end
                else
                    -- Invalid dict entry, duplicate code
                    file:close()
                    return nil, nil, -1, nil
                end
            end
        end
    end
    file:close()

    -- Prefix dicts
    local code_len = 2
    while code_len <= max_code_len do
        for code, text in pairs(dict) do
            if #code >= code_len then
                local prefix = code:sub(1, code_len - 1)
                if not prefix_dict[prefix] then
                    prefix_dict[prefix] = {}
                end
                table.insert(prefix_dict[prefix], text)
            end
        end
        code_len = code_len + 1
    end

    return dict, prefix_dict, max_code_len, lower2upper
end

local function latin2russian(env, input)
    -- Greedy longest-match translation
    -- returns candidates, upper_pattern
    local result = {}
    local upper_pattern = {}
    local pos = 1
    local len = #input
    local max_len = env.max_code_len or 0

    while pos <= len do
        local best = nil
        local best_len = 0
        local best_is_upper = false
        local end_pos = math.min(len, pos + max_len - 1)
        for i = end_pos, pos, -1 do
            local raw_substr = input:sub(pos, i)
            local substr = raw_substr:lower()
            local acc = env.dict[substr]
            if acc then
                best = acc
                local first_char = raw_substr:sub(1, 1)
                best_is_upper = "A" <= first_char and first_char <= "Z"
                best_len = #substr
                break
            end
        end

        if best then
            table.insert(result, best)
            table.insert(upper_pattern, best_is_upper)
            pos = pos + best_len
        else
            table.insert(result, input:sub(pos, pos))
            table.insert(upper_pattern, "A" <= input:sub(pos, pos) and input:sub(pos, pos) <= "Z")
            pos = pos + 1
        end
    end

    return { table.concat(result, "") }, upper_pattern
end

local function apply_upper_pattern(env, str, pattern)
    -- use upper_pattern to determine the case of each character in str
    local result = {}
    local pattern_len = #pattern
    local i = 1
    for index, cp in utf8.codes(str) do
        local char = utf8.char(cp)
        if i > pattern_len then
            table.insert(result, str:sub(index))
            break
        end
        if pattern[i] then
            local upper = env.lower2upper[char]
            if upper then
                table.insert(result, upper)
            else
                table.insert(result, char)
            end
        else
            table.insert(result, char)
        end
        i = i + 1
    end
    return table.concat(result, "")
end

local function is_chinese(codepoint)
    return (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
        or (codepoint >= 0x3400 and codepoint <= 0x4DBF)
        or (codepoint >= 0x20000 and codepoint <= 0x2A6DF)
        or (codepoint >= 0x2A700 and codepoint <= 0x2B73F)
        or (codepoint >= 0x2B740 and codepoint <= 0x2B81F)
        or (codepoint >= 0x2B820 and codepoint <= 0x2CEAF)
        or (codepoint >= 0x2CEB0 and codepoint <= 0x2EBE0)
        or (codepoint >= 0x30000 and codepoint <= 0x3134A)
        or (codepoint >= 0x31350 and codepoint <= 0x323AF)
        or (codepoint >= 0x2EBF0 and codepoint <= 0x2EE5F)
        or (codepoint >= 0x323B0 and codepoint <= 0x3347F)
end

local function truncate_comment(word, comment, max_total)
    if not comment or comment == "" then
        return ""
    end

    local word_len = utf8.len(word) or #word
    local ellipsis = "..."
    local ellipsis_cost = #ellipsis

    if word_len >= max_total then
        return ""
    end

    local function total_cost(non_chinese, chinese)
        return word_len + non_chinese + 2 * chinese
    end

    local non_chinese = 0
    local chinese = 0
    for _, cp in utf8.codes(comment) do
        if is_chinese(cp) then
            chinese = chinese + 1
        else
            non_chinese = non_chinese + 1
        end
    end

    if total_cost(non_chinese, chinese) <= max_total then
        return comment
    end

    local budget = max_total - word_len - ellipsis_cost
    if budget <= 0 then
        return ""
    end

    local out = {}
    non_chinese = 0
    chinese = 0
    for _, cp in utf8.codes(comment) do
        local next_non = non_chinese
        local next_ch = chinese
        if is_chinese(cp) then
            next_ch = next_ch + 1
        else
            next_non = next_non + 1
        end
        if (next_non + 2 * next_ch) > budget then
            break
        end
        non_chinese = next_non
        chinese = next_ch
        table.insert(out, utf8.char(cp))
    end

    local truncated = table.concat(out, "")
    if truncated ~= "" then
        truncated = truncated .. ellipsis
    end
    return truncated
end

local function format_comment(word, comment)
    local trimmed = truncate_comment(word, comment, 60)
    if trimmed == "" then
        return ""
    end
    return "\n" .. trimmed
end

local function init(env)
    env.dict, env.prefix_dict, env.max_code_len, env.lower2upper = load_csv_dict()
    env.russian_dict = Component.Translator(env.engine, "", "table_translator@most_russian")
end

local function translator(input, segment, env)
    if input == "" then
        return
    end

    local candidates, upper_pattern = latin2russian(env, input)
    if #candidates == 1 and env.russian_dict then
        local prefix = candidates[1]
        if not prefix:find("%s") then
            local seg = Segment(0, #prefix)
            seg.tags = Set({"abc"})
            local xlation = env.russian_dict:query(prefix, seg)
            if xlation then
                local cnt = 0
                local all_upper = true
                for _, is_upper in ipairs(upper_pattern) do
                    if not is_upper then
                        all_upper = false
                        break
                    end
                end
                for cand in xlation:iter() do
                    local word = prefix .. cand.comment:sub(2)
                    local comment = format_comment(word, cand.text)
                    cnt = cnt + 1
                    if cnt == 1 and prefix ~= word then
                        yield(Candidate("completion", segment.start, segment._end, apply_upper_pattern(env, prefix, upper_pattern), ""))
                    end
                    local word_upper_pattern = {}
                    if all_upper then
                        for _ in utf8.codes(word) do
                            table.insert(word_upper_pattern, true)
                        end
                    else
                        word_upper_pattern = upper_pattern
                    end
                    yield(Candidate("phrase", segment.start, segment._end, apply_upper_pattern(env, word, word_upper_pattern), comment))
                    if cnt >= 15 then
                        break
                    end
                end
                if cnt > 0 then
                    return
                end
            end
        end
    end

    for _, cand in ipairs(candidates) do
        yield(Candidate("completion", segment.start, segment._end, apply_upper_pattern(env, cand, upper_pattern), ""))
    end
end

return { init = init, func = translator }
