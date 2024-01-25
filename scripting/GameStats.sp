#include <clientmod/multicolors>
#include <sourcemod>
#include <clientmod>
#include <sdkhooks>
#include <sdktools>
#include <lvl_ranks>
#include <cstrike>

#undef REQUIRE_PLUGIN
#include <warmix>

#undef REQUIRE_EXTENSIONS
#include <ripext>

#define RIP_ON()		(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "HTTPRequest.HTTPRequest")

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
    name = "GameStats",
    author = "Laravelka",
    description = "",
    version = "1.2.3",
    url = "https://github.com/Laravelka/GameStats"
};

int g_iKillsPerRound[MAXPLAYERS+1],
    g_iPauseCounts[4],
    g_iWhirlInterval = 2,
    m_hActiveWeapon,
    m_vecVelocity,
    g_iEloDraw = 100,
    g_iEloLose = 200,
    g_iEloWin = 300,
    g_iGameId,
    m_iClip1;

float g_flRotation[MAXPLAYERS+1],
    g_flMinLenVelocity = 100.0,
    g_fPauseTime = 20.00,
    g_flWhirl = 200.0;
    
char g_sMapName[128], 
    g_sServerSlug[32], 
    g_sTableName[96], 
    g_sPluginTitle[64],
    g_sTeamOneName[128],
    g_sTeamTwoName[128];

bool g_isOverTime = false,
    g_isHalfTime = false,
    g_isOpKill = false,
    g_isPause[4];

enum struct PlayerStat {
    char ip;
    int team;
    char steam;
    int aces;
    int runs;
    int kills;
    int jumps;
    int whirls;
    int smokes;
    int deaths;
    int blinds;
    int game_id;
    int assists;
    int quadros;
    int triples;
    int noscopes;
    int headshots;
    int open_frags;
    int last_clips;
    int penetrateds;
}

PlayerStat stats[MAXPLAYERS+1];
Handle g_svPausable;

public void OnPluginStart()
{
    HookEvent("player_death", OnPlayerDeath);
    HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);
    HookEvent("player_disconnect", OnPlayerDisconnect);

    RegConsoleCmd("sm_pause", CommandPause);

    m_iClip1 = FindSendPropInfo("CBaseCombatWeapon", "m_iClip1");
    m_hActiveWeapon = FindSendPropInfo("CBasePlayer", "m_hActiveWeapon");
    m_vecVelocity = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");

    if(LR_IsLoaded())
    {
        LR_GetTableName(g_sTableName, sizeof(g_sTableName));
        LR_GetTitleMenu(g_sPluginTitle, sizeof(g_sPluginTitle));
    }

    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/GameStats.ini");
    KeyValues kv = new KeyValues("GameStats");
    
    if (!FileExists(sPath, false)) {
        kv.SetString("server", "mix");
        kv.SetNum("elo_win", 300);
        kv.SetNum("elo_lose", 200);
        kv.SetNum("elo_draw", 100);
        kv.SetFloat("pause_time", 20.00);
        kv.ExportToFile(sPath);
    }

    if (kv.ImportFromFile(sPath)) {
        kv.GetString("server", g_sServerSlug, sizeof(g_sServerSlug));
        kv.GetNum("elo_win", g_iEloWin);
        kv.GetNum("elo_lose", g_iEloLose);
        kv.GetNum("elo_draw", g_iEloDraw);
        kv.GetFloat("pause_time", g_fPauseTime);
    } else {
        SetFailState("[GameStats] KeyValues Error!");
    }
    delete kv;
}

public void OnConfigsExecuted()
{
    g_svPausable = FindConVar("sv_pausable");
}

public void OnClientPutInServer(int client)
{
    if (client > 0)
    {
        CreateTimer(1.00, OnClientConnectedTimer, client, TIMER_REPEAT);
    }
}

