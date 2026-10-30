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
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
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
check(#layout.pads==5,"co-op and team bays at Schili / Kroko, the co-op group at the meeting point")
check(#layout.tribuneDoors==3,"three live entrances")
check(#layout.trainingSlots==6,"six training cages")
check(#layout.modeBoards==5,"all modes, team selector and meeting point")
check(#layout.archiveSlots==6,"six separate prisoner cells")
check(#layout.arenaTriggers==3 and #layout.bossBoards==3,"walk-in arena gate and boss entrance in every hall")
for _,trigger in layout.arenaTriggers do check(trigger.CanCollide==false and trigger.CanTouch~=false and trigger.Transparency==1,"invisible walk-in trigger at the gate") end
check(layout.arenaGate==layout.arenaTriggers[1] and #layout.introTargets==5,"start hall gate and one target per intro stage")
-- Otti's hall is the old lobby's start: no group bays or queues, a gentle ramp to the gate
local function under(p,ancestorName)
    local a=p.Parent
    while a do if a.Name==ancestorName then return true end a=a.Parent end
    return false
end
for _,pad in layout.pads do check(pad.def.Id~="ZombieCoop" or pad.cframe.Position.Y<-50,"Otti co-op group moved to the meeting point") end
for _,p in all do
    if not p.dead and (p.Name=="BayBack" or p.Name=="PadCarpet" or p.Name=="TeamQueueEntrance") then check(not under(p,"OttiArenaApproach"),"start corridor stays free of "..p.Name) end
end
local stages={}
for _,p in all do if not p.dead and p.attrs and p.attrs.IntroStage then stages[p.attrs.IntroStage]=(stages[p.attrs.IntroStage] or 0)+1; check(p.CanCollide==false,"only decoration is hidden by the intro") end end
for stage=1,4 do check((stages[stage] or 0)>0,"start hall reveals something at intro stage "..stage) end
local ottiRamp=false
for _,route in layout.stairRoutes do if route.run>=50 and route.rise==modules.ColosseumLayout.FloorTop-modules.ColosseumLayout.LobbyFloor and modules.Arena.isInside(route.cf*vector(0,route.rise,route.run),10) then ottiRamp=true; check(route.rise/route.run<=0.55 and route.rise/route.count<=0.55,"gentle start ramp") end end
check(ottiRamp,"long ramp in Otti's approach")
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
check(#queue==layout.mazeCellCount and layout.mazeCellCount<(layout.mazeHalf*2+1)^2,"all hypogeum cells under the Colosseum connect to meeting point")
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
-- Shop racks stay on the solid walls: the doors at local x = +-27 carry the ring through the aisle.
local shopFrame={Weapons=modules.ColosseumLayout.frame(math.rad(150),100,-20),Shields=modules.ColosseumLayout.frame(math.rad(30),100,-20),Armor=modules.ColosseumLayout.frame(math.rad(270),100,-20)}
local armory=layout.armory
for name,line in {blades=armory.blades,heavy=armory.heavy,ranged=armory.ranged,light=armory.shields.Light,balanced=armory.shields.Balanced,heavyShields=armory.shields.Heavy,armor=armory.armor} do
    local frame=if name=="armor" then shopFrame.Armor elseif name=="light" or name=="balanced" or name=="heavyShields" then shopFrame.Shields else shopFrame.Weapons
    for _,x in {-line.length/2,0,line.length/2} do
        local o=frame:PointToObjectSpace(line.cframe*vector(x,0,0))
        check(math.abs(o.Z)>=10 and math.abs(o.X)<=24,"shop display "..name.." keeps the door aisle free")
    end
end
-- Start pedestals stand beside the walk-on pad, never on the mosaic, and leave the corridor free.
for _,pad in layout.pads do
    for _,button in pad.buttons do
        local o=pad.cframe:PointToObjectSpace(button.part.Position)
        check(math.abs(o.Z)>pad.size.Z/2+1 and math.abs(o.X)<=pad.size.X/2,"pedestal beside pad "..pad.def.Id)
    end
end
-- Signs are read from where players arrive: their text side (-Z) points at that spot.
local function facing(host,from) local front=host.CFrame*vector(0,0,-1)-host.Position; local to=from-host.Position; return front.X*to.X+front.Z*to.Z>0 end
for _,entry in layout.matchActions do
    check(facing(entry.part,vector(0,-52,0)),"team queue sign faces the meeting room")
    check(entry.part.Size.X<=6,"queue signs fit side by side")
end
for _,p in all do
    if not p.dead and p.Name=="TrainingEntrance" then check(facing(p,vector(0,-52,0)),"training sign faces the meeting point") end
end
check(#layout.liveBoards==3,"live count in every hall")
-- The enlarged Colosseum: eight tiers, a statue in every upper arch, stairs to every gallery level
local count={}
for _,p in all do if not p.dead and p.Name then count[p.Name]=(count[p.Name] or 0)+1 end end
check(count.Tier8==1 and count.Tier9==nil,"eight seating tiers")
check(count.Statue==2*modules.ColosseumLayout.FacadeArches,"a statue in every arch of storeys 2 and 3")
check(count.GalleryStair==12,"four stair sets of three flights up to the top gallery")
check(modules.Arena.Layout.GalleryTop==modules.ColosseumLayout.tierTop(8),"top gallery level with the top tier")
-- Every gallery level leads onto the stands: along each vomitorium there is a floor between
-- its two levels, nothing solid at head height, and no step higher than one stud.
local solids={}
for _,part in all do
    if not part.dead and part.ClassName=="Part" and part.CanCollide~=false and part.CFrame and part.Size and part.Shape~=Enum.PartType.Cylinder then table.insert(solids,part) end
end
local function probe(x,z,below)
    local floor,blocked=-math.huge,nil
    for _,part in solids do
        local o=part.CFrame:PointToObjectSpace(vector(x,part.CFrame.Position.Y,z))
        if math.abs(o.X)<part.Size.X/2 and math.abs(o.Z)<part.Size.Z/2 then
            local top,bottom=part.CFrame.Position.Y+part.Size.Y/2,part.CFrame.Position.Y-part.Size.Y/2
            if top<=below and top>floor then floor=top end
            if bottom<below+5.5 and top>below+0.3 then blocked=part.Name end
        end
    end
    return floor,blocked
end
local vomitoria=modules.Arena.Layout.Vomitoria
check(#vomitoria==12,"a vomitorium per gallery level and quarter")
local seatsEnd=modules.Arena.Layout.SeatsEnd
for _,v in vomitoria do
    local last=nil
    local samples={}
    for o=v.exit+1,seatsEnd-1,2 do table.insert(samples,o) end
    if v.from>modules.Arena.Layout.FloorTop then table.insert(samples,seatsEnd+3.5) end
    for _,o in samples do
        local p=modules.ColosseumLayout.point(v.theta,o)
        local floor=probe(p.X,p.Z,math.max(v.from,v.to)+0.01)
        check(floor>=math.min(v.from,v.to)-0.01,"vomitorium floor at offset "..o)
        local _,blocked=probe(p.X,p.Z,floor)
        check(blocked==nil,"vomitorium headroom at offset "..o.." blocked by "..tostring(blocked))
        if last and o<=seatsEnd then check(math.abs(floor-last)<=1.05,"vomitorium step height") end
        last=floor
    end
end
check((count.GalleryRail or 0)>100 and (count.StairGuard or 0)>200,"railings along the balconies, the stairwell and the stairs")
for _,p in all do
    if not p.dead and p.Name=="GroundExit" then check(p.CanCollide==false,"Hub opens the ground arches to the grounds") end
end
-- The basement stays underground: nothing of halls, shops, ring or hypogeum shows above the
-- ground, except the gate tunnels inside the stands and the six stairways out onto the grounds.
local exitModels=0
for _,p in all do if not p.dead and p.ClassName=="Model" and p.Name and p.Name:match("Exit$") then exitModels+=1 end end
check(exitModels==6,"an exit behind every hall and three from the hypogeum")
local function inExit(p)
    local a=p.Parent
    while a do if a.Name and a.Name:match("Exit$") then return true end a=a.Parent end
    return false
end
for _,p in all do
    if not p.dead and p.ClassName=="Part" and p.CFrame and p.Size and under(p,"GeneratedLobby") and not inExit(p) then
        local top=p.CFrame.Position.Y+p.Size.Y/2
        local q=p.CFrame.Position
        if top>0.05 then check((q.X/(70+34))^2+(q.Z/(55+34))^2<=1,"underground basement: "..p.Name.." pokes above the ground at "..math.floor(q.X)..","..math.floor(q.Z)) end
    end
end
for key in layout.mazeCells do
    local x,z=key:match("(-?%d+):(-?%d+)")
    local px,pz=tonumber(x)*layout.mazeCellSize,tonumber(z)*layout.mazeCellSize
    check(modules.Arena.isInside(vector(px,1,pz),modules.ColosseumLayout.facadeEnd()+40),"hypogeum cell under the Colosseum "..key)
end
-- Gaps: a player (5 studs tall, climbing or jumping up to 6) walks from every spawn over the top
-- surfaces of all solid parts, sampled in columns. A step into a column without any floor below
-- falls into the void; long drops are listed. Parts are widened by half a column so thin rails
-- and walls stay closed between the samples.
local CELL,WIDEN,BODY,CLIMB,DROP=1.5,0.75,5,6.2,12
local HALF=360
local N=math.floor(2*HALF/CELL)
local columns={}
local function cellOf(x,z) return math.floor((x+HALF)/CELL),math.floor((z+HALF)/CELL) end
for _,part in all do
    if not part.dead and (part.ClassName=="Part" or part.ClassName=="SpawnLocation") and part.CanCollide~=false and part.CFrame and part.Size then
        local r,p,s=part.CFrame.r,part.CFrame.Position,part.Size
        local h={s.X/2,s.Y/2,s.Z/2}
        local disc=part.Shape==Enum.PartType.Cylinder and math.abs(r[4])>0.99
        for k=1,3 do if math.abs(r[3+k])<0.7 then h[k]+=WIDEN end end
        local ex=math.abs(r[1])*h[1]+math.abs(r[2])*h[2]+math.abs(r[3])*h[3]
        local ey=math.abs(r[4])*h[1]+math.abs(r[5])*h[2]+math.abs(r[6])*h[3]
        local ez=math.abs(r[7])*h[1]+math.abs(r[8])*h[2]+math.abs(r[9])*h[3]
        local i0,j0=cellOf(p.X-ex,p.Z-ez)
        local i1,j1=cellOf(p.X+ex,p.Z+ez)
        for i=math.max(i0,0),math.min(i1,N-1) do
            local x=-HALF+(i+0.5)*CELL
            for j=math.max(j0,0),math.min(j1,N-1) do
                local z=-HALF+(j+0.5)*CELL
                local lo,hi=-math.huge,math.huge
                if disc then
                    local radius=math.min(s.Y,s.Z)/2+WIDEN
                    if (x-p.X)^2+(z-p.Z)^2<=radius*radius then lo,hi=p.Y-ey,p.Y+ey end
                else
                    local dx,dy,dz=x-p.X,-p.Y,z-p.Z
                    for k=1,3 do
                        local a=r[k]*dx+r[3+k]*dy+r[6+k]*dz
                        local b=r[3+k]
                        if math.abs(b)<1e-6 then
                            if math.abs(a)>h[k] then lo=math.huge; break end
                        else
                            local t1,t2=(-h[k]-a)/b,(h[k]-a)/b
                            if t1>t2 then t1,t2=t2,t1 end
                            lo,hi=math.max(lo,t1),math.min(hi,t2)
                        end
                    end
                end
                if lo<hi then
                    local key=i*N+j
                    local c=columns[key]
                    if not c then c={}; columns[key]=c end
                    table.insert(c,{lo,hi})
                end
            end
        end
    end
end
-- Merge every column into disjoint solid intervals, bottom to top
for key,c in columns do
    table.sort(c,function(a,b) return a[1]<b[1] end)
    local merged={}
    for _,iv in c do
        local last=merged[#merged]
        if last and iv[1]<=last[2]+0.05 then last[2]=math.max(last[2],iv[2]) else table.insert(merged,{iv[1],iv[2]}) end
    end
    columns[key]=merged
end
local function above(c,k) local next=c and c[k+1]; return if next then next[1] else math.huge end
local reached={}
local queue={}
local voids,drops={},{}
local function visit(key,k)
    local id=key*64+k
    if not reached[id] then reached[id]=true; table.insert(queue,{key,k}) end
end
local function seed(position)
    local i,j=cellOf(position.X,position.Z)
    local c=columns[i*N+j]
    for k=#(c or {}),1,-1 do
        if c[k][2]<=position.Y+1 and above(c,k)-c[k][2]>=BODY then visit(i*N+j,k); return true end
    end
    return false
end
local head=1
local function walk()
while head<=#queue do
    local key,k=queue[head][1],queue[head][2]; head+=1
    local i,j=key//N,key%N
    local c=columns[key]
    local top,room=c[k][2],above(c,k)
    for _,d in {{1,0},{-1,0},{0,1},{0,-1}} do
        local ni,nj=i+d[1],j+d[2]
        if ni>=0 and nj>=0 and ni<N and nj<N then
            local nkey=ni*N+nj
            local n=columns[nkey]
            local best=nil
            for m=#(n or {}),1,-1 do if n[m][2]<=top+CLIMB then best=m; break end end
            if best then
                local land=n[best][2]
                if above(n,best)>=math.max(land,top)+BODY and room>=math.max(land,top)+BODY then
                    if top-land>DROP then table.insert(drops,{x=-HALF+(ni+0.5)*CELL,z=-HALF+(nj+0.5)*CELL,from=top,to=land}) end
                    visit(nkey,best)
                end
            elseif (if n then n[1][1] else math.huge)>=top+BODY then
                table.insert(voids,{x=-HALF+(ni+0.5)*CELL,z=-HALF+(nj+0.5)*CELL,y=top})
            end
        end
    end
end
end
local function reachedAt(position,tolerance)
    local i,j=cellOf(position.X,position.Z)
    local c=columns[i*N+j]
    for k=1,#(c or {}) do if reached[(i*N+j)*64+k] and math.abs(c[k][2]-position.Y)<(tolerance or 0.6) then return true end end
    return false
end
-- From the hall spawn alone: out onto the grounds, into the galleries up to the top and down into
-- the hypogeum
check(seed(modules.ColosseumLayout.frame(math.rad(90),100,-28)*vector(0,0,12)),"walkable floor at the hall spawn")
walk()
for label,position in {grounds=vector(330,0.95,330),topGallery=modules.ColosseumLayout.point(math.rad(90),seatsEnd+10)+vector(0,modules.Arena.Layout.GalleryTop,0),hypogeum=vector(0,-60,10)} do
    check(reachedAt(position),"from the hall spawn a player reaches the "..label)
end
-- Every stairway out onto the grounds is walked: its middle step is reached from the hall spawn
local outside=0
for _,route in layout.stairRoutes do
    local top=route.cf*vector(0,route.rise,route.run)
    local flat=vector(top.X,modules.ColosseumLayout.FloorTop,top.Z)
    if math.abs(top.Y-modules.ColosseumLayout.FloorTop)<0.01 and not modules.Arena.isInside(flat,modules.ColosseumLayout.facadeEnd()) then
        outside+=1
        local i=route.count//2
        check(reachedAt(route.cf*vector(0,i*route.rise/route.count,(i-0.5)*route.run/route.count),1.6),"exit stairway walked at "..math.floor(top.X)..","..math.floor(top.Z))
    end
end
check(outside==6,"six stairways end outside the Colosseum")
-- Then from every spot of the fight place: sand, team spawns and tribunes
local seeds={modules.Arena.Layout.StartPosition,modules.Arena.getTeamSpawnCFrame("Red",1).Position,modules.Arena.getTeamSpawnCFrame("Blue",1).Position}
for seedIndex=0,11 do table.insert(seeds,modules.Arena.getTribuneCFrame(seedIndex).Position) end
for _,position in seeds do check(seed(position),"walkable floor at spawn "..math.floor(position.X)..","..math.floor(position.Z)) end
walk()
local function report(list,label)
    local groups,order={},{}
    for _,g in list do
        local id=math.floor(g.x/12)..":"..math.floor(g.z/12)..":"..math.floor((g.y or g.from)/6)
        if not groups[id] then groups[id]={n=0,g=g}; table.insert(order,id) end
        groups[id].n+=1
    end
    print(("%s: %d spots in %d places"):format(label,#list,#order))
    for index,id in order do
        if index>60 then break end
        local g=groups[id].g
        print(("  %4d,%4d  y %6.1f%s  (%d)"):format(math.floor(g.x),math.floor(g.z),g.y or g.from,if g.to then (" -> %6.1f"):format(g.to) else "",groups[id].n))
    end
end
local reachedCount=0
for _ in reached do reachedCount+=1 end
print(("gap walk: %d standing spots reached"):format(reachedCount))
report(voids,"falls into the void")
report(drops,"drops over "..DROP.." studs")
check(#voids==0,"no way to fall into the void")
check(#drops==0,"no drop of more than "..DROP.." studs")
local solid=modules.ColosseumGate.build(Workspace,CFrame.new(500,1,500),"Solid")
check(solid.Transparency==1 and solid.CanCollide~=false,"solid gate still blocks passage")
check(solid.Parent:FindFirstChild("TimberLeaves")~=nil,"opaque gate variant has timber leaves")
local grille=modules.ColosseumGate.build(Workspace,CFrame.new(600,1,500),"Grille")
check(grille.Parent:FindFirstChild("TimberLeaves")==nil and grille.Parent:FindFirstChild("IronBar")~=nil,"grille variant keeps the view open")
print("PASS: actual Arena and Lobby builders, three full hero halls and shops, five group bays, six prisoner cells, six training cages, twelve vomitoria, six exits to the grounds and no gap to fall through; "..tested.." stair positions checked ("..checks.." checks)")
