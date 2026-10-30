--!strict
-- Full-size vaulted hero halls, a sealed connecting ring and a navigable hypogeum.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Layout = require(ReplicatedStorage.Shared.ColosseumLayout)
local Config = require(ReplicatedStorage.Shared.Config)
local PadDefinitions = require(ReplicatedStorage.Shared.LobbyPadDefinitions)
local Statue = require(script.Parent.LobbyStatue)
local Mosaics = require(script.Parent.LobbyMosaics)
local Battles = require(script.Parent.ShopBattleMosaics)
local Arena = require(script.Parent.Arena)

local Architecture = {}
local FLOOR, LOWER = Layout.LobbyFloor, Layout.HypogeumFloor
local STONE = Color3.fromRGB(116, 103, 87)
local SANDSTONE = Color3.fromRGB(207, 182, 141)
local DARK = Color3.fromRGB(68, 56, 45)
local GOLD = Color3.fromRGB(224, 176, 70)
local IRON = Color3.fromRGB(62, 64, 61)
local WOOD = Color3.fromRGB(100, 65, 38)
local WHITE = Color3.fromRGB(245, 231, 202)
type Volume = { cf: CFrame, size: Vector3 }
local volumes: { Volume } = {}
local shops: { Volume } = {}
local routes: { { cf: CFrame, rise: number, run: number, count: number } } = {}
local function inside(v: Volume, p: Vector3): boolean
    local o = v.cf:PointToObjectSpace(p)
    return math.abs(o.X)<=v.size.X/2 and math.abs(o.Y)<=v.size.Y/2 and math.abs(o.Z)<=v.size.Z/2
end
local function zone(cf: CFrame, size: Vector3, shop: boolean?)
    local v = {cf=cf,size=size}
    table.insert(volumes,v)
    if shop then table.insert(shops,v) end
end
-- Intro: decoration built while this is set appears for a player only from that intro stage on
-- (LobbyIntroController hides it locally until then). Colliding parts are never hidden.
local revealStage: number? = nil
local function part(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, decor: boolean?): Part
    local p=Instance.new("Part")
    p.Name,p.Anchored,p.CFrame,p.Size=name,true,cf,size
    p.Color,p.Material=color,Enum.Material.Limestone
    p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    if decor then p.CanCollide,p.CanQuery,p.CanTouch,p.CastShadow=false,false,false,false end
    if decor and revealStage then p:SetAttribute("IntroStage",revealStage) end
    p.Parent=parent
    return p
end
local function model(parent: Instance, name: string): Model
    local m=Instance.new("Model"); m.Name=name; m.Parent=parent; return m
end
-- Text faces the board's -Z (Front). `size` resizes the board together with its accent strip.
local function sign(parent: Instance, name: string, cf: CFrame, title: string, subtitle: string, color: Color3?, size: Vector2?): (BasePart, TextLabel)
    local w,h=if size then size.X else 18,if size then size.Y else 4.5
    local host=part(parent,name,cf,Vector3.new(w,h,0.35),DARK,true)
    host.Material=Enum.Material.Wood
    if color then part(parent,"SignAccent",cf*CFrame.new(0,h/2-0.1,-0.2),Vector3.new(w,0.2,0.12),color,true) end
    local gui=Instance.new("SurfaceGui"); gui.Face=Enum.NormalId.Front; gui.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud; gui.PixelsPerStud=32; gui.MaxDistance=110; gui.Parent=host
    local label=Instance.new("TextLabel"); label.Size=UDim2.fromScale(0.94,0.5); label.Position=UDim2.fromScale(0.03,0.04); label.BackgroundTransparency=1; label.TextColor3=GOLD; label.Font=Enum.Font.Garamond; label.TextScaled=true; label.Text=title; label.Parent=gui
    local sub=Instance.new("TextLabel"); sub.Size=UDim2.fromScale(0.94,0.38); sub.Position=UDim2.fromScale(0.03,0.56); sub.BackgroundTransparency=1; sub.TextColor3=WHITE; sub.Font=Enum.Font.GothamBold; sub.TextScaled=true; sub.Text=subtitle; sub.Parent=gui
    if name=="MazeDirections" or name=="ExitWayfinding" or name=="HypogeumSign" then
        local back=Instance.new("SurfaceGui"); back.Face=Enum.NormalId.Back; back.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud; back.PixelsPerStud=32; back.MaxDistance=110; back.Parent=host
        for i,text in {title,subtitle} do
            local l=Instance.new("TextLabel"); l.Size=UDim2.fromScale(0.94,0.42); l.Position=UDim2.fromScale(0.03,0.04+(i-1)*0.5); l.BackgroundTransparency=1; l.TextColor3=if i==1 then GOLD else WHITE; l.Font=Enum.Font.Garamond; l.TextScaled=true; l.Text=text; l.Parent=back
        end
    end
    return host,sub
end
local function lamp(parent: Instance, cf: CFrame)
    local p=part(parent,"BrazierFlame",cf,Vector3.new(0.8,1.2,0.8),Color3.fromRGB(255,180,76),true)
    p.Material=Enum.Material.Neon
    part(parent,"BrazierBowl",cf*CFrame.new(0,-0.75,0),Vector3.new(1.8,0.5,1.8),GOLD,true).Material=Enum.Material.Metal
    part(parent,"BrazierBracket",cf*CFrame.new(0,-1.3,0),Vector3.new(0.45,0.8,0.45),IRON,true).Material=Enum.Material.Metal
    local light=Instance.new("PointLight"); light.Color=Color3.fromRGB(255,219,168); light.Range=24; light.Brightness=0.85; light.Parent=p
