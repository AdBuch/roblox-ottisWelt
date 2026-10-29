-- Minimal Roblox geometry adapter: executes the actual builder and tests its produced solids.
local checks = 0
local function check(value, message) assert(value, message); checks += 1 end
local V = {}
V.__index = V
local function vector(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},V) end
V.__add = function(a,b) return vector(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V.__sub = function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V.__mul = function(a,b) if type(a)=="number" then a,b=b,a end return vector(a.X*b,a.Y*b,a.Z*b) end
V.__div = function(a,b) return a*(1/b) end
V.__unm = function(a) return a*-1 end
V.__index = function(a,k) if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) elseif k=="Unit" then return a/a.Magnitude end return V[k] end
function V:Cross(b) return vector(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
local Vector3 = {new=vector,one=vector(1,1,1),zero=vector(),xAxis=vector(1,0,0),yAxis=vector(0,1,0),zAxis=vector(0,0,1)}
local Vector2 = {new=function(x,y) return {X=x,Y=y} end}
local C = {}
C.__index = C
local function transform(p,r) return setmetatable({Position=p,r=r or {1,0,0,0,1,0,0,0,1}},C) end
local function rotate(r,v) return vector(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z) end
C.__mul = function(a,b)
    if getmetatable(b)==V then return a.Position+rotate(a.r,b) end
    local r={}
    for i=0,2 do for j=0,2 do r[i*3+j+1]=0; for k=0,2 do r[i*3+j+1]+=a.r[i*3+k+1]*b.r[k*3+j+1] end end end
    return transform(a.Position+rotate(a.r,b.Position),r)
end
C.__add = function(a,b) return transform(a.Position+b,a.r) end
function C:PointToObjectSpace(p)
    local r=self.r
    return rotate({r[1],r[4],r[7],r[2],r[5],r[8],r[3],r[6],r[9]},p-self.Position)
end
local CFrame = {}
CFrame.new = function(x,y,z) return transform(if type(x)=="table" then x else vector(x,y,z)) end
CFrame.Angles = function(x,y,z)
    local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
    return transform(vector(),{1,0,0,0,cx,-sx,0,sx,cx}) * transform(vector(),{cy,0,sy,0,1,0,-sy,0,cy}) * transform(vector(),{cz,-sz,0,sz,cz,0,0,0,1})
end
CFrame.lookAt = function(p,target)
    local d=target-p
    local yaw=math.atan2(-d.X,-d.Z)
    return CFrame.new(p)*CFrame.Angles(0,yaw,0)
end
CFrame.identity=CFrame.new()
CFrame.fromMatrix=function(p,x,y) local z=x:Cross(y); return transform(p,{x.X,y.X,z.X,x.Y,y.Y,z.Y,x.Z,y.Z,z.Z}) end
local Color3={fromRGB=function(...) return {...} end,new=function(...) return {...} end}
local function enum() return setmetatable({},{__index=function(t,k) local v=enum(); rawset(t,k,v); return v end}) end
local Enum=enum()
local all={}
local Instance={}
function Instance.new(class)
    local n={ClassName=class,attrs={}}
    function n:SetAttribute(k,v) self.attrs[k]=v end
    function n:FindFirstChild(name) for _,v in all do if v.Parent==self and not v.dead and v.Name==name then return v end end end
    function n:IsA(c) return self.ClassName==c or (c=="BasePart" and (self.ClassName=="Part" or self.ClassName=="SpawnLocation")) end
    function n:GetChildren() local t={} for _,v in all do if v.Parent==self and not v.dead then table.insert(t,v) end end return t end
    function n:GetDescendants() local t={} for _,v in all do local p=v.Parent; while p do if p==self and not v.dead then table.insert(t,v); break end p=p.Parent end end return t end
    function n:GetPivot() return if self.PrimaryPart then self.PrimaryPart.CFrame else CFrame.new() end
    function n:PivotTo(cf) local delta=cf.Position-self:GetPivot().Position; for _,p in self:GetDescendants() do if p.CFrame then p.CFrame=p.CFrame+delta end end end
    function n:FindFirstAncestorWhichIsA(c)
        local p=self.Parent
        while p do if p.ClassName=="Part" or p.ClassName==c then return p end p=p.Parent end
    end
    function n:Destroy() self.dead=true; self.Parent=nil end
    setmetatable(n,{__index=function(t,k) if k=="Position" then return t.CFrame.Position end end})
    table.insert(all,n)
    return n
end
local UDim2={fromScale=function(...) return {...} end,fromOffset=function(...) return {...} end}
local Workspace=Instance.new("Workspace")
local Lighting={}
local ReplicatedStorage={Shared={Config="Config",LobbyPadDefinitions="LobbyPadDefinitions",ColosseumLayout="ColosseumLayout"}}
local script={Parent={LobbyMosaics="LobbyMosaics",LobbyStatue="LobbyStatue",ShopBattleMosaics="ShopBattleMosaics",LobbyArchitecture="LobbyArchitecture",ColosseumGate="ColosseumGate",Arena="Arena"}}
local game={GetService=function(_,name) return ({Workspace=Workspace,Lighting=Lighting,ReplicatedStorage=ReplicatedStorage,CollectionService={AddTag=function() end}})[name] end}
local modules={Config={LobbyFolderName="GeneratedLobby",ArenaFolderName="GeneratedArena"},LobbyMosaics={has=function() return false end,build=function() end},LobbyStatue={build=function(_,_,_,id) table.insert(all,{ClassName="Statue",Name=id.."Statue"}) end}}
local require=function(id) return assert(modules[id],id) end
local Random={new=function(seed) local rng={seed=seed}; function rng:NextInteger(a,b) self.seed=(self.seed*16807)%2147483647; return a+self.seed%(b-a+1) end return rng end}

-- INSERT_DEFINITIONS
-- INSERT_BATTLE_MOSAICS
-- INSERT_LAYOUT
-- INSERT_GATE
-- INSERT_ARENA
-- INSERT_ARCHITECTURE
-- INSERT_BUILDER

local layout=modules.LobbyService.build()
check(#layout.pads==5,"three co-op bays and two opposing team bays")
check(#layout.tribuneDoors==3,"three live entrances")
check(#layout.trainingSlots==6,"six training cages")
check(#layout.modeBoards==5,"all modes, team selector and meeting point")
check(#layout.archiveSlots==6,"six separate prisoner cells")
check(#layout.soloHosts==3 and #layout.bossBoards==3,"intentional solo and boss entrances in every hall")
local byName={}
for _,p in all do byName[p.Name or ""]=true end
for _,id in {"Otti","Schili","Kroko"} do check(byName[id.."Statue"],"statue "..id) end
for _,cf in layout.trainingSlots do check(modules.LobbyService.isInside(cf.Position+vector(0,3,0)),"training safety zone") end
check(not modules.LobbyService.isInArmory(vector(0,-17,0)),"no purchases outside shops")
for _,angle in {30,270,150} do
    local cf=modules.ColosseumLayout.frame(math.rad(angle),100,-17)
    check(modules.LobbyService.isInArmory(cf.Position),"shop region "..angle)
end
local tested=0
local function clearHead(foot,label)
    local head=foot+vector(0,4.8,0)
    for _,part in all do
        if not part.dead and part.ClassName=="Part" and part.CanCollide~=false and part.CFrame and part.Size and part.Shape~=Enum.PartType.Cylinder then
            local p=part.CFrame:PointToObjectSpace(head)
            check(not (math.abs(p.X)<part.Size.X/2+0.6 and math.abs(p.Y)<part.Size.Y/2+0.3 and math.abs(p.Z)<part.Size.Z/2+0.6),label.." blocked by "..part.Name)
        end
    end
end
for _,part in all do
    if not part.dead and part.Name=="PassageFloor" then
        for i=-2,2 do
            local point=part.CFrame*vector(0,1,i*part.Size.Z/5)
            check(modules.LobbyService.isInside(point+vector(0,3,0)),"passage safety zone")
            clearHead(point,"concourse / approach centre "..point.X..","..point.Z)
        end
    end
end
-- Every maze cell is connected to the meeting point by a doorway graph.
local seen={['0:0']=true}; local queue={{0,0}}; local n=1
local function edge(ax,az,bx,bz) local a,b=ax..":"..az,bx..":"..bz; return if a<b then a.."/"..b else b.."/"..a end
while n<=#queue do
    local p=queue[n]; n+=1
    for _,d in {{1,0},{-1,0},{0,1},{0,-1}} do
        local x,z=p[1]+d[1],p[2]+d[2]; local key=x..":"..z
        if not seen[key] and layout.mazeEdges[edge(p[1],p[2],x,z)] then seen[key]=true; table.insert(queue,{x,z}) end
    end
end
check(#queue==(layout.mazeHalf*2+1)^2,"all hypogeum cells connect to meeting point")
-- New tunnel openings must leave every existing spectator spawn on a solid walkway.
for seed=0,11 do
    local foot=modules.Arena.getTribuneCFrame(seed).Position-vector(0,3,0)
    local supported=false
    for _,part in all do
        if not part.dead and part.ClassName=="Part" and part.CanCollide~=false and part.CFrame and part.Size then
            local o=part.CFrame:PointToObjectSpace(foot)
            if math.abs(o.X)<part.Size.X/2 and math.abs(o.Z)<part.Size.Z/2 and math.abs(o.Y-part.Size.Y/2)<0.3 then supported=true; break end
        end
    end
    check(supported,"spectator walkway support at spawn "..seed)
end
for _,flight in layout.stairRoutes do
        for i=1,flight.count do
            local y=i*flight.rise/flight.count
            local foot=flight.cf*vector(0,y,(i-0.5)*flight.run/flight.count)
            check(modules.LobbyService.isInside(foot+vector(0,3,0)),"stair safety zone")
            local head=foot+vector(0,4.8,0)
            for _,part in all do
                if not part.dead and part.ClassName=="Part" and part.CanCollide~=false and part.CFrame and part.Size and part.Shape~=Enum.PartType.Cylinder then
                    local p=part.CFrame:PointToObjectSpace(head)
                    check(not (math.abs(p.X)<part.Size.X/2+0.6 and math.abs(p.Y)<part.Size.Y/2+0.3 and math.abs(p.Z)<part.Size.Z/2+0.6),"stair head blocked by "..part.Name.." route "..tostring(flight.cf.Position.X)..","..tostring(flight.cf.Position.Z).." step "..i)
                end
            end
            tested+=1
        end
end
local solid=modules.ColosseumGate.build(Workspace,CFrame.new(500,1,500),"Solid")
check(solid.Transparency==1 and solid.CanCollide~=false,"solid gate still blocks passage")
check(solid.Parent:FindFirstChild("TimberLeaves")~=nil,"opaque gate variant has timber leaves")
local grille=modules.ColosseumGate.build(Workspace,CFrame.new(600,1,500),"Grille")
check(grille.Parent:FindFirstChild("TimberLeaves")==nil and grille.Parent:FindFirstChild("IronBar")~=nil,"grille variant keeps the view open")
print("PASS: actual Arena and Lobby builders, three full hero halls and shops, five group bays, six prisoner cells and six training cages; "..tested.." stair positions checked ("..checks.." checks)")
