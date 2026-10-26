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
V.__index = function(a,k) if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end return V[k] end
local Vector3 = {new=vector,one=vector(1,1,1),zero=vector(),xAxis=vector(1,0,0),zAxis=vector(0,0,1)}
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
local Color3={fromRGB=function(...) return {...} end,new=function(...) return {...} end}
local function enum() return setmetatable({},{__index=function(t,k) local v=enum(); rawset(t,k,v); return v end}) end
local Enum=enum()
local all={}
local Instance={}
function Instance.new(class)
    local n={ClassName=class,attrs={}}
    function n:SetAttribute(k,v) self.attrs[k]=v end
    function n:FindFirstChild() return nil end
    function n:FindFirstAncestorWhichIsA(c)
        local p=self.Parent
        while p do if p.ClassName=="Part" or p.ClassName==c then return p end p=p.Parent end
    end
    function n:Destroy() end
    table.insert(all,n)
    return n
end
local UDim2={fromScale=function(...) return {...} end,fromOffset=function(...) return {...} end}
local Workspace=Instance.new("Workspace")
local Lighting={}
local ReplicatedStorage={Shared={Config="Config",LobbyPadDefinitions="LobbyPadDefinitions"}}
local script={Parent={LobbyMosaics="LobbyMosaics",LobbyStatue="LobbyStatue"}}
local game={GetService=function(_,name) return ({Workspace=Workspace,Lighting=Lighting,ReplicatedStorage=ReplicatedStorage})[name] end}
local modules={Config={LobbyFolderName="GeneratedLobby"},LobbyMosaics={has=function() return false end},LobbyStatue={build=function(_,_,_,id) table.insert(all,{ClassName="Statue",Name=id.."Statue"}) end}}
local require=function(id) return assert(modules[id],id) end

-- INSERT_DEFINITIONS
-- INSERT_BUILDER

local layout=modules.LobbyService.build()
check(#layout.pads==3,"exactly three existing lobby mosaics")
check(#layout.tribuneDoors==3,"three live entrances")
check(#layout.trainingSlots==6,"six training cages")
check(#layout.modeBoards==4,"all modes from each hall and the meeting point")
local byName={}
for _,p in all do byName[p.Name or ""]=true end
for _,id in {"Otti","Schili","Kroko"} do check(byName[id.."Statue"],"statue "..id) end
for _,cf in layout.trainingSlots do check(modules.LobbyService.isInside(cf.Position+vector(0,3,0)),"training safety zone") end
check(not modules.LobbyService.isInArmory(vector(0,-17,0)),"no purchases outside shops")
for _,angle in {60,180,300} do
    local cf=CFrame.Angles(0,math.rad(angle),0)*CFrame.new(0,-17,118)
    check(modules.LobbyService.isInArmory(cf.Position),"shop region "..angle)
end
local tested=0
for _,angle in {0,120,240} do
    local turn=CFrame.Angles(0,math.rad(angle),0)
    for _,flight in {{x=-23,start=136,run=60,rise=36,base=-20,n=36},{x=23,start=172,run=36,rise=24,base=-44,n=24}} do
        for i=1,flight.n do
            local radial=flight.start-(i-0.5)*flight.run/flight.n
            local y=flight.base+i*flight.rise/flight.n
            local foot=turn*vector(flight.x,y,radial)
            check(modules.LobbyService.isInside(foot+vector(0,3,0)),"stair safety zone")
            local head=foot+vector(0,4.8,0)
            for _,part in all do
                if part.ClassName=="Part" and part.CanCollide~=false and part.CFrame and part.Size and part.Shape~=Enum.PartType.Cylinder then
                    local p=part.CFrame:PointToObjectSpace(head)
                    check(not (math.abs(p.X)<part.Size.X/2+0.6 and math.abs(p.Y)<part.Size.Y/2+0.3 and math.abs(p.Z)<part.Size.Z/2+0.6),"stair head blocked by "..part.Name.." angle "..angle.." step "..i)
                end
            end
            tested+=1
        end
    end
end
print("PASS: ring builder, three shops, three statues, six cages; "..tested.." stair positions checked against generated collision parts ("..checks.." checks)")