public Action OnClientConnectedTimer(Handle timer, any client)
{

    if (IsClientConnected(client) && IsClientInGame(client))
    {
        char steam[40], url[240];
        int userId = GetClientUserId(client);
        GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);
        FormatEx(url, sizeof url, "https://po-rb.ru/clientConnected?steam=%s&server=%s&user_id=%d", steam, g_sServerSlug, userId);
        
        KeyValues data = new KeyValues("data");
        data.SetNum("type", MOTDPANEL_TYPE_URL);
        data.SetString("title", "Добро пожаловать!");
        data.SetString("msg", url);
        
        ShowVGUIPanel(client, "info", data, true);

        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Action CommandPause(int client, int args)
{
    if (!WarMix_IsMatchLive())
    {
        MC_PrintToChat(client, "{rare}[По-Белорусски] {red}Пауза доступна только во время матча!");
        return Plugin_Handled;
    }

    int team = GetClientTeam(client);
    int oppositeTeam = team == CS_TEAM_CT ? CS_TEAM_T : CS_TEAM_CT;

    if (team == CS_TEAM_T || team == CS_TEAM_CT)
    {
        if (!g_isPause[team])
        {
            if (g_iPauseCounts[team] >= 1) {
                MC_PrintToChat(client, "{rare}[По-Белорусски] {red}Разрешена только одна пауза на матч!");
            } else if (g_isPause[oppositeTeam]) {
                MC_PrintToChat(client, "{rare}[По-Белорусски] {red}Противоположная команда уже включила паузу!");
            } else {
                char name[MAX_NAME_LENGTH];
                GetClientName(client, name, sizeof name);
                g_iPauseCounts[team]++;
                g_isPause[team] = true;
                SetConVarInt(g_svPausable, true);
                FakeClientCommand(client, "pause");
                SetConVarInt(g_svPausable, false);
                
                MC_PrintToChatAll("{rare}[По-Белорусски] {lime}%s {white}установил паузу на {green}%.2f {white}сек.", name, g_fPauseTime);
                CreateTimer(g_fPauseTime, EndPause, client);
            }
        } else {
            g_isPause[team] = false;
            SetConVarInt(g_svPausable, true);
            FakeClientCommand(client, "pause");
            SetConVarInt(g_svPausable, false);
        }
    }

    return Plugin_Continue;
}

Action EndPause(Handle timer, any client)
{
    int team = GetClientTeam(client);

    if (g_isPause[team])
    {
        g_isPause[team] = false;
        SetConVarInt(g_svPausable, true);
        FakeClientCommand(client, "pause");
        SetConVarInt(g_svPausable, false);
        MC_PrintToChatAll("{rare}[По-Белорусски] {white}Пауза закончилась по истечению времени.");
    }
    return Plugin_Stop;
}

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof g_sMapName);
}

public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] szError, int iErr_max)
{
    #if defined _ripext_included_
        MarkNativeAsOptional("HTTPRequest.HTTPRequest");
        MarkNativeAsOptional("HTTPRequest.SetHeader");
        MarkNativeAsOptional("HTTPRequest.Get");
        MarkNativeAsOptional("HTTPRequest.Post");
        MarkNativeAsOptional("HTTPRequest.AppendFormParam");
        MarkNativeAsOptional("HTTPResponse.Status.get");
    #endif
        return APLRes_Success;
}

public void OnPlayerRunCmdPost(int iClient, int iButtons, int iImpulse, const float flVel[3], const float flAngles[3], int iWeapon, int iSubType, int iCmdNum, int iTickCount, int iSeed, const int iMouse[2])
{
    static int iInterval[MAXPLAYERS+1];

    if(IsPlayerAlive(iClient) && (g_flRotation[iClient] += iMouse[0] / 50.0) && iInterval[iClient] - GetTime() < 1)
    {
        g_flRotation[iClient] = 0.0;
        iInterval[iClient] = GetTime() + g_iWhirlInterval;
    }
}

