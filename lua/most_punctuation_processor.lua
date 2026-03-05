local kNoop = 2
local kAccepted = 1

local KEY_COMMA = string.byte(",")
local KEY_PERIOD = string.byte(".")
local KEY_LESS = string.byte("<")
local KEY_GREATER = string.byte(">")

local function func(key_event, env)
	if key_event:release() then
		return kNoop
	end

	if key_event:ctrl() or key_event:alt() then
		return kNoop
	end

	if not env.engine.context:get_option("punctuation") then
		return kNoop
	end

	local keycode = key_event.keycode
	local is_less = (keycode == KEY_LESS) or (keycode == KEY_COMMA and key_event:shift())
	local is_greater = (keycode == KEY_GREATER) or (keycode == KEY_PERIOD and key_event:shift())

	if is_less then
		env.engine:commit_text("«")
		return kAccepted
	end

	if is_greater then
		env.engine:commit_text("»")
		return kAccepted
	end

	return kNoop
end

return { func = func }
