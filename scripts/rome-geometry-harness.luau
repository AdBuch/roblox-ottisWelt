-- Runs the actual Rome builders (streets, crossings, houses with the smithy, forum and temple,
-- town walls, harbour) in a small Roblox geometry adapter and walks their collision surfaces:
--   * every stepping-stone crossing, across the street and along it, both directions
--   * the kerbs of every main street
--   * from the forum up the temple stair and the side ramp into the cella to the oracle
--   * from the Handwerksgasse into the smithy to the smith
-- A walk fails on a rise of more than MAX_STEP within half a stud (a step that needs a jump or
-- snags the feet), a missing floor, or a solid part at head height. It also checks the house
-- models (80, attributes, door anchors, only the smithy open) and reports part counts.
-- The adapter does not replace a test of the Roblox physics in Studio.
-- ADAPTER (from lobby-ring-harness, with full look-at frames and wedges)
local V = {}
local function vector(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},V) end
V.__add = function(a,b) return vector(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V.__sub = function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V.__mul = function(a,b) if type(a)=="number" then a,b=b,a end return vector(a.X*b,a.Y*b,a.Z*b) end
V.__div = function(a,b) return a*(1/b) end
V.__unm = function(a) return a*-1 end
V.__index = function(a,k) if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) elseif k=="Unit" then return a/a.Magnitude end return V[k] end
function V:Cross(b) return vector(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
local Vector3 = {new=vector,one=vector(1,1,1),zero=vector(),xAxis=vector(1,0,0),yAxis=vector(0,1,0),zAxis=vector(0,0,1)}
local Vector2 = {new=function(x,y) return {X=x,Y=y} end}
local C = {}
local function transform(p,r) return setmetatable({Position=p,r=r or {1,0,0,0,1,0,0,0,1}},C) end
C.__index = function(cf,k)
    local r=cf.r
    if k=="LookVector" then return vector(-r[3],-r[6],-r[9]) elseif k=="UpVector" then return vector(r[2],r[5],r[8]) elseif k=="RightVector" then return vector(r[1],r[4],r[7]) end
    return C[k]
end
local function rotate(r,v) return vector(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z) end
C.__mul = function(a,b)
    if getmetatable(b)==V then return a.Position+rotate(a.r,b) end
    local r={}
    for i=0,2 do for j=0,2 do r[i*3+j+1]=0; for k=0,2 do r[i*3+j+1]+=a.r[i*3+k+1]*b.r[k*3+j+1] end end end
    return transform(a.Position+rotate(a.r,b.Position),r)
end
C.__add = function(a,b) return transform(a.Position+b,a.r) end
C.__sub = function(a,b) return transform(a.Position-b,a.r) end
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
CFrame.fromMatrix=function(p,x,y) local z=x:Cross(y); return transform(p,{x.X,y.X,z.X,x.Y,y.Y,z.Y,x.Z,y.Z,z.Z}) end
CFrame.lookAt = function(p,target,up)
    local f=(target-p).Unit
    local u=up or vector(0,1,0)
    local right=f:Cross(u)
    if right.Magnitude<1e-6 then right=vector(1,0,0) end
    right=right.Unit
    local up2=right:Cross(f)
    return CFrame.fromMatrix(p,right,up2)
end
CFrame.identity=CFrame.new()
local Color3={fromRGB=function(...) return {...} end,new=function(...) return {...} end}
local function enum() return setmetatable({},{__index=function(t,k) local v=enum(); rawset(t,k,v); return v end}) end
local Enum=enum()
local all={}
local Instance={}
local BASE={Part=true,WedgePart=true,SpawnLocation=true}
function Instance.new(class)
    local n={ClassName=class,attrs={},CanCollide=true,Transparency=0}
    function n:SetAttribute(k,v) self.attrs[k]=v end
    function n:GetAttribute(k) return self.attrs[k] end
    function n:IsA(c) return self.ClassName==c or (c=="BasePart" and BASE[self.ClassName]==true) end
    function n:GetChildren() local t={} for _,v in all do if v.Parent==self then table.insert(t,v) end end return t end
    function n:Destroy() self.dead=true; self.Parent=nil end
    setmetatable(n,{__index=function(t,k) if k=="Position" then return t.CFrame.Position end end})
    table.insert(all,n)
    return n
end
local UDim2={fromScale=function(...) return {...} end,fromOffset=function(...) return {...} end,new=function(...) return {...} end}
local UDim={new=function(...) return {...} end}
local ColorSequence={new=function(...) return {...} end}
local NumberSequence={new=function(...) return {...} end}
local NumberSequenceKeypoint={new=function(...) return {...} end}
local NumberRange={new=function(...) return {...} end}
local Workspace=Instance.new("Workspace")
local ReplicatedStorage={Shared={ColosseumLayout="ColosseumLayout"}}
local script={Parent={RomeLayout="RomeLayout",RomeParts="RomeParts",StreetBuilder="StreetBuilder",HouseKit="HouseKit",Smithy="Smithy",ForumTemple="ForumTemple",CityShell="CityShell",Harbor="Harbor",IslandBuilder="IslandBuilder",Yards="Yards"}}
local Lighting={}
local game={GetService=function(_,name) return ({Workspace=Workspace,ReplicatedStorage=ReplicatedStorage,Lighting=Lighting})[name] end}
local modules={}
local require=function(id) return assert(modules[id],id) end

-- INSERT_MODULES

local checks,failures=0,{}
local function check(value,message) checks+=1; if not value then table.insert(failures,message) end end
local root=Instance.new("Folder")
local crossings=modules.StreetBuilder.build(root)
local forum=modules.ForumTemple.build(root)
modules.CityShell.build(root)
modules.Harbor.build(root)
modules.Yards.build(root)
local houses={}
for _,h in modules.RomeLayout.houses() do table.insert(houses,modules.HouseKit.build(root,h,modules.Smithy.build)) end
local R=modules.RomeLayout

-- solids: collidable boxes and wedges
local solids={}
for _,p in all do
    if not p.dead and BASE[p.ClassName] and p.CanCollide~=false and p.CFrame and p.Size and p.Shape~=Enum.PartType.Ball then table.insert(solids,p) end
end
local GRID=12
local grid={}
local function extent(p)
    local r,s=p.CFrame.r,p.Size
    return (math.abs(r[1])*s.X+math.abs(r[2])*s.Y+math.abs(r[3])*s.Z)/2,(math.abs(r[7])*s.X+math.abs(r[8])*s.Y+math.abs(r[9])*s.Z)/2
end
for _,p in solids do
    local ex,ez=extent(p)
    local c=p.CFrame.Position
    for gx=math.floor((c.X-ex)/GRID),math.floor((c.X+ex)/GRID) do
        for gz=math.floor((c.Z-ez)/GRID),math.floor((c.Z+ez)/GRID) do
            local key=gx..":"..gz
            grid[key]=grid[key] or {}
            table.insert(grid[key],p)
        end
    end
end
-- the vertical extent of a part above (x, z): bottom and top (a wedge's top follows its slope)
local function span(p,x,z)
    local s=p.Size
    local r=p.CFrame.r
    -- intersect the vertical line with the part: sample y range analytically for boxes / wedges
    local lo,hi=math.huge,-math.huge
    for y=p.CFrame.Position.Y-60,p.CFrame.Position.Y+60,0.05 do end
    -- solve per axis like the lobby harness (slab method)
    local dx,dy,dz=x-p.CFrame.Position.X,-p.CFrame.Position.Y,z-p.CFrame.Position.Z
    local h={s.X/2,s.Y/2,s.Z/2}
    lo,hi=-math.huge,math.huge
    for k=1,3 do
        local a=r[k]*dx+r[3+k]*dy+r[6+k]*dz
        local b=r[3+k]
        if math.abs(b)<1e-9 then
            if math.abs(a)>h[k] then return nil end
        else
            local t1,t2=(-h[k]-a)/b,(h[k]-a)/b
            if t1>t2 then t1,t2=t2,t1 end
            lo,hi=math.max(lo,t1),math.min(hi,t2)
        end
    end
    if lo>hi then return nil end
    if p.ClassName=="WedgePart" then
        -- keep only the part under the slope: local y <= -h/2 + h*(z + d/2)/d
        local function inside(y)
            local o=p.CFrame:PointToObjectSpace(vector(x,y,z))
            return o.Y <= -s.Y/2 + s.Y*(o.Z+s.Z/2)/s.Z + 1e-6
        end
        local a,b=lo,hi
        if not inside(a) and not inside(b) then return nil end
        -- the slope plane is monotonic along the vertical line: bisection for the boundary
        local inA=inside(a)
        for _=1,30 do
            local m=(a+b)/2
            if inside(m)==inA then a=m else b=m end
        end
        if inA then hi=a else lo=a end
    end
    return lo,hi
end
local function column(x,z)
    local list={}
    for _,p in grid[math.floor(x/GRID)..":"..math.floor(z/GRID)] or {} do
        local lo,hi=span(p,x,z)
        if lo then table.insert(list,{lo,hi,p}) end
    end
    return list
end
-- the floor a walker standing near `y` steps onto at (x, z), and what blocks the head
local MAX_STEP,BODY=0.45,5
local function floorAt(x,z,y)
    local best,blocked=nil,nil
    for _,s in column(x,z) do
        if s[2]<=y+1.2 and (not best or s[2]>best) then best=s[2] end
    end
    if best then
        for _,s in column(x,z) do
            if s[1]<best+BODY and s[2]>best+0.3 then blocked=s[3].Name end
        end
    end
    return best,blocked
end
local worst=0
local function walk(label,points,startY)
    local y=startY
    local length=0
    for i=1,#points-1 do
        local a,b=points[i],points[i+1]
        local d=(vector(b.X,0,b.Z)-vector(a.X,0,a.Z)).Magnitude
        local n=math.max(1,math.floor(d/0.5))
        for k=0,n do
            local p=a+(b-a)*(k/n)
            local f,blocked=floorAt(p.X,p.Z,y)
            if not f then check(false,label..": no floor at "..math.floor(p.X)..","..math.floor(p.Z)); return end
            local rise=f-y
            worst=math.max(worst,rise)
            check(rise<=MAX_STEP,("%s: a step of %.2f at %.1f,%.1f"):format(label,rise,p.X,p.Z))
            check(y-f<=3,("%s: a drop of %.2f at %.1f,%.1f"):format(label,y-f,p.X,p.Z))
            check(blocked==nil,("%s: %s at head height at %.1f,%.1f"):format(label,tostring(blocked),p.X,p.Z))
            if rise>MAX_STEP or y-f>3 or blocked then return end
            y=f
        end
        length+=d
    end
    return y,length
end
local function ground(x,z) local f=floorAt(x,z,40); return f end

-- 1 crossings: across (sidewalk -> stones -> sidewalk) and along the street through them, both ways
local crossingCount=0
for _,crossing in R.Crossings do
    local street=R.street(crossing.street)
    local section=R.Sections[street.kind]
    local a,b=street.points[crossing.segment],street.points[crossing.segment+1]
    local dir=(vector(b.x,0,b.z)-vector(a.x,0,a.z)).Unit
    local nrm=vector(-dir.Z,0,dir.X)
    local c=vector(a.x,0,a.z)+(vector(b.x,0,b.z)-vector(a.x,0,a.z))*crossing.t
    local reach=section.road/2+section.walk-0.4
    for _,s in {1,-1} do
        local from,to=c+nrm*(s*reach),c-nrm*(s*reach)
        walk("crossing "..crossing.id.." across",{from,to},ground(from.X,from.Z))
        local p0,p1=c-dir*(s*8),c+dir*(s*8)
        walk("crossing "..crossing.id.." along",{p0,p1},ground(p0.X,p0.Z))
        -- along the street over the stones, beside the middle (the wheel gap line)
        local q0,q1=p0+nrm*1.6,p1+nrm*1.6
        walk("crossing "..crossing.id.." along the gap",{q0,q1},ground(q0.X,q0.Z))
    end
    check(crossings[crossing.id]~=nil,"crossing built: "..crossing.id)
    crossingCount+=1
end
-- 2 kerbs: across every main street piece, every 20 studs, road -> sidewalk on both sides
for _,street in R.Streets do
    if street.kind=="Main" then
        local section=R.Sections[street.kind]
        for i=1,#street.points-1 do
            local a,b=street.points[i],street.points[i+1]
            local d=(vector(b.x,0,b.z)-vector(a.x,0,a.z))
            local dir=d.Unit
            local nrm=vector(-dir.Z,0,dir.X)
            for t=10,d.Magnitude-10,20 do
                local c=vector(a.x,0,a.z)+dir*t
                for _,s in {1,-1} do
                    local ramp=a.y~=b.y
                    local from,to=c,c+nrm*(s*(section.road/2+section.walk-(if ramp then 1.4 else 0.5)))
                    walk(("kerb %s %d at %d"):format(street.id,i,t),{from,to},ground(from.X,from.Z))
                    walk(("kerb %s %d at %d back"):format(street.id,i,t),{to,from},ground(to.X,to.Z))
                end
            end
        end
    end
end
-- 3 the temple: up the front stair (half-stud steps are allowed there), and up the side ramp
local T=R.Temple
local F=R.Forum
local stairWalk=walk
do
    MAX_STEP=0.55
    local y=stairWalk("temple stair",{vector(-425,0,0),vector(T.stairsTo+1,0,0),vector(T.x1-1,0,0),vector(T.cella.x1+2,0,0),vector(T.cella.x1-3,0,0),vector(R.Anchors.OracleSpot.x+1,0,0)},F.top)
    check(y and math.abs(y-T.top)<0.1,"the stair reaches the temple floor")
    MAX_STEP=0.45
    local y2=walk("temple side ramp",{vector(-430,0,20),vector(T.ramp.x0+1,0,20),vector(T.ramp.x1,0,20),vector(T.ramp.landingTo+2,0,20),vector(T.ramp.landingTo+2,0,13.3),vector(T.x1-10,0,13.3),vector(T.x1-6,0,11)},F.top)
    check(y2 and math.abs(y2-T.top)<0.1,"the side ramp reaches the temple floor")
    for _,route in forum.priestRoutes do
        for i=1,#route do
            local a,b=route[i],route[i%#route+1]
            walk("priest route",{a,b},T.top)
        end
    end
end
-- 4 the smithy: from the street through the opening to the smith
local smithy=modules.Smithy.result()
do
    local spot=smithy.smithSpot.Position
    local door=smithy.entrance.Position
    local out=door+(door-spot).Unit*10
    local y=walk("into the smithy",{out,door,spot+(door-spot).Unit*5.5},ground(out.X,out.Z))
    check(y and math.abs(y-(R.Levels.Lower+1.2))<0.1,"the smithy floor is reached")
end
-- 5 forum to harbour: down the Hafenstrasse onto the quay
walk("Hafenstrasse",{vector(-410,0,-20),vector(-430,0,-42),vector(-496,0,-40),vector(-526,0,-40),vector(-534,0,-40),vector(-536,0,-66),vector(-552,0,-86),vector(-590,0,-84)},F.top)
-- 6 the Handwerksgasse ramp from the forecourt
walk("Handwerksgasse",{vector(-200,0,0),vector(-232,0,0),vector(-262,0,0),vector(-326,0,0)},1)
-- private yards and gardens: every gate is closed, the yards are walled toward the public way
do
    for _,w in R.YardWalls do
        if w.gate then
            local g=vector(w.a.x+(w.b.x-w.a.x)*w.gate,0,w.a.z+(w.b.z-w.a.z)*w.gate)
            local solid=false
            for _,s in column(g.X,g.Z) do if s[1]<R.Levels.Lower+2 and s[2]>R.Levels.Lower+4 then solid=true end end
            check(solid,"garden gate closed: "..w.id)
        end
    end
    -- from the Handwerksgasse sidewalk no walk leads into the northern work yard
    local closed=false
    for z=-8,-30,-0.5 do
        for _,s in column(-248,z) do if (s[3].Name=="GardenWall" or s[3].Name=="GateLeaves") and s[2]>R.Levels.Lower+2 then closed=true end end
    end
    check(closed,"a wall closes the work yard toward the street")
end
-- houses
local typeCount,open={},{}
for _,m in houses do
    check(m.attrs.HouseId and m.attrs.HouseType and m.attrs.DoorAnchor,"house attributes: "..tostring(m.Name))
    typeCount[m.attrs.HouseType]=(typeCount[m.attrs.HouseType] or 0)+1
    if m.attrs.OpenInMVP then table.insert(open,m.attrs.HouseId) end
end
check(#houses==80,"80 house models")
check(#open==1,"exactly one open house (the smithy)")
-- every closed house: a solid body behind its door
for _,m in houses do
    if not m.attrs.OpenInMVP then
        local d=m.attrs.DoorAnchor
        local inward=d*vector(0,3,2)
        local blocked=false
        for _,s in column(inward.X,inward.Z) do if s[1]<inward.Y and s[2]>inward.Y then blocked=true end end
        check(blocked,"closed door is solid: "..m.attrs.HouseId)
    end
end
-- the island terrain (height function of IslandBuilder): every outside path dry and gentle, the
-- gates and outside anchors on dry ground, the coast meets the sea
do
    local I=modules.IslandBuilder
    local W=R.Levels.Water
    local steepest=0
    for _,path in R.Paths do
        for i=1,#path.points-1 do
            local a,b=path.points[i],path.points[i+1]
            local d=math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)
            local prev=nil
            for t=0,d,2 do
                local x,z=a.x+(b.x-a.x)*t/d,a.z+(b.z-a.z)*t/d
                local h=I.heightAt(x,z)
                check(h>W+1,("path %s dry at %d,%d (%.1f)"):format(path.id,x,z,h))
                if prev and math.abs(h-prev)/2>0.45 then print("STEEP",path.id,math.floor(x),math.floor(z),prev,h) end
                if prev then steepest=math.max(steepest,math.abs(h-prev)/2) end
                prev=h
            end
        end
    end
    check(steepest<0.45,("outside paths stay gentle (steepest %.2f)"):format(steepest))
    for name,a in R.Anchors do
        if name=="Viewpoint" or name=="SecretRuin" or name=="Clearing" or name=="Beach" then
            check(I.heightAt(a.x,a.z)>W+0.5,"anchor on dry ground: "..name)
        end
    end
    for _,g in R.Gates do
        local outward=1
        local h=I.heightAt(g.x+(if g.name=="LANDTOR" then 0 else -8),g.z+(if g.name=="LANDTOR" then -8 else -6))
        check(math.abs(h-g.level)<2.5,("ground outside the %s near the gate level (%.1f)"):format(g.name,h))
    end
    check(I.heightAt(R.Disc.x+R.Disc.radius-40,R.Disc.z)<W-5,"open sea before the rim")
    print(("island: steepest path slope %.2f"):format(steepest))
end
local counts={}
for _,p in all do if not p.dead and BASE[p.ClassName] then counts.parts=(counts.parts or 0)+1; if p.CanCollide~=false then counts.solid=(counts.solid or 0)+1 end end end
print(("rome geometry: %d parts (%d colliding), %d crossings walked, worst rise %.2f"):format(counts.parts,counts.solid,crossingCount,worst))
for i,m in failures do if i<=40 then print("FAIL "..m) end end
assert(#failures==0,#failures.." geometry checks failed")
print(("PASS: Rome builders, crossings, kerbs, temple, smithy, harbour way (%d checks)"):format(checks))