void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (WarMix_IsMatchLive())
    {
        g_isOpKill = false;

        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientConnected(i))
            {
                g_iKillsPerRound[i] = 0;
            }
        }
    }
}

void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientConnected(i))
        {
            switch (g_iKillsPerRound[i])
            {
                case 0,1,2 :
                {
                }
                case 3 :
                {
                    stats[i].triples++;
                }
                case 4 :
                {
                    stats[i].quadros++;
                }
                case 5 :
                {
                    stats[i].aces++;
                }
            }

            g_iKillsPerRound[i] = 0;
        }
    }

    
}

public int WarMix_OnPlayerReplaced(int client, const char[] target)
{
    char ip[64], steam[32];
    int team = GetClientTeam(client);
    JSONObject player = new JSONObject();
    //int captainOne = WarMix_GetCaptain(2);
    //int captainTwo = WarMix_GetCaptain(3);
    //int captainOneTeam = captainOne > 0 ? GetClientTeam(captainOne) : 0;
    //int captainTwoTeam = captainTwo > 0 ? GetClientTeam(captainTwo) : 0;
    GetClientIP(client, ip, sizeof ip);
    GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);

    player.SetInt("team", team);
    player.SetString("ip", ip);
    player.SetInt("game_id", g_iGameId);
    player.SetString("replacer_steam", steam);
    player.SetString("replaced_steam", target);
    
    if (WarMix_IsMatchLive())
    {
        PlayerReplaceRequest(player, client);
    }
}

public int WarMix_OnMatchStart(iMatchMode mode, const Players[], int numPlayers)
{
    JSONObject game = new JSONObject();
    JSONArray arrayOnePlayers = new JSONArray();
    JSONArray arrayTwoPlayers = new JSONArray();
    char teamOneName[128], teamTwoName[128];
    int captainOne = WarMix_GetCaptain(2);
    int captainTwo = WarMix_GetCaptain(3);
    int captainOneTeam = captainOne > 0 ? GetClientTeam(captainOne) : 0;
    int captainTwoTeam = captainTwo > 0 ? GetClientTeam(captainTwo) : 0;

    g_iPauseCounts[2] = 0;
    g_iPauseCounts[3] = 0;

    if (captainOne != 0) 
    {
        GetClientName(captainOne, teamOneName, sizeof teamOneName);
    } 
    else 
    {
        FormatEx(teamOneName, sizeof teamOneName, "%s", "Team one");
    }

    if (captainTwo != 0) 
    {
        GetClientName(captainTwo, teamTwoName, sizeof teamTwoName);
    } 
    else 
    {
        FormatEx(teamTwoName, sizeof teamTwoName, "%s", "Team two");
    }
    
    game.SetString("team_one_name", teamOneName);
    game.SetString("team_two_name", teamTwoName);
    game.SetString("server", g_sServerSlug);
    game.SetString("map", g_sMapName);

    for (int i = 0; i < numPlayers; i++)
    {
        int client = Players[i];
        int team = GetClientTeam(client);
        JSONObject player = new JSONObject();
        char ip[64], name[MAX_NAME_LENGTH], steam[30];
        GetClientIP(client, ip, sizeof ip);
        GetClientName(client, name, sizeof name);
        GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);

        player.SetString("ip", ip);
        player.SetString("name", name);
        player.SetString("steam", steam);

        if (captainOne == client || captainTwo == client)
        {
            player.SetInt("is_captain", 1);
        }
        else
        {
            player.SetInt("is_captain", 0);
        }

        if (team == captainOneTeam)
        {
            player.SetInt("team", 1);
            arrayOnePlayers.Push(player);
        }
        else if (team == captainTwoTeam)
        {
            player.SetInt("team", 2);
            arrayTwoPlayers.Push(player);
        }
        
        delete player;
    }
    
    game.Set("one_players", arrayOnePlayers);
    game.Set("two_players", arrayTwoPlayers);
    CreateGameRequest(game);

    delete game;
    delete arrayOnePlayers;
    delete arrayTwoPlayers;
}

