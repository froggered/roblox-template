-- Number and time formatting for UI. Shared so a balance reads the same
-- everywhere it's shown.
local Format = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

-- 1234 -> "1,234"
function Format.comma(n: number): string
	local whole = tostring(math.floor(math.abs(n)))
	local grouped = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (if n < 0 then "-" else "") .. grouped
end

-- 1234 -> "1.2K". Values under 1,000 keep their exact digits — players
-- notice a small balance rounding, never a large one.
function Format.abbreviate(n: number): string
	local sign = if n < 0 then "-" else ""
	local value = math.abs(n)
	if value < 1000 then
		return sign .. tostring(math.floor(value))
	end
	for index, suffix in SUFFIXES do
		local scale = 1000 ^ index
		if value < scale * 1000 or index == #SUFFIXES then
			local scaled = value / scale
			-- One decimal below 100 ("9.9K"), none above ("120K") — keeps the
			-- label a predictable width.
			local text = if scaled < 100
				then string.format("%.1f", math.floor(scaled * 10) / 10)
				else tostring(math.floor(scaled))
			return sign .. (text:gsub("%.0$", "")) .. suffix
		end
	end
	return sign .. tostring(math.floor(value))
end

-- 125 -> "2:05"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- 90061 -> "1d 1h"; for "played for" style labels.
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then return `{seconds}s` end
	if seconds < 3600 then return `{seconds // 60}m` end
	if seconds < 86400 then return `{seconds // 3600}h {(seconds % 3600) // 60}m` end
	return `{seconds // 86400}d {(seconds % 86400) // 3600}h`
end

return Format
