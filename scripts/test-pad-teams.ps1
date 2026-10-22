param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$code = Get-Content -LiteralPath (Join-Path $repo 'src/hub/server/PadTeamBattleService.luau') -Raw
$defs = Get-Content -LiteralPath (Join-Path $repo 'src/shared/LobbyPadDefinitions.luau') -Raw
$test = @'
local checks = 0
local function check(ok, message) assert(ok,message); checks += 1 end
local now = 0
local os = {clock = function() return now end}
local delayed = {}
local task = {delay = function(_,fn) table.insert(delayed,fn) end}
local function signal() return {Connect = function() end} end
local all = {}
local function player(id,x)
	local p = {UserId=id,DisplayName="P"..id,Parent=true,loaded=true,valid=true,queued=false,alive=true,position={X=x,Y=3,Z=0},attrs={GameState="LOBBY"}}
	function p:GetAttribute(key) return self.attrs[key] end
	function p:SetAttribute(key,value) self.attrs[key]=value end
	table.insert(all,p)
	return p
end
local a,b,c,d = player(1,0),player(2,40),player(3,0),player(4,40)
local parties = {}
local mock = true
local reserveFails = false
local sendFails = false
local reserveHook = nil
local createdCount = 0
local discarded = 0
local sent = nil
local lastFighters = nil
local GameStates = {StateAttribute="GameState",Countdown="COUNTDOWN",PartyForming="PARTY_FORMING",isInLobby=function(state) return state=="LOBBY" or state=="PARTY_FORMING" end}
local modules = {
	GameStates=GameStates,MatchTypes={},LobbyService={},
	CombatUtil={getLivingCharacter=function(p) if p.alive then return {},{},{Position=p.position} end return nil,nil,nil end},
	InventoryService={hasValidLoadout=function(p) return p.valid,"invalid gear" end},
	PlayerDataService={isReady=function(p) return p.loaded end},
	PartyService={padParty=function(id) return parties[id] end,setLocked=function(party,locked) party.locked=locked end},
	MatchmakingService={isQueued=function(p) return p.queued end},
	ArenaReservationService={
		create=function(mode,fighters)
			createdCount+=1
			lastFighters=fighters
			check(mode=="TIME_BATTLE","physical team pads use one default mode")
			if reserveHook then reserveHook() end
			if reserveFails then return nil end
			return {record={matchId="test"},mock=mock}
		end,
		discard=function() discarded+=1 end,
	},
	HubTeleportService={send=function(players,options)
		if sendFails then error("test transport failure") end
		sent={players=players,options=options}
		if options.mock then for _,p in players do options.onFailed(p,"MOCK") end end
		return players
	end},
}
local server = {CombatUtil="CombatUtil",InventoryService="InventoryService",PlayerDataService="PlayerDataService",LobbyService="LobbyService"}
local script = {Parent={Parent=server,PartyService="PartyService",MatchmakingService="MatchmakingService",ArenaReservationService="ArenaReservationService",HubTeleportService="HubTeleportService"}}
local shared = {GameStates="GameStates",MatchTypes="MatchTypes"}
local services = {Players={GetPlayers=function() return all end,PlayerRemoving=signal()},ReplicatedStorage={Shared=shared}}
local game = {GetService=function(_,name) return services[name] end}
local require = function(key) return assert(modules[key],"unknown module") end
local Color3 = {fromRGB=function(...) return {...} end}
local function pad(id,x,team)
	return {def={Id=id,Team=team},size={X=24,Z=16},cframe={PointToObjectSpace=function(_,p) return {X=p.X-x,Y=p.Y,Z=p.Z} end}}
end
'@
$test += "`nlocal function definitionModule()`n$defs`nend`nlocal definitions=definitionModule()`n"
$test += "`nlocal function teamModule()`n$code`nend`nlocal teams=teamModule()`n"
$test += @'
teams.init({pad("TeamSchili",0,"Blue"),pad("TeamKrokero",40,"Red")})
local function reset()
	for _,fn in delayed do fn() end
	table.clear(delayed)
	for _,p in all do p.Parent=true;p.loaded=true;p.valid=true;p.queued=false;p.alive=true;p.attrs.GameState="LOBBY" end
	a.position.X=0;b.position.X=40;c.position.X=0;d.position.X=40
	parties={TeamSchili={id="blue",members={a},locked=false},TeamKrokero={id="red",members={b},locked=false}}
	mock=true;reserveFails=false;sendFails=false;reserveHook=nil;sent=nil;lastFighters=nil
	teams.invalidate()
