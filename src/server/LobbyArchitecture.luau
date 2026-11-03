--!strict
-- The Hub at the arena's height: three hero lobbies on the granite ground in front of the
-- Colosseum, each facing its hero gate across the open ground floor of the stands. Otti's is the
-- main lobby, the old start hall made simpler: Otti's monument beside the way to the arena, the
-- zombie archive along the front wall, the shop street to the left, the co-op group and the
-- training yard (straw dummies) to the right, the boards for teams, bosses and live battles on
-- the rear wall. Schili's and Kroko's halls are smaller: their co-op group and their team.
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
local FLOOR = Layout.FloorTop
local STONE = Color3.fromRGB(116, 103, 87)
local SANDSTONE = Color3.fromRGB(207, 182, 141)
local DARK = Color3.fromRGB(68, 56, 45)
local GOLD = Color3.fromRGB(224, 176, 70)
local IRON = Color3.fromRGB(62, 64, 61)
local WOOD = Color3.fromRGB(100, 65, 38)
local WHITE = Color3.fromRGB(245, 231, 202)
local YARD = Color3.fromRGB(196, 170, 120)
-- Lobbies stand this far in front of the facade (centre offset = facade + GAP + half depth)
local GAP = 10
type Volume = { cf: CFrame, size: Vector3 }
local volumes: { Volume } = {}
local shops: { Volume } = {}
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
local function floorRect(parent: Instance, cf: CFrame, x0: number,x1: number,z0: number,z1: number, color: Color3?)
    part(parent,"HallFloor",cf*CFrame.new((x0+x1)/2,-1,(z0+z1)/2),Vector3.new(x1-x0,2,z1-z0),color or STONE)
end
-- A roof at `height` over x -hx..hx, z -hz..hz with an open skylight of 2sx x 2sz in the middle.
local function roof(parent: Instance, cf: CFrame, hx: number, hz: number, height: number, sx: number, sz: number)
    local y=height+1
    part(parent,"HallVault",cf*CFrame.new(0,y,-(hz+sz)/2),Vector3.new(2*hx,2,hz-sz),DARK)
    part(parent,"HallVault",cf*CFrame.new(0,y,(hz+sz)/2),Vector3.new(2*hx,2,hz-sz),DARK)
    for _,s in {-1,1} do part(parent,"HallVault",cf*CFrame.new(s*(hx+sx)/2,y,0),Vector3.new(hx-sx,2,2*sz),DARK) end
    for _,s in {-1,1} do
        part(parent,"SkylightRim",cf*CFrame.new(s*sx,y+1.2,0),Vector3.new(1,0.6,2*sz+1),GOLD,true).Material=Enum.Material.Metal
        part(parent,"SkylightRim",cf*CFrame.new(0,y+1.2,s*sz),Vector3.new(2*sx+1,0.6,1),GOLD,true).Material=Enum.Material.Metal
    end
end
local function spawn(parent: Instance,name: string,cf: CFrame): SpawnLocation
    local p=Instance.new("SpawnLocation"); p.Name=name; p.Anchored=true; p.Neutral=true; p.Duration=0; p.Transparency=1; p.Size=Vector3.new(6,1,6); p.CFrame=cf*CFrame.new(0,-0.5,0); p.Parent=parent; return p
end
local function monument(parent: Instance, cf: CFrame, hero: any)
    part(parent,"MonumentStep",cf*CFrame.new(0,0.5,0),Vector3.new(14,1,14),SANDSTONE)
    part(parent,"MonumentPedestal",cf*CFrame.new(0,3,0),Vector3.new(10,5,10),SANDSTONE)
    part(parent,"BronzePedestalCap",cf*CFrame.new(0,5.7,0),Vector3.new(11,0.5,11),GOLD,true)
    -- the statue looks along the monument frame's +Z, the inscription sits on that face
    Statue.build(parent,cf*CFrame.new(0,6,0)*CFrame.Angles(0,math.pi,0),1.6,hero.id)
    sign(parent,"HeroInscription",cf*CFrame.new(0,3,5.2)*CFrame.Angles(0,math.pi,0),hero.name,hero.motto,hero.color)
