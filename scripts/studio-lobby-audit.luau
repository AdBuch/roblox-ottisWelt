-- Run in the Studio CLIENT command bar while playing the Hub. Never publish as a game script.
assert(game:GetService("RunService"):IsStudio(), "Studio audit only")
local player = game.Players.LocalPlayer
local layout = require(game.ReplicatedStorage.Shared.ColosseumLayout)
local stairRise = layout.LobbyFloor - layout.HypogeumFloor
assert(player and player.Character, "Run in the playing client")
local character = player.Character
local humanoid = character:FindFirstChildOfClass("Humanoid")
local controls = require(player.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
local saved = character:GetPivot()
controls:Disable()
task.spawn(function()
    local ok, err = pcall(function()
        local index = 0
        for _, model in workspace.GeneratedLobby:GetDescendants() do
            if not model:IsA("Model") or model.Name ~= "DownStaircase" or model:GetAttribute("Rise") ~= stairRise then continue end
            index += 1
            -- Names repeat; FindFirstChild("Stair") need not return the lowest step in Studio.
            local lowest: BasePart? = nil
            for _, step in model:GetChildren() do
                if step:IsA("BasePart") and step.Name == "Stair" and (not lowest or step.Size.Y < lowest.Size.Y) then lowest = step end
            end
            assert(lowest)
            local base = model:GetAttribute("StairBase") or lowest.CFrame * CFrame.new(0, -lowest.Size.Y/2, -lowest.Size.Z/2+0.025)
            local top = (base*CFrame.new(0, stairRise+3.1, model:GetAttribute("Run")+2)).Position
            local bottom = (base*CFrame.new(0, 3.1, -3)).Position
            character:PivotTo(CFrame.new(top))
            character.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
            -- Allow server character replication / the lobby safety loop to settle after a long teleport.
            task.wait(1.5)
            humanoid:MoveTo(bottom)
            local down = humanoid.MoveToFinished:Wait()
            task.wait(0.25)
            print("[LobbyQA] DOWN", index, down, (character:GetPivot().Position-bottom).Magnitude, character:GetPivot().Position)
            assert(down and (character:GetPivot().Position-bottom).Magnitude < 3, "Descent did not reach the landing")
            humanoid:MoveTo(top)
            local up = humanoid.MoveToFinished:Wait()
            print("[LobbyQA] UP", index, up, (character:GetPivot().Position-top).Magnitude, character:GetPivot().Position)
            assert(up and (character:GetPivot().Position-top).Magnitude < 3, "Ascent did not reach the landing")
        end
    end)
    character:PivotTo(saved)
    character.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
    controls:Enable()
    workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
    workspace.CurrentCamera.CameraSubject = humanoid
    print("[LobbyQA] STAIR AUDIT COMPLETE", ok, err or "")
end)
