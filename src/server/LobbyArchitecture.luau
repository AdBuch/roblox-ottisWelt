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
local function part(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, decor: boolean?): Part
    local p=Instance.new("Part")
    p.Name,p.Anchored,p.CFrame,p.Size=name,true,cf,size
    p.Color,p.Material=color,Enum.Material.Limestone
    p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
    if decor then p.CanCollide,p.CanQuery,p.CanTouch,p.CastShadow=false,false,false,false end
    p.Parent=parent
    return p
end
local function model(parent: Instance, name: string): Model
    local m=Instance.new("Model"); m.Name=name; m.Parent=parent; return m
end
local function sign(parent: Instance, name: string, cf: CFrame, title: string, subtitle: string, color: Color3?): (BasePart, TextLabel)
    local host=part(parent,name,cf,Vector3.new(18,4.5,0.35),DARK,true)
    host.Material=Enum.Material.Wood
    if color then part(parent,"SignAccent",cf*CFrame.new(0,2.15,-0.2),Vector3.new(18,0.2,0.12),color,true) end
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
    zone(cf*CFrame.new(0,rise/2+4,run/2),Vector3.new(width+2,rise+14,run+4))
    table.insert(routes,{cf=cf,rise=rise,run=run,count=count})
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
    local folder=Instance.new("Folder"); folder.Name=Config.LobbyFolderName
    local pads,menus,liveDoors,entries,matchActions={},{},{},{},{}
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
    -- Arched connections join side doors; no giant slab can accidentally seal a stairwell.
    local ring=model(folder,"EnclosedConcourse")
    for _,hero in heroes do
        local hall=Layout.frame(math.rad(hero.angle),100,FLOOR)
        for _,side in {-1,1} do
            local curve=Layout.frame(math.rad(hero.angle-side*18),100,FLOOR)
            passage(ring,(hall*CFrame.new(side*42,0,0)).Position,curve.Position,20,inShop)
        end
        for i=0,20 do
            local a=Layout.frame(math.rad(hero.angle-18-i*4),100,FLOOR)
            local b=Layout.frame(math.rad(hero.angle-22-i*4),100,FLOOR)
            passage(ring,a.Position,b.Position,20,inShop)
            if i%4==0 then lamp(ring,(a*CFrame.new(8,12,0))) end
        end
    end
    local soloHosts,bossHosts={},{}
    for _,hero in heroes do
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
        part(hall,"RearWall",cf*CFrame.new(0,13,39),Vector3.new(88,26,2),STONE)
        for _,side in {-1,1} do
            doorway(hall,cf*CFrame.new(side*43,0,0)*CFrame.Angles(0,math.pi/2,0),78,26,24)
            -- Descend at both original front-corner stair locations, protected along their edges.
            local lower=cf*CFrame.new(side*30,LOWER-FLOOR,22)*CFrame.Angles(0,math.pi,0)
            stairs(hall,lower,FLOOR-LOWER,48,32,10)
            part(hall,"StairLanding",cf*CFrame.new(side*30,LOWER-FLOOR-1,27),Vector3.new(12,2,10),SANDSTONE)
            table.insert(entries,(cf*CFrame.new(side*30,LOWER-FLOOR,29)).Position)
            for _,z in {-18,0,18} do
                part(hall,"InnerStairParapet",cf*CFrame.new(side*24.5,2,z),Vector3.new(1,4,18),STONE)
                part(hall,"OuterStairParapet",cf*CFrame.new(side*35.5,2,z),Vector3.new(1,4,18),STONE)
            end
            sign(hall,"HypogeumSign",cf*CFrame.new(side*29,9,-30)*CFrame.Angles(0,math.pi,0),"DOWN · HYPOGEUM","Prisoners · training · meeting rooms",hero.color)
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
        for _,x in {-29,0,29} do
            local flag=part(hall,"HeroBanner",cf*CFrame.new(x,17,37.7),Vector3.new(6,10,0.15),hero.color,true)
            flag.Material=Enum.Material.Fabric
            part(hall,"BannerGoldHem",cf*CFrame.new(x,13,37.5),Vector3.new(6,0.5,0.2),GOLD,true)
        end
        local menu=sign(hall,"AllModes",cf*CFrame.new(15,8,37),"PLAY · ALL MODES","Solo · Co-op · Teams · Boss · Watch",hero.color)
        table.insert(menus,menu)
        local boss=sign(hall,"BossSelection",cf*CFrame.new(-9,8,37),"BOSS FIGHT","Otti · Schili · Krokero",hero.color)
        table.insert(bossHosts,boss)
        local live=sign(hall,"WatchLive",cf*CFrame.new(29,7,32),"LIVE BATTLES","Watch from the tribunes",hero.color)
        table.insert(liveDoors,live)

        -- Original arena approach: the old cage bays are now actual group chambers.
        local approach=model(folder,hero.id.."ArenaApproach")
        local entryFrame=Layout.frame(math.rad(hero.angle),0,FLOOR)
        part(approach,"ApproachFloor",entryFrame*CFrame.new(0,-1,50),Vector3.new(72,2,28),STONE)
        part(approach,"ApproachRoof",entryFrame*CFrame.new(0,20,50),Vector3.new(72,2,28),DARK)
        for _,s in {-1,1} do
            part(approach,"BayBack",entryFrame*CFrame.new(s*35,9,50),Vector3.new(2,18,28),STONE)
            for _,z in {36,64} do part(approach,"BaySide",entryFrame*CFrame.new(s*23,9,z),Vector3.new(24,18,2),STONE) end
            arch(approach,entryFrame*CFrame.new(s*11,0,50)*CFrame.Angles(0,math.pi/2,0),20,15)
            lamp(approach,entryFrame*CFrame.new(s*25,13,50))
        end
        zone(entryFrame*CFrame.new(0,9,50),Vector3.new(72,24,30))
        -- Closed narrow approach from the lobby, followed by a rising tunnel to the real gate.
        passage(approach,(entryFrame*CFrame.new(0,0,64)).Position,(cf*CFrame.new(0,0,-38)).Position,20)
        passage(approach,(entryFrame*CFrame.new(0,0,36)).Position,(entryFrame*CFrame.new(0,0,30)).Position,20)
        local ramp=entryFrame*CFrame.new(0,0,30)*CFrame.Angles(0,math.pi,0)
        stairs(approach,ramp,Layout.FloorTop-FLOOR,28,28,18)
        -- The stepped tunnel clears the shared Arena's seats / outer wall through real openings.
        for i=0,6 do
            local z=4+i*4
            local y=(Layout.FloorTop-FLOOR)*(30-z)/28
            for _,side in {-1,1} do part(approach,"RampTunnelWall",entryFrame*CFrame.new(side*11,y+6,z),Vector3.new(2,12,4.2),STONE) end
            part(approach,"RampTunnelVault",entryFrame*CFrame.new(0,y+13,z),Vector3.new(24,2,4.2),DARK)
        end
        local atGate=entryFrame*CFrame.new(0,Layout.FloorTop-FLOOR,2)
        part(approach,"GateLanding",atGate*CFrame.new(0,-0.5,0),Vector3.new(20,1,4),SANDSTONE)
        zone(atGate*CFrame.new(0,5,0),Vector3.new(23,14,5))
        local solo=sign(approach,"StartSoloFight",entryFrame*CFrame.new(0,6,36)*CFrame.Angles(0,math.pi,0),"START SOLO FIGHT","F · start your own zombie run",hero.color)
        table.insert(soloHosts,solo)
        local coopDef=table.clone(assert(PadDefinitions.get("ZombieCoop"),"ZombieCoop pad missing"))
        coopDef.Id=if hero.id=="Otti" then "ZombieCoop" else hero.id.."ZombieCoop"
        coopDef.Title="JOIN GROUP · ZOMBIES"
        coopDef.Emblem=if hero.id=="Kroko" then "Krokero" else hero.id
        coopDef.Subtitle="Co-op · group forms in this side chamber"
        coopDef.Actions={{Id="StartCoop",Label="START GROUP"},{Id="COOP_ZOMBIES",Label="FIND PLAYERS"},{Id="Ready",Label="READY"},{Id="LeaveGroup",Label="LEAVE"}}
        table.insert(pads,buildPad(approach,coopDef,entryFrame*CFrame.new(-23,0,50)*CFrame.Angles(0,math.pi/2,0),Vector2.new(22,18),entryFrame*CFrame.new(-34,10,50)*CFrame.Angles(0,-math.pi/2,0),0))
        if hero.id=="Otti" then
            local host=sign(approach,"TeamsMenu",entryFrame*CFrame.new(30,6,51)*CFrame.Angles(0,math.pi/2,0),"TEAM BATTLES","Time · First to · Elimination",hero.color)
            host:SetAttribute("MenuTab","TEAMS"); table.insert(menus,host)
            for i,mode in {{"TIME_BATTLE","TIME BATTLE"},{"FIRST_TO","FIRST TO"},{"ELIMINATION","ELIMINATION"}} do
                local queueHost=sign(approach,"TeamQueueEntrance",entryFrame*CFrame.new(22,5,39+i*6)*CFrame.Angles(0,-math.pi/2,0),mode[2],"F · join / leave queue with your party",hero.color)
                queueHost.Size=Vector3.new(5.4,4,0.35)
                table.insert(matchActions,{part=queueHost,mode=mode[1]})
            end
        else
            local def=table.clone(assert(PadDefinitions.get(if hero.id=="Schili" then "TeamSchili" else "TeamKrokero"),"team pad missing"))
            def.Actions={{Id="ConfirmTeam",Label="READY TEAM"},{Id="Ready",Label="READY"},{Id="LeaveGroup",Label="LEAVE"}}
            table.insert(pads,buildPad(approach,def,entryFrame*CFrame.new(23,0,50)*CFrame.Angles(0,-math.pi/2,0),Vector2.new(22,18),entryFrame*CFrame.new(34,10,50)*CFrame.Angles(0,math.pi/2,0),0))
        end
    end

    -- Three proper shop chambers, each with a continuous central passage and working displays.
    local function shop(cf: CFrame,name: string,first: string,second: string)
        local room=model(folder,name.."Shop")
        part(room,"ShopFloor",cf*CFrame.new(0,-1,0),Vector3.new(56,2,46),STONE)
        part(room,"ShopVault",cf*CFrame.new(0,21,0),Vector3.new(56,2,46),DARK)
        for _,z in {-23,23} do part(room,"ShopWall",cf*CFrame.new(0,10,z),Vector3.new(56,20,2),SANDSTONE) end
        for _,side in {-1,1} do doorway(room,cf*CFrame.new(side*27,0,0)*CFrame.Angles(0,math.pi/2,0),46,20,18) end
        local title=sign(room,"ShopSign",cf*CFrame.new(0,18,21.5),name:upper(),first.." & "..second.." · equipment")
        title.Size=Vector3.new(24,4,0.35)
        lamp(room,cf*CFrame.new(-17,16,0)); lamp(room,cf*CFrame.new(17,16,0))
        Battles.build(room,cf,name,first,second)
        zone(cf*CFrame.new(0,9,0),Vector3.new(56,26,46),true)
    end
    shop(shopFrames[1],"Shields","Otti","Schili")
    shop(shopFrames[2],"Armor","Schili","Krokero")
    shop(shopFrames[3],"Weapons","Krokero","Otti")
    local function display(cf: CFrame,x: number,z: number,length: number): any return {cframe=cf*CFrame.new(x,0,z),length=length} end
    local weapons,shields,armor=shopFrames[3],shopFrames[1],shopFrames[2]
    local armory={blades=display(weapons,0,13,40),heavy=display(weapons*CFrame.Angles(0,math.pi/2,0),-2,21,24),ranged=display(weapons*CFrame.Angles(0,-math.pi/2,0),2,21,24),shields={Light=display(shields,-14,13,12),Balanced=display(shields,0,13,12),Heavy=display(shields,14,13,12)},armor=display(armor,0,10,38),floorY=FLOOR}

    local hypogeum=model(folder,"HypogeumMaze")
    local cell,half=32,6
    local open: {[string]: boolean}={}
    local function edge(ax: number,az: number,bx: number,bz: number): string
        local a,b=ax..":"..az,bx..":"..bz
        return if a<b then a.."/"..b else b.."/"..a
    end
    local visited: {[string]: boolean}={}
    local rng=Random.new(1783)
    local function dig(x: number,z: number)
        visited[x..":"..z]=true
        local dirs={{1,0},{-1,0},{0,1},{0,-1}}
        for i=#dirs,2,-1 do local j=rng:NextInteger(1,i); dirs[i],dirs[j]=dirs[j],dirs[i] end
        for _,d in dirs do local nx,nz=x+d[1],z+d[2]
            if math.abs(nx)<=half and math.abs(nz)<=half and not visited[nx..":"..nz] then open[edge(x,z,nx,nz)]=true; dig(nx,nz) end
        end
    end
    dig(0,0)
    -- Main axes plus cross-links make the maze readable instead of a long single winding path.
    for i=-half,half-1 do
        for _,axis in {-3,0,3} do open[edge(i,axis,i+1,axis)]=true; open[edge(axis,i,axis,i+1)]=true end
    end
    local function chamber(x: number,z: number): number
        if math.abs(x)<=48 and math.abs(z)<=48 then return 1 end
        if x>=64 and x<=176 and math.abs(z)<=48 then return 2 end
        if x>=-176 and x<=-80 and math.abs(z)<=56 then return 3 end
        return 0
    end
    for x=-half,half do for z=-half,half do
        local cf=CFrame.new(x*cell,LOWER,z*cell)
        part(hypogeum,"MazeFloor",cf*CFrame.new(0,-1,0),Vector3.new(cell+0.1,2,cell+0.1),STONE)
        part(hypogeum,"MazeVault",cf*CFrame.new(0,19,0),Vector3.new(cell+0.1,2,cell+0.1),DARK)
        zone(cf*CFrame.new(0,8,0),Vector3.new(cell+1,24,cell+1))
        for _,d in {{1,0},{0,1}} do
            local nx,nz=x+d[1],z+d[2]
            local same=chamber(x*cell,z*cell)>0 and chamber(x*cell,z*cell)==chamber(nx*cell,nz*cell)
            if nx>half or nz>half or (not open[edge(x,z,nx,nz)] and not same) then
                part(hypogeum,"MazeWall",cf*CFrame.new(d[1]*cell/2,9,d[2]*cell/2),Vector3.new(if d[1]==1 then 2 else cell+2,18,if d[2]==1 then 2 else cell+2),SANDSTONE)
            end
        end
        if x==-half then part(hypogeum,"MazeBoundary",cf*CFrame.new(-cell/2,9,0),Vector3.new(2,18,cell+2),STONE) end
        if z==-half then part(hypogeum,"MazeBoundary",cf*CFrame.new(0,9,-cell/2),Vector3.new(cell+2,18,2),STONE) end
        if (x+z)%2==0 then lamp(hypogeum,cf*CFrame.new(0,14,0)) end
    end end
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
    for _,x in {-28,28} do part(hypogeum,"MeetingBench",CFrame.new(x,LOWER+1,0),Vector3.new(3,2,28),WOOD) end
    for _,x in {-40,40} do for _,z in {-40,40} do
        part(hypogeum,"HypogeumPier",CFrame.new(x,LOWER+9,z),Vector3.new(3.5,18,3.5),SANDSTONE)
    end end
    for _,offset in {-128,-64,64,128} do
        arch(hypogeum,CFrame.new(0,LOWER,offset),25,16)
        arch(hypogeum,CFrame.new(offset,LOWER,0)*CFrame.Angles(0,math.pi/2,0),25,16)
    end
    for _,z in {-96,0,96} do
        sign(hypogeum,"MazeDirections",CFrame.new(0,LOWER+12,z+8),"HYPOGEUM","WEST: PRISONERS · CENTRE: MEETING · EAST: TRAINING")
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
    sign(hypogeum,"TrainingEntrance",CFrame.new(64,LOWER+12,0)*CFrame.Angles(0,-math.pi/2,0),"TRAINING YARD","Safe practice · regenerating zombies · no rewards")
    part(hypogeum,"ComboTrainingBoard",CFrame.new(173,LOWER+7,0)*CFrame.Angles(0,math.pi/2,0),Vector3.new(12,9,0.5),WOOD,true)
    local rome=sign(hypogeum,"RomeGate",CFrame.new(0,LOWER+8,205),"PORTA ROMA","The road to Rome · opening soon")
    part(hypogeum,"RomeTimberGate",CFrame.new(0,LOWER+7,207),Vector3.new(18,14,2),WOOD)
    local start=Layout.frame(math.rad(90),100,FLOOR)
    local arrival=spawn(folder,"LobbyArrivalSpawn",start*CFrame.new(8,0,27))
    local respawn=spawn(folder,"LobbyRespawn",start*CFrame.new(12,0,20))
    local _,live=sign(folder,"LiveBoard",start*CFrame.new(28,10,30),"LIVE IN THE COLOSSEUM","No live battles")
    Lighting.Ambient=Color3.fromRGB(78,69,59); Lighting.OutdoorAmbient=Color3.fromRGB(112,103,88); Lighting.Brightness=1.3; Lighting.ClockTime=14
    Lighting.EnvironmentDiffuseScale=0.35; Lighting.EnvironmentSpecularScale=0.2; Lighting.ExposureCompensation=-0.25
    folder.Parent=Workspace
    return {folder=folder,spawnCFrame=respawn.CFrame,arrivalSpawn=arrival,respawnSpawn=respawn,armory=armory,pads=pads,
        arenaGate=soloHosts[1],soloHosts=soloHosts,bossBoard=bossHosts[1],bossBoards=bossHosts,modeBoards=menus,matchActions=matchActions,
        romeGate=rome,tribuneDoors=liveDoors,liveBoard=live,liveCFrame=respawn.CFrame,
        archiveSlots=archives,archivePlaques=plaques,trainingSlots=training,
        trainingCFrame=CFrame.new(120,LOWER+7,0),trainingSize=Vector3.new(112,18,96),floorY=FLOOR,
        stairRoutes=routes,mazeEdges=open,mazeCellSize=cell,mazeHalf=half}
end
function Architecture.isInside(p: Vector3): boolean
    for _,v in volumes do if inside(v,p) then return true end end; return false
end
function Architecture.isInArmory(p: Vector3): boolean
    for _,v in shops do if inside(v,p) then return true end end; return false
end
return Architecture