public int WarMix_OnMatchHalfTime(iMatchMode mode, const Players[], int numPlayers, bool overtime)
{
    g_isHalfTime = true;

    LogMessage("[WarMix_OnMatchHalfTime] players: %d", numPlayers);

    JSONObject game = new JSONObject();
    JSONArray arrayOnePlayers = new JSONArray();
    JSONArray arrayTwoPlayers = new JSONArray();

    int scoreOne = WarMix_GetScore(2, g_isOverTime);
    int scoreTwo = WarMix_GetScore(3, g_isOverTime);
    int captainOne = WarMix_GetCaptain(2);
    int captainTwo = WarMix_GetCaptain(3);
    int captainOneTeam = captainOne > 0 ? GetClientTeam(captainOne) : 0;
    int captainTwoTeam = captainTwo > 0 ? GetClientTeam(captainTwo) : 0;

    game.SetInt("team_one_score", scoreOne);
    game.SetInt("team_two_score", scoreTwo);
    
    char steam[30];
    for (int i = 0; i < numPlayers; i++)
    {
        int client = Players[i];
        if (IsClientConnected(client) && IsClientInGame(client))
        {
            int team = GetClientTeam(client);
            JSONObject player = new JSONObject();
            GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);
            
            player.SetString("steam", steam);
            player.SetInt("runs", stats[client].runs);
            player.SetInt("jumps", stats[client].jumps);
            player.SetInt("kills", stats[client].kills);
            player.SetInt("smokes", stats[client].smokes);
            player.SetInt("blinds", stats[client].blinds);
            player.SetInt("whirls", stats[client].whirls);
            player.SetInt("deaths", stats[client].deaths);
            player.SetInt("assists", stats[client].assists);
            player.SetInt("noscopes", stats[client].noscopes);
            player.SetInt("headshots", stats[client].headshots);
            player.SetInt("penetrateds", stats[client].penetrateds);

            if (team == captainOneTeam)
            {
                player.SetInt("team", 1);
                arrayOnePlayers.Push(player);
            }
            else if (team == captainTwoTeam)
            {
                player.SetInt("team", 2);
                arrayTwoPlayers.Push(player);
            }

        }
    }

    game.Set("one_players", arrayOnePlayers);
    game.Set("two_players", arrayTwoPlayers);
    UpdateGameRequest(game);

    delete game;
    delete arrayOnePlayers;
    delete arrayTwoPlayers;
}

public int WarMix_OnMatchOvertime()
{
    g_isOverTime = true;

    LogMessage("[WarMix_OnMatchOvertime]");
}

public int WarMix_OnRestartsCompleted()
{
    g_isOverTime = false;

    LogMessage("[WarMix_OnRestartsCompleted]");
}

