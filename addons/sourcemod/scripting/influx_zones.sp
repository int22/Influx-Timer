#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include <influx/core>
#include <influx/zones>

#include <msharedutil/arrayvec>
#include <msharedutil/ents>
#include <msharedutil/misc>

#undef REQUIRE_PLUGIN
#include <influx/zones_beams>
#include <influx/help>


//#define DEBUG
//#define DEBUG_CHECKZONES

#define BUILD_MAT                   "materials/sprites/laserbeam.vmt"
#define BUILD_SPRITE_MAT            "materials/sprites/glow01.vmt"


// Exists for both CSS and CS:GO
#define MAGIC_BRUSH_MODEL       "models/props/cs_office/vending_machine.mdl"


#define ZONE_BUILDDRAW_INTERVAL     0.1

#define BUILD_DEF_DIST              512.0
#define BUILD_MAXDIST               2048.0
#define BUILD_MINDIST               64.0
#define BUILD_DIST_RATE             32.0



enum
{
    ZTYPE_NAME[MAX_ZONE_NAME] = 0,
    ZTYPE_SHORTNAME[MAX_ZONE_NAME],
    
    ZTYPE_TYPE,
    
    ZTYPE_HAS_SETTINGS,
    
    ZTYPE_SIZE
};



ZoneType_t g_iBuildingType[INF_MAXPLAYERS];
float g_vecBuildingStart[INF_MAXPLAYERS][3];
//int g_iBuildingZoneId[INF_MAXPLAYERS];
//int g_iBuildingRunId[INF_MAXPLAYERS];
int g_nBuildingGridSize[INF_MAXPLAYERS];
char g_szBuildingName[INF_MAXPLAYERS][MAX_ZONE_NAME];
bool g_bBuildStart[INF_MAXPLAYERS];
float g_flBuildDist[INF_MAXPLAYERS];



ArrayList g_hZones;
ArrayList g_hZoneTypes;

//int g_nNewZoneId;

int g_iBuildBeamMat;
int g_iBuildSprite;


bool g_bLate;


// CONVARS
ConVar g_ConVar_SaveZonesOnMapEnd;

ConVar g_ConVar_Admin_ConfZonesFlags;
ConVar g_ConVar_Admin_SaveZonesFlags;

ConVar g_ConVar_MinSize;
ConVar g_ConVar_HeightGrace;
ConVar g_ConVar_DefZoneHeight;

ConVar g_ConVar_CrosshairBuild;
ConVar g_ConVar_SpriteSize;


// FORWARDS
Handle g_hForward_OnZoneSettings;

Handle g_hForward_OnPostZoneLoad;
Handle g_hForward_OnZoneLoadPost;
Handle g_hForward_OnZoneLoad;
Handle g_hForward_OnZoneSavePost;
Handle g_hForward_OnZoneSave;

Handle g_hForward_OnZoneBuildAsk;

Handle g_hForward_OnZoneCreated;
Handle g_hForward_OnZoneDeleted;
Handle g_hForward_OnZoneSpawned;

Handle g_hForward_OnRequestZoneTypes;


// LIBRARIES
bool g_bLib_Zones_Beams;


#include "influx_zones/menus.sp"
#include "influx_zones/timers.sp"
#include "influx_zones/natives.sp"

public Plugin myinfo =
{
    author = INF_AUTHOR,
    url = INF_URL,
    name = INF_NAME..." - Zones",
    description = "",
    version = INF_VERSION
};

public APLRes AskPluginLoad2( Handle hPlugin, bool late, char[] szError, int error_len )
{
    // LIBRARIES
    RegPluginLibrary( INFLUX_LIB_ZONES );
    
    // NATIVES
    CreateNative( "Influx_GetZonesArray", Native_GetZonesArray );
    
    CreateNative( "Influx_FindZoneById", Native_FindZoneById );
    
    CreateNative( "Influx_GetZoneName", Native_GetZoneName );
    CreateNative( "Influx_SetZoneName", Native_SetZoneName );
    
    CreateNative( "Influx_GetZoneMinsMaxs", Native_GetZoneMinsMaxs );
    
    CreateNative( "Influx_BuildZone", Native_BuildZone );
    CreateNative( "Influx_DeleteZone", Native_DeleteZone );
    
    CreateNative( "Influx_CanUserModifyZones", Native_CanUserModifyZones );
    
    CreateNative( "Influx_RegZoneType", Native_RegZoneType );
    CreateNative( "Influx_RemoveZoneType", Native_RemoveZoneType );
    
    CreateNative( "Influx_IsValidZoneType", Native_IsValidZoneType );
    CreateNative( "Influx_GetZoneTypeName", Native_GetZoneTypeName );
    CreateNative( "Influx_GetZoneTypeShortName", Native_GetZoneTypeShortName );
    CreateNative( "Influx_GetZoneTypeByShortName", Native_GetZoneTypeByShortName );
    
    
    g_bLate = late;
}

