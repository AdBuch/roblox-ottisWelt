--!strict
-- Hooks the server-created sword and shield Tools. Clicks are forwarded to the server as
-- plain requests; the server decides whether anything happens.

local ToolInput = {}

type Remotes = {
	swordAttack: RemoteEvent,
	shieldBlock: RemoteEvent,
}

function ToolInput.bind(player: Player, toolAttribute: string, remotes: Remotes)
	local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	local function hook(child: Instance)
		if not child:IsA("Tool") or hooked[child] then
			return
		end
		local kind = child:GetAttribute(toolAttribute)
		if kind == "Sword" then
			hooked[child] = true
			child.Activated:Connect(function()
				remotes.swordAttack:FireServer()
			end)
		elseif kind == "Shield" then
			hooked[child] = true
			child.Activated:Connect(function()
				remotes.shieldBlock:FireServer(true)
			end)
			child.Deactivated:Connect(function()
				remotes.shieldBlock:FireServer(false)
			end)
			child.Unequipped:Connect(function()
				remotes.shieldBlock:FireServer(false)
			end)
		end
	end

	local function watch(container: Instance)
		for _, child in container:GetChildren() do
			hook(child)
		end
		container.ChildAdded:Connect(hook)
	end

	-- Tools move between the Backpack and the character; both are replaced on respawn.
	local function onCharacter(character: Model)
		watch(character)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			watch(backpack)
		end
	end

	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watch(child)
		end
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

return ToolInput