public int WarMix_OnMatchEnd(iMatchMode mode, int winnerTeam, const winPlayers[], int numWinPlayers, const loosePlayers[], int numLoosePlayers)
{
    char winnerName[128];
    JSONObject game = new JSONObject();
    JSONArray arrayOnePlayers = new JSONArray();
    JSONArray arrayTwoPlayers = new JSONArray();
    Format(winnerName, sizeof winnerName, winnerTeam == 2 ? g_sTeamOneName : g_sTeamTwoName);

    int scoreOne = WarMix_GetScore(2, g_isOverTime);
    int scoreTwo = WarMix_GetScore(3, g_isOverTime);
    int captainOne = WarMix_GetCaptain(2);
    int captainTwo = WarMix_GetCaptain(3);
    int captainOneTeam = captainOne > 0 ? GetClientTeam(captainOne) : 0;
    int captainTwoTeam = captainTwo > 0 ? GetClientTeam(captainTwo) : 0;

    if (scoreOne == scoreTwo)
    {
        game.SetInt("team_winner", 0);
    } else {
        game.SetInt("team_winner", winnerTeam);
    }

    LogMessage("[WarMix_OnMatchEnd] score: %d/%d captains: %L / %L overtime: %d", scoreOne, scoreTwo, captainOne, captainTwo, g_isOverTime ? 1 : 0);
    
    game.SetInt("team_one_score", scoreOne);
    game.SetInt("team_two_score", scoreTwo);
    game.SetBool("is_overtime", g_isOverTime);

    for (int i = 0; i < numWinPlayers; i++)
    {
        char steam[30];
        int client = winPlayers[i];

        if (IsClientConnected(client) && IsClientInGame(client))
        {
            int team = GetClientTeam(client);
            GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);
            JSONObject player = new JSONObject();

            player.SetInt("win", 1);
            player.SetString("steam", steam);
            player.SetInt("runs", stats[client].runs);
            player.SetInt("jumps", stats[client].jumps);
            player.SetInt("kills", stats[client].kills);
            player.SetInt("smokes", stats[client].smokes);
            player.SetInt("blinds", stats[client].blinds);
            player.SetInt("whirls", stats[client].whirls);
            player.SetInt("deaths", stats[client].deaths);
            player.SetInt("assists", stats[client].assists);
            player.SetInt("noscopes", stats[client].noscopes);
            player.SetInt("headshots", stats[client].headshots);
            player.SetInt("penetrateds", stats[client].penetrateds);

            if (team == captainOneTeam)
            {
                player.SetInt("team", 1);
                arrayOnePlayers.Push(player);
            }
            else if (team == captainTwoTeam)
            {
                player.SetInt("team", 2);
                arrayTwoPlayers.Push(player);
            }

            ClearPlayer(client);
            delete player;

            if (scoreOne == scoreTwo)
            {
                if (g_isOverTime)
                {
                    LogMessage("[WarMix_OnMatchEnd] OVERTIME: %d vs %d", scoreOne, scoreTwo);
                }
                else
                {
                    LogMessage("[WarMix_OnMatchEnd] Ничья");

                    if (StrEqual(g_sServerSlug, "mix6")) 
                    {
                        LR_ChangeClientValue(client, g_iEloDraw);
                        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}Ничья!");
                        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}Обе команды получают по {green}%d ELO{white}. {green}GG!", g_iEloDraw);
                        int newExp = LR_GetClientValue(client);
                        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}У вас: {green}%d ELO", newExp);
                    }
                    
                }
                
            } 
            else 
            {
                LogMessage("[WarMix_OnMatchEnd] Победила команда: %s", winnerName);

                if (StrEqual(g_sServerSlug, "mix6")) 
                {
                    LR_ChangeClientValue(client, g_iEloWin);
                    MC_PrintToChat(client, "{rare}[По-Белорусски] {white}Победила команда: {green}%s", winnerName);
                    MC_PrintToChat(client, "{rare}[По-Белорусски] {white}За победу вы получаете {green}%d ELO{white}. {green}GG!", g_iEloWin);
                    int newExp = LR_GetClientValue(client);
                    MC_PrintToChat(client, "{rare}[По-Белорусски] {white}У вас: {green}%d ELO", newExp);
                }
            }
        }
    }

    for (int i = 0; i < numLoosePlayers; i++)
    {
        char steam[30];
        int client = loosePlayers[i];
        
        if (IsClientConnected(client) && IsClientInGame(client))
        {
            int team = GetClientTeam(client);
            GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);
            JSONObject player = new JSONObject();
            
            player.SetInt("win", 0);
            player.SetString("steam", steam);
            player.SetInt("runs", stats[client].runs);
            player.SetInt("jumps", stats[client].jumps);
            player.SetInt("kills", stats[client].kills);
            player.SetInt("smokes", stats[client].smokes);
            player.SetInt("blinds", stats[client].blinds);
            player.SetInt("whirls", stats[client].whirls);
            player.SetInt("deaths", stats[client].deaths);
            player.SetInt("assists", stats[client].assists);
            player.SetInt("noscopes", stats[client].noscopes);
            player.SetInt("headshots", stats[client].headshots);
            player.SetInt("penetrateds", stats[client].penetrateds);

            if (team == captainOneTeam)
            {
                player.SetInt("team", 1);
                arrayOnePlayers.Push(player);
            }
            else if (team == captainTwoTeam)
            {
                player.SetInt("team", 2);
                arrayTwoPlayers.Push(player);
            }

            ClearPlayer(client);
            delete player;

            if (scoreOne == scoreTwo)
            {
                if (g_isOverTime)
                {
                    LogMessage("[WarMix_OnMatchEnd] OVERTIME: %d vs %d", scoreOne, scoreTwo);
                } 
                else
                {
                    LogMessage("[WarMix_OnMatchEnd] Ничья");

                    if (StrEqual(g_sServerSlug, "mix6")) 
                    {
                        LR_ChangeClientValue(client, g_iEloDraw);
                        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}Ничья!");
                        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}Обе команды получают по {green}%d ELO{white}. {green}GG!", g_iEloDraw);
                        int newExp = LR_GetClientValue(client);
                        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}У вас: {green}%d ELO", newExp);
                    }
                }
            } 
            else 
            {
                LogMessage("[WarMix_OnMatchEnd] LOOSE: %d/%d", scoreOne, scoreTwo);

                if (StrEqual(g_sServerSlug, "mix6")) 
                {
                    LR_ChangeClientValue(client, -g_iEloLose);
                    MC_PrintToChat(client, "{rare}[По-Белорусски] {white}Победила команда: {green}%s", winnerName);
                    MC_PrintToChat(client, "{rare}[По-Белорусски] {white}За поражение вы теряете {red}%d ELO{white}. {orange}В следующий раз повезет!", g_iEloLose);
                    int newExp = LR_GetClientValue(client);
                    MC_PrintToChat(client, "{rare}[По-Белорусски] {white}У вас: {green}%d ELO", newExp);
                }
            }
        }
    }

    game.Set("one_players", arrayOnePlayers);
    game.Set("two_players", arrayTwoPlayers);
    EndGameRequest(game);
    delete arrayOnePlayers;
    delete arrayTwoPlayers;
    delete game;
}

