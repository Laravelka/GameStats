#include <clientmod/multicolors>
#include <sourcemod>
#include <clientmod>
#include <sdkhooks>
#include <sdktools>
#include <lvl_ranks>

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

int g_iWhirlInterval = 2,
    m_vecVelocity,
    g_iGameId,
    g_iEloWin = 300,
    g_iEloLose = 200;

float g_flRotation[MAXPLAYERS+1],
    g_flMinLenVelocity = 100.0,
    g_flWhirl = 200.0;

char g_sMapName[128], 
    g_sServerSlug[32], 
    g_sTableName[96], 
    g_sPluginTitle[64];

bool g_isOpKill = false;

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

public void OnPluginStart()
{
    HookEvent("player_death", OnPlayerDeath);
    HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);

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
        kv.ExportToFile(sPath);
    }

    if (kv.ImportFromFile(sPath)) {
        kv.GetString("server", g_sServerSlug, sizeof(g_sServerSlug));
        kv.GetNum("elo_win", g_iEloWin);
        kv.GetNum("elo_lose", g_iEloLose);
    } else {
        SetFailState("[GameStats] KeyValues Error!");
    }
    delete kv;
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
    if (!WarMix_IsMatchLive())
    {
        g_isOpKill = false;
    }
}

void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    //
}

public int WarMix_OnMatchStart(iMatchMode mode, const Players[], int numPlayers)
{
    JSONObject game = new JSONObject();
    JSONArray arrayPlayers = new JSONArray();
    char teamOneName[128], teamTwoName[128];
    int captainOne = WarMix_GetCaptain(2);
    int captainTwo = WarMix_GetCaptain(3);

    if (captainOne != 0) {
        GetClientName(captainOne, teamOneName, sizeof teamOneName);
    } else {
        FormatEx(teamOneName, sizeof teamOneName, "%s", "Team one");
    }

    if (captainTwo != 0) {
        GetClientName(captainTwo, teamTwoName, sizeof teamTwoName);
    } else {
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
        player.SetInt("team", team);
        player.SetString("name", name);
        player.SetString("steam", steam);

        arrayPlayers.Push(player);
        delete player;
    }
    
    game.Set("players", arrayPlayers);
    CreateGameRequest(game);

    delete game;
    delete arrayPlayers;
}

public int WarMix_OnMatchEnd(iMatchMode mode, int winner_team, const winPlayers[], int numWinPlayers, const loosePlayers[], int numLoosePlayers)
{
    JSONObject game = new JSONObject();
    JSONArray arrayPlayers = new JSONArray();

    int scoreOne = WarMix_GetScore(2);
    int scoreTwo = WarMix_GetScore(3);

    game.SetInt("team_winner", winner_team);
    game.SetInt("team_one_score", scoreOne);
    game.SetInt("team_two_score", scoreTwo);
    
    for (int i = 0; i < numWinPlayers; i++)
    {
        char steam[30];
        int client = winPlayers[i];
        int team = GetClientTeam(client);
        GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);
        JSONObject player = new JSONObject();

        player.SetInt("team", team);
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

        arrayPlayers.Push(player);
        ClearPlayer(client);
        delete player;

        LR_ChangeClientValue(client, 300);
        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}За победу вы получаете {green}300 ELO{white}. {green}GG!");
        int newExp = LR_GetClientValue(client);
        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}У вас: {green}%d ELO", newExp);
    }

    for (int i = 0; i < numLoosePlayers; i++)
    {
        char steam[30];
        int client = loosePlayers[i];
        int team = GetClientTeam(client);
        GetClientAuthId(client, AuthId_Steam2, steam, sizeof steam);
        JSONObject player = new JSONObject();
        
        player.SetInt("team", team);
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

        arrayPlayers.Push(player);
        ClearPlayer(client);
        delete player;
    }

    game.Set("players", arrayPlayers);
    EndGameRequest(game);
    delete arrayPlayers;
    delete game;
    
    /*
        

        LR_ChangeClientValue(client, -200);
        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}За поражение вы теряете {red}200 ELO{white}. {orange}В следующий раз повезет!");
        int newExp = LR_GetClientValue(client);
        MC_PrintToChat(client, "{rare}[По-Белорусски] {white}У вас: {green}%d ELO", newExp);
    */
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

    if (IsClientInGame(client) && IsClientInGame(attacker))
    {
        /*char clientSteam[128], attackerSteam[128];
        GetClientAuthId(client, AuthId_Steam2, clientSteam, 30, true);
        GetClientAuthId(client, AuthId_Steam2, attackerSteam, 30, true);*/

        stats[client].deaths++;

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
    if (response.Status != HTTPStatus_OK) {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("message")) {
            char description[1024];
            data.GetString("message", description, sizeof description);

            LogMessage("[OnCreateGame] Error: %s", description);
        } else {
            LogMessage("[OnCreateGame] Error: %s", jsonResponse);
        }
        
        delete data;
        return;
    } else {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        if (data.HasKey("game")) {
            JSONObject game = view_as<JSONObject>(data.Get("game"));
            g_iGameId = game.GetInt("id");

            LogMessage("[OnCreateGame]: %d", g_iGameId);
        }

        // LogMessage("[OnCreateGame]: %s", jsonResponse);
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
        return;
    } else {
        char jsonResponse[2048];
        JSONObject data = view_as<JSONObject>(response.Data);
        data.ToString(jsonResponse, sizeof jsonResponse);

        /*if (data.HasKey("game")) {
            JSONObject game = view_as<JSONObject>(data.Get("game"));
            g_iGameId = game.GetInt("id");

            LogMessage("[OnEndGame]: %d", g_iGameId);
        }*/

        LogMessage("[OnEndGame]: %s", jsonResponse);
        delete data;
    }
}