end
local function arch(parent: Instance, cf: CFrame, width: number, height: number)
    for _,x in {-width/2-1,width/2+1} do
        part(parent,"ArchPier",cf*CFrame.new(x,height/2,0),Vector3.new(2,height,3),SANDSTONE)
        part(parent,"PierBase",cf*CFrame.new(x,0.6,0),Vector3.new(3,1.2,4),GOLD,true)
    end
    part(parent,"ArchLintel",cf*CFrame.new(0,height+0.7,0),Vector3.new(width+4,1.4,3),SANDSTONE)
    for _,side in {-1,1} do
        part(parent,"VaultHaunch",cf*CFrame.new(side*(width/2-1),height-1.3,0)*CFrame.Angles(0,0,side*math.pi/4),Vector3.new(4,1.1,2),SANDSTONE,true)
    end
end
-- A wall along the local X axis, with a real central door opening.
local function doorway(parent: Instance, cf: CFrame, width: number, height: number, opening: number)
    local side=(width-opening)/2
    for _,s in {-1,1} do part(parent,"ChamberWall",cf*CFrame.new(s*(opening/2+side/2),height/2,0),Vector3.new(side,height,2),STONE) end
    part(parent,"DoorHeader",cf*CFrame.new(0,(height+16)/2,0),Vector3.new(opening,math.max(1,height-16),2),STONE)
    arch(parent,cf,opening,15)
end
local function passage(parent: Instance, a: Vector3, b: Vector3, width: number, omitWall: ((Vector3)->boolean)?)
    local cf=CFrame.lookAt((a+b)/2,b)
    local length=(b-a).Magnitude+1
    part(parent,"PassageFloor",cf*CFrame.new(0,-1,0),Vector3.new(width+2,2,length),STONE)
    part(parent,"PassageVault",cf*CFrame.new(0,19,0),Vector3.new(width+3,2,length),DARK)
    for _,s in {-1,1} do
        local wall=cf*CFrame.new(s*(width/2+1),9,0)
        if not omitWall or not omitWall(wall.Position) then part(parent,"PassageWall",wall,Vector3.new(2,18,length+0.2),STONE) end
    end
    zone(cf*CFrame.new(0,8,0),Vector3.new(width+3,24,length+1))
end
local function stairs(parent: Instance, cf: CFrame, rise: number, run: number, count: number, width: number)
    local m=model(parent,"DownStaircase")
    m:SetAttribute("Rise",rise); m:SetAttribute("Run",run)
    m:SetAttribute("StairBase",cf)
    for i=1,count do
        local h=rise*i/count
        part(m,"Stair",cf*CFrame.new(0,h/2,(i-0.5)*run/count),Vector3.new(width,h,run/count+0.05),SANDSTONE)
        for _,side in {-1,1} do
            part(m,"StairGuard",cf*CFrame.new(side*(width/2+0.5),h+2.1,(i-0.5)*run/count),Vector3.new(1,4.2,run/count+0.05),STONE)
        end
    end
    -- One invisible sloped wall over each row of guards, up to 8.5 above the steps: no jumping off
    local slope=math.atan2(rise,run)
    for _,side in {-1,1} do
        local g=part(m,"GuardExtension",cf*CFrame.new(side*(width/2+0.5),rise/2+6.35,run/2)*CFrame.Angles(-slope,0,0),Vector3.new(1,4.3*math.cos(slope),math.sqrt(rise*rise+run*run)),STONE)
        g.Transparency,g.CanQuery,g.CanTouch,g.CastShadow=1,false,false,false
    end
    zone(cf*CFrame.new(0,rise/2+4,run/2),Vector3.new(width+2,rise+14,run+4))
    table.insert(routes,{cf=cf,rise=rise,run=run,count=count})
end
-- A corridor along a polyline (points at floor level): per leg a floor and a vault, the walls
-- along the mitred side lines, so bends of any angle stay closed. Legs whose middle lies in
-- `omit` (the shops, which bring their own room) are left out.
local function corridor(parent: Instance, points: { Vector3 }, width: number, omit: ((Vector3)->boolean)?)
    local function left(i: number): Vector3 local d=(points[i+1]-points[i]).Unit; return Vector3.new(-d.Z,0,d.X) end
    local function side(i: number, e: number): (Vector3, number) -- mitred point e studs to the left, tan(half bend)
        if i==1 then return points[1]+left(1)*e,0 end
        if i==#points then return points[i]+left(i-1)*e,0 end
        local a,b=left(i-1),left(i)
        local m=(a+b).Unit
        local c=m:Dot(a)
        return points[i]+m*(e/c),math.sqrt(math.max(0,1-c*c))/c
    end
    for i=1,#points-1 do
        local a,b=points[i],points[i+1]
        local mid=(a+b)/2
        if not (omit and omit(mid)) then
            local cf=CFrame.lookAt(mid,b)
            local lo,hi=math.huge,-math.huge
            for _,e in {-(width/2+2),width/2+2} do
                for _,v in {i,i+1} do local z=cf:PointToObjectSpace((side(v,e))).Z; lo,hi=math.min(lo,z),math.max(hi,z) end
            end
            local centre=cf*CFrame.new(0,0,(lo+hi)/2)
            part(parent,"PassageFloor",centre*CFrame.new(0,-1,0),Vector3.new(width+4,2,hi-lo),STONE)
            part(parent,"PassageVault",centre*CFrame.new(0,19,0),Vector3.new(width+4,2,hi-lo),DARK)
            for _,e in {-(width/2+1),width/2+1} do
                -- each wall runs past its mitre point far enough to close the outer corner
                local p,tp=side(i,e)
                local q,tq=side(i+1,e)
                local d=(q-p).Unit
                p,q=p-d*(0.1+tp),q+d*(0.1+tq)
                part(parent,"PassageWall",CFrame.lookAt((p+q)/2,q)*CFrame.new(0,9,0),Vector3.new(2,18,(q-p).Magnitude),STONE)
            end
            if i%3==0 then lamp(parent,cf*CFrame.new(width/2-2,12,0)) end
            zone(centre*CFrame.new(0,8,0),Vector3.new(width+3,24,hi-lo+1))
        end
    end
