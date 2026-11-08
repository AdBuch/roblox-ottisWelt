--!strict
-- Schili's new staff-and-shell choreography, independent of Kroko and legacy Motor6D poses.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local source=require(ReplicatedStorage.Shared.SchiliMotion)
local Player=require(script.Parent.BakedBoneClips)
local clips=Player.decode(source)
local boneIndex: {[string]: number} = {}
for i, name in source.bones do boneIndex[name] = i end
local states: {[Model]: any}=setmetatable({}, {__mode="k"}) :: any
local Animator={}

-- Apply an offset in actor space around the bone's own pivot, regardless of FBX bone axes.
local function offsetBone(bone: Bone, root: BasePart, offset: CFrame)
	local axes = bone.TransformedWorldCFrame.Rotation:ToObjectSpace(root.CFrame.Rotation)
	bone.Transform *= axes * offset * axes:Inverse()
end

function Animator.update(model: Model,dt: number)
	local state=states[model]
	if not state then
		local bones={}
		for _,d in model:GetDescendants() do if d:IsA("Bone") then bones[d.Name]=d end end
		local tuckedParts = {}
		for _, name in {"Schili_Body", "Schili_Details", "Schili_Staff"} do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then table.insert(tuckedParts, part) end
		end
		state={bones=bones,tuckedParts=tuckedParts,current={},phase=0,loco="",locoStart=0,guard=false,guardStart=0,lastStrike="Schili_StaffStrike"}
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
	if pose~=state.pose then
		state.pose=pose
		state.recoveryTuck=state.tuck or 0
		state.recoverySpin=state.spin or 0
	end
	local tuck, spin, vault = 0, 0, 0
	if pose=="StaffParry" then
		name="Schili_StaffSweep";t=.64*math.clamp(elapsed/.16,0,1)
	elseif pose=="StaffDeflect" then
		name="Schili_StaffSweep";t=.64+.52*math.clamp(elapsed/.2,0,1)
	elseif pose=="StaffVault" then
		name="Schili_Walk";t=.24+.48*math.clamp(elapsed/.8,0,1)
		vault=math.clamp((elapsed-.12)/.60,0,1)
	elseif pose=="ShellTuck" then
		local progress=math.clamp(elapsed/wind,0,1)
		name="Schili_ShellGuard";t=.46*progress
		tuck=math.clamp((progress-.45)/.55,0,1)
	elseif pose=="ShellRoll" then
		name="Schili_ShellGuard";t=.46
		tuck=1
		spin=-math.tau*2*math.clamp(elapsed/active,0,1)
	elseif pose=="FeintWind" then
		name="Schili_Feint";t=math.clamp(elapsed/wind,0,1)
	elseif pose=="StaffWind" or pose=="StaffStrike" then
		name="Schili_StaffStrike";state.lastStrike=name
		t=if pose=="StaffWind" then .8*math.clamp(elapsed/wind,0,1) else .8+.272*math.clamp(elapsed/active,0,1)
	elseif pose=="StaffSweepWind" or pose=="StaffSweepStrike" then
		name="Schili_StaffSweep";state.lastStrike=name
		t=if pose=="StaffSweepWind" then .9*math.clamp(elapsed/wind,0,1) else .9+.396*math.clamp(elapsed/active,0,1)
	elseif pose=="Recover" then
		if model:GetAttribute("Attack")=="SchiliCharge" then
			local blend=math.clamp(elapsed/.26,0,1)
			tuck=state.recoveryTuck*(1-blend)
			local from=state.recoverySpin
			spin=from+(math.round(from/math.tau)*math.tau-from)*blend
			name="Schili_ShellGuard";t=.46*tuck
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
	state.tuck,state.spin=tuck,spin
	local goals=Player.sample(clips[name],t)
	if pose=="StaffVault" and elapsed < .24 then
		-- The staff is vertical in bind pose. Brace it before the feet leave the floor.
		local plant=1-math.clamp((elapsed-.12)/.12,0,1)
		for _, arm in {"UpperArm.R", "Forearm.R", "Hand.R"} do
			local i=boneIndex[arm]
			goals[i]=goals[i]:Lerp(CFrame.identity,plant)
		end
	end
	local alpha=1-math.exp(-dt*24)
	for i,boneName in source.bones do
		local bone=state.bones[boneName]
		if bone then
			local current=(state.current[i] or CFrame.identity):Lerp(goals[i],alpha)
			state.current[i]=current;bone.Transform=current
		end
	end
	for _, part in state.tuckedParts do part.LocalTransparencyModifier=tuck end
	if tuck>0 and state.bones.Shell then
		offsetBone(state.bones.Shell,root,CFrame.new(0,-.65*tuck,0)*CFrame.Angles(spin,0,0))
	end
	if vault>0 and vault<1 and state.bones.Pelvis then
		local lift=math.sin(math.pi*vault)
		offsetBone(state.bones.Pelvis,root,CFrame.new(0,.65*lift,0)*CFrame.Angles(-math.tau*vault,0,0))
	end
end
return Animator
