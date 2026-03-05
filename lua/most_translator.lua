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
    -- returns candidate, upper_pattern
    local result = {}
    local upper_pattern = {}
    local accent_pattern = {}
    local pos = 1
    local len = #input
    local max_len = env.max_code_len or 0

    while pos <= len do
        if input:sub(pos, pos) == "." then
            table.insert(result, ".")
            table.insert(upper_pattern, false)
            table.insert(accent_pattern, false)
            pos = pos + 1
        else
            local best = nil
            local best_len = 0
            local best_is_upper = false
            local end_pos = math.min(len, pos + max_len - 1)
            -- Check if "'" is used
            for i = pos, end_pos do
                if input:sub(i, i) == "'" or input:sub(i, i) == "." then
                    end_pos = i - 1
                    break
                end
            end
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
                -- Try to double write the current character
                local char = input:sub(pos, pos)
                local is_upper = "A" <= char and char <= "Z"
                local acc = env.dict[char:lower() .. char:lower()]
                if acc then
                    table.insert(result, acc)
                else
                    table.insert(result, char:lower())
                end
                table.insert(upper_pattern, is_upper)
                pos = pos + 1
            end

            if pos <= len and input:sub(pos, pos) == "'" then
                pos = pos + 1
                table.insert(accent_pattern, true)
            else
                table.insert(accent_pattern, false)
            end
        end
    end

    return table.concat(result, ""), upper_pattern, accent_pattern
end

local function apply_pattern(env, str, upper_pattern, accent_pattern)
    -- use upper_pattern to determine the case of each character in str
    local result = {}
    local upper_pattern_len = #upper_pattern
    local accent_pattern_len = #accent_pattern
    local i = 1
    for index, cp in utf8.codes(str) do
        local char = utf8.char(cp)
        local applied_char = char
        if i <= upper_pattern_len and upper_pattern[i] then
            local upper = env.lower2upper[char]
            if upper then
                applied_char = upper
            end
        end
        if i <= accent_pattern_len and accent_pattern[i] then
            applied_char = applied_char .. "\u{0301}"
        end
        table.insert(result, applied_char)
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
    local configured_top_k = env.engine.schema.config:get_int("most/topk")
    env.top_k = (configured_top_k and configured_top_k > 0) and configured_top_k or 49
    env.tag_ru_zh_1 = env.engine.schema.config:get_string("most_ru_zh_1/tag") or "most_ru_zh_1_tag"
    env.tag_ru_zh_2 = env.engine.schema.config:get_string("most_ru_zh_2/tag") or "most_ru_zh_2_tag"
    env.tag_ru_zh = env.engine.schema.config:get_string("most_ru_zh/tag") or "most_ru_zh_tag"
    env.tag_ru_zh_full = env.engine.schema.config:get_string("most_ru_zh_full/tag") or "most_ru_zh_full_tag"
    env.ru_zh_1 = Component.Translator(env.engine, "", "table_translator@most_ru_zh_1")
    env.ru_zh_2 = Component.Translator(env.engine, "", "table_translator@most_ru_zh_2")
    env.ru_zh = Component.Translator(env.engine, "", "table_translator@most_ru_zh")
    env.ru_zh_full = Component.Translator(env.engine, "", "table_translator@most_ru_zh_full")
end

local function better_candidate(a, b)
    if a.quality ~= b.quality then
        return a.quality > b.quality
    end
    return a.word < b.word
end

local function to_word(prefix, cand)
    local suffix = cand.comment or ""
    if suffix:sub(1, 1) == "~" then
        suffix = suffix:sub(2)
    end
    return prefix .. suffix
end

local function collect_from_translator(translator, prefix, tag, merged)
    if not translator then
        return 0
    end
    local seg = Segment(0, #prefix)
    seg.tags = Set({tag})
    local xlation = translator:query(prefix, seg)
    if not xlation then
        return 0
    end
    local added = 0
    for cand in xlation:iter() do
        local word = to_word(prefix, cand)
        local quality = cand.quality or 0
        local old = merged[word]
        if not old then
            merged[word] = {
                word = word,
                cand = cand,
                quality = quality,
            }
            added = added + 1
        elseif quality > old.quality then
            old.cand = cand
            old.quality = quality
        end
    end
    return added
end

local function sorted_top_k(merged, k)
    local items = {}
    for _, item in pairs(merged) do
        table.insert(items, item)
    end
    table.sort(items, better_candidate)
    if #items > k then
        for i = #items, k + 1, -1 do
            items[i] = nil
        end
    end
    return items
end

local function translator(input, segment, env)
    if input == "" then
        return
    end

    local prefix, upper_pattern, accent_pattern = latin2russian(env, input)
    if not prefix:find("%s") then
        local modified_prefix_table = {}
        for _, cp in utf8.codes(prefix) do
            if utf8.char(cp) == "." then
                table.insert(modified_prefix_table, "-")
            else
                table.insert(modified_prefix_table, utf8.char(cp))
            end
        end
        local modified_prefix = table.concat(modified_prefix_table, "")
        local merged = {}
        local prefix_len = utf8.len(modified_prefix) or 0

        if prefix_len == 1 then
            collect_from_translator(env.ru_zh_1, modified_prefix, env.tag_ru_zh_1, merged)
        elseif prefix_len == 2 then
            collect_from_translator(env.ru_zh_2, modified_prefix, env.tag_ru_zh_2, merged)
        else
            local cnt = collect_from_translator(env.ru_zh, modified_prefix, env.tag_ru_zh, merged)
            if cnt < env.top_k then
                collect_from_translator(env.ru_zh_full, modified_prefix, env.tag_ru_zh_full, merged)
            end
        end

        local top_items = sorted_top_k(merged, env.top_k)
        local cnt = #top_items
        if cnt == 0 then
            yield(Candidate("completion", segment.start, segment._end, apply_pattern(env, prefix, upper_pattern, accent_pattern), ""))
            return
        end

        local all_upper = true
        for _, is_upper in ipairs(upper_pattern) do
            if not is_upper then
                all_upper = false
                break
            end
        end
        for idx, item in ipairs(top_items) do
            local word = item.word
            local comment = format_comment(word, item.cand.text)
            if idx == 1 and modified_prefix ~= word then
                yield(Candidate("completion", segment.start, segment._end, apply_pattern(env, prefix, upper_pattern, accent_pattern), ""))
            end
            local word_upper_pattern = {}
            if all_upper then
                for _ in utf8.codes(word) do
                    table.insert(word_upper_pattern, true)
                end
            else
                word_upper_pattern = upper_pattern
            end
            yield(Candidate("phrase", segment.start, segment._end, apply_pattern(env, word, word_upper_pattern, accent_pattern), comment))
        end
    end
end

return { init = init, func = translator }