public void OnPluginStart()
{
    // FORWARDS
    g_hForward_OnZoneCreated = CreateGlobalForward( "Influx_OnZoneCreated", ET_Ignore, Param_Cell, Param_Cell, Param_Cell );
    g_hForward_OnZoneDeleted = CreateGlobalForward( "Influx_OnZoneDeleted", ET_Ignore, Param_Cell, Param_Cell );
    g_hForward_OnZoneSpawned = CreateGlobalForward( "Influx_OnZoneSpawned", ET_Ignore, Param_Cell, Param_Cell, Param_Cell );
    
    g_hForward_OnRequestZoneTypes = CreateGlobalForward( "Influx_OnRequestZoneTypes", ET_Ignore );
    
    
    g_hForward_OnPostZoneLoad = CreateGlobalForward( "Influx_OnPostZoneLoad", ET_Ignore );
    
    
    g_hForward_OnZoneLoad = CreateGlobalForward( "Influx_OnZoneLoad", ET_Hook, Param_Cell, Param_Cell, Param_Cell );
    g_hForward_OnZoneLoadPost = CreateGlobalForward( "Influx_OnZoneLoadPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell );
    g_hForward_OnZoneSave = CreateGlobalForward( "Influx_OnZoneSave", ET_Hook, Param_Cell, Param_Cell, Param_Cell );
    g_hForward_OnZoneSavePost = CreateGlobalForward( "Influx_OnZoneSavePost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell );
    
    g_hForward_OnZoneBuildAsk = CreateGlobalForward( "Influx_OnZoneBuildAsk", ET_Hook, Param_Cell, Param_Cell );
    
    g_hForward_OnZoneSettings = CreateGlobalForward( "Influx_OnZoneSettings", ET_Hook, Param_Cell, Param_Cell, Param_Cell );
    
    
    // EVENTS
    if ( GetEngineVersion() == Engine_CSGO )
    {
        HookEvent( "round_poststart", E_RoundRestart, EventHookMode_PostNoCopy );
    }
    else
    {
        HookEvent( "teamplay_round_start", E_RoundRestart, EventHookMode_PostNoCopy );
    }
    
    
    
    // CMDS
#if defined DEBUG_CHECKZONES
    RegAdminCmd( "sm_checkzones", Cmd_Debug_CheckZones, ADMFLAG_ROOT );
#endif

#if defined DEBUG
    RegAdminCmd( "sm_printzonetypes", Cmd_Debug_PrintZoneTypes, ADMFLAG_ROOT );
#endif
    
    RegConsoleCmd( "sm_savezones", Cmd_SaveZones );
    
    RegConsoleCmd( "sm_zone", Cmd_ZoneMain );
    RegConsoleCmd( "sm_zones", Cmd_ZoneMain );
    
    RegConsoleCmd( "sm_createzone", Cmd_CreateZone );
    RegConsoleCmd( "sm_cancelzone", Cmd_CancelZone );
    RegConsoleCmd( "sm_endzone", Cmd_EndZone );
    RegConsoleCmd( "sm_deletezone", Cmd_DeleteZone );
    //RegConsoleCmd( "sm_beamsettings", Cmd_BeamSettings );
    RegConsoleCmd( "sm_zonesettings", Cmd_ZoneSettings );
    RegConsoleCmd( "sm_teletozone", Cmd_ZoneTele );
    
    
    // CONVARS
    g_ConVar_SaveZonesOnMapEnd = CreateConVar( "influx_zones_savezones", "0", "Do we automatically save zones on map end?", FCVAR_NOTIFY, true, 0.0, true, 1.0 );
    
    g_ConVar_Admin_ConfZonesFlags = CreateConVar( "influx_zones_configurezones", "z", "Required flags to configure zones." );
    g_ConVar_Admin_SaveZonesFlags = CreateConVar( "influx_zones_savezones", "z", "Required flags to save zones to a file." );
    
    
    g_ConVar_MinSize = CreateConVar( "influx_zones_minzonesize", "4", "Minimum size of a zone in X, Y and Z.", FCVAR_NOTIFY, true, 1.0 );
    g_ConVar_HeightGrace = CreateConVar( "influx_zones_heightgrace", "4", "If zone height is smaller than this, use default zone height. 0 = disable", FCVAR_NOTIFY, true, 0.0 );
    g_ConVar_DefZoneHeight = CreateConVar( "influx_zones_defzoneheight", "128", "Default zone height to use.", FCVAR_NOTIFY, true, 0.0 );
    
    g_ConVar_CrosshairBuild = CreateConVar( "influx_zones_crosshairbuild", "1", "Use crosshair to build instead of your position.", FCVAR_NOTIFY, true, 0.0, true, 1.0 );
    g_ConVar_SpriteSize = CreateConVar( "influx_zones_buildspritesize", "0.2", "Size of the sprite when lining the start of the zone.", FCVAR_NOTIFY, true, 0.0 );
    
    
    AutoExecConfig( true, "zones", "influx" );
    
    
    // LIBRARIES
    g_bLib_Zones_Beams = LibraryExists( INFLUX_LIB_ZONES_BEAMS );
    
    
    g_hZones = new ArrayList( ZONE_SIZE );
    g_hZoneTypes = new ArrayList( ZTYPE_SIZE );
}

public void OnLibraryAdded( const char[] lib )
{
    if ( StrEqual( lib, INFLUX_LIB_ZONES_BEAMS ) ) g_bLib_Zones_Beams = true;
}

public void OnLibraryRemoved( const char[] lib )
{
    if ( StrEqual( lib, INFLUX_LIB_ZONES_BEAMS ) ) g_bLib_Zones_Beams = false;
}

public void OnAllPluginsLoaded()
{
    if ( g_bLate )
    {
        Call_StartForward( g_hForward_OnRequestZoneTypes );
        Call_Finish();
    }
}

public void Influx_RequestHelpCmds()
{
    Influx_AddHelpCommand( "zone", "Display zone menu.", true );
    Influx_AddHelpCommand( "savezones", "Saves all current zones.", true );
}

public void Influx_OnPreRunLoad()
{
    // OnMapStart but make sure it's done before zones are loaded.
    if ( !PrecacheModel( MAGIC_BRUSH_MODEL ) )
    {
        SetFailState( INF_CON_PRE..."Couldn't precache brush model '%s'!", MAGIC_BRUSH_MODEL );
    }
    
    if ( !(g_iBuildBeamMat = PrecacheModel( BUILD_MAT )) )
    {
        SetFailState( INF_CON_PRE..."Couldn't precache building beam material '%s'!", BUILD_MAT );
    }
    
    if ( !(g_iBuildSprite = PrecacheModel( BUILD_SPRITE_MAT )) )
    {
        SetFailState( INF_CON_PRE..."Couldn't precache building sprite material '%s'!", BUILD_SPRITE_MAT );
    }
    
    
    g_hZones.Clear();
}

public void OnMapEnd()
{
    if ( g_ConVar_SaveZonesOnMapEnd.BoolValue )
    {
        WriteZoneFile();
    }
}

public void Influx_OnPostRunLoad()
{
    ReadZoneFile();
    
    Call_StartForward( g_hForward_OnPostZoneLoad );
    Call_Finish();
    
    //g_nNewZoneId = FindZoneHighestId() + 1;
}

public void OnClientPutInServer( int client )
{
    g_iBuildingType[client] = ZONETYPE_INVALID;
    g_nBuildingGridSize[client] = 8;
    g_szBuildingName[client][0] = '\0';
    g_bBuildStart[client] = false;
    g_flBuildDist[client] = BUILD_DEF_DIST;
    
    
    CheckZones();
}

public void E_RoundRestart( Event event, const char[] szEvent, bool bImUselessWhyDoIExist )
{
    CreateTimer( 0.2, T_RoundRestart_Delay, _, TIMER_FLAG_NO_MAPCHANGE );
}

public Action T_RoundRestart_Delay( Handle hTimer )
{
    CheckZones();
}

stock void ReadZoneFile()
{
    char szPath[PLATFORM_MAX_PATH];
    BuildPath( Path_SM, szPath, sizeof( szPath ), "influxzones" );
    
    if ( !DirExistsEx( szPath ) ) return;
    
    
    char szMap[64];
    GetCurrentMapSafe( szMap, sizeof( szMap ) );
    Format( szPath, sizeof( szPath ), "%s/%s.ini", szPath, szMap );
    
    
    KeyValues kv = new KeyValues( "Zones" );
    kv.ImportFromFile( szPath );
    
    if ( !kv.GotoFirstSubKey() )
    {
        delete kv;
        return;
    }
    
    
    decl data[ZONE_SIZE];
    
    float mins[3], maxs[3];
    ZoneType_t zonetype;
    int zoneid;
    
    char szType[32];
    
    do
    {
        kv.GetString( "type", szType, sizeof( szType ), "" );
        
        if ( IsCharNumeric( szType[0] ) )
        {
            zonetype = view_as<ZoneType_t>( StringToInt( szType ) );
        }
        else
        {
            zonetype = FindZoneTypeByShortName( szType );
        }
        
        if ( zonetype == ZONETYPE_INVALID || FindZoneType( zonetype ) == -1 )
        {
            //LogError( INF_CON_PRE..."Found invalid zone type %i!", zonetype );
            continue;
        }
        
        zoneid = kv.GetNum( "id", -1 );
        if ( zoneid < 1 )
        {
            LogError( INF_CON_PRE..."Found invalid zone id value! (id: %i)", zoneid );
            continue;
        }
        
        
        if ( FindZoneById( zoneid ) != -1 )
        {
            LogError( INF_CON_PRE..."Found duplicate zone id! (id: %i)", zoneid );
            continue;
        }
        
        kv.GetVector( "mins", mins, ORIGIN_VECTOR );
        kv.GetVector( "maxs", maxs, ORIGIN_VECTOR );
        
        if ( GetVectorDistance( mins, maxs, false ) < 1.0 )
        {
            LogError( INF_CON_PRE..."Invalid zone mins and maxs! (id: %i)", zoneid );
            continue;
        }
        
        
        kv.GetSectionName( view_as<char>( data[ZONE_NAME] ), MAX_ZONE_NAME );
        
        
        // Ask other plugins what to load.
        Action res;
        
        Call_StartForward( g_hForward_OnZoneLoad );
        Call_PushCell( zoneid );
        Call_PushCell( zonetype );
        Call_PushCell( view_as<int>( kv ) );
        Call_Finish( res );
        
        if ( res != Plugin_Handled )
        {
            if ( res == Plugin_Stop )
            {
                LogError( INF_CON_PRE..."Couldn't load zone %s with type %i from file! (id: %i)", data[ZONE_NAME], zonetype, zoneid );
            }
            
            continue;
        }
        
        // Post load (this zone will be loaded)
        Call_StartForward( g_hForward_OnZoneLoadPost );
        Call_PushCell( zoneid );
        Call_PushCell( zonetype );
        Call_PushCell( view_as<int>( kv ) );
        Call_Finish();
        
        
        
        data[ZONE_ID] = zoneid;
        data[ZONE_TYPE] = view_as<int>( zonetype );
        
        CopyArray( mins, data[ZONE_MINS], 3 );
        CopyArray( maxs, data[ZONE_MAXS], 3 );
        
        
        CreateZoneEntityByIndex( g_hZones.PushArray( data ) );
    }
    while( kv.GotoNextKey() );
    
    delete kv;
    
    
    //CheckRuns();
}

stock int WriteZoneFile()
{
    int len = g_hZones.Length;
    if ( len < 1 ) return 0;
    
    
    
    
    decl String:szMap[64];
    decl String:szPath[PLATFORM_MAX_PATH];
    GetCurrentMapSafe( szMap, sizeof( szMap ) );
    
    BuildPath( Path_SM, szPath, sizeof( szPath ), "influxzones/%s.ini", szMap );
    
    
    int num = 0;

    decl data[ZONE_SIZE];
    decl String:szBuffer[64];
    decl zoneid;
    ZoneType_t zonetype;
    int itype;
    
    
    KeyValues kv = new KeyValues( "Zones" );
    
    for ( int i = 0; i < len; i++ )
    {
        g_hZones.GetArray( i, data, sizeof( data ) );
        
        zoneid = data[ZONE_ID];
        if ( zoneid < 1 ) continue;
        
        
        zonetype = view_as<ZoneType_t>( data[ZONE_TYPE] );
        
        itype = FindZoneType( zonetype );
        if ( itype == -1 )
        {
            continue;
        }
        
        if ( !kv.JumpToKey( view_as<char>( data[ZONE_NAME] ), true ) )
        {
            continue;
        }
        
        
        // Ask other plugins what to save.
        Action res;
        
        Call_StartForward( g_hForward_OnZoneSave );
        Call_PushCell( zoneid );
        Call_PushCell( zonetype );
        Call_PushCell( view_as<int>( kv ) );
        Call_Finish( res );
        
        if ( res != Plugin_Handled )
        {
            if ( res == Plugin_Stop )
            {
                LogError( INF_CON_PRE..."Couldn't save zone %s (id: %i) with type %i!", data[ZONE_NAME], zoneid, zonetype );
            }
            
            kv.DeleteThis();
            //kv.GoBack();
            continue;
        }
        
        // Post save (this zone will be saved)
        Call_StartForward( g_hForward_OnZoneSavePost );
        Call_PushCell( zoneid );
        Call_PushCell( zonetype );
        Call_PushCell( view_as<int>( kv ) );
        Call_Finish();
        
        
        
        kv.SetNum( "id", zoneid );
        
        
        GetZoneTypeShortNameByIndex( itype, szBuffer, sizeof( szBuffer ) );
        kv.SetString( "type", szBuffer );
        
        
        FormatEx( szBuffer, sizeof( szBuffer ), "%.1f %.1f %.1f",
            data[ZONE_MINS],
            data[ZONE_MINS + 1],
            data[ZONE_MINS + 2] );
        kv.SetString( "mins", szBuffer );
        
        FormatEx( szBuffer, sizeof( szBuffer ), "%.1f %.1f %.1f",
            data[ZONE_MAXS],
            data[ZONE_MAXS + 1],
            data[ZONE_MAXS + 2] );
        kv.SetString( "maxs", szBuffer );
        
        kv.GoBack();
        
        ++num;
    }
    
    
    if ( num )
    {
        kv.Rewind();
        
        if ( !kv.ExportToFile( szPath ) )
        {
            LogError( INF_CON_PRE..."Can't save zone file '%s'!!", szPath );
        }
    }
    else
    {
        LogError( INF_CON_PRE..."No valid zones exist to save. Can't save zone file '%s'!", szPath );
    }
    
    
    delete kv;
    
    return num;
}

#if defined DEBUG_CHECKZONES
public Action Cmd_Debug_CheckZones( int client, int args )
{
    CheckZones( client );
    
    return Plugin_Handled;
}
#endif

#if defined DEBUG
public Action Cmd_Debug_PrintZoneTypes( int client, int args )
{
    if ( client ) return Plugin_Handled;
    
    
    decl data[ZTYPE_SIZE];
    
    int len = g_hZoneTypes.Length;
    for ( int i = 0; i < len; i++ )
    {
        g_hZoneTypes.GetArray( i, data );
        
        PrintToServer( "%i | %s | %s", data[ZTYPE_TYPE], data[ZTYPE_NAME], data[ZTYPE_SHORTNAME] );
    }
    
    if ( !len )
    {
        PrintToServer( "None!" );
    }
    
    return Plugin_Handled;
}
#endif

stock void CheckZones( int issuer = 0 )
{
    int num = 0;
    
    int len = g_hZones.Length;
    for ( int i = 0; i < len; i++ )
    {
        if ( EntRefToEntIndex( g_hZones.Get( i, ZONE_ENTREF ) ) < 1 )
        {
            if ( CreateZoneEntityByIndex( i ) != -1 )
                ++num;
        }
    }
    
    if ( num )
    {
        PrintToServer( INF_CON_PRE..."Spawned %i zones!", num );
        
        if ( IS_ENT_PLAYER( issuer ) && IsClientInGame( issuer ) )
        {
            Influx_PrintToChat( _, issuer, "Spawned {MAINCLR1}%i{CHATCLR} zones!", num );
        }
    }
}

stock void RoundVector( float vec[3] )
{
    for ( int i = 0; i < 3; i++ ) vec[i] = float( RoundFloat( vec[i] ) );
}

stock void SnapToGrid( float vec[3], int grid, int axis = 2 )
{
    if ( axis < 0 ) axis = 0;
    else if ( axis > 3 ) axis = 3;
    
    for ( int i = 0; i < axis; i++ )
    {
        vec[i] = Inf_SnapTo( vec[i], grid );
    }
}

stock bool StartToBuild( int client, ZoneType_t zonetype, const char[] name = "" )
{
    if ( !VALID_ZONETYPE( zonetype ) ) return false;
    
    
    g_iBuildingType[client] = zonetype;
    
    float pos[3];
    
    if ( g_ConVar_CrosshairBuild.BoolValue )
    {
        GetEyeTrace( client, pos );
    }
    else
    {
        GetClientAbsOrigin( client, pos );
    }
    
    SnapToGrid( pos, g_nBuildingGridSize[client], 2 );
    RoundVector( pos );
    
    
    g_vecBuildingStart[client] = pos;
    
    
    CreateTimer( ZONE_BUILDDRAW_INTERVAL, T_DrawBuildBeams, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
    
    
    char szName[MAX_ZONE_NAME];
    
    if ( name[0] != '\0' )
    {
        strcopy( g_szBuildingName[client], sizeof( g_szBuildingName[] ), name );
        
        strcopy( szName, sizeof( szName ), name );
    }
    else
    {
        g_szBuildingName[client][0] = '\0';
        
        GetZoneTypeName( zonetype, szName, sizeof( szName ) );
    }
    
    
    Influx_PrintToChat( _, client, "Started building {MAINCLR1}%s{CHATCLR}!", szName );
    
    return true;
}

stock int GetZoneTypeCount( ZoneType_t zonetype )
{
    int count = 0;
    
    int len = g_hZones.Length;
    if ( len > 0 )
    {
        for ( int i = 0; i < len; i++  )
        {
            if ( view_as<ZoneType_t>( g_hZones.Get( i, ZONE_TYPE ) ) == zonetype )
            {
                ++count;
            }
        }
    }
    
    return count;
}

stock int GetZoneFromPos( int startindex, const float pos[3] )
{
    if ( startindex < 0 ) startindex = 0;
    
    
    int len = g_hZones.Length;
    if ( startindex >= len ) return -1;
    
    
    float mins[3], maxs[3];
    int data[ZONE_SIZE];
    
    for ( int i = startindex; i < len; i++ )
    {
        g_hZones.GetArray( i, data, sizeof( data ) );
        
        CopyArray( data[ZONE_MINS], mins, 3 );
        CopyArray( data[ZONE_MAXS], maxs, 3 );
        
        if ( IsInsideBounds( pos, mins, maxs ) )
        {
            return i;
        }
    }
    
    return -1;
}

stock int CreateZoneEntity( int zoneid )
{
    int index = FindZoneById( zoneid );
    if ( index == -1 ) return -1;
    
    
    return CreateZoneEntityByIndex( index );
}

stock int CreateZoneEntityByIndex( int index )
{
    float mins[3], maxs[3];
    GetZoneMinsMaxsByIndex( index, mins, maxs );
    
    int ent = CreateTriggerEnt( mins, maxs );
    if ( ent < 1 ) return -1;
    
    g_hZones.Set( index, EntIndexToEntRef( ent ), ZONE_ENTREF );
    
    
    Call_StartForward( g_hForward_OnZoneSpawned );
    Call_PushCell( g_hZones.Get( index, ZONE_ID ) );
    Call_PushCell( g_hZones.Get( index, ZONE_TYPE ) );
    Call_PushCell( ent );
    Call_Finish();
    
    return ent;
}

stock int CreateZone( int client, const float mins[3], const float maxs[3], ZoneType_t zonetype )
{
    char szName[MAX_ZONE_NAME];
    
    if ( g_szBuildingName[client][0] == '\0' )
    {
        GetZoneTypeName( zonetype, szName, sizeof( szName ) );
        
        Format( szName, sizeof( szName ), "%s #%i", szName, GetZoneTypeCount( zonetype ) + 1 );
    }
    else
    {
        strcopy( szName, sizeof( szName ), g_szBuildingName[client] );
    }
    
    
    
    
    // Find unused zone id.
    int zoneid = 1;
    for ( int i = 0; i < g_hZones.Length; )
    {
        if ( g_hZones.Get( i, ZONE_ID ) == zoneid )
        {
            ++zoneid;
            i = 0;
        }
        else
        {
            ++i;
        }
    }
    
    //int zoneid = g_nNewZoneId++;
    
    int data[ZONE_SIZE];
    
    data[ZONE_TYPE] = view_as<int>( zonetype );
    data[ZONE_ID] = zoneid;
    CopyArray( mins, data[ZONE_MINS], 3 );
    CopyArray( maxs, data[ZONE_MAXS], 3 );
    
    int index = g_hZones.PushArray( data );
    
    SetZoneNameByIndex( index, szName );
    
    
    Call_StartForward( g_hForward_OnZoneCreated );
    Call_PushCell( client );
    Call_PushCell( zoneid );
    Call_PushCell( zonetype );
    Call_Finish();
    
    
    g_iBuildingType[client] = ZONETYPE_INVALID;
    
    // Get name again in case it was updated.
    GetZoneName( zoneid, szName, sizeof( szName ) );
    
    Influx_PrintToChat( _, client, "Created zone {MAINCLR1}%s{CHATCLR}!", szName );
    
    
    // May be changed above.
    return CreateZoneEntity( zoneid );
}

stock int GetZoneNameCount( const char[] szName )
{
    int num = 0;
    
    char szComp[32];
    
    int len = g_hZones.Length;
    for ( int i = 0; i < len; i++ )
    {
        GetZoneNameByIndex( i, szComp, sizeof( szComp ) )
        
        if ( StrContains( szComp, szName, false ) == 0 )
        {
            ++num;
        }
    }
    
    return num;
}

stock void GetZoneName( int id, char[] sz, int len )
{
    GetZoneNameByIndex( FindZoneById( id ), sz, len );
}

stock void GetZoneNameByIndex( int index, char[] sz, int len )
{
    if ( index == -1 ) return;
    
    
    g_hZones.GetString( index, sz, len );
}

stock void GetZoneMinsMaxsByIndex( int index, float mins_out[3], float maxs_out[3] )
{
    mins_out[0] = g_hZones.Get( index, ZONE_MINS );
    mins_out[1] = g_hZones.Get( index, ZONE_MINS + 1 );
    mins_out[2] = g_hZones.Get( index, ZONE_MINS + 2 );
    
    maxs_out[0] = g_hZones.Get( index, ZONE_MAXS );
    maxs_out[1] = g_hZones.Get( index, ZONE_MAXS + 1 );
    maxs_out[2] = g_hZones.Get( index, ZONE_MAXS + 2 );
}

stock void DeleteZoneWithClient( int client, int index )
{
    if ( index <= -1 )
    {
        Influx_PrintToChat( _, client, "Couldn't find a zone!" );
        return;
    }
    
    
    decl String:szZone[MAX_ZONE_NAME];
    g_hZones.GetString( index, szZone, sizeof( szZone ) );
    
    if ( DeleteZoneByIndex( index ) )
    {
        Influx_PrintToChat( _, client, "Deleted {MAINCLR1}%s{CHATCLR}!", szZone );
    }
    else
    {
        Influx_PrintToChat( _, client, "Couldn't delete {MAINCLR1}%s{CHATCLR}!", szZone );
    }
}

stock bool DeleteZone( int id )
{
    int index = FindZoneById( id );
    
    return DeleteZoneByIndex( index );
}

stock bool DeleteZoneByIndex( int index )
{
    if ( !VALID_ARRAY_INDEX( g_hZones, index ) )
        return false;
    
    
    int ent = EntRefToEntIndex( g_hZones.Get( index, ZONE_ENTREF ) );
    
    if ( ent > 0 && !KillEntity( ent ) )
    {
        LogError( "Couldn't kill zone entity! (%i)", ent );
    }
    
    
    int zoneid = g_hZones.Get( index, ZONE_ID );
    ZoneType_t zonetype = view_as<ZoneType_t>( g_hZones.Get( index, ZONE_TYPE ) );
    
    
    g_hZones.Erase( index );
    
    Call_StartForward( g_hForward_OnZoneDeleted );
    Call_PushCell( zoneid );
    Call_PushCell( zonetype );
    Call_Finish();
    
    return true;
}

stock int FindZoneHighestId()
{
    int highest = 0;
    
    int len = g_hZones.Length;
    
    if ( len > 0 )
    {
        for ( int i = 0; i < len; i++ )
        {
            if ( g_hZones.Get( i, ZONE_ID ) > highest )
            {
                highest = g_hZones.Get( i, ZONE_ID );
            }
        }
    }
    
    return highest;
}

stock int FindZoneById( int zoneid )
{
    int len = g_hZones.Length;
    if ( len > 0 )
    {
        for ( int i = 0; i < len; i++ )
        {
            if ( g_hZones.Get( i, ZONE_ID ) == zoneid )
            {
                return i;
            }
        }
    }
    
    return -1;
}

stock bool CanUserModifyZones( int client )
{
    if ( client == 0 ) return true;
    
    
    decl String:szFlags[32];
    g_ConVar_Admin_ConfZonesFlags.GetString( szFlags, sizeof( szFlags ) );
    
    int wantedflags = ReadFlagString( szFlags );
    
    return ( (GetUserFlagBits( client ) & wantedflags) == wantedflags );
}

stock bool CanUserSaveZones( int client )
{
    if ( client == 0 ) return true;
    
    
    decl String:szFlags[32];
    g_ConVar_Admin_SaveZonesFlags.GetString( szFlags, sizeof( szFlags ) );
    
    int wantedflags = ReadFlagString( szFlags );
    
    return ( (GetUserFlagBits( client ) & wantedflags) == wantedflags );
}

stock void StartShowBuild( int client )
{
    if ( g_bBuildStart[client] )
    {
        g_bBuildStart[client] = false;
        return;
    }
    
    
    CreateTimer( ZONE_BUILDDRAW_INTERVAL, T_DrawBuildStart, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
    
    g_bBuildStart[client] = true;
}

stock void GetEyeTrace( int client, float pos[3] )
{
    decl Float:temp[3];
    
    GetClientEyePosition( client, pos );
    GetClientEyeAngles( client, temp );
    
    GetAngleVectors( temp, temp, NULL_VECTOR, NULL_VECTOR );
    
    for ( int i = 0; i < 3; i++ ) temp[i] = pos[i] + temp[i] * g_flBuildDist[client];
    
    TR_TraceRayFilter( pos, temp, MASK_SOLID, RayType_EndPoint, TraceFilter_Build );
    
    TR_GetEndPosition( pos );
}

public bool TraceFilter_Build( int ent, int mask )
{
    return ( ent == 0 || ent > MaxClients );
}

stock void HandleTraceDist( int client )
{
    // Poor man's version.
    int buttons = GetEntProp( client, Prop_Data, "m_nOldButtons" );
    
    if ( buttons & IN_ATTACK )
    {
        g_flBuildDist[client] += BUILD_DIST_RATE;
    }
    else if ( buttons & IN_ATTACK2 )
    {
        g_flBuildDist[client] -= BUILD_DIST_RATE;
    }
    
    if ( g_flBuildDist[client] > BUILD_MAXDIST )
    {
        g_flBuildDist[client] = BUILD_MAXDIST;
    }
    else if ( g_flBuildDist[client] < BUILD_MINDIST )
    {
        g_flBuildDist[client] = BUILD_MINDIST;
    }
}

stock int CreateTriggerEnt( const float mins[3], const float maxs[3] )
{
    int ent = CreateEntityByName( "trigger_multiple" );
    
    if ( ent < 1 )
    {
        LogError( INF_CON_PRE..."Couldn't create trigger entity!" );
        return -1;
    }
    
    
    DispatchKeyValue( ent, "wait", "0" );
    
#define SF_CLIENTS  1
#define SF_NOBOTS   4096
    
    char szSpawn[16];
    FormatEx( szSpawn, sizeof( szSpawn ), "%i", SF_CLIENTS | SF_NOBOTS );
    DispatchKeyValue( ent, "spawnflags", szSpawn ); 
    
    if ( !DispatchSpawn( ent ) )
    {
        LogError( INF_CON_PRE..."Couldn't spawn trigger entity!" );
        return -1;
    }
    
    
    float origin[3], newmins[3], newmaxs[3];
    
    ActivateEntity( ent );
    
    
    SetEntityModel( ent, MAGIC_BRUSH_MODEL );
    
    
#define EF_NODRAW   32
    
    SetEntProp( ent, Prop_Send, "m_fEffects", EF_NODRAW );
    
    
    newmaxs[0] = ( maxs[0] - mins[0] ) * 0.5;
    newmaxs[1] = ( maxs[1] - mins[1] ) * 0.5;
    newmaxs[2] = ( maxs[2] - mins[2] ) * 0.5;
    
    origin[0] = mins[0] + newmaxs[0];
    origin[1] = mins[1] + newmaxs[1];
    origin[2] = mins[2] + newmaxs[2];
    
    
    TeleportEntity( ent, origin, NULL_VECTOR, NULL_VECTOR );
    
    
    newmins[0] = -newmaxs[0];
    newmins[1] = -newmaxs[1];
    newmins[2] = -newmaxs[2];
    
    SetEntPropVector( ent, Prop_Send, "m_vecMins", newmins );
    SetEntPropVector( ent, Prop_Send, "m_vecMaxs", newmaxs );
    SetEntProp( ent, Prop_Send, "m_nSolidType", 2 ); // Essential! Use bounding box instead of model's bsp(?) for input.
    
    return ent;
}

stock bool AddZoneType( ZoneType_t type, const char[] szName, const char[] szShortName, bool bHasSettings )
{
    if ( FindZoneType( type ) != -1 ) return false;
    
    
    int data[ZTYPE_SIZE];
    
    strcopy( view_as<char>( data[ZTYPE_NAME] ), MAX_ZONE_NAME, szName );
    strcopy( view_as<char>( data[ZTYPE_SHORTNAME] ), MAX_ZONE_NAME, szShortName );
    
    data[ZTYPE_TYPE] = view_as<int>( type );
    data[ZTYPE_HAS_SETTINGS] = bHasSettings;
    
    g_hZoneTypes.PushArray( data );
    
    return true;
}

stock bool RemoveZoneType( ZoneType_t type )
{
    int index = FindZoneType( type );
    
    if ( index != -1 )
    {
        g_hZoneTypes.Erase( index );
        return true;
    }
    
    return false;
}

stock int FindZoneType( ZoneType_t type )
{
    int len = g_hZoneTypes.Length;
    for ( int i = 0; i < len; i++ )
    {
        if ( g_hZoneTypes.Get( i, ZTYPE_TYPE ) == view_as<int>( type ) )
        {
            return i;
        }
    }
    
    return -1;
}

stock void GetZoneTypeName( ZoneType_t type, char[] sz, int len )
{
    GetZoneTypeNameByIndex( FindZoneType( type ), sz, len );
}

stock void GetZoneTypeNameByIndex( int index, char[] sz, int len )
{
    if ( index != -1 )
    {
        g_hZoneTypes.GetString( index, sz, len );
    }
    else
    {
        strcopy( sz, len, "N/A" );
    }
}

stock void GetZoneTypeShortName( ZoneType_t type, char[] sz, int len )
{
    GetZoneTypeShortNameByIndex( FindZoneType( type ), sz, len );
}

stock void GetZoneTypeShortNameByIndex( int index, char[] sz, int len )
{
    if ( index != -1 )
    {
        decl name[MAX_ZONE_NAME_CELL];
        
        for ( int i = 0; i < MAX_ZONE_NAME_CELL; i++ )
        {
            name[i] = g_hZoneTypes.Get( index, ZTYPE_SHORTNAME + i ); 
        }
        
        strcopy( sz, len, view_as<char>( name ) );
    }
    else
    {
        strcopy( sz, len, "N/A" );
    }
}

stock ZoneType_t FindZoneTypeByShortName( const char[] sz )
{
    decl String:szName[32];
    
    int len = g_hZoneTypes.Length;
    for ( int i = 0; i < len; i++ )
    {
        GetZoneTypeShortNameByIndex( i, szName, sizeof( szName ) );
        
        if ( StrEqual( sz, szName ) )
        {
            return view_as<ZoneType_t>( g_hZoneTypes.Get( i, ZTYPE_TYPE ) );
        }
    }
    
    return ZONETYPE_INVALID;
}

// This stock name is giving me cancer.
stock bool ZoneTypeHasSettings( ZoneType_t type )
{
    int i = FindZoneType( type );
    if ( i == -1 ) return false;
    
    return g_hZoneTypes.Get( i, ZTYPE_HAS_SETTINGS );
}

stock void SetZoneName( int zoneid, const char[] szName )
{
    SetZoneNameByIndex( FindZoneById( zoneid ), szName );
}

stock void SetZoneNameByIndex( int index, const char[] szName )
{
    if ( index == -1 ) return;
    
    
    char sz[MAX_ZONE_NAME];
    
    strcopy( sz, sizeof( sz ), szName );
    
    
    // Make sure our name isn't already taken.
    int num = GetZoneNameCount( sz );
    if ( num )
    {
        Format( sz, sizeof( sz ), "%s (%i)", sz, num + 1 );
    }
    
    
    g_hZones.SetString( index, sz );
}