void ClearPlayer(int client)
{
    stats[client].ip = 0;
    stats[client].team = 0;
    stats[client].steam = 0;
    stats[client].aces = 0;
    stats[client].runs = 0;
    stats[client].kills = 0;
    stats[client].jumps = 0;
    stats[client].whirls = 0;
    stats[client].smokes = 0;
    stats[client].deaths = 0;
    stats[client].blinds = 0;
    stats[client].game_id = 0;
    stats[client].assists = 0;
    stats[client].quadros = 0;
    stats[client].triples = 0;
    stats[client].noscopes = 0;
    stats[client].headshots = 0;
    stats[client].open_frags = 0;
    stats[client].last_clips = 0;
    stats[client].penetrateds = 0;
}

public Action OnPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    if (!WarMix_IsMatchLive())
    {
        return Plugin_Handled;
    }

    char steam[32];
    JSONObject player = new JSONObject();
    int client = GetClientOfUserId(event.GetInt("userid"));
    GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);

    player.SetString("steam", steam);
    player.SetInt("game_id", g_iGameId);
    player.SetInt("runs", stats[client].runs);
    player.SetInt("jumps", stats[client].jumps);
    player.SetInt("kills", stats[client].kills);
    player.SetInt("smokes", stats[client].smokes);
    player.SetInt("blinds", stats[client].blinds);
    player.SetInt("whirls", stats[client].whirls);
    player.SetInt("deaths", stats[client].deaths);
    player.SetInt("assists", stats[client].assists);
    player.SetInt("noscopes", stats[client].noscopes);
    player.SetInt("headshots", stats[client].headshots);
    player.SetInt("penetrateds", stats[client].penetrateds);
    HTTPRequest http = new HTTPRequest("https://po-rb.ru/api/games/playerDisconnect");
    http.Post(player, OnPlayerDisconnectRequest, client);

    return Plugin_Continue;
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!WarMix_IsMatchLive())
    {
        return Plugin_Handled;
    }

    float vecVelocity[3];
    int client = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int assister = GetClientOfUserId(event.GetInt("assister"));
    int attackerBlind = GetClientOfUserId(event.GetInt("attackerblind"));

    int isSmoke = event.GetBool("smoke");        
    int isNoScope = event.GetBool("noscope");        
    int isHeadshot = event.GetBool("headshot");        
    int isPenetrated = event.GetBool("penetrated");        
    int activeWeapon = GetEntDataEnt2(attacker, m_hActiveWeapon);

    if ((!IsFakeClient(client) && !IsFakeClient(attacker)) && IsClientInGame(client) && IsClientInGame(attacker))
    {
        if (!attacker || GetClientTeam(client) == GetClientTeam(attacker))
        {
            return Plugin_Handled;
        }

        stats[client].deaths++;
        g_iKillsPerRound[attacker]++;

        if (!g_isOpKill)
        {
            stats[attacker].open_frags++;
            g_isOpKill = true;
        }

        if (client == attacker)
        {
            if (stats[attacker].kills < 2) 
                stats[attacker].kills = 0;
            else
                stats[attacker].kills--;
        } else {
            stats[attacker].kills++;
        }

        stats[assister].assists++;

        if (attackerBlind == attacker)
        {
            stats[attacker].blinds++;
        }

        if (isPenetrated)
        {
            stats[attacker].penetrateds++;
        }

        if (isHeadshot)
        {
            stats[attacker].headshots++;
        }

        if (isNoScope)
        {
            stats[attacker].noscopes++;
        }

        if (isSmoke)
        {
            stats[attacker].smokes++;
        }

        if((g_flRotation[attacker] < 0.0 ? -g_flRotation[attacker] : g_flRotation[attacker]) > g_flWhirl)
        {
            stats[attacker].whirls++;
        }

        GetEntDataVector(attacker, m_vecVelocity, vecVelocity);

        if(vecVelocity[2])
        {
            stats[attacker].jumps++;
            vecVelocity[2] = 0.0;
        }

        if(GetVectorDistance(NULL_VECTOR, vecVelocity) > g_flMinLenVelocity)
        {
            stats[attacker].runs++;
        }

        if(activeWeapon != -1 && GetEntData(activeWeapon, m_iClip1) == 1)
        {
            stats[attacker].last_clips++;
        }
    }

    return Plugin_Continue;
}



