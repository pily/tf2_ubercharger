/**
 * vim: set ai et ts=4 sw=4 :
 * File: ubercharger.sp
 * Description: Medic Uber Charger for TF2
 * Author(s): -=|JFH|=-Naris (Murray Wilson)
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

#define PL_VERSION "1.0.3"

#define SOUND_BLIP		"buttons/blip1.wav"

public Plugin:myinfo = 
{
    name = "TF2 Uber Charger",
    author = "-=|JFH|=-Naris",
    description = "Continously recharges Medic's Uber",
    version = PL_VERSION,
    url = "http://www.jigglysfunhouse.net/"
}

// Charged sounds
new const String:Charged[][] = { "vo/medic_autochargeready01.wav",
                                 "vo/medic_autochargeready02.wav",
                                 "vo/medic_autochargeready03.wav"};

// Basic color arrays for temp entities
new const redColor[4] = {255, 75, 75, 255};
new const greenColor[4] = {75, 255, 75, 255};
new const blueColor[4] = {75, 75, 255, 255};
new const greyColor[4] = {128, 128, 128, 255};

// Following are model indexes for temp entities
new g_BeamSprite;
new g_HaloSprite;

new Float:g_ChargeDelay = 5.0;
new Float:g_BeaconDelay = 3.0;
new Float:g_PingDelay = 12.0;

new Float:g_lastChargeTime = 0.0;
new Float:g_lastBeaconTime = 0.0;
new Float:g_lastPingTime = 0.0;

new Handle:g_IsUberchargerOn = INVALID_HANDLE;
new Handle:g_EnableBeacon = INVALID_HANDLE;
new Handle:g_BeaconRadius = INVALID_HANDLE;
new Handle:g_BeaconTimer = INVALID_HANDLE;
new Handle:g_ChargeAmount1 = INVALID_HANDLE;
new Handle:g_ChargeAmount2 = INVALID_HANDLE;
new Handle:g_ChargeAmount3 = INVALID_HANDLE;
new Handle:g_ChargeTimer1 = INVALID_HANDLE;
new Handle:g_ChargeTimer2 = INVALID_HANDLE;
new Handle:g_ChargeTimer3 = INVALID_HANDLE;
new Handle:g_EnablePing = INVALID_HANDLE;
new Handle:g_PingTimer = INVALID_HANDLE;
new Handle:g_TimerHandle1 = INVALID_HANDLE;
new Handle:g_TimerHandle2 = INVALID_HANDLE;
new Handle:g_TimerHandle3 = INVALID_HANDLE;
new bool:ConfigsExecuted = false;
new bool:NativeControl = false;
new bool:NativeMedicEnabled[MAXPLAYERS + 1] = { false, ...};
new Float:NativeAmount[MAXPLAYERS + 1];

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    // Register Natives
    CreateNative("ControlUberCharger",Native_ControlUberCharger);
    CreateNative("SetUberCharger",Native_SetUberCharger);
    RegPluginLibrary("ubercharger");
    return APLRes_Success;
}

/**
 * Description: Stocks to return information about TF2 UberCharge.
 */
#tryinclude <tf2_uber>
#if !defined _tf2_uber_included
    stock Float:TF2_GetUberLevel(client)
    {
        new index = GetPlayerWeaponSlot(client, 1);
        if (index > 0)
            return GetEntPropFloat(index, Prop_Send, "m_flChargeLevel");
        else
            return 0.0;
    }

    stock TF2_SetUberLevel(client, Float:uberlevel)
    {
        new index = GetPlayerWeaponSlot(client, 1);
        if (index > 0)
            SetEntPropFloat(index, Prop_Send, "m_flChargeLevel", uberlevel);
    }
#endif

/**
 * Description: Functions to return information about weapons.
 */
#tryinclude <weapons>
#if !defined _weapons_included
    stock GetCurrentWeaponClass(client, String:name[], maxlength)
    {
        new index = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        if (index > 0)
            GetEntityNetClass(index, name, maxlength);
    }
#endif

