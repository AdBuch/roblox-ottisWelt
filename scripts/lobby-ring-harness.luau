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
local L=modules.ColosseumLayout
local A=modules.Arena
local FLOOR=L.FloorTop
check(#layout.pads==5,"co-op group in Otti's yard, co-op group and team in the Schili and Kroko halls")
check(#layout.tribuneDoors==3,"three live entrances")
check(#layout.trainingSlots==6,"six training dummies")
check(#layout.modeBoards==4,"all modes in every hall and the team selector")
check(#layout.archiveSlots==6 and #layout.archivePlaques==6,"six cages in the zombie archive")
check(#layout.arenaTriggers==3 and #layout.bossBoards==3,"walk-in arena gate and boss entrance for every hall")
for _,trigger in layout.arenaTriggers do check(trigger.CanCollide==false and trigger.CanTouch~=false and trigger.Transparency==1,"invisible walk-in trigger at the gate") end
check(layout.arenaGate==layout.arenaTriggers[1] and #layout.introTargets==5,"start hall gate and one target per intro stage")
local function under(p,ancestorName)
    local a=p.Parent
    while a do if a.Name==ancestorName then return true end a=a.Parent end
    return false
end
-- Otti's hall is the old lobby's start: groups gather in the yard and the two smaller halls
for _,pad in layout.pads do
    check(not under(pad.ring,"OttiHeroLobby"),"Otti's hall stays free of group pads: "..pad.def.Id)
    if pad.def.Id=="ZombieCoop" then check(under(pad.ring,"TrainingYard"),"Otti co-op group in the training yard") end
end
local stages={}
for _,p in all do if not p.dead and p.attrs and p.attrs.IntroStage then stages[p.attrs.IntroStage]=(stages[p.attrs.IntroStage] or 0)+1; check(p.CanCollide==false,"only decoration is hidden by the intro") end end
for stage=1,4 do check((stages[stage] or 0)>0,"start hall reveals something at intro stage "..stage) end
local byName={}
for _,p in all do byName[p.Name or ""]=true end
for _,id in {"Otti","Schili","Kroko"} do check(byName[id.."Statue"],"statue "..id) end
for _,name in {"TrainingZombie1","PrisonerCell","HypogeumMaze"} do check(not byName[name],"no "..name.." any more") end
for _,cf in layout.trainingSlots do
    check(modules.LobbyService.isInside(cf.Position+vector(0,3,0)),"training safety zone")
    local o=layout.trainingCFrame:PointToObjectSpace(cf.Position+vector(0,3,0))
    check(math.abs(o.X)<=layout.trainingSize.X/2 and math.abs(o.Y)<=layout.trainingSize.Y/2 and math.abs(o.Z)<=layout.trainingSize.Z/2,"dummy inside the training area")
end
check(not modules.LobbyService.isInArmory(layout.arrivalSpawn.Position+vector(0,3,0)),"no purchases outside shops")
for name,cf in layout.shopFrames do check(modules.LobbyService.isInArmory(cf.Position+vector(0,3,0)),"shop region "..name) end
-- The lobbies are built INTO the Colosseum: every lobby part stands on the hall floor inside the
-- facade, and no lobby part cuts into the Colosseum's own structure (stands, piers, stair houses,
-- vomitoria, galleries, facade, gates). Colliding fittings may only touch it; decoration may
-- graze it by half a stud at most (the gate approach signs are older and keep their place).
local facade=L.facadeEnd()
local galleryEnd=A.Layout.SeatsEnd+L.GalleryWidth
local function axes(p) local r=p.CFrame.r; return {vector(r[1],r[4],r[7]),vector(r[2],r[5],r[8]),vector(r[3],r[6],r[9])} end
local function halfOf(p) return {p.Size.X/2,p.Size.Y/2,p.Size.Z/2} end
local function extent(p)
    local r,s=p.CFrame.r,p.Size
    return vector((math.abs(r[1])*s.X+math.abs(r[2])*s.Y+math.abs(r[3])*s.Z)/2,(math.abs(r[4])*s.X+math.abs(r[5])*s.Y+math.abs(r[6])*s.Z)/2,(math.abs(r[7])*s.X+math.abs(r[8])*s.Y+math.abs(r[9])*s.Z)/2)
end
-- Separating-axis test of two boxes; true when they overlap deeper than `tolerance`.
local function penetrates(a,b,tolerance)
    local aa,ba,ha,hb=axes(a),axes(b),halfOf(a),halfOf(b)
    local d=b.CFrame.Position-a.CFrame.Position
    local list={aa[1],aa[2],aa[3],ba[1],ba[2],ba[3]}
    for i=1,3 do for j=1,3 do local c=aa[i]:Cross(ba[j]); if c.Magnitude>1e-4 then table.insert(list,c.Unit) end end end
    for _,l in list do
        local ra=math.abs(l:Dot(aa[1]))*ha[1]+math.abs(l:Dot(aa[2]))*ha[2]+math.abs(l:Dot(aa[3]))*ha[3]
        local rb=math.abs(l:Dot(ba[1]))*hb[1]+math.abs(l:Dot(ba[2]))*hb[2]+math.abs(l:Dot(ba[3]))*hb[3]
        if math.abs(l:Dot(d))>ra+rb-tolerance then return false end
    end
    return true
end
local arenaSolids,grid={}, {}
local GRID=16
local function cells(c,e,fn)
    for gx=math.floor((c.X-e.X)/GRID),math.floor((c.X+e.X)/GRID) do
        for gz=math.floor((c.Z-e.Z)/GRID),math.floor((c.Z+e.Z)/GRID) do fn(gx..":"..gz) end
    end
end
for _,p in all do
    if not p.dead and p.ClassName=="Part" and p.CanCollide~=false and p.CFrame and p.Size and under(p,"GeneratedArena") and p.Parent and p.Parent.Name~="Ground" then
        table.insert(arenaSolids,p)
        local e=extent(p)
        cells(p.CFrame.Position,e,function(key) grid[key]=grid[key] or {}; table.insert(grid[key],p) end)
    end
end
local lobbyParts,clashes=0,{}
for _,p in all do
    if not p.dead and (p.ClassName=="Part" or p.ClassName=="SpawnLocation") and p.CFrame and p.Size and under(p,"GeneratedLobby") then
        lobbyParts+=1
        local e=extent(p)
        local c=p.CFrame.Position
        check(c.Y-e.Y>=FLOOR-2.05,"lobby at the arena's height: "..p.Name.." reaches down to "..(c.Y-e.Y))
        check(A.isInside(c,galleryEnd),"lobby inside the Colosseum's facade: "..p.Name)
        local approach=p.Parent and p.Parent.Name and p.Parent.Name:match("ArenaApproach$")
        if not approach and p.Transparency~=1 then
            local tolerance=if p.CanCollide~=false then 0.05 else 0.5
            local seen={}
            cells(c,e,function(key)
                for _,s in grid[key] or {} do
                    if not seen[s] then
                        seen[s]=true
                        local se=extent(s)
                        local sc=s.CFrame.Position
                        if math.abs(sc.X-c.X)<se.X+e.X and math.abs(sc.Y-c.Y)<se.Y+e.Y and math.abs(sc.Z-c.Z)<se.Z+e.Z and penetrates(p,s,tolerance) then
                            table.insert(clashes,("%s (%s) cuts into %s at %.0f,%.0f,%.0f"):format(p.Name,p.Parent and p.Parent.Name or "?",s.Name,c.X,c.Y,c.Z))
                        end
                    end
                end
            end)
        end
    end
end
do -- the detector itself: a box inside a pier clashes, one beside it does not
    local pier
    for _,s in arenaSolids do if s.Name=="Pier" and s.Size.Y<20 then pier=s; break end end
    check(pier and penetrates({CFrame=pier.CFrame,Size=vector(1,1,1)},pier,0.05),"clash detector finds a box inside a pier")
    check(pier and not penetrates({CFrame=pier.CFrame*CFrame.new(4,0,0),Size=vector(1,1,1)},pier,0.05),"clash detector ignores a box beside a pier")
end
for i,line in clashes do if i<=25 then print("CLASH "..line) end end
check(#clashes==0,#clashes.." lobby parts cut into the Colosseum's structure")
print(("lobby fittings: %d parts checked against %d Colosseum colliders"):format(lobbyParts,#arenaSolids))
-- Steeper stands: about 34 degrees below, over 40 above the praecinctio
for k=1,L.SeatTiers do
    local slope=(L.tierTop(k)-L.tierTop(k-1))/L.tierDepth(k)
    check(slope>=(if k<=4 then 0.65 else 0.85),"steep tier "..k)
end
check(L.tierTop(2)==FLOOR+A.Layout.Storey and math.abs(L.tierTop(5)-(FLOOR+2*A.Layout.Storey))<1e-6,"tiers 2 and 5 level with the ambulatories of storeys 2 and 3")
check(A.Layout.GalleryTop==L.tierTop(8),"top gallery level with the top tier")
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
        for i=-1,1 do
            local point=part.CFrame*vector(0,1,i*part.Size.Z/4)
            check(modules.LobbyService.isInside(point+vector(0,3,0)),"passage safety zone")
            clearHead(point,"shop street passage "..point.X..","..point.Z)
        end
    end
end
-- Existing spectator spawns stand on solid walkways.
for seed=0,11 do
    local foot=A.getTribuneCFrame(seed).Position-vector(0,3,0)
    local supported=false
    for _,part in all do
        if not part.dead and part.ClassName=="Part" and part.CanCollide~=false and part.CFrame and part.Size then
            local o=part.CFrame:PointToObjectSpace(foot)
            if math.abs(o.X)<part.Size.X/2 and math.abs(o.Z)<part.Size.Z/2 and math.abs(o.Y-part.Size.Y/2)<0.3 then supported=true; break end
        end
    end
    check(supported,"spectator walkway support at spawn "..seed)
end
-- Stair houses: two flights per storey, all with headroom
check(#A.Layout.StairFlights==4*3*2,"four stair houses, two flights per storey")
for _,flight in A.Layout.StairFlights do
    for i=1,flight.count do
        local foot=flight.cf*vector(0,i*flight.rise/flight.count,(i-0.5)*flight.run/flight.count)
        clearHead(foot,"stair house step "..i.." at "..math.floor(foot.X)..","..math.floor(foot.Y)..","..math.floor(foot.Z))
        tested+=1
    end
end
-- Shop displays (EquipmentShopService spreads them along each line, at most `max` apart): every
-- display, a rack 4 wide, 14 high and 3 deep standing behind its slot, fits between the piers
-- under the stands, and every slot lies in its shop's purchase zone.
local armory=layout.armory
for name,spec in {blades={armory.blades,3,10},heavy={armory.heavy,4,12},ranged={armory.ranged,1,11},light={armory.shields.Light,3,7.5},balanced={armory.shields.Balanced,2,7.5},heavyShields={armory.shields.Heavy,3,7.5},armor={armory.armor,4,9}} do
    local line,count,max=spec[1],spec[2],spec[3]
    local spacing=math.min(max,line.length/count)
    check(spacing>=4.2,"shop line "..name.." leaves room for every display ("..spacing..")")
    for i=1,count do
        local slot=line.cframe*CFrame.new((i-(count+1)/2)*spacing,0,0)
        check(modules.LobbyService.isInArmory(slot.Position+vector(0,3,0)),"display "..name.." "..i.." inside its shop")
        local box={CFrame=slot*CFrame.new(0,7.05,1.5),Size=vector(4,14,3)}
        local e=extent(box)
        local c=box.CFrame.Position
        cells(c,e,function(key)
            for _,s in grid[key] or {} do
                check(not penetrates(box,s,0.05),"display "..name.." "..i.." cuts into "..s.Name)
            end
        end)
    end
end
-- Start pedestals stand beside the walk-on pad, never on the mosaic.
for _,pad in layout.pads do
    for _,button in pad.buttons do
        local o=pad.cframe:PointToObjectSpace(button.part.Position)
        check(math.abs(o.Z)>pad.size.Z/2+1 and math.abs(o.X)<=pad.size.X/2,"pedestal beside pad "..pad.def.Id)
    end
end
-- Signs are read from where players stand: their text side (-Z) points at that spot.
local function facing(host,from) local front=host.CFrame*vector(0,0,-1)-host.Position; local to=from-host.Position; return front.X*to.X+front.Z*to.Z>0 end
local mainHall=layout.hallFrames.Otti.Position
for _,entry in layout.matchActions do
    check(facing(entry.part,mainHall),"team queue sign faces Otti's hall")
    check(entry.part.Size.X<=6,"queue signs fit side by side")
end
for _,pad in layout.pads do
    for _,p in all do
        if not p.dead and p.Name=="PadBoard" and p.Parent and p.Parent.Name=="Pad_"..pad.def.Id then check(facing(p,pad.cframe.Position),"pad board faces its pad "..pad.def.Id) end
    end
end
check(#layout.liveBoards==3,"live count in every hall")
local count={}
for _,p in all do if not p.dead and p.Name then count[p.Name]=(count[p.Name] or 0)+1 end end
check(count.Tier8==1 and count.Tier9==nil,"eight seating tiers")
check(count.Statue==2*L.FacadeArches,"a statue in every arch of storeys 2 and 3")
check(count.StairHouse==4,"four stair houses")
check((count.GalleryStair or 0)==0,"no stairs in the ambulatories")
check((count.Pier or 0)>=40,"piers carry the open substructure")
-- Every vomitorium: a level floor from its ambulatory to its terrace, nothing solid at head height
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
local vomitoria=A.Layout.Vomitoria
check(#vomitoria==8,"a vomitorium per upper ambulatory and quarter")
local seatsEnd=A.Layout.SeatsEnd
for _,v in vomitoria do
    check(v.from==v.to,"vomitorium level with its ambulatory")
    for o=v.exit+1,seatsEnd+3,2 do
        local p=L.point(v.theta,o)
        local floor=probe(p.X,p.Z,v.to+0.01)
        check(math.abs(floor-v.to)<0.01,"vomitorium floor at offset "..o)
        local _,blocked=probe(p.X,p.Z,floor)
        check(blocked==nil,"vomitorium headroom at offset "..o.." blocked by "..tostring(blocked))
    end
end
-- From every lobby straight to its gate: level paving and free headroom along the hero axis
for _,angle in L.HeroAngles do
    for o=6,facade+8,2 do
        local p=L.point(math.rad(angle),o)
        local floor=probe(p.X,p.Z,FLOOR+0.01)
        check(floor>=FLOOR-0.06,"floor on the way to the "..angle.." gate at offset "..o.." is "..floor)
        local _,blocked=probe(p.X,p.Z,floor)
        check(blocked==nil,"open way to the "..angle.." gate at offset "..o.." blocked by "..tostring(blocked))
    end
end
for _,p in all do
    if not p.dead and p.Name=="GroundExit" then check(p.CanCollide==false,"Hub opens the ground arches to the grounds") end
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
local steps={}
local queue={}
local voids,drops={},{}
local function visit(key,k,d)
    local id=key*64+k
    if not reached[id] then reached[id]=true; steps[id]=d or 0; table.insert(queue,{key,k}) end
end
local function seed(position)
    local i,j=cellOf(position.X,position.Z)
    local c=columns[i*N+j]
    for k=#(c or {}),1,-1 do
        if c[k][2]<=position.Y+1 and above(c,k)-c[k][2]>=BODY then visit(i*N+j,k,0); return true end
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
                    visit(nkey,best,steps[key*64+k]+1)
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
-- From the hall spawn alone: every room of the three lobbies, the gates, the grounds, every
-- ambulatory, each stair house up to the top tier and both vomitorium terraces
check(seed(layout.arrivalSpawn.Position+vector(0,0.5,0)),"walkable floor at the hall spawn")
walk()
-- The walk from the arrival spawn to the walk-in trigger at Otti's gate (grid steps of CELL)
local function stepsTo(position,half)
    local best=math.huge
    for x=position.X-half.X,position.X+half.X,CELL/2 do
        for z=position.Z-half.Z,position.Z+half.Z,CELL/2 do
            local i,j=cellOf(x,z)
            local c=columns[i*N+j]
            for k=1,#(c or {}) do local id=(i*N+j)*64+k; if reached[id] and math.abs(c[k][2]-FLOOR)<0.6 then best=math.min(best,steps[id]) end end
        end
    end
    return best*CELL
end
local gate=layout.arenaTriggers[1]
local gateWalk=stepsTo(gate.Position,vector(gate.Size.X/2-1,0,gate.Size.Z/2))
local straight=(vector(gate.Position.X,0,gate.Position.Z)-vector(layout.arrivalSpawn.Position.X,0,layout.arrivalSpawn.Position.Z)).Magnitude-gate.Size.Z/2
print(("arrival spawn -> Otti gate trigger: %.1f studs walked on the grid, %.1f straight (%.1f s at walk speed 16)"):format(gateWalk,straight,straight/16))
check(gateWalk<=70,"the arena start is a short walk from the arrival spawn")
for _,spawn in {layout.arrivalSpawn,layout.respawnSpawn} do
    local o=gate.CFrame:PointToObjectSpace(spawn.Position)
    check(not (math.abs(o.X)<=gate.Size.X/2+3 and math.abs(o.Z)<=gate.Size.Z/2+3),"spawn stays clear of the gate trigger")
    local floor,blocked=probe(spawn.Position.X,spawn.Position.Z,FLOOR+0.01)
    check(math.abs(floor-FLOOR)<0.1 and blocked==nil,"spawn on the floor with headroom: "..spawn.Name)
end
for _,pad in layout.pads do
    for _,o in {vector(0,0,0),vector(9,0,5),vector(-9,0,-5),vector(9,0,-5),vector(-9,0,5)} do
        local p=pad.cframe*o
        local floor,blocked=probe(p.X,p.Z,FLOOR+0.5)
        check(math.abs(floor-FLOOR)<0.3 and blocked==nil,"pad "..pad.def.Id.." on the floor with headroom ("..tostring(blocked)..")")
    end
end
local targets={cityExit=layout.cityExit.Position+vector(0,FLOOR-layout.cityExit.Position.Y-0.05,0),grounds=vector(330,0.95,330),topGallery=L.point(math.rad(90),seatsEnd+7)+vector(0,A.Layout.GalleryTop,0),trainingYard=layout.trainingCFrame.Position-vector(0,8,0)}
for name,cf in layout.shopFrames do targets["shop "..name]=cf.Position end
for id,cf in layout.hallFrames do targets["hall "..id]=cf.Position end
for i,trigger in layout.arenaTriggers do targets["gate "..i]=trigger.Position-vector(0,4,0) end
for level=1,2 do targets["ambulatory "..level]=L.point(math.rad(0),seatsEnd+7)+vector(0,FLOOR+level*A.Layout.Storey,0) end
for _,v in vomitoria do targets["vomitorium exit "..math.floor(math.deg(v.theta))]=L.point(v.theta,v.exit-2)+vector(0,v.to,0) end
for i,flight in A.Layout.StairFlights do targets["stair house flight "..i]=flight.cf*vector(0,(flight.count//2)*flight.rise/flight.count,(flight.count//2-0.5)*flight.run/flight.count) end
for label,position in targets do
    check(reachedAt(position,if label:match("^stair") then 1.6 else nil),"from the hall spawn a player reaches the "..label)
end
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
print("PASS: actual Arena and Lobby builders, three hero lobbies at the arena's height, shop street, training yard, five group pads, steep stands on an open substructure, four stair houses, eight level vomitoria, open ways to the gates and no gap to fall through; "..tested.." stair positions checked ("..checks.." checks)")