end
-- A stairway from `foot` (its local +Z leads up and out) to the ground: walled and vaulted while
-- it runs below the ground, then an open stairwell between parapets up to a portal arch with a
-- sign towards the grounds. Returns the stairwell for Arena.cutGround.
local function descent(parent: Instance, name: string, foot: CFrame, run: number, width: number, title: string, subtitle: string, color: Color3): (CFrame, number, number, number)
    local m=model(parent,name)
    local base=foot.Position.Y
    local rise=Layout.FloorTop-base
    stairs(m,foot,rise,run,math.ceil(rise),width)
    local wall=width/2+1.5
    local open=0
    for d=0,run,4 do
        local y=base+rise*d/run
        local top=y+14
        if top+1<=0 then
            for _,s in {-1,1} do part(m,"TunnelWall",foot*CFrame.new(s*wall,(y+top)/2-base,d),Vector3.new(1,top-y,4.2),STONE) end
            part(m,"TunnelVault",foot*CFrame.new(0,top+0.5-base,d),Vector3.new(width+4,1,4.2),DARK)
            open=d+2.1
            if d%16==0 then lamp(m,foot*CFrame.new(width/2-0.5,top-2-base,d)) end
        else
            -- beside the open stairwell the walls stand as parapets above the ground
            local wallTop=Layout.FloorTop+3
            for _,s in {-1,1} do Arena.guardAbove(m,part(m,"TunnelWall",foot*CFrame.new(s*wall,(y+wallTop)/2-base,d),Vector3.new(1,wallTop-y,4.2),STONE),Layout.FloorTop) end
        end
    end
    Arena.guardAbove(m,part(m,"StairwellParapet",foot*CFrame.new(0,Layout.FloorTop+1.5-base,open-0.5),Vector3.new(width+4,3,1),STONE),Layout.FloorTop)
    local gate=foot*CFrame.new(0,rise,run)
    arch(m,gate,width,14)
    sign(m,name.."Sign",gate*CFrame.new(0,17.5,1.6)*CFrame.Angles(0,math.pi,0),title,subtitle,color,Vector2.new(width+6,3.5))
    return foot+Vector3.new(0,-base,0),wall+0.5,open,run
end
local function floorRect(parent: Instance, cf: CFrame, x0: number,x1: number,z0: number,z1: number)
    part(parent,"HallFloor",cf*CFrame.new((x0+x1)/2,-1,(z0+z1)/2),Vector3.new(x1-x0,2,z1-z0),STONE)
end
local function spawn(parent: Instance,name: string,cf: CFrame): SpawnLocation
    local p=Instance.new("SpawnLocation"); p.Name=name; p.Anchored=true; p.Neutral=true; p.Duration=0; p.Transparency=1; p.Size=Vector3.new(6,1,6); p.CFrame=cf*CFrame.new(0,-0.5,0); p.Parent=parent; return p
end

