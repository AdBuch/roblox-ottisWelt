--!strict
-- Lightweight local rope lattice, driven by the server's committed cast and victim.
local Players=game:GetService("Players")
local Debris=game:GetService("Debris")
local Workspace=game:GetService("Workspace")
local Effects={}
local states: {[Model]: any}=setmetatable({}, {__mode="k"}) :: any
local function rope(parent: Instance): Part
	local p=Instance.new("Part")
	p.Name="NetRope";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
	p.Material=Enum.Material.Fabric;p.Color=Color3.fromRGB(221,204,162);p.Size=Vector3.new(.045,.045,.1);p.Parent=parent
	return p
end
function Effects.update(model: Model)
	local start=model:GetAttribute("NetStart")
	if typeof(start)~="number" then return end
	local state=states[model]
	local now=Workspace:GetServerTimeNow()
	local flight=tonumber(model:GetAttribute("NetFlightDuration")) or .55
	if not state or state.start~=start then
		if now-start>flight+3.2 then return end
		if state and state.folder then state.folder:Destroy() end
		local from=model:GetAttribute("NetFrom")
		local target=model:GetAttribute("NetTarget")
		if typeof(from)~="Vector3" or typeof(target)~="Vector3" then return end
		local hand=model:FindFirstChild("Hand.L",true)
		local folder=Instance.new("Folder");folder.Name="OttiCastingNet";folder.Parent=Workspace
		local edges={}
		for i=0,4 do for j=0,4 do
			local n=i*5+j+1
			if i<4 then table.insert(edges,{a=n,b=n+5,part=rope(folder)}) end
			if j<4 then table.insert(edges,{a=n,b=n+1,part=rope(folder)}) end
		end end
		local weights={}
		for _,index in {1,5,21,25} do
			local p=rope(folder);p.Name="NetWeight";p.Shape=Enum.PartType.Ball;p.Color=Color3.fromRGB(161,124,68);p.Material=Enum.Material.Wood;p.Size=Vector3.one*.2
			table.insert(weights,{index=index,part=p})
		end
		state={start=start,folder=folder,edges=edges,weights=weights,target=target,from=from,
			handFrom=if hand and hand:IsA("Bone") then hand.TransformedWorldCFrame.Position else from}
		states[model]=state
		Debris:AddItem(folder,flight+4)
	end
	if not state.folder.Parent then return end
	local age=now-start
	if model:GetAttribute("NetCancelled")==true or age>flight+3.2 then state.folder:Destroy();return end
	local u=math.clamp(age/flight,0,1)
	local center=state.from:Lerp(state.target,u)+Vector3.new(0,math.sin(u*math.pi)*3.5,0)
	-- Start at the rendered release hand, converge onto the authoritative trajectory.
	center+=(state.handFrom-state.from)*(1-u)^2
	local radius=.22+2.7*math.sin(u*math.pi/2)
	local drape=.15*u
	local fade=0
	local victimId=model:GetAttribute("NetVictim")
	if typeof(victimId)=="number" then
		local player=Players:GetPlayerByUserId(victimId)
		local character=player and player.Character
		local root=character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local landed=root.Position+Vector3.new(0,2.1,0)
			local caught=tonumber(model:GetAttribute("NetCatchStart")) or now
			local settle=math.clamp((now-caught)/.18,0,1)
			center=center:Lerp(landed,settle);radius=radius+(1.85-radius)*settle;drape=.15+2.8*settle
		end
	elseif age>flight then
		center-=Vector3.new(0,math.min(3.2,(age-flight)*5),0)
		fade=math.clamp((age-flight-.35)/.5,0,1)
		if fade>=1 then state.folder:Destroy();return end
	end
	local points={}
	for i=0,4 do for j=0,4 do
		local x,z=(i-2)/2,(j-2)/2
		points[i*5+j+1]=center+Vector3.new(x*radius,-drape*math.max(x*x,z*z),z*radius)
	end end
	for _,edge in state.edges do
		local a,b=points[edge.a],points[edge.b]
		edge.part.Size=Vector3.new(.045,.045,(a-b).Magnitude)
		edge.part.CFrame=CFrame.lookAt((a+b)/2,b);edge.part.Transparency=fade
	end
	for _,weight in state.weights do weight.part.Position=points[weight.index];weight.part.Transparency=fade end
end
return Effects
