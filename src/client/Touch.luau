--!strict
-- Touch mode, pure: detection, gesture phases and the UI scale (docs/mobile-contract.md).
-- No Roblox calls here so the spec can run headless; Settings.touch() feeds the device in.

local Touch = {}

Touch.HOLD_S = 0.35
Touch.DRAG_PX = 12
Touch.CONTROLS = { "auto", "touch", "desktop" }

-- Touch when there is a touch screen and no keyboard, unless the setting says otherwise.
function Touch.detect(touchEnabled: boolean, keyboardEnabled: boolean, controls: string?): boolean
	if controls == "touch" then
		return true
	elseif controls == "desktop" then
		return false
	end
	return touchEnabled and not keyboardEnabled
end

-- One finger: "pending" until it moves (drag) or stays HOLD_S (hold); a hold that then moves
-- is a "holdDrag". Phases never go back.
function Touch.phase(prev: string, elapsed: number, dist: number): string
	if prev == "pending" then
		if dist > Touch.DRAG_PX then
			return "drag"
		elseif elapsed >= Touch.HOLD_S then
			return "hold"
		end
	elseif prev == "hold" and dist > Touch.DRAG_PX then
		return "holdDrag"
	end
	return prev
end

-- What a release means: a finger lifted while still pending was a tap.
function Touch.release(phase: string): string
	return if phase == "pending" then "tap" else phase
end

-- UI scale: phones (short side under 600 px) 1.5 so 30 px plaques meet the 44 px tap target,
-- tablets 1.15, desktop 1.
function Touch.scale(viewportX: number, viewportY: number, touch: boolean): number
	if not touch then
		return 1
	end
	return if math.min(viewportX, viewportY) < 600 then 1.5 else 1.15
end

-- A centred panel designed w x h on a screen availW x availH units (pixels over the UI scale),
-- 8 units clear of each edge: the scale that fits its width, and the height (design units) to
-- give it so it fits too; its scrolling body takes up the difference.
function Touch.fitPanel(availW: number, availH: number, w: number, h: number): (number, number)
	local k = math.min(1, (availW - 16) / w)
	return k, math.min(h, (availH - 16) / k)
end

-- A column laid out for `full` units of height (or `compact` without its header) on a screen
-- `height` units tall (pixels over the UI scale): compact when the full one does not fit, and
-- the scale that fits whichever is shown.
function Touch.fitColumn(height: number, full: number, compact: number): (boolean, number)
	local small = height < full
	return small, math.min(1, height / (if small then compact else full))
end

return Touch