/**
 * create game
 *
 * @return void
 *
 */
stock void CreateGameRequest(JSONObject data)
{
    HTTPRequest http = new HTTPRequest("https://po-rb.ru/api/games/create");
    http.Post(data, OnCreateGame);
}

void OnCreateGame(HTTPResponse response, any client)
{
    if (response.Status != HTTPStatus_OK && response.Status != HTTPStatus_Created) {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("message")) {
            char description[1024];
            data.GetString("message", description, sizeof description);
            
            LogError("[OnCreateGame] Error: %s", description);
        } else {
            LogError("[OnCreateGame] Error: %s", response.Status, jsonResponse);
        }
        
        delete data;
        return;
    } else {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("data")) {
            JSONObject game = view_as<JSONObject>(data.Get("data"));
            g_iGameId = game.GetInt("id");
            game.GetString("team_one_name", g_sTeamOneName, sizeof g_sTeamOneName);
            game.GetString("team_two_name", g_sTeamTwoName, sizeof g_sTeamTwoName);
            
            LogMessage("Матч начался, %s VS %s. ID: %d", g_sTeamOneName, g_sTeamTwoName, g_iGameId);
        }
        delete data;
    }
}


/**
 * end game
 *
 * @return void
 *
 */
stock void EndGameRequest(JSONObject data)
{
    char url[64];
    FormatEx(url, sizeof url, "https://po-rb.ru/api/games/end/%d", g_iGameId);

    HTTPRequest http = new HTTPRequest(url);
    http.Post(data, OnEndGame);
}