function Architecture.build(buildPad: any): any
    table.clear(volumes); table.clear(shops); table.clear(routes)
    local existing=Workspace:FindFirstChild(Config.LobbyFolderName); if existing then existing:Destroy() end
    -- Exactly the same builder, gates, sand, walls and spectator geometry as the fight place.
    Arena.build()
    Arena.setGroundExits(true) -- in the Hub the plaza, galleries and stands are part of the lobby
    local folder=Instance.new("Folder"); folder.Name=Config.LobbyFolderName
    local pads,menus,liveDoors,liveBoards,entries,matchActions={},{},{},{},{},{}
    local heroes={
        {id="Otti",name="OTTI",angle=90,color=Color3.fromRGB(140,38,37),motto="COURAGE · FRIENDSHIP · UNITY"},
        {id="Schili",name="SCHILIBITZLI · SCHILI",angle=330,color=Color3.fromRGB(52,111,112),motto="WISDOM · ENDURANCE · KINDNESS"},
        {id="Kroko",name="KROKERO · KROKO",angle=210,color=Color3.fromRGB(125,93,43),motto="COURAGE · ACTION · LOYALTY"},
    }
    local shopFrames={}
    for _,theta in {30,270,150} do table.insert(shopFrames,Layout.frame(math.rad(theta),100,FLOOR)) end
    local function inShop(p: Vector3): boolean
        for _,cf in shopFrames do local o=cf:PointToObjectSpace(p); if math.abs(o.X)<28 and math.abs(o.Z)<24 then return true end end
        return false
    end
    -- One closed corridor from each hall's side door to the next hall's: straight out of the door,
    -- along the ring and straight through the shop between them (door to door).
    local ring=model(folder,"EnclosedConcourse")
    for index,hero in heroes do
        local nextHero=heroes[index%#heroes+1]
        local from=Layout.frame(math.rad(hero.angle),100,FLOOR)
        local to=Layout.frame(math.rad(nextHero.angle),100,FLOOR)
        local points={(from*CFrame.new(42,0,0)).Position,(from*CFrame.new(50,0,0)).Position}
        local throughShop=false
        for k=0,15 do
            local p=Layout.frame(math.rad(hero.angle-30-4*k),100,FLOOR).Position
            local room=nil
            for _,cf in shopFrames do local o=cf:PointToObjectSpace(p); if math.abs(o.X)<40 and math.abs(o.Z)<30 then room=cf end end
            if not room then
                table.insert(points,p)
            elseif not throughShop then
                throughShop=true
                for _,x in {-36,-27,27,36} do table.insert(points,(room*CFrame.new(x,0,0)).Position) end
            end
        end
        table.insert(points,(to*CFrame.new(-50,0,0)).Position)
        table.insert(points,(to*CFrame.new(-42,0,0)).Position)
        corridor(ring,points,20,inShop)
    end
    local triggers,bossHosts={},{}
    local holes: { { any } }={} -- stairwells up to the ground, for Arena.cutGround
    local introTargets: { Vector3 }={}
    for _,hero in heroes do
        -- Otti's hall is the start: spawn, a free walk to the gate, nothing else in sight at first
        local isStart=hero.id=="Otti"
        local cf=Layout.frame(math.rad(hero.angle),100,FLOOR)
        local hall=model(folder,hero.id.."HeroLobby")
        hall:SetAttribute("Hero",hero.id)
        hall:SetAttribute("OriginalHallWidth",80); hall:SetAttribute("OriginalHallDepth",72)
        -- 80 x 72 original hall proportions, with two protected stair shafts at its sides.
        floorRect(hall,cf,-44,44,-40,-26)
        floorRect(hall,cf,-44,44,22,40)
        floorRect(hall,cf,-24,24,-26,22)
        floorRect(hall,cf,-44,-36,-26,22)
        floorRect(hall,cf,36,44,-26,22)
        part(hall,"HallVault",cf*CFrame.new(0,27,0),Vector3.new(88,2,80),DARK)
        doorway(hall,cf*CFrame.new(0,0,-38),88,26,20)
        -- The rear wall's door leads up a stairway out onto the grounds
        doorway(hall,cf*CFrame.new(0,0,39),88,26,14)
        table.insert(holes,{descent(hall,hero.id.."HallExit",cf*CFrame.new(0,0,40),54,12,hero.name,"Hall · shops · the arena",hero.color)})
        revealStage=if isStart then 1 else nil
        sign(hall,"HallExitSign",cf*CFrame.new(0,19.5,37.2),"EXIT","Up the stairs · out onto the grounds",hero.color,Vector2.new(14,3.5))
        revealStage=nil
        for _,side in {-1,1} do
            doorway(hall,cf*CFrame.new(side*43,0,0)*CFrame.Angles(0,math.pi/2,0),78,26,24)
            -- Descend at both original front-corner stair locations, protected along their edges.
            local lower=cf*CFrame.new(side*30,LOWER-FLOOR,22)*CFrame.Angles(0,math.pi,0)
            stairs(hall,lower,FLOOR-LOWER,48,32,10)
            part(hall,"StairLanding",cf*CFrame.new(side*30,LOWER-FLOOR-1,27),Vector3.new(12,2,10),SANDSTONE)
            table.insert(entries,(cf*CFrame.new(side*30,LOWER-FLOOR,29)).Position)
            for _,z in {-18,0,18} do
                Arena.guardAbove(hall,part(hall,"InnerStairParapet",cf*CFrame.new(side*24.5,2,z),Vector3.new(1,4,18),STONE),FLOOR)
                Arena.guardAbove(hall,part(hall,"OuterStairParapet",cf*CFrame.new(side*35.5,2,z),Vector3.new(1,4,18),STONE),FLOOR)
            end
            -- ...and across the shaft's rear end, where the stair is already far below
            Arena.guardAbove(hall,part(hall,"RearStairParapet",cf*CFrame.new(side*30,2,22.5),Vector3.new(12,4,1),STONE),FLOOR)
            revealStage=if isStart then 3 else nil
            sign(hall,"HypogeumSign",cf*CFrame.new(side*29,9,-30)*CFrame.Angles(0,math.pi,0),"DOWN · HYPOGEUM","Group fights · team battles · training",hero.color)
            revealStage=nil
        end
        zone(cf*CFrame.new(0,10,0),Vector3.new(90,32,82))
        for _,x in {-18,18} do
            for _,z in {-23,23} do
                part(hall,"VaultColumn",cf*CFrame.new(x,13,z),Vector3.new(3,26,3),SANDSTONE)
                part(hall,"ColumnCapital",cf*CFrame.new(x,24,z),Vector3.new(4.5,2,4.5),GOLD,true)
                lamp(hall,cf*CFrame.new(x,13,z))
            end
            part(hall,"VaultRib",cf*CFrame.new(x,24,0),Vector3.new(1.2,1.5,72),SANDSTONE,true)
        end
        -- Monument stands beside the approach, as it did in the original lobby.
        part(hall,"MonumentStep",cf*CFrame.new(-10,0.5,3),Vector3.new(14,1,14),SANDSTONE)
        part(hall,"MonumentPedestal",cf*CFrame.new(-10,3,3),Vector3.new(10,5,10),SANDSTONE)
        part(hall,"BronzePedestalCap",cf*CFrame.new(-10,5.7,3),Vector3.new(11,0.5,11),GOLD,true)
        Statue.build(hall,cf*CFrame.new(-10,6,3)*CFrame.Angles(0,math.pi,0),1.6,hero.id)
        sign(hall,"HeroInscription",cf*CFrame.new(-10,3,8.2)*CFrame.Angles(0,math.pi,0),hero.name,hero.motto,hero.color)
        Mosaics.build(hall,cf*CFrame.new(11,0.05,8),if hero.id=="Kroko" then "Krokero" else hero.id,1.0,SANDSTONE)
        for _,x in {-15,15} do
            part(hall,"Bench",cf*CFrame.new(x,1.1,33),Vector3.new(10,2.2,3),WOOD)
        end
        for _,x in {-29,29} do
            local flag=part(hall,"HeroBanner",cf*CFrame.new(x,17,37.7),Vector3.new(6,10,0.15),hero.color,true)
            flag.Material=Enum.Material.Fabric
            part(hall,"BannerGoldHem",cf*CFrame.new(x,13,37.5),Vector3.new(6,0.5,0.2),GOLD,true)
        end
        revealStage=if isStart then 4 else nil
        local menu=sign(hall,"AllModes",cf*CFrame.new(17,8,37),"PLAY · ALL MODES","Solo · Co-op · Teams · Boss · Watch",hero.color)
        table.insert(menus,menu)
        local boss=sign(hall,"BossSelection",cf*CFrame.new(-17,8,37),"BOSS FIGHT","Otti · Schili · Krokero",hero.color)
        table.insert(bossHosts,boss)
        -- The live count is this sign's subtitle (a separate board used to cover it in Otti's hall)
        local live,liveCount=sign(hall,"WatchLive",cf*CFrame.new(29,7,32),"LIVE BATTLES","No live battles",hero.color)
        table.insert(liveDoors,live); table.insert(liveBoards,liveCount)
        revealStage=nil
        if isStart then
            -- The old lobby's start: one sign over the way out, a gold strip on the floor to the ramp
            sign(hall,"ArenaSign",cf*CFrame.new(0,20.5,-36.6)*CFrame.Angles(0,math.pi,0),"THE ARENA","Walk through the gate · your fight starts there",GOLD,Vector2.new(22,4.5))
            part(hall,"ArenaGuide",cf*CFrame.new(0,0.03,-14.5),Vector3.new(1.2,0.06,53),GOLD,true).Material=Enum.Material.Neon
            -- Revealed one return at a time: the shops beside the hall, then the group halls
            for _,side in {-1,1} do
                local over=cf*CFrame.new(side*41.6,0,0)*CFrame.Angles(0,side*math.pi/2,0)
                revealStage=1
                sign(hall,"ShopDirection",over*CFrame.new(0,18.6,0),if side==1 then "SHIELD SHOP" else "WEAPON SHOP","Weapons · shields · armor for denarii",hero.color)
                revealStage=2
                sign(hall,"GroupDirection",over*CFrame.new(0,23,0),if side==1 then "SCHILI HALL" else "KROKO HALL","Co-op groups · team battles",hero.color)
                revealStage=nil
            end
        end

        local approach=model(folder,hero.id.."ArenaApproach")
        local entryFrame=Layout.frame(math.rad(hero.angle),0,FLOOR)
        -- Otti: a plain corridor and a long, gentle ramp. Schili / Kroko: the old cage bays are
        -- group chambers on both sides of the corridor, the ramp starts behind them.
        local rampStart=if isStart then 60 else 30
        passage(approach,(entryFrame*CFrame.new(0,0,64)).Position,(cf*CFrame.new(0,0,-38)).Position,20)
        if isStart then
            passage(approach,(entryFrame*CFrame.new(0,0,64)).Position,(entryFrame*CFrame.new(0,0,rampStart)).Position,20)
            sign(approach,"ArenaRampSign",entryFrame*CFrame.new(0,12,63)*CFrame.Angles(0,math.pi,0),"ZOMBIE ARENA","Up the ramp · through the gate",GOLD)
        else
            part(approach,"ApproachFloor",entryFrame*CFrame.new(0,-1,50),Vector3.new(72,2,28),STONE)
            part(approach,"ApproachRoof",entryFrame*CFrame.new(0,20,50),Vector3.new(72,2,28),DARK)
            for _,s in {-1,1} do
                part(approach,"BayBack",entryFrame*CFrame.new(s*35,9,50),Vector3.new(2,18,28),STONE)
                for _,z in {36,64} do part(approach,"BaySide",entryFrame*CFrame.new(s*23,9,z),Vector3.new(24,18,2),STONE) end
                arch(approach,entryFrame*CFrame.new(s*11,0,50)*CFrame.Angles(0,math.pi/2,0),20,15)
                lamp(approach,entryFrame*CFrame.new(s*25,13,50))
            end
            zone(entryFrame*CFrame.new(0,9,50),Vector3.new(72,24,30))
            passage(approach,(entryFrame*CFrame.new(0,0,36)).Position,(entryFrame*CFrame.new(0,0,rampStart)).Position,20)
            sign(approach,"ArenaRampSign",entryFrame*CFrame.new(0,10,36)*CFrame.Angles(0,math.pi,0),"ZOMBIE ARENA","Up the ramp · through the gate",hero.color)
        end
        local rise,run=Layout.FloorTop-FLOOR,rampStart-2
        stairs(approach,entryFrame*CFrame.new(0,0,rampStart)*CFrame.Angles(0,math.pi,0),rise,run,math.ceil(run),18)
        -- The stepped tunnel clears the shared Arena's seats / outer wall through real openings.
        for z=4,rampStart-2,4 do
            local y=rise*(rampStart-z)/run
            for _,side in {-1,1} do part(approach,"RampTunnelWall",entryFrame*CFrame.new(side*11,y+6,z),Vector3.new(2,12,4.2),STONE) end
            part(approach,"RampTunnelVault",entryFrame*CFrame.new(0,y+13,z),Vector3.new(24,2,4.2),DARK)
        end
        local atGate=entryFrame*CFrame.new(0,rise,2)
        part(approach,"GateLanding",atGate*CFrame.new(0,-0.5,0),Vector3.new(20,1,4),SANDSTONE)
        zone(atGate*CFrame.new(0,5,0),Vector3.new(23,14,5))
        -- Walking up to the gate starts a solo zombie run (HubMatchService): no key, no menu
        local trigger=part(approach,"ArenaTrigger",atGate*CFrame.new(0,4,2.5),Vector3.new(18,8,6),GOLD)
        trigger.Transparency,trigger.CanCollide,trigger.CanQuery,trigger.CastShadow=1,false,false,false
        table.insert(triggers,trigger)
        if isStart then
            -- Where each intro stage points (LobbyIntroService): the gate, the weapon shop door, the
            -- Schili side door, the stairs down and the boss / live signs on the rear wall
            introTargets={trigger.Position,(cf*CFrame.new(-40,0,0)).Position,(cf*CFrame.new(40,0,0)).Position,(cf*CFrame.new(30,0,-28)).Position,(cf*CFrame.new(0,0,30)).Position}
        else
            local coopDef=table.clone(assert(PadDefinitions.get("ZombieCoop"),"ZombieCoop pad missing"))
            coopDef.Id=hero.id.."ZombieCoop"
            coopDef.Title="JOIN GROUP · ZOMBIES"
            coopDef.Emblem=if hero.id=="Kroko" then "Krokero" else hero.id
            coopDef.Subtitle="Co-op · group forms in this side chamber"
            coopDef.Actions={{Id="StartCoop",Label="START GROUP"},{Id="COOP_ZOMBIES",Label="FIND PLAYERS"},{Id="Ready",Label="READY"},{Id="LeaveGroup",Label="LEAVE"}}
            -- Pads sit against the bay's back wall (pad +Z points to the arch); the start pedestals
            -- stand in a row between pad and arch instead of on the mosaic itself
            table.insert(pads,buildPad(approach,coopDef,entryFrame*CFrame.new(-26,0,50)*CFrame.Angles(0,math.pi/2,0),Vector2.new(22,14),entryFrame*CFrame.new(-34,10,50)*CFrame.Angles(0,-math.pi/2,0),1))
            local def=table.clone(assert(PadDefinitions.get(if hero.id=="Schili" then "TeamSchili" else "TeamKrokero"),"team pad missing"))
            def.Actions={{Id="ConfirmTeam",Label="READY TEAM"},{Id="Ready",Label="READY"},{Id="LeaveGroup",Label="LEAVE"}}
            table.insert(pads,buildPad(approach,def,entryFrame*CFrame.new(26,0,50)*CFrame.Angles(0,-math.pi/2,0),Vector2.new(22,14),entryFrame*CFrame.new(34,10,50)*CFrame.Angles(0,math.pi/2,0),1))
        end
    end

    -- Three proper shop chambers, each with a continuous central passage and working displays.
    local function shop(cf: CFrame,name: string,first: string,second: string)
        local room=model(folder,name.."Shop")
        part(room,"ShopFloor",cf*CFrame.new(0,-1,0),Vector3.new(56,2,46),STONE)
        part(room,"ShopVault",cf*CFrame.new(0,21,0),Vector3.new(56,2,46),DARK)
        for _,z in {-23,23} do part(room,"ShopWall",cf*CFrame.new(0,10,z),Vector3.new(56,20,2),SANDSTONE) end
        for _,side in {-1,1} do doorway(room,cf*CFrame.new(side*27,0,0)*CFrame.Angles(0,math.pi/2,0),46,20,18) end
        sign(room,"ShopSign",cf*CFrame.new(0,18,21.5),name:upper(),first.." & "..second.." · equipment",nil,Vector2.new(24,4))
        lamp(room,cf*CFrame.new(-17,16,0)); lamp(room,cf*CFrame.new(17,16,0))
        Battles.build(room,cf,name,first,second)
        zone(cf*CFrame.new(0,9,0),Vector3.new(56,26,46),true)
    end
    shop(shopFrames[1],"Shields","Otti","Schili")
    shop(shopFrames[2],"Armor","Schili","Krokero")
    shop(shopFrames[3],"Weapons","Krokero","Otti")
    local function display(cf: CFrame,x: number,z: number,length: number): any return {cframe=cf*CFrame.new(x,0,z),length=length} end
    local weapons,shields,armor=shopFrames[3],shopFrames[1],shopFrames[2]
    -- Racks only along the solid rear (+Z) and front (-Z) walls: the side doors carry the ring
    -- passage, so the aisle between them (|z| < 12) stays free. Heavy faces the blades across it.
    local armory={blades=display(weapons,-6,13,30),ranged=display(weapons,15,13,10),heavy=display(weapons*CFrame.Angles(0,math.pi,0),0,13,44),shields={Light=display(shields,-14,13,12),Balanced=display(shields,0,13,12),Heavy=display(shields,14,13,12)},armor=display(armor,0,13,38),floorY=FLOOR}

    local hypogeum=model(folder,"HypogeumMaze")
    local cell,half=32,6
    local open: {[string]: boolean}={}
    local function edge(ax: number,az: number,bx: number,bz: number): string
        local a,b=ax..":"..az,bx..":"..bz
        return if a<b then a.."/"..b else b.."/"..a
    end
    -- Only cells under the Colosseum (inside the facade, plus the cells the hall stairs land in)
    local footprint=Layout.facadeEnd()+5
    local keptCells: {[string]: boolean}={}
    local cellCount=0
    for x=-half,half do for z=-half,half do
        local px,pz=x*cell,z*cell
        local inside=(px/(Layout.SemiAxisX+footprint))^2+(pz/(Layout.SemiAxisZ+footprint))^2<=1
        for _,p in entries do
            if math.abs(p.X-px)<=cell/2 and math.abs(p.Z-pz)<=cell/2 then inside=true end
        end
        if inside then keptCells[x..":"..z]=true; cellCount+=1 end
    end end
    local function kept(x: number,z: number): boolean return keptCells[x..":"..z]==true end
    local visited: {[string]: boolean}={}
    local rng=Random.new(1783)
    local function dig(x: number,z: number)
        visited[x..":"..z]=true
        local dirs={{1,0},{-1,0},{0,1},{0,-1}}
        for i=#dirs,2,-1 do local j=rng:NextInteger(1,i); dirs[i],dirs[j]=dirs[j],dirs[i] end
        for _,d in dirs do local nx,nz=x+d[1],z+d[2]
            if kept(nx,nz) and not visited[nx..":"..nz] then open[edge(x,z,nx,nz)]=true; dig(nx,nz) end
        end
    end
    dig(0,0)
    -- Main axes plus cross-links make the maze readable instead of a long single winding path.
    for i=-half,half-1 do
        for _,axis in {-3,0,3} do
            if kept(i,axis) and kept(i+1,axis) then open[edge(i,axis,i+1,axis)]=true end
            if kept(axis,i) and kept(axis,i+1) then open[edge(axis,i,axis,i+1)]=true end
        end
    end
    -- Exits up to the grounds between the halls: the outermost cells on the east, west and north
    -- axes open their outer side onto a stairway (dx, dz: the way out)
    local exits={}
    for _,way in {{dx=1,dz=0,name="East"},{dx=-1,dz=0,name="West"},{dx=0,dz=-1,name="North"}} do
        local x,z=0,0
        while kept(x+way.dx,z+way.dz) do x+=way.dx; z+=way.dz end
        table.insert(exits,{x=x,z=z,dx=way.dx,dz=way.dz,name=way.name})
    end
    local function isExit(x: number,z: number,dx: number,dz: number): boolean
        for _,e in exits do if e.x==x and e.z==z and e.dx==dx and e.dz==dz then return true end end
        return false
    end
    local function chamber(x: number,z: number): number
        if math.abs(x)<=48 and math.abs(z)<=48 then return 1 end
        if x>=64 and x<=176 and math.abs(z)<=48 then return 2 end
        if x>=-176 and x<=-80 and math.abs(z)<=56 then return 3 end
        return 0
    end
    for x=-half,half do for z=-half,half do if kept(x,z) then
        local cf=CFrame.new(x*cell,LOWER,z*cell)
        part(hypogeum,"MazeFloor",cf*CFrame.new(0,-1,0),Vector3.new(cell+0.1,2,cell+0.1),STONE)
        part(hypogeum,"MazeVault",cf*CFrame.new(0,19,0),Vector3.new(cell+0.1,2,cell+0.1),DARK)
        zone(cf*CFrame.new(0,8,0),Vector3.new(cell+1,24,cell+1))
        for _,d in {{1,0},{0,1}} do
            local nx,nz=x+d[1],z+d[2]
            local same=chamber(x*cell,z*cell)>0 and chamber(x*cell,z*cell)==chamber(nx*cell,nz*cell)
            if kept(nx,nz) and not open[edge(x,z,nx,nz)] and not same then
                part(hypogeum,"MazeWall",cf*CFrame.new(d[1]*cell/2,9,d[2]*cell/2),Vector3.new(if d[1]==1 then 2 else cell+2,18,if d[2]==1 then 2 else cell+2),SANDSTONE)
            end
        end
        -- Outer boundary wherever the neighbouring cell lies outside the footprint
        for _,d in {{1,0},{-1,0},{0,1},{0,-1}} do
            if not kept(x+d[1],z+d[2]) and not isExit(x,z,d[1],d[2]) then
                part(hypogeum,"MazeBoundary",cf*CFrame.new(d[1]*cell/2,9,d[2]*cell/2),Vector3.new(if d[1]~=0 then 2 else cell+2,18,if d[2]~=0 then 2 else cell+2),STONE)
            end
        end
        if (x+z)%2==0 then lamp(hypogeum,cf*CFrame.new(0,14,0)) end
    end end end
    -- Stair shafts penetrate their local ceiling, with protected landing routes into the maze.
    for _,p in entries do
        part(hypogeum,"StairExitFloor",CFrame.new(p)*CFrame.new(0,-1,0),Vector3.new(16,2,16),SANDSTONE)
        sign(hypogeum,"ExitWayfinding",CFrame.new(p)*CFrame.new(0,9,5),"HYPOGEUM","Gold: meeting · green: training · west: prisoners")
        -- The maze cell containing a stair is kept clear by the clipping pass below.
    end
    -- Remove only generated maze ceiling / wall pieces intersecting the six actual stair volumes.
    -- Keeps headroom through the ceiling and avoids a maze wall across an exit.
    for _,p in hypogeum:GetChildren() do
        if p:IsA("BasePart") and (p.Name=="MazeVault" or p.Name=="MazeWall") then
            for _,route in routes do
                if route.rise==FLOOR-LOWER then
                    local localP=route.cf:PointToObjectSpace(p.Position)
                    local radius=math.sqrt(p.Size.X*p.Size.X+p.Size.Z*p.Size.Z)/2
                    if math.abs(localP.X)<7+radius and localP.Z>-8-radius and localP.Z<route.run+radius then p:Destroy(); break end
                end
            end
        end
    end
    local meeting=sign(hypogeum,"GroupMeetingPoint",CFrame.new(0,LOWER+9,-38)*CFrame.Angles(0,math.pi,0),"GROUP MEETING POINT","Create party · invite · ready · choose a mode")
    table.insert(menus,meeting)
    -- Group fights gather here (Schili / Kroko keep theirs in their halls): the Otti co-op group
    -- west of the meeting sign, the three team-battle queues east of it, all facing the room
    local coopDef=table.clone(assert(PadDefinitions.get("ZombieCoop"),"ZombieCoop pad missing"))
    coopDef.Title="JOIN GROUP · ZOMBIES"
    coopDef.Emblem="Otti"
    coopDef.Subtitle="Co-op · the group forms on this mosaic"
    coopDef.Actions={{Id="StartCoop",Label="START GROUP"},{Id="COOP_ZOMBIES",Label="FIND PLAYERS"},{Id="Ready",Label="READY"},{Id="LeaveGroup",Label="LEAVE"}}
    table.insert(pads,buildPad(hypogeum,coopDef,CFrame.new(-24,LOWER,-28),Vector2.new(22,14),CFrame.new(-24,LOWER+10,-36)*CFrame.Angles(0,math.pi,0),1))
    local teamWall=CFrame.new(24,LOWER,-36)*CFrame.Angles(0,math.pi,0)
    local teams=sign(hypogeum,"TeamsMenu",teamWall*CFrame.new(0,12,0),"TEAM BATTLES","Time · First to · Elimination",GOLD)
    teams:SetAttribute("MenuTab","TEAMS"); table.insert(menus,teams)
    for i,mode in {{"TIME_BATTLE","TIME BATTLE"},{"FIRST_TO","FIRST TO"},{"ELIMINATION","ELIMINATION"}} do
        local queueHost=sign(hypogeum,"TeamQueueEntrance",teamWall*CFrame.new((i-2)*6.5,5.5,0),mode[2],"F · join / leave queue",GOLD,Vector2.new(6,4))
        table.insert(matchActions,{part=queueHost,mode=mode[1]})
    end
    for _,x in {-28,28} do part(hypogeum,"MeetingBench",CFrame.new(x,LOWER+1,0),Vector3.new(3,2,28),WOOD) end
    for _,x in {-40,40} do for _,z in {-40,40} do
        part(hypogeum,"HypogeumPier",CFrame.new(x,LOWER+9,z),Vector3.new(3.5,18,3.5),SANDSTONE)
    end end
    for _,offset in {-128,-64,64,128} do
        arch(hypogeum,CFrame.new(0,LOWER,offset),25,16)
        arch(hypogeum,CFrame.new(offset,LOWER,0)*CFrame.Angles(0,math.pi/2,0),25,16)
    end
    for _,z in {-96,0,96} do
        sign(hypogeum,"MazeDirections",CFrame.new(0,LOWER+12,z+8),"HYPOGEUM","WEST: PRISONERS · EAST: TRAINING · EXITS: N · E · W")
        part(hypogeum,"GoldGuide",CFrame.new(0,LOWER+0.03,z),Vector3.new(2,0.06,30),GOLD,true)
    end
    local archives,plaques,training={},{},{}
    local function cage(cf: CFrame,trainingCage: boolean)
        local m=model(hypogeum,if trainingCage then "TrainingCage" else "PrisonerCell")
        for _,side in {-1,1} do
            part(m,"CageSide",cf*CFrame.new(side*7,6,0),Vector3.new(0.6,12,14),IRON)
        end
        for x=-6,6,1.2 do part(m,"CageBackBar",cf*CFrame.new(x,6,7),Vector3.new(0.3,12,0.3),IRON) end
        if not trainingCage then
            for x=-6,6,1.2 do part(m,"PrisonBars",cf*CFrame.new(x,6,-7),Vector3.new(0.3,12,0.3),IRON) end
            table.insert(archives,cf)
            table.insert(plaques,cf*CFrame.new(0,14,-7))
        else
            table.insert(training,cf)
            sign(m,"TrainingCageSign",cf*CFrame.new(0,14,6),"TRAINING","Open bay · practise attacks / blocks")
        end
        lamp(m,cf*CFrame.new(0,14,0))
    end
    for _,z in {-36,-16,24} do
        cage(CFrame.new(-152,LOWER,z)*CFrame.Angles(0,-math.pi/2,0),false)
        cage(CFrame.new(-96,LOWER,z)*CFrame.Angles(0,math.pi/2,0),false)
    end
    for _,x in {88,120,152} do
        cage(CFrame.new(x,LOWER,-28)*CFrame.Angles(0,math.pi,0),true)
        cage(CFrame.new(x,LOWER,28),true)
    end
    -- Faces -X: read while walking in from the meeting point
    sign(hypogeum,"TrainingEntrance",CFrame.new(64,LOWER+12,0)*CFrame.Angles(0,math.pi/2,0),"TRAINING YARD","Safe practice · regenerating zombies · no rewards")
    part(hypogeum,"ComboTrainingBoard",CFrame.new(173,LOWER+7,0)*CFrame.Angles(0,math.pi/2,0),Vector3.new(12,9,0.5),WOOD,true)
    -- The exits stand open: an arch in the outer wall with the wall closed beside and above it,
    -- then a stairway that climbs out under the facade line onto the grounds.
    for _,e in exits do
        local gate=CFrame.new(e.x*cell+e.dx*cell/2,LOWER,e.z*cell+e.dz*cell/2)*CFrame.Angles(0,math.atan2(e.dx,e.dz),0)
        arch(hypogeum,gate,12,14)
        for _,s in {-1,1} do part(hypogeum,"MazeBoundary",gate*CFrame.new(s*12.25,9,0),Vector3.new(9.5,18,2),STONE) end
        part(hypogeum,"MazeBoundary",gate*CFrame.new(0,16,0),Vector3.new(15,4,2),STONE)
        part(hypogeum,"ExitLanding",gate*CFrame.new(0,-1,1),Vector3.new(14,2,4),SANDSTONE)
        sign(hypogeum,"HypogeumExitSign",gate*CFrame.new(0,16,-1.4),"EXIT · "..e.name:upper(),"Stairs up · out onto the grounds",GOLD,Vector2.new(14,3))
        table.insert(holes,{descent(hypogeum,"Hypogeum"..e.name.."Exit",gate*CFrame.new(0,0,2),106,12,"HYPOGEUM","Training · prisoners · group meeting point",GOLD)})
    end
    for _,hole in holes do Arena.cutGround(hole[1],hole[2],hole[3],hole[4]) end
    -- Both spawns face the way out to the arena, on the free centre line of Otti's hall
    local start=Layout.frame(math.rad(90),100,FLOOR)
    local arrival=spawn(folder,"LobbyArrivalSpawn",start*CFrame.new(0,0,12))
    local respawn=spawn(folder,"LobbyRespawn",start*CFrame.new(5,0,18))
    Lighting.Ambient=Color3.fromRGB(78,69,59); Lighting.OutdoorAmbient=Color3.fromRGB(112,103,88); Lighting.Brightness=1.3; Lighting.ClockTime=14
    Lighting.EnvironmentDiffuseScale=0.35; Lighting.EnvironmentSpecularScale=0.2; Lighting.ExposureCompensation=-0.25
    folder.Parent=Workspace
    return {folder=folder,spawnCFrame=respawn.CFrame,arrivalSpawn=arrival,respawnSpawn=respawn,armory=armory,pads=pads,
        arenaGate=triggers[1],arenaTriggers=triggers,introTargets=introTargets,bossBoard=bossHosts[1],bossBoards=bossHosts,modeBoards=menus,matchActions=matchActions,
        tribuneDoors=liveDoors,liveBoards=liveBoards,liveCFrame=respawn.CFrame,
        archiveSlots=archives,archivePlaques=plaques,trainingSlots=training,
        trainingCFrame=CFrame.new(120,LOWER+7,0),trainingSize=Vector3.new(112,18,96),floorY=FLOOR,
        stairRoutes=routes,mazeEdges=open,mazeCellSize=cell,mazeHalf=half,mazeCells=keptCells,mazeCellCount=cellCount}
end
function Architecture.isInside(p: Vector3): boolean
    for _,v in volumes do if inside(v,p) then return true end end
    return Arena.isOnGrounds(p) -- the granite ground, galleries and stands above ground
end
function Architecture.isInArmory(p: Vector3): boolean
    for _,v in shops do if inside(v,p) then return true end end; return false
end
return Architecture