end
local function banners(parent: Instance, cf: CFrame, xs: { number }, z: number, color: Color3)
    for _,x in xs do
        local flag=part(parent,"HeroBanner",cf*CFrame.new(x,16,z),Vector3.new(6,10,0.15),color,true)
        flag.Material=Enum.Material.Fabric
        part(parent,"BannerGoldHem",cf*CFrame.new(x,11.2,z-0.05*math.sign(z)),Vector3.new(6,0.5,0.2),GOLD,true)
    end
end

function Architecture.build(buildPad: any): any
    table.clear(volumes); table.clear(shops)
    local existing=Workspace:FindFirstChild(Config.LobbyFolderName); if existing then existing:Destroy() end
    -- Exactly the same builder, gates, sand, stands and galleries as the fight place.
    Arena.build()
    Arena.setGroundExits(true) -- in the Hub the ground floor, galleries and stands are part of the lobby
    local folder=Instance.new("Folder"); folder.Name=Config.LobbyFolderName
    local pads,menus,liveDoors,liveBoards,matchActions={},{},{},{},{}
    local heroes={
        {id="Otti",name="OTTI",angle=90,color=Color3.fromRGB(140,38,37),motto="COURAGE · FRIENDSHIP · UNITY"},
        {id="Schili",name="SCHILIBITZLI · SCHILI",angle=330,color=Color3.fromRGB(52,111,112),motto="WISDOM · ENDURANCE · KINDNESS"},
        {id="Kroko",name="KROKERO · KROKO",angle=210,color=Color3.fromRGB(125,93,43),motto="COURAGE · ACTION · LOYALTY"},
    }
    local triggers,bossHosts={},{}
    local hallFrames: {[string]: CFrame}={}
    -- Every hero gate: walking up to it starts a solo zombie run (HubMatchService), no key or menu.
    -- A sign under the stands and a gold strip on the paving lead there from the facade.
    for _,hero in heroes do
        local gate=Layout.frame(math.rad(hero.angle),0,FLOOR)
        local approach=model(folder,hero.id.."ArenaApproach")
        local trigger=part(approach,"ArenaTrigger",gate*CFrame.new(0,4,5.5),Vector3.new(18,8,6),GOLD)
        trigger.Transparency,trigger.CanCollide,trigger.CanQuery,trigger.CastShadow=1,false,false,false
        table.insert(triggers,trigger)
        sign(approach,"ArenaRampSign",gate*CFrame.new(0,10.5,8)*CFrame.Angles(0,math.pi,0),"ZOMBIE ARENA","Walk through the gate · your fight starts there",hero.color,Vector2.new(16,3.5))
        local guide=part(approach,"ArenaGuide",Layout.frame(math.rad(hero.angle),(8+Layout.facadeEnd()+GAP)/2,FLOOR)*CFrame.new(0,0.03,0),Vector3.new(1.2,0.06,Layout.facadeEnd()+GAP-8),GOLD,true)
        guide.Material=Enum.Material.Neon
    end

    -- OTTI · the main lobby
    local otti=heroes[1]
    local HX,HZ=44,40
    local main=Layout.frame(math.rad(otti.angle),Layout.facadeEnd()+GAP+HZ,FLOOR)
    hallFrames.Otti=main
    local hall=model(folder,"OttiHeroLobby")
    hall:SetAttribute("Hero","Otti")
    floorRect(hall,main,-HX,HX,-HZ,HZ)
    roof(hall,main,HX,HZ,26,16,14)
    doorway(hall,main*CFrame.new(0,0,-HZ+2),2*HX,26,24)
    for _,side in {-1,1} do doorway(hall,main*CFrame.new(side*(HX-1),0,0)*CFrame.Angles(0,math.pi/2,0),2*HZ-4,26,24) end
    part(hall,"HallWall",main*CFrame.new(0,13,HZ-1),Vector3.new(2*HX,26,2),STONE)
    zone(main*CFrame.new(0,10,0),Vector3.new(2*HX+2,32,2*HZ+2))
    for _,x in {-18,18} do
        for _,z in {-24,24} do
            part(hall,"VaultColumn",main*CFrame.new(x,13,z),Vector3.new(3,26,3),SANDSTONE)
            part(hall,"ColumnCapital",main*CFrame.new(x,24,z),Vector3.new(4.5,2,4.5),GOLD,true)
            lamp(hall,main*CFrame.new(x,13,z+2*math.sign(z)))
        end
    end
    -- Otti's monument beside the way to the arena, looking at the arriving player
    monument(hall,main*CFrame.new(-15,0,-6),otti)
    Mosaics.build(hall,main*CFrame.new(15,0.05,-6),"Otti",1.0,SANDSTONE)
    for _,x in {-14,14} do part(hall,"Bench",main*CFrame.new(x,1.1,30),Vector3.new(10,2.2,3),WOOD) end
    banners(hall,main,{-40,40},HZ-2.3,otti.color)
    sign(hall,"HallName",main*CFrame.new(0,22.5,-HZ+0.6),"OTTI'S HALL","The start · shops · co-op · training",otti.color,Vector2.new(24,4))
    sign(hall,"ArenaSign",main*CFrame.new(0,20.5,-HZ+3.4)*CFrame.Angles(0,math.pi,0),"THE ARENA","Out through the Colosseum · walk through the gate",GOLD,Vector2.new(22,4.5))
    part(hall,"ArenaGuide",main*CFrame.new(0,0.03,-(HZ-4)/2+2),Vector3.new(1.2,0.06,HZ),GOLD,true).Material=Enum.Material.Neon
    -- The zombie archive: three cages on each side of the way out, open towards the hall
    local archives,plaques={},{}
    for _,side in {-1,1} do
        for _,x in {19,28,37.5} do
            local cf=main*CFrame.new(side*x,0,-HZ+7)*CFrame.Angles(0,math.pi,0)
            local cage=model(hall,"ArchiveCage")
            for _,s in {-1,1} do part(cage,"CageSide",cf*CFrame.new(s*4.4,5,0),Vector3.new(0.6,10,8),IRON) end
            part(cage,"CageRoof",cf*CFrame.new(0,10.2,0),Vector3.new(9.4,0.4,8),IRON)
            for bx=-3.6,3.61,1.2 do part(cage,"PrisonBars",cf*CFrame.new(bx,5,-4),Vector3.new(0.3,10,0.3),IRON) end
            table.insert(archives,cf)
            table.insert(plaques,cf*CFrame.new(0,12.5,-4.3))
        end
    end
    for _,side in {-1,1} do sign(hall,"ArchiveSign",main*CFrame.new(side*28,17,-HZ+3.4)*CFrame.Angles(0,math.pi,0),"ZOMBIE ARCHIVE","Know your enemy before the gate",nil,Vector2.new(16,3)) end
    -- Rear wall: teams (stage 3), bosses and live battles (stage 4)
    local rear=main*CFrame.new(0,0,HZ-2.2)
    revealStage=3
    local teams=sign(hall,"TeamsMenu",rear*CFrame.new(0,13,0),"TEAM BATTLES","Time · First to · Elimination",GOLD)
    teams:SetAttribute("MenuTab","TEAMS"); table.insert(menus,teams)
    for i,mode in {{"TIME_BATTLE","TIME BATTLE"},{"FIRST_TO","FIRST TO"},{"ELIMINATION","ELIMINATION"}} do
        local queueHost=sign(hall,"TeamQueueEntrance",rear*CFrame.new((i-2)*6.5,6.5,0),mode[2],"F · join / leave queue",GOLD,Vector2.new(6,4))
        table.insert(matchActions,{part=queueHost,mode=mode[1]})
    end
    revealStage=4
    local menu=sign(hall,"AllModes",rear*CFrame.new(27,8,0),"PLAY · ALL MODES","Solo · Co-op · Teams · Boss · Watch",otti.color)
    table.insert(menus,menu)
    table.insert(bossHosts,(sign(hall,"BossSelection",rear*CFrame.new(-27,8,0),"BOSS FIGHT","Otti · Schili · Krokero",otti.color)))
    local live,liveCount=sign(hall,"WatchLive",rear*CFrame.new(27,15,0),"LIVE BATTLES","No live battles",otti.color)
    table.insert(liveDoors,live); table.insert(liveBoards,liveCount)
    revealStage=nil
    -- Over the doors: the shop street (stage 1), the training yard (stage 3), the group halls (stage 2)
    for _,side in {-1,1} do
        local over=main*CFrame.new(side*(HX-2.4),0,0)*CFrame.Angles(0,side*math.pi/2,0)
        revealStage=if side<0 then 1 else 3
        sign(hall,if side<0 then "ShopDirection" else "TrainingDirection",over*CFrame.new(0,18.6,0),if side<0 then "SHOP STREET" else "CO-OP & TRAINING",if side<0 then "Weapons · shields · armor for denarii" else "Co-op group · straw dummies · no rewards",otti.color)
        revealStage=2
        sign(hall,"GroupDirection",main*CFrame.new(side*25,20.5,-HZ+3.4)*CFrame.Angles(0,math.pi,0),if side<0 then "← KROKO HALL" else "SCHILI HALL →","Co-op groups · team battles",otti.color,Vector2.new(16,3.5))
        revealStage=nil
    end

    -- The shop street: weapons, shields and armor in a row, door to door, out of the left door
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
    local street=model(folder,"ShopStreet")
    local shopFrames={}
    for k,entry in {{"Weapons","Krokero","Otti"},{"Shields","Otti","Schili"},{"Armor","Schili","Krokero"}} do
        local cf=main*CFrame.new(-HX-32-60*(k-1),0,0)
        shopFrames[entry[1]]=cf
        shop(cf,entry[1],entry[2],entry[3])
        -- a short covered passage from the previous door (the hall's for the first shop)
        local passage=cf*CFrame.new(30,0,0)
        part(street,"PassageFloor",passage*CFrame.new(0,-1,0),Vector3.new(4.4,2,24),STONE)
        part(street,"PassageVault",passage*CFrame.new(0,19,0),Vector3.new(4.4,2,24),DARK)
        for _,s in {-1,1} do part(street,"PassageWall",passage*CFrame.new(0,9,s*12.5),Vector3.new(4.4,18,1),STONE) end
        zone(passage*CFrame.new(0,9,0),Vector3.new(5,22,26))
    end
    local function display(cf: CFrame,x: number,z: number,length: number): any return {cframe=cf*CFrame.new(x,0,z),length=length} end
    local weapons,shields,armor=shopFrames.Weapons,shopFrames.Shields,shopFrames.Armor
    -- Racks only along the solid rear (+Z) and front (-Z) walls: the side doors carry the street
    -- through the aisle (|z| < 12). Heavy faces the blades across it.
    local armory={blades=display(weapons,-6,13,30),ranged=display(weapons,15,13,10),heavy=display(weapons*CFrame.Angles(0,math.pi,0),0,13,44),shields={Light=display(shields,-14,13,12),Balanced=display(shields,0,13,12),Heavy=display(shields,14,13,12)},armor=display(armor,0,13,38),floorY=FLOOR}

    -- The open yard out of the right door: the Otti co-op group by the hall, straw dummies beyond
    local yard=model(folder,"TrainingYard")
    local Y0,Y1,YZ=HX,HX+80,30
    floorRect(yard,main,Y0,Y1,-YZ,YZ,YARD)
    for _,z in {-YZ-0.5,YZ+0.5} do part(yard,"YardWall",main*CFrame.new((Y0+Y1)/2,6,z),Vector3.new(Y1-Y0,12,1),SANDSTONE) end
    doorway(yard,main*CFrame.new(Y1+0.5,0,0)*CFrame.Angles(0,math.pi/2,0),2*YZ+2,18,20)
    zone(main*CFrame.new((Y0+Y1)/2,8,0),Vector3.new(Y1-Y0,24,2*YZ+2))
    for _,x in {Y0+12,Y0+40,Y1-8} do for _,z in {-YZ+1.5,YZ-1.5} do lamp(yard,main*CFrame.new(x,8,z)) end end
    local coopDef=table.clone(assert(PadDefinitions.get("ZombieCoop"),"ZombieCoop pad missing"))
    coopDef.Title="JOIN GROUP · ZOMBIES"
    coopDef.Emblem="Otti"
    coopDef.Subtitle="Co-op · the group forms on this mosaic"
    coopDef.Actions={{Id="StartCoop",Label="START GROUP"},{Id="COOP_ZOMBIES",Label="FIND PLAYERS"},{Id="Ready",Label="READY"},{Id="LeaveGroup",Label="LEAVE"}}
    -- the pad's board stands against the front wall, its pedestals face the yard's middle
    table.insert(pads,buildPad(yard,coopDef,main*CFrame.new(Y0+18,0,-14),Vector2.new(22,14),main*CFrame.new(Y0+18,10,-YZ+0.3)*CFrame.Angles(0,math.pi,0),1))
    local training={}
    for _,x in {Y0+40,Y0+54,Y0+68} do
        for _,z in {-14,14} do
            -- dummies face the yard's middle
            table.insert(training,main*CFrame.new(x,0,z)*(if z<0 then CFrame.Angles(0,math.pi,0) else CFrame.identity))
        end
    end
    sign(yard,"TrainingEntrance",main*CFrame.new(Y0+54,9,-YZ+0.4)*CFrame.Angles(0,math.pi,0),"TRAINING YARD","Straw dummies · practise attacks, blocks and specials · no rewards",nil,Vector2.new(26,4.5))
    part(yard,"ComboTrainingBoard",main*CFrame.new(Y1-2,7,0)*CFrame.Angles(0,-math.pi/2,0),Vector3.new(12,9,0.5),WOOD,true)

    -- SCHILI and KROKO · smaller halls with their co-op group and their team
    local SX,SZ=30,26
    for index=2,3 do
        local hero=heroes[index]
        local cf=Layout.frame(math.rad(hero.angle),Layout.facadeEnd()+GAP+SZ,FLOOR)
        hallFrames[hero.id]=cf
        local small=model(folder,hero.id.."HeroLobby")
        small:SetAttribute("Hero",hero.id)
        floorRect(small,cf,-SX,SX,-SZ,SZ)
        roof(small,cf,SX,SZ,22,10,8)
        doorway(small,cf*CFrame.new(0,0,-SZ+1),2*SX,22,20)
        for _,side in {-1,1} do part(small,"HallWall",cf*CFrame.new(side*(SX-1),11,0),Vector3.new(2,22,2*SZ),STONE) end
        part(small,"HallWall",cf*CFrame.new(0,11,SZ-1),Vector3.new(2*SX,22,2),STONE)
        zone(cf*CFrame.new(0,10,0),Vector3.new(2*SX+2,28,2*SZ+2))
        -- the statue at the back looks at the door
        monument(small,cf*CFrame.new(0,0,15)*CFrame.Angles(0,math.pi,0),hero)
        for _,x in {-20,20} do lamp(small,cf*CFrame.new(x,14,SZ-2.5)) end
        for _,x in {-20,20} do lamp(small,cf*CFrame.new(x,14,-SZ+2.5)) end
        banners(small,cf,{-10,10},SZ-2.3,hero.color)
        sign(small,"HallName",cf*CFrame.new(0,19.5,-SZ-0.4),hero.name.." HALL","Co-op group · team "..(if hero.id=="Kroko" then "Krokero" else "Schili"),hero.color,Vector2.new(24,4))
        local back=cf*CFrame.new(0,0,SZ-2.2)
        local menuHost=sign(small,"AllModes",back*CFrame.new(18,8,0),"PLAY · ALL MODES","Solo · Co-op · Teams · Boss · Watch",hero.color,Vector2.new(14,4))
        table.insert(menus,menuHost)
        table.insert(bossHosts,(sign(small,"BossSelection",back*CFrame.new(-18,8,0),"BOSS FIGHT","Otti · Schili · Krokero",hero.color,Vector2.new(14,4))))
        local liveHost,count=sign(small,"WatchLive",back*CFrame.new(0,18,0),"LIVE BATTLES","No live battles",hero.color,Vector2.new(14,4))
        table.insert(liveDoors,liveHost); table.insert(liveBoards,count)
        local emblem=if hero.id=="Kroko" then "Krokero" else hero.id
        local coop=table.clone(assert(PadDefinitions.get("ZombieCoop"),"ZombieCoop pad missing"))
        coop.Id=hero.id.."ZombieCoop"
        coop.Title="JOIN GROUP · ZOMBIES"
        coop.Emblem=emblem
        coop.Subtitle="Co-op · the group forms on this mosaic"
        coop.Actions={{Id="StartCoop",Label="START GROUP"},{Id="COOP_ZOMBIES",Label="FIND PLAYERS"},{Id="Ready",Label="READY"},{Id="LeaveGroup",Label="LEAVE"}}
        -- Pads lie along the side walls (their boards hang there), the pedestals face the aisle
        table.insert(pads,buildPad(small,coop,cf*CFrame.new(-SX+12,0,0)*CFrame.Angles(0,math.pi/2,0),Vector2.new(22,14),cf*CFrame.new(-SX+2.3,10,0)*CFrame.Angles(0,-math.pi/2,0),1))
        local def=table.clone(assert(PadDefinitions.get(if hero.id=="Schili" then "TeamSchili" else "TeamKrokero"),"team pad missing"))
        def.Actions={{Id="ConfirmTeam",Label="READY TEAM"},{Id="Ready",Label="READY"},{Id="LeaveGroup",Label="LEAVE"}}
        table.insert(pads,buildPad(small,def,cf*CFrame.new(SX-12,0,0)*CFrame.Angles(0,-math.pi/2,0),Vector2.new(22,14),cf*CFrame.new(SX-2.3,10,0)*CFrame.Angles(0,math.pi/2,0),1))
    end

    -- Both spawns face the way out to the arena, on the free centre line of Otti's hall
    local arrival=spawn(folder,"LobbyArrivalSpawn",main*CFrame.new(0,0,4))
    local respawn=spawn(folder,"LobbyRespawn",main*CFrame.new(5,0,12))
    -- Where each intro stage points (LobbyIntroService): the gate, the shop street door, Schili's
    -- hall, the training yard door and the boards on the rear wall
    local introTargets={triggers[1].Position,(main*CFrame.new(-HX,0,0)).Position,(hallFrames.Schili*CFrame.new(0,0,-SZ)).Position,(main*CFrame.new(HX,0,0)).Position,(main*CFrame.new(0,0,HZ-8)).Position}
    Lighting.Ambient=Color3.fromRGB(96,88,78); Lighting.OutdoorAmbient=Color3.fromRGB(128,120,106); Lighting.Brightness=2; Lighting.ClockTime=14
    Lighting.EnvironmentDiffuseScale=0.4; Lighting.EnvironmentSpecularScale=0.2; Lighting.ExposureCompensation=-0.1
    folder.Parent=Workspace
    return {folder=folder,spawnCFrame=respawn.CFrame,arrivalSpawn=arrival,respawnSpawn=respawn,armory=armory,pads=pads,
        arenaGate=triggers[1],arenaTriggers=triggers,introTargets=introTargets,bossBoard=bossHosts[1],bossBoards=bossHosts,modeBoards=menus,matchActions=matchActions,
        tribuneDoors=liveDoors,liveBoards=liveBoards,liveCFrame=respawn.CFrame,
        archiveSlots=archives,archivePlaques=plaques,trainingSlots=training,
        trainingCFrame=main*CFrame.new((Y0+Y1)/2,8,0),trainingSize=Vector3.new(Y1-Y0,18,2*YZ),floorY=FLOOR,
        hallFrames=hallFrames,shopFrames=shopFrames}
end
function Architecture.isInside(p: Vector3): boolean
    for _,v in volumes do if inside(v,p) then return true end end
    return Arena.isOnGrounds(p) -- the granite ground, galleries and stands above ground
end
function Architecture.isInArmory(p: Vector3): boolean
    for _,v in shops do if inside(v,p) then return true end end; return false
end
return Architecture
