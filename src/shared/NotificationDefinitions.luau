--!strict
-- Notification kinds for the single HUD notification queue (NotificationController).
-- Lower Priority number = more important. Critical warnings and results are never hidden by the
-- HUD mode; everything else follows the "Notifications" group.

export type Kind = "Critical" | "Result" | "Round" | "Heal" | "Aura" | "Info"

export type Definition = {
	Priority: number,
	Color: Color3,
	Seconds: number?, -- default: UiConfig.NotificationSeconds
	AlwaysShown: boolean,
	Combine: boolean, -- repeated messages of this kind merge into one
}

local NotificationDefinitions: { [Kind]: Definition } = {
	Critical = { Priority = 1, Color = Color3.fromRGB(255, 110, 60), Seconds = 1.4, AlwaysShown = true, Combine = false },
	Result = { Priority = 2, Color = Color3.fromRGB(255, 215, 90), Seconds = 3, AlwaysShown = true, Combine = false },
	Round = { Priority = 3, Color = Color3.fromRGB(255, 215, 90), Seconds = 1.6, AlwaysShown = false, Combine = false },
	Heal = { Priority = 4, Color = Color3.fromRGB(120, 255, 120), Seconds = 1.4, AlwaysShown = false, Combine = true },
	Aura = { Priority = 5, Color = Color3.fromRGB(255, 210, 80), Seconds = 1.5, AlwaysShown = false, Combine = true },
	Info = { Priority = 6, Color = Color3.fromRGB(235, 235, 235), Seconds = 1.6, AlwaysShown = false, Combine = false },
}

return table.freeze(NotificationDefinitions)