void OnEndGame(HTTPResponse response, any client)
{
    if (response.Status != HTTPStatus_OK) {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("message")) {
            char description[1024];
            data.GetString("message", description, sizeof description);

            LogMessage("[OnEndGame] Error: %s", description);
        } else {
            LogMessage("[OnEndGame] Error: %s", jsonResponse);
        }
        
        delete data;
    } else {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("data")) {
            JSONObject game = view_as<JSONObject>(data.Get("data"));
            g_iGameId = 0;

            LogMessage("[OnEndGame]: %d", game.GetInt("id"));
        }
        delete data;
    }
}

/**
 * Обновление данных матча
 *
 * @return void
 *
 */
stock void UpdateGameRequest(JSONObject data)
{
    char url[64];
    FormatEx(url, sizeof url, "https://po-rb.ru/api/games/update/%d", g_iGameId);

    HTTPRequest http = new HTTPRequest(url);
    http.Post(data, OnUpdateGame);
}

void OnUpdateGame(HTTPResponse response, any client)
{
    if (response.Status != HTTPStatus_OK) {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("message")) {
            char description[1024];
            data.GetString("message", description, sizeof description);

            LogMessage("[OnUpdateGame] Error: %s", description);
        } else {
            LogMessage("[OnUpdateGame] Error: %s", jsonResponse);
        }
        
        delete data;
    } else {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("data")) {
            JSONObject game = view_as<JSONObject>(data.Get("data"));

            LogMessage("[OnUpdateGame]: %d", game.GetInt("id"));
        }
        delete data;
    }
}

stock int GetClientIdBySteam(const char[] steamTarget)
{
    char steams[30];
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientConnected(i))
        {
            GetClientAuthId(i, AuthId_Steam2, steams, sizeof(steams));
            if(StrContains(steams, steamTarget, true) != -1)
                return i;
        }
    }

    return -1;
} 


/**
 * create game
 *
 * @return void
 *
 */
stock void PlayerReplaceRequest(JSONObject data, int client)
{
    HTTPRequest http = new HTTPRequest("https://po-rb.ru/api/games/playerReplace");
    http.Post(data, OnPlayerReplaceRequest, client);
}

void OnPlayerReplaceRequest(HTTPResponse response, any client)
{
    if (response.Status != HTTPStatus_OK && response.Status != HTTPStatus_Created) {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("message")) {
            char description[1024];
            data.GetString("message", description, sizeof description);
            
            LogError("[OnPlayerReplaceRequest] Error: %s", description);
        } else {
            LogError("[OnPlayerReplaceRequest] Error: %s", response.Status, jsonResponse);
        }
        
        delete data;
        return;
    } else {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        LogMessage("[OnPlayerReplaceRequest] %s", jsonResponse);
    }
}


void OnPlayerDisconnectRequest(HTTPResponse response, any client)
{
    if (response.Status != HTTPStatus_OK && response.Status != HTTPStatus_Created) {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("message")) {
            char description[1024];
            data.GetString("message", description, sizeof description);
            
            LogError("[OnPlayerDisconnectRequest] Error: %s", description);
        } else {
            LogError("[OnPlayerDisconnectRequest] Error: %s", response.Status, jsonResponse);
        }
        
        delete data;
        return;
    } else {
        /*char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        LogMessage("[OnPlayerDisconnectRequest] %s", jsonResponse);*/
    }
}
