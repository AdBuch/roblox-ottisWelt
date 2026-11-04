--!strict
-- A committed, dodgeable cast. The client draws rope; only this trajectory can catch.
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local Animation=require(script.Parent.OttiAnimationService)
local Util=require(script.Parent.CombatUtil)
local Effects=require(script.Parent.CombatEffects)
local Arena=require(script.Parent.Arena)
local Equipment=require(script.Parent.OttiEquipment)
type Boss=Animation.Boss
type Context=Animation.BossContext
local Net={}
local SNARE_SECONDS=2.4
local function valid(boss: Boss,ctx: Context): boolean
	return ctx.stillValid() and not boss.interrupted and not boss.defeated and boss.model.Parent~=nil
end
function Net.execute(boss: Boss,ctx: Context,move: any,target: Player,ignore: {Instance}): boolean
	local _,_,root=Util.getLivingCharacter(target)
	if not root or not table.find(ctx.fighters(),target) then return false end
	if Util.flatDistance(boss.root.Position,root.Position)>move.Range then return false end
	local aim=root.Position+Vector3.new(0,.7,0)
	if not Util.hasLineOfSight(boss.root.Position,aim,ignore) then return false end
	Animation.faceTowards(boss,aim,0)
	Animation.setPose(boss,"NetWind",.2)
	Effects.groundMarker(Vector3.new(aim.X,Arena.Layout.FloorTop+.03,aim.Z),move.Radius,move.WindUp+move.Active,Color3.fromRGB(235,210,145))
	local elapsed=0
	while elapsed<move.WindUp do
		elapsed+=RunService.Heartbeat:Wait()
		if not valid(boss,ctx) then return false end
	end
	Animation.setPose(boss,"NetRelease",.04)
	-- Release when the throwing hand has come forward, not at its wind-up position.
	elapsed=0
	while elapsed<.14 do
		elapsed+=RunService.Heartbeat:Wait()
		if not valid(boss,ctx) then return false end
	end
	local from=boss.root.CFrame:PointToWorldSpace(Vector3.new(2,.8,-1))
	local start=Workspace:GetServerTimeNow()
	boss.model:SetAttribute("NetFrom",from)
	boss.model:SetAttribute("NetTarget",aim)
	boss.model:SetAttribute("NetFlightDuration",move.Active)
	boss.model:SetAttribute("NetVictim",nil)
	boss.model:SetAttribute("NetCancelled",false)
	boss.model:SetAttribute("NetReleased",true)
	boss.model:SetAttribute("NetStart",start) -- publish last, after the immutable trajectory
	Equipment.refresh(boss.model)
	local previous=from
	elapsed=0
	while elapsed<move.Active do
		elapsed+=RunService.Heartbeat:Wait()
		local u=math.clamp(elapsed/move.Active,0,1)
		local position=from:Lerp(aim,u)+Vector3.new(0,math.sin(u*math.pi)*3.5,0)
		if not valid(boss,ctx) or not Util.hasLineOfSight(previous,position,ignore) then
			boss.model:SetAttribute("NetCancelled",true)
			return false
		end
		previous=position
	end
	local _,humanoid,victimRoot=Util.getLivingCharacter(target)
	if not humanoid or not victimRoot or not table.find(ctx.fighters(),target) then return false end
	if Util.flatDistance(victimRoot.Position,aim)>move.Radius or math.abs(victimRoot.Position.Y-aim.Y)>4.5 then return false end
	if not Util.hasLineOfSight(aim,victimRoot.Position,ignore) then return false end
	local dealt,blocked=ctx.hitPlayer(target,{fromPosition=from,damage=move.Damage,blockable=true,blockStops=true,knockback=0})
	boss.lastAttacked[target]=os.clock()
	if blocked or dealt<=0 then return false end
	boss.model:SetAttribute("AttackDamaged",true)
	boss.model:SetAttribute("NetCatchStart",Workspace:GetServerTimeNow())
	boss.model:SetAttribute("NetVictim",target.UserId)
	local release=if ctx.snarePlayer then ctx.snarePlayer(target,SNARE_SECONDS) else function() end
	task.spawn(function()
		local finish=os.clock()+SNARE_SECONDS
		while os.clock()<finish and valid(boss,ctx) and target.Character and humanoid.Health>0 do
			RunService.Heartbeat:Wait()
		end
		release()
		if boss.model.Parent and boss.model:GetAttribute("NetStart")==start then
			boss.model:SetAttribute("NetVictim",nil)
			boss.model:SetAttribute("NetCancelled",true)
		end
	end)
	return true
end
return Net