end
check(#definitions.Pads==3,"only three physical side pads; Solo entrance is separate")
for _,p in definitions.Pads do check(p.Enabled,"no coming-soon pads") end
check(definitions.get("TeamSchili").Emblem=="Schili","Schili emblem")
check(definitions.get("TeamKrokero").Emblem=="Krokero","Krokero emblem")
check(definitions.get("ZombieCoop").Wing=="Single","co-op moved to training wing")
reset()
local ok=teams.confirm(a,"TeamSchili")
check(ok and sent==nil,"one captain cannot start the match alone")
check(teams.status("TeamSchili")~=nil,"first captain readiness visible")
ok=teams.confirm(b,"TeamKrokero")
check(ok and sent~=nil,"both captains start one match")
check(#sent.players==2,"1v1 sends two fighters")
check(lastFighters[1].team=="Blue" and lastFighters[2].team=="Red","mosaic choice maps to actual opposing teams")
check(not parties.TeamSchili.locked and not parties.TeamKrokero.locked,"mock returns unlock both teams")
check(a.attrs.GameState=="PARTY_FORMING" and b.attrs.GameState=="PARTY_FORMING","mock restores lobby state")
reset();parties.TeamSchili.members={a,c}
check(not teams.confirm(a,"TeamSchili"),"unequal teams rejected")
reset();parties.TeamSchili.members={a,c};parties.TeamKrokero.members={b,d}
check(not teams.confirm(c,"TeamSchili"),"non-captain cannot ready team")
check(teams.confirm(a,"TeamSchili"),"2v2 first captain")
check(teams.confirm(b,"TeamKrokero"),"2v2 second captain")
check(#sent.players==4,"2v2 keeps all fighters")
reset()
local e,f,g,h = player(5,0),player(6,40),player(7,0),player(8,40)
parties.TeamSchili.members={a,c,e,g};parties.TeamKrokero.members={b,d,f,h}
check(teams.confirm(a,"TeamSchili"),"4v4 first captain")
check(teams.confirm(b,"TeamKrokero"),"4v4 second captain")
check(#sent.players==8,"4v4 sends eight fighters without splitting sides")
reset();parties.TeamSchili.members={a,c,e,g,player(9,0)};parties.TeamKrokero.members={b,d,f,h}
check(not teams.confirm(a,"TeamSchili"),"more than four per side rejected")
reset();a.position.X=20
check(not teams.confirm(a,"TeamSchili"),"captain must stand on their own mosaic")
reset();b.loaded=false
check(not teams.confirm(a,"TeamSchili"),"unloaded opponent blocks start")
reset();b.valid=false
check(not teams.confirm(a,"TeamSchili"),"invalid opponent gear blocks start")
reset();b.queued=true
check(not teams.confirm(a,"TeamSchili"),"queued opponent cannot be double assigned")
reset();b.alive=false
check(not teams.confirm(a,"TeamSchili"),"dead opponent cannot start")
reset();parties.TeamKrokero=nil
check(not teams.confirm(a,"TeamSchili"),"missing opposing team rejected")
reset();teams.confirm(a,"TeamSchili");teams.invalidate();teams.confirm(b,"TeamKrokero")
check(sent==nil,"changing teams invalidates previous confirmation")
reset();teams.confirm(a,"TeamSchili");now+=31;teams.confirm(b,"TeamKrokero")
check(sent==nil,"expired captain confirmation cannot start a match")
reset();teams.confirm(a,"TeamSchili");reserveFails=true
check(not teams.confirm(b,"TeamKrokero"),"reservation failure reported")
check(not parties.TeamSchili.locked and not parties.TeamKrokero.locked,"reservation failure releases locks")
check(a.attrs.GameState=="PARTY_FORMING","reservation failure restores state")
reset();teams.confirm(a,"TeamSchili");reserveHook=function() b.position.X=70 end
local before=discarded
check(not teams.confirm(b,"TeamKrokero"),"walking away during reservation cancels start")
check(discarded==before+1 and sent==nil,"cancelled reservation discarded without teleport")
reset();mock=false;teams.confirm(a,"TeamSchili");check(teams.confirm(b,"TeamKrokero"),"live route starts")
check(parties.TeamSchili.locked and parties.TeamKrokero.locked,"teams locked while travelling")
check(not teams.confirm(a,"TeamSchili"),"duplicate start rejected")
check(#delayed==1,"live start schedules recovery")
for _,fn in delayed do fn() end
table.clear(delayed)
check(not parties.TeamSchili.locked and a.attrs.GameState=="PARTY_FORMING","recovery unlocks players still in Hub")
reset();mock=false;sendFails=true;teams.confirm(a,"TeamSchili")
check(not teams.confirm(b,"TeamKrokero"),"unexpected transport failure reported")
check(#delayed==1,"transport exception still has recovery scheduled")
for _,fn in delayed do fn() end
check(not parties.TeamSchili.locked and not parties.TeamKrokero.locked,"transport recovery releases both teams")
print("PASS: "..checks.." team-pad checks against actual Luau sources (mock Roblox services).")
'@
$target = Join-Path ([System.IO.Path]::GetTempPath()) ('OttiTeams-' + [guid]::NewGuid().ToString() + '.luau')
[System.IO.File]::WriteAllText($target,$test,[System.Text.UTF8Encoding]::new($false))
try { & $LuauPath $target; $testExit=$LASTEXITCODE } finally { Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue }
exit $testExit
