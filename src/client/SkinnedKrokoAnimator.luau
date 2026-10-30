--!strict
-- Plays Blender-authored skin deformation on the imported bones. No animation asset IDs
-- are required; the server remains authoritative over all combat windows and damage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local source = require(ReplicatedStorage.Shared.KrokoMotion)
local Animator = {}
local states: {[Model]: any} = setmetatable({}, {__mode="k"}) :: any
local clips: {[string]: any} = {}
for _, name in {"Kroko_Idle","Kroko_Walk","Kroko_ClubStrike","Kroko_Stagger"} do
	local raw = (source :: any)[name]
	local frames = {}
	for _, frame in raw.frames do
		local poses = {}
		for i=1,#source.bones do
			local o=2+(i-1)*7
			poses[i]=CFrame.new(table.unpack(frame,o,o+6))
		end
		table.insert(frames,{time=frame[1],poses=poses})
	end
	clips[name]={duration=raw.duration,frames=frames}
end
local function sample(name: string, t: number): {CFrame}
	local frames=clips[name].frames
	for i=2,#frames do
		local b=frames[i]
		if t<=b.time then
			local a=frames[i-1]
			local alpha=math.clamp((t-a.time)/(b.time-a.time),0,1)
			local poses={}
			for j, cf in a.poses do poses[j]=cf:Lerp(b.poses[j],alpha) end
			return poses
		end
	end
	return table.clone(frames[#frames].poses)
end
function Animator.update(model: Model, dt: number)
	local state=states[model]
	if not state then
		local bones={}
		for _, d in model:GetDescendants() do if d:IsA("Bone") then bones[d.Name]=d end end
		state={bones=bones,current={},phase=0,loco="",locoStart=0}
		states[model]=state
	end
	local root=model.PrimaryPart
	if not root then return end
	local now=Workspace:GetServerTimeNow()
	local pose=tostring(model:GetAttribute("Pose") or "")
	local loco=tostring(model:GetAttribute("Loco") or "")
	if loco~=state.loco then state.loco=loco; state.locoStart=now end
	local elapsed=math.max(0,now-(tonumber(model:GetAttribute("PoseStart")) or now))
	local moving=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude
	state.phase+=dt*math.clamp(moving/7,.4,2)
	local name=if moving>1 then "Kroko_Walk" else "Kroko_Idle"
	local t=if moving>1 then state.phase%1 else now%2
	if pose=="ClubWind" or pose=="FeintWind" or pose=="BashWind" then
		name="Kroko_ClubStrike"; t=.6*math.clamp(elapsed/math.max(.01,tonumber(model:GetAttribute("AttackWindDuration")) or .45),0,1)
	elseif pose=="ClubStrike" or pose=="BashStrike" then
		name="Kroko_ClubStrike"; t=.6+.255*math.clamp(elapsed/math.max(.01,tonumber(model:GetAttribute("AttackActiveDuration")) or .22),0,1)
	elseif pose=="Recover" and (tostring(model:GetAttribute("Attack") or ""):find("Strike") or tostring(model:GetAttribute("Attack") or ""):find("Feint")) then
		name="Kroko_ClubStrike"; t=.855+.645*math.clamp(elapsed/math.max(.01,tonumber(model:GetAttribute("AttackRecoveryDuration")) or .7),0,1)
	elseif loco=="STAGGER" or loco=="KNOCKDOWN" then
		name="Kroko_Stagger"; t=math.min(now-state.locoStart,1)
	end
	local goals=sample(name,t)
	local alpha=1-math.exp(-dt*25)
	for i, boneName in source.bones do
		local bone=state.bones[boneName]
		if bone then
			local goal=goals[i]
			if model:GetAttribute("Guard") and boneName=="UpperArm.L" then goal*=CFrame.Angles(math.rad(-45),0,math.rad(-15)) end
			if loco=="DEFEATED" and boneName=="Chest" then goal*=CFrame.Angles(math.rad(-35),0,0) end
			local current=(state.current[i] or CFrame.identity):Lerp(goal,alpha)
			state.current[i]=current; bone.Transform=current
		end
	end
end
return Animator