public OnPluginStart()
{
    g_IsUberchargerOn = CreateConVar("sm_ubercharger","1","Enable/Disable ubercharger",0);
    g_ChargeAmount1 = CreateConVar("sm_ubercharger_charge_amount1", "0.35", "Sets the amount of uber charge to add time for medigun.",
                                  0, true, 0.0, true, 1.0);
    g_ChargeAmount2 = CreateConVar("sm_ubercharger_charge_amount2", "0.33", "Sets the amount of uber charge to add time for quick-fix.",
                                0, true, 0.0, true, 1.0);
    g_ChargeAmount3 = CreateConVar("sm_ubercharger_charge_amount3", "0.25", "Sets the amount of uber charge to add time for vaccinator.",
                                0, true, 0.0, true, 1.0);

    g_ChargeTimer1 = CreateConVar("sm_ubercharger_charge_timer1", "1.0", "Sets the time interval for medigun",0);
    g_ChargeTimer2 = CreateConVar("sm_ubercharger_charge_timer2", "1.0", "Sets the time interval for quick-fix",0);
    g_ChargeTimer3 = CreateConVar("sm_ubercharger_charge_timer3", "3.0", "Sets the time interval for vaccinator",0);

    g_EnableBeacon = CreateConVar("sm_ubercharger_beacon","1","Enable/Disable ubercharger beacon",0);
    g_BeaconTimer = CreateConVar("sm_ubercharger_beacon_timer","3.0","Sets the time interval of beacons for ubercharger",0);
    g_BeaconRadius = CreateConVar("sm_ubercharger_beacon_radius", "375", "Sets the radius for medic enhancer beacon's light rings.",
                                  0, true, 50.0, true, 1500.0);

    g_EnablePing = CreateConVar("sm_ubercharger_ping","1","Enable/Disable ubercharger ping",0);
    g_PingTimer = CreateConVar("sm_ubercharger_ping_timer", "12.0", "Sets the time interval of pings for ubercharger.",0);

    // Execute the config file
    AutoExecConfig(true, "sm_ubercharger");

    CreateConVar("sm_tf_ubercharger", PL_VERSION, "TF2 Medic Uber Charger Version", 0|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
}

public OnConfigsExecuted()
{
    if (NativeControl || GetConVarBool(g_IsUberchargerOn))
    {
        if (g_TimerHandle1 == INVALID_HANDLE)
            g_TimerHandle1 = CreateTimer(CalcDelay1(), Medic_Timer1, _, TIMER_REPEAT);
        if (g_TimerHandle2 == INVALID_HANDLE)
            g_TimerHandle2 = CreateTimer(CalcDelay2(), Medic_Timer2, _, TIMER_REPEAT);
        if (g_TimerHandle3 == INVALID_HANDLE)
            g_TimerHandle3 = CreateTimer(CalcDelay3(), Medic_Timer3, _, TIMER_REPEAT);
    }

    ConfigsExecuted = true;
}

public OnMapStart()
{
    PrecacheSound(SOUND_BLIP, true);
    for (new i = 0; i < sizeof(Charged); i++)
        PrecacheSound(Charged[i], true);

    g_BeamSprite = PrecacheModel("materials/sprites/laser.vmt");
    g_HaloSprite = PrecacheModel("materials/sprites/halo01.vmt");	

    g_lastChargeTime = 0.0;
    g_lastBeaconTime = 0.0;
    g_lastPingTime = 0.0;
}

public OnMapEnd()
{
    if (g_TimerHandle1 != INVALID_HANDLE)
    {
        KillTimer(g_TimerHandle1);
        g_TimerHandle1 = INVALID_HANDLE;
    }
    if (g_TimerHandle2 != INVALID_HANDLE)
    {
        KillTimer(g_TimerHandle2);
        g_TimerHandle2 = INVALID_HANDLE;
    }
    if (g_TimerHandle3 != INVALID_HANDLE)
    {
        KillTimer(g_TimerHandle3);
        g_TimerHandle3 = INVALID_HANDLE;
    }
}

// When a new client connects we reset their flags
public OnClientPutInServer(client)
{
    if (client && !IsFakeClient(client))
        NativeMedicEnabled[client] = false;

    if (!NativeControl && GetConVarBool(g_IsUberchargerOn))
        CreateTimer(45.0, Timer_Advert, client);
}

public Action:Timer_Advert(Handle:timer, any:client)
{
    if (!NativeControl &&
        GetConVarBool(g_IsUberchargerOn) &&
        IsClientInGame(client))
    {
        PrintToChat(client, "\x01\x04[SM]\x01 Medics will auto-charge uber (and will beacon while charging)");
    }
}

public Action:Medic_Timer1(Handle:timer, any:value)
{
    if (!NativeControl && !GetConVarBool(g_IsUberchargerOn))
        return;

    new Float:gameTime = GetGameTime();
    new bool:charge    = (gameTime - g_lastChargeTime >= g_ChargeDelay);
    new bool:beacon    = (gameTime - g_lastBeaconTime >= g_BeaconDelay);
    new bool:ping      = (gameTime - g_lastPingTime >= g_PingDelay);

    if (charge)
        g_lastChargeTime = gameTime;

    if (beacon)
        g_lastBeaconTime = gameTime;

    if (ping)
        g_lastPingTime = gameTime;

    for (new client = 1; client <= MaxClients; client++)
    {
        if (!NativeControl || NativeMedicEnabled[client])
        {
            if (IsClientInGame(client) && IsPlayerAlive(client))
            {
                new team = GetClientTeam(client);
                if (team >= 2 && team <= 3)
                {
                    if (TF2_GetPlayerClass(client) == TFClass_Medic)
                    {
                        
                        decl String:classname[64];
                        GetCurrentWeaponClass(client, classname, sizeof(classname));
                        if (StrEqual(classname, "CWeaponMedigun"))
                        {
                            new m_nPlayerCond = FindSendPropInfo("CTFPlayer","m_nPlayerCond") ;
                            new cond = GetEntData(client, m_nPlayerCond, sizeof(m_nPlayerCond)); // status is not ubered
                            if(cond != 32)
                            {
                                new weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

                                if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 29 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 211 
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 663 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 796
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 805 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 885
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 894 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 903
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 912 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 961
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 970 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15008
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15010 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15025
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15039 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15050
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15078 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15097
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15120 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15121
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15122 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15145
                                || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 15146)
                                {
                                    new Float:UberCharge = TF2_GetUberLevel(client);
                                    if (UberCharge < 1.0)
                                    {
                                        if (charge)
                                        {
                                            new Float:amt = NativeAmount[client];
                                            UberCharge += (amt > 0.0) ? amt : GetConVarFloat(g_ChargeAmount1);
                                            if (UberCharge >= 1.0)
                                            {
                                                UberCharge = 1.0;
                                                EmitSoundToAll(Charged[GetRandomInt(0,sizeof(Charged)-1)],client);
                                            }
                                            TF2_SetUberLevel(client, UberCharge);
                                        }

                                        if (beacon && GetConVarInt(g_EnableBeacon))
                                        {
                                            BeaconPing(client, ping && GetConVarInt(g_EnablePing));
                                        }
                                        else if (ping && GetConVarInt(g_EnablePing))
                                        {
                                            new Float:vec[3];
                                            GetClientEyePosition(client, vec);
                                            EmitAmbientSound(SOUND_BLIP, vec, client, SNDLEVEL_RAIDSIREN);	
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

public Action:Medic_Timer2(Handle:timer, any:value)
{
    if (!NativeControl && !GetConVarBool(g_IsUberchargerOn))
        return;

    new Float:gameTime = GetGameTime();
    new bool:charge    = (gameTime - g_lastChargeTime >= g_ChargeDelay);
    new bool:beacon    = (gameTime - g_lastBeaconTime >= g_BeaconDelay);
    new bool:ping      = (gameTime - g_lastPingTime >= g_PingDelay);

    if (charge)
        g_lastChargeTime = gameTime;

    if (beacon)
        g_lastBeaconTime = gameTime;

    if (ping)
        g_lastPingTime = gameTime;

    for (new client = 1; client <= MaxClients; client++)
    {
        if (!NativeControl || NativeMedicEnabled[client])
        {
            if (IsClientInGame(client) && IsPlayerAlive(client))
            {
                new team = GetClientTeam(client);
                if (team >= 2 && team <= 3)
                {
                    if (TF2_GetPlayerClass(client) == TFClass_Medic)
                    {
                        
                        decl String:classname[64];
                        GetCurrentWeaponClass(client, classname, sizeof(classname));
                        if (StrEqual(classname, "CWeaponMedigun"))
                        {
                            new m_nPlayerCond = FindSendPropInfo("CTFPlayer","m_nPlayerCond") ;
                            new cond = GetEntData(client, m_nPlayerCond, sizeof(m_nPlayerCond)); // status is not ubered
                            if(cond != 32)
                            {
                                if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 411)
                                {
                                    new Float:UberCharge = TF2_GetUberLevel(client);
                                    if (UberCharge < 1.0)
                                    {
                                        if (charge)
                                        {
                                            new Float:amt = NativeAmount[client];
                                            UberCharge += (amt > 0.0) ? amt : GetConVarFloat(g_ChargeAmount2);
                                            if (UberCharge >= 1.0)
                                            {
                                                UberCharge = 1.0;
                                                EmitSoundToAll(Charged[GetRandomInt(0,sizeof(Charged)-1)],client);
                                            }
                                            TF2_SetUberLevel(client, UberCharge);
                                        }

                                        if (beacon && GetConVarInt(g_EnableBeacon))
                                        {
                                            BeaconPing(client, ping && GetConVarInt(g_EnablePing));
                                        }
                                        else if (ping && GetConVarInt(g_EnablePing))
                                        {
                                            new Float:vec[3];
                                            GetClientEyePosition(client, vec);
                                            EmitAmbientSound(SOUND_BLIP, vec, client, SNDLEVEL_RAIDSIREN);	
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

public Action:Medic_Timer3(Handle:timer, any:value)
{
    if (!NativeControl && !GetConVarBool(g_IsUberchargerOn))
        return;

    new Float:gameTime = GetGameTime();
    new bool:charge    = (gameTime - g_lastChargeTime >= g_ChargeDelay);
    new bool:beacon    = (gameTime - g_lastBeaconTime >= g_BeaconDelay);
    new bool:ping      = (gameTime - g_lastPingTime >= g_PingDelay);

    if (charge)
        g_lastChargeTime = gameTime;

    if (beacon)
        g_lastBeaconTime = gameTime;

    if (ping)
        g_lastPingTime = gameTime;

    for (new client = 1; client <= MaxClients; client++)
    {
        if (!NativeControl || NativeMedicEnabled[client])
        {
            if (IsClientInGame(client) && IsPlayerAlive(client))
            {
                new team = GetClientTeam(client);
                if (team >= 2 && team <= 3)
                {
                    if (TF2_GetPlayerClass(client) == TFClass_Medic)
                    {
                        
                        decl String:classname[64];
                        GetCurrentWeaponClass(client, classname, sizeof(classname));
                        if (StrEqual(classname, "CWeaponMedigun"))
                        {
                            new m_nPlayerCond = FindSendPropInfo("CTFPlayer","m_nPlayerCond") ;
                            new cond = GetEntData(client, m_nPlayerCond, sizeof(m_nPlayerCond)); // status is not ubered
                            if(cond != 32)
                            {
                                if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 998)
                                {
                                    new Float:UberCharge = TF2_GetUberLevel(client);
                                    if (UberCharge < 1.0)
                                    {
                                        if (charge)
                                        {
                                            new Float:amt = NativeAmount[client];
                                            UberCharge += (amt > 0.0) ? amt : GetConVarFloat(g_ChargeAmount3);
                                            if (UberCharge >= 1.0)
                                            {
                                                UberCharge = 1.0;
                                                EmitSoundToAll(Charged[GetRandomInt(0,sizeof(Charged)-1)],client);
                                            }
                                            TF2_SetUberLevel(client, UberCharge);
                                        }

                                        if (beacon && GetConVarInt(g_EnableBeacon))
                                        {
                                            BeaconPing(client, ping && GetConVarInt(g_EnablePing));
                                        }
                                        else if (ping && GetConVarInt(g_EnablePing))
                                        {
                                            new Float:vec[3];
                                            GetClientEyePosition(client, vec);
                                            EmitAmbientSound(SOUND_BLIP, vec, client, SNDLEVEL_RAIDSIREN);	
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

BeaconPing(client,bool:ping)
{
    new team = GetClientTeam(client);

    new Float:vec[3];
    GetClientAbsOrigin(client, vec);
    vec[2] += 10;

    TE_SetupBeamRingPoint(vec, 10.0, GetConVarFloat(g_BeaconRadius), g_BeamSprite, g_HaloSprite, 0, 15, 0.5, 5.0, 0.0, greyColor, 10, 0);
    TE_SendToAll();

    if (team == 2)
    {
        TE_SetupBeamRingPoint(vec, 10.0, GetConVarFloat(g_BeaconRadius), g_BeamSprite, g_HaloSprite, 0, 10, 0.6, 10.0, 0.5, redColor, 10, 0);
    }
    else if (team == 3)
    {
        TE_SetupBeamRingPoint(vec, 10.0, GetConVarFloat(g_BeaconRadius), g_BeamSprite, g_HaloSprite, 0, 10, 0.6, 10.0, 0.5, blueColor, 10, 0);
    }
    else
    {
        TE_SetupBeamRingPoint(vec, 10.0, GetConVarFloat(g_BeaconRadius), g_BeamSprite, g_HaloSprite, 0, 10, 0.6, 10.0, 0.5, greenColor, 10, 0);
    }

    TE_SendToAll();

    if (ping)
    {
        GetClientEyePosition(client, vec);
        EmitAmbientSound(SOUND_BLIP, vec, client, SNDLEVEL_RAIDSIREN);	
    }
}

Float:CalcDelay1()
{
    g_ChargeDelay = GetConVarFloat(g_ChargeTimer1);
    g_BeaconDelay = GetConVarFloat(g_BeaconTimer);
    g_PingDelay = GetConVarFloat(g_PingTimer);

    new Float:delay = g_ChargeDelay;
    if (delay > g_BeaconDelay)
        delay = g_BeaconDelay;
    if (delay > g_PingDelay)
        delay = g_PingDelay;

    return delay;
}

Float:CalcDelay2()
{
    g_ChargeDelay = GetConVarFloat(g_ChargeTimer2);
    g_BeaconDelay = GetConVarFloat(g_BeaconTimer);
    g_PingDelay = GetConVarFloat(g_PingTimer);

    new Float:delay = g_ChargeDelay;
    if (delay > g_BeaconDelay)
        delay = g_BeaconDelay;
    if (delay > g_PingDelay)
        delay = g_PingDelay;

    return delay;
}

Float:CalcDelay3()
{
    g_ChargeDelay = GetConVarFloat(g_ChargeTimer3);
    g_BeaconDelay = GetConVarFloat(g_BeaconTimer);
    g_PingDelay = GetConVarFloat(g_PingTimer);

    new Float:delay = g_ChargeDelay;
    if (delay > g_BeaconDelay)
        delay = g_BeaconDelay;
    if (delay > g_PingDelay)
        delay = g_PingDelay;

    return delay;
}

public Native_ControlUberCharger(Handle:plugin,numParams)
{
    NativeControl = GetNativeCell(1);

    if (g_TimerHandle1 == INVALID_HANDLE && NativeControl && ConfigsExecuted)
        g_TimerHandle1 = CreateTimer(CalcDelay1(), Medic_Timer1, _, TIMER_REPEAT);
    if (g_TimerHandle2 == INVALID_HANDLE && NativeControl && ConfigsExecuted)
        g_TimerHandle2 = CreateTimer(CalcDelay2(), Medic_Timer2, _, TIMER_REPEAT);
    if (g_TimerHandle3 == INVALID_HANDLE && NativeControl && ConfigsExecuted)
        g_TimerHandle3 = CreateTimer(CalcDelay3(), Medic_Timer3, _, TIMER_REPEAT);
}

public Native_SetUberCharger(Handle:plugin,numParams)
{
    new client = GetNativeCell(1);
    NativeMedicEnabled[client] = GetNativeCell(2);
    NativeAmount[client] = Float:GetNativeCell(3);
}

