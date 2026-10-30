--!strict
-- Schili's new staff-and-shell choreography, independent of Kroko and legacy Motor6D poses.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local source=require(ReplicatedStorage.Shared.SchiliMotion)
local Player=require(script.Parent.BakedBoneClips)
local clips=Player.decode(source)
local states: {[Model]: any}=setmetatable({}, {__mode="k"}) :: any
local Animator={}
function Animator.update(model: Model,dt: number)
	local state=states[model]
	if not state then
		local bones={}
		for _,d in model:GetDescendants() do if d:IsA("Bone") then bones[d.Name]=d end end
		state={bones=bones,current={},phase=0,loco="",locoStart=0,guard=false,guardStart=0,lastStrike="Schili_StaffStrike"}
		states[model]=state
	end
	local root=model.PrimaryPart
	if not root then return end
	local now=Workspace:GetServerTimeNow()
	local pose=tostring(model:GetAttribute("Pose") or "")
	local loco=tostring(model:GetAttribute("Loco") or "")
	if loco~=state.loco then state.loco=loco;state.locoStart=now end
	local guarding=model:GetAttribute("Guard")==true
	if guarding~=state.guard then state.guard=guarding;state.guardStart=now end
	local elapsed=math.max(0,now-(tonumber(model:GetAttribute("PoseStart")) or now))
	local speed=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude
	state.phase+=dt*math.clamp(speed/6,.4,2)
	local name=if speed>1 then "Schili_Walk" else "Schili_Idle"
	local t=if speed>1 then state.phase%1.2 else now%3
	local wind=math.max(.01,tonumber(model:GetAttribute("AttackWindDuration")) or .65)
	local active=math.max(.01,tonumber(model:GetAttribute("AttackActiveDuration")) or .25)
	local recovery=math.max(.01,tonumber(model:GetAttribute("AttackRecoveryDuration")) or .8)
	if pose=="FeintWind" then
		name="Schili_Feint";t=math.clamp(elapsed/wind,0,1)
	elseif pose=="StaffWind" or pose=="StaffStrike" then
		name="Schili_StaffStrike";state.lastStrike=name
		t=if pose=="StaffWind" then .8*math.clamp(elapsed/wind,0,1) else .8+.272*math.clamp(elapsed/active,0,1)
	elseif pose=="StaffSweepWind" or pose=="StaffSweepStrike" then
		name="Schili_StaffSweep";state.lastStrike=name
		t=if pose=="StaffSweepWind" then .9*math.clamp(elapsed/wind,0,1) else .9+.396*math.clamp(elapsed/active,0,1)
	elseif pose=="Recover" then
		if tostring(model:GetAttribute("Attack") or ""):find("Charge") then
			name="Schili_ShellGuard";t=.35*(1-math.clamp(elapsed/recovery,0,1))
		else
			name=state.lastStrike
			local start=if name=="Schili_StaffSweep" then 1.296 else 1.072
			t=start+(clips[name].duration-start)*math.clamp(elapsed/recovery,0,1)
		end
	elseif pose=="RushRun" then
		name="Schili_Rush";t=elapsed%.8
	elseif pose=="RushWind" or pose=="ShellGuard" or (guarding and pose=="") then
		name="Schili_ShellGuard";t=math.min(1,(if pose~="" then elapsed else now-state.guardStart)*1.4)
	elseif loco=="STAGGER" or loco=="KNOCKDOWN" then
		name="Schili_Stagger";t=math.min(now-state.locoStart,1.2)
	elseif pose=="Surrender" or pose=="Roar" then
		name="Schili_Bow";t=math.min(elapsed,if pose=="Surrender" then 1 else 2)
	end
	local goals=Player.sample(clips[name],t)
	local alpha=1-math.exp(-dt*24)
	for i,boneName in source.bones do
		local bone=state.bones[boneName]
		if bone then
			local current=(state.current[i] or CFrame.identity):Lerp(goals[i],alpha)
			state.current[i]=current;bone.Transform=current
		end
	end
end
return Animator
