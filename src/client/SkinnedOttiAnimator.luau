--!strict
-- Authored otter spine, paw placement and six-joint tail, sampled at render time.
local RS=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local source=require(RS.Shared.OttiMotion)
local Player=require(script.Parent.BakedBoneClips)
local clips=Player.decode(source)
local states: {[Model]: any}=setmetatable({}, {__mode="k"}) :: any
local Animator={}
local attacks={SlashH="Slash",SlashH2="Backslash",Thrust="Thrust",Slash="Slash",Bash="Bash",
	Sweep="Sweep",Trip="Trip",Counter="Sweep",Slam="Slam",Bite="Bite",Grab="Grapple"}
local function duration(name: string): number return clips["Otti_"..name].duration end
local function attackEdges(name: string): (number, number)
	if name=="Sweep" or name=="Trip" then return .48,.7 end
	if name=="Slam" then return .48,.6 end
	if name=="Bite" then return .4,.58 end
	return .4,.56
end
function Animator.update(model: Model,dt: number)
	local root=model.PrimaryPart
	if not root then return end
	local state=states[model]
	if not state then
		local bones,axes={},{}
		for _,b in model:GetDescendants() do
			if b:IsA("Bone") then bones[b.Name]=b; axes[b.Name]=b.WorldCFrame:VectorToObjectSpace(Vector3.yAxis) end
		end
		state={bones=bones,axes=axes,current={},phase=0,loco="",locoStart=0,lastStrike="Slash",yaw=0,yawRate=0}
		states[model]=state
	end
	local now=Workspace:GetServerTimeNow()
	local pose=tostring(model:GetAttribute("Pose") or "")
	local loco=tostring(model:GetAttribute("Loco") or "")
	if loco~=state.loco then state.loco=loco;state.locoStart=now end
	local elapsed=math.max(0,now-(tonumber(model:GetAttribute("PoseStart")) or now))
	local speed=Vector3.new(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z).Magnitude
	local quad=model:GetAttribute("Stance")=="Quad"
	state.phase+=dt*math.clamp(speed/(if quad then 24 else 9),.2,2)
	local name=if quad then (if speed>18 then "QuadRun" elseif speed>1 then "QuadWalk" else "QuadIdle") else (if speed>1 then "BipedWalk" else "BipedIdle")
	local t=if speed>1 then state.phase%duration(name) else now%duration(name)
	local wind=math.max(.01,tonumber(model:GetAttribute("AttackWindDuration")) or .3)
	local active=math.max(.01,tonumber(model:GetAttribute("AttackActiveDuration")) or .12)
	local recovery=math.max(.01,tonumber(model:GetAttribute("AttackRecoveryDuration")) or .6)
	local owns=false
	for key,clip in attacks do
		if pose==key.."Wind" or pose==key.."Strike" then
			name=clip;state.lastStrike=clip;owns=true
			local a,b=attackEdges(name)
			t=duration(name)*(if pose==key.."Wind" then a*math.clamp(elapsed/wind,0,1) else a+(b-a)*math.clamp(elapsed/active,0,1))
			break
		end
	end
	if pose=="SweepExtend" or pose=="TripSweep" or pose=="SlamRaise" or pose=="BiteLunge" then
		name=if pose=="TripSweep" then "Trip" elseif pose=="SlamRaise" then "Slam" elseif pose=="BiteLunge" then "Bite" else "Sweep"
		state.lastStrike=name;owns=true
		local a,b=attackEdges(name)
		t=duration(name)*(if pose=="SlamRaise" then a*math.clamp(elapsed/wind,0,1) else a+(b-a)*math.clamp(elapsed/active,0,1))
	elseif pose=="Recover" then
		name=state.lastStrike;owns=true
		local _,b=attackEdges(name)
		t=duration(name)*(b+(1-b)*math.clamp(elapsed/recovery,0,1))
		if model:GetAttribute("Attack")=="RiverDash" then name="QuadIdle";t=elapsed%duration(name) end
	elseif pose=="FeintWind" or pose=="FeintStrike" then
		name="Feint";owns=true;t=duration(name)*math.clamp(elapsed/wind,0,1)
	elseif pose=="DashWind" then
		name="QuadRun";t=0
	elseif pose=="DashRun" then
		name="QuadRun";t=elapsed%duration(name)
	elseif pose=="GrabOpen" or pose=="GrabLunge" or pose=="GrabHold" or pose=="Throw" then
		name="Grapple";state.lastStrike=name;owns=true
		t=duration(name)*(if pose=="GrabOpen" then .4*math.clamp(elapsed/wind,0,1) elseif pose=="GrabLunge" then .4+.16*math.clamp(elapsed/active,0,1) elseif pose=="GrabHold" then .56 else .56+.44*math.clamp(elapsed/.35,0,1))
	elseif pose=="Roar" then name="Roar";t=elapsed%duration(name);state.lastStrike=name
	elseif pose=="Surrender" or loco=="DEFEATED" then name="Surrender";t=math.min(elapsed,duration(name))
	elseif pose=="Leap" or pose=="ClimbRail" then name="Leap";t=math.min(elapsed,duration(name))
	elseif pose=="Land" then name="Land";t=math.min(elapsed,duration(name))
	elseif pose=="DrawSword" then name="Draw";t=math.min(elapsed,duration(name))
	elseif pose=="StandUp" or loco=="RISE_TO_BIPED" then name="Rise";t=math.min(if pose=="StandUp" then elapsed else now-state.locoStart,.5)
	elseif loco=="DROP_TO_QUADRUPED" then name="Rise";t=.5*(1-math.clamp((now-state.locoStart)/.4,0,1))
	elseif loco=="STAGGER" or loco=="KNOCKDOWN" then name="Stagger";t=math.min(now-state.locoStart,duration(name))
	elseif loco=="SITTING" or model:GetAttribute("OttiState")=="OTTI_SPECTATING" then
		name=if pose=="Clap" or pose=="PawRaise" or pose=="Surprised" then "Celebrate" else "Sit"
		t=now%duration(name)
	elseif model:GetAttribute("Guard")==true and pose=="" then name="Guard";t=duration(name)*.5
	end
	local goals=Player.sample(clips["Otti_"..name],t)
	local yaw=math.atan2(-root.CFrame.LookVector.X,-root.CFrame.LookVector.Z)
	local change=(yaw-state.yaw+math.pi)%(2*math.pi)-math.pi
	state.yaw=yaw;state.yawRate+=(math.clamp(change/math.max(dt,.001),-6,6)-state.yawRate)*(1-math.exp(-dt*8))
	local alpha=1-math.exp(-dt*(if owns then 65 else 22))
	for i,boneName in source.bones do
		local bone=state.bones[boneName]
		if bone then
			local goal=goals[i]
			-- The imported paw padding sits 0.22 studs above the authored contact plane.
			-- Translate the skeleton, keeping the server's collision capsule unchanged.
			if boneName=="Root" then
				local contact=if name:sub(1,4)=="Quad" or name=="Trip" or name=="Bite" then 1 elseif name=="Rise" then 1-math.clamp(t/.5,0,1) else 0
				goal*=CFrame.new(state.axes[boneName]*(-.22*contact))
			end
			if not owns then
				local tailIndex=tonumber(boneName:match("^Tail(%d+)$"))
				if tailIndex then goal*=CFrame.fromAxisAngle(state.axes[boneName],-state.yawRate*.018*tailIndex)
				elseif boneName=="Lumbar" or boneName=="Spine" then goal*=CFrame.fromAxisAngle(state.axes[boneName],state.yawRate*.025) end
				local lookAt=model:GetAttribute("LookAt")
				if boneName=="Head" and name=="Sit" and typeof(lookAt)=="Vector3" then
					local direction=root.CFrame:VectorToObjectSpace(lookAt-root.Position)
					goal*=CFrame.fromAxisAngle(state.axes[boneName],math.clamp(math.atan2(-direction.X,-direction.Z),-.55,.55))
				end
			end
			local current=(state.current[i] or goal):Lerp(goal,alpha)
			state.current[i]=current;bone.Transform=current
		end
	end
end
return Animator
