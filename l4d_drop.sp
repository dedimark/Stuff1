#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "2.0"

ConVar g_hCvarBlockSecondaryDrop;
ConVar g_hCvarBlockM60Drop;
ConVar g_hCvarBlockDropMidAction;
bool g_bBlockSecondaryDrop;
bool g_bBlockM60Drop;
bool g_bLeft4Dead2;
int g_iBlockDropMidAction;

public Plugin myinfo = 
{
	name = "[L4D/2] Weapon Drop",
	author = "Machine, dcx2, Electr000999 /z, Senip, Shao, HarryPotter",
	description = "Allows players to drop the weapon they are holding.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=123098"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if (test == Engine_Left4Dead2)
	{
		g_bLeft4Dead2 = true;
		return APLRes_Success;
	}
	else if (test == Engine_Left4Dead)
	{
		g_bLeft4Dead2 = false;
		return APLRes_Success;
	}
	strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
	return APLRes_SilentFailure;
}

public void OnPluginStart()
{
	CreateConVar("sm_drop_version", PLUGIN_VERSION, "[L4D/2] Weapon Drop Version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_hCvarBlockSecondaryDrop = CreateConVar("sm_drop_block_secondary", "0", "Prevent players from dropping their secondaries? (Fixes bugs that can come with incapped weapons or A-Posing.)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarBlockDropMidAction = CreateConVar("sm_drop_block_mid_action", "1", "Prevent players from dropping objects in between actions? (Fixes throwable cloning.) 1 = All weapons. 2 = Only throwables.", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	if (g_bLeft4Dead2)
	{
		g_hCvarBlockM60Drop = CreateConVar("sm_drop_block_m60", "0", "Prevent players from dropping the M60? (Allows for better compatibility with certain plugins.)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
		g_hCvarBlockM60Drop.AddChangeHook(ConVarChanged_Cvars);
	}

	GetCvars();

	g_hCvarBlockSecondaryDrop.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarBlockDropMidAction.AddChangeHook(ConVarChanged_Cvars);

	RegConsoleCmd("sm_drop", Command_Drop);

	AutoExecConfig(true, "l4d_drop");

	LoadTranslations("common.phrases");
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{ 
	GetCvars(); 
}

void GetCvars()
{
	g_bBlockSecondaryDrop = g_hCvarBlockSecondaryDrop.BoolValue;
	g_iBlockDropMidAction = g_hCvarBlockDropMidAction.IntValue;
	if (g_bLeft4Dead2) 
	{ 
		g_bBlockM60Drop = g_hCvarBlockM60Drop.BoolValue;
	}
}

Action Command_Drop(int client, int args)
{
	if (args > 2)
	{
		if (GetAdminFlag(GetUserAdmin(client), Admin_Root))
		{
			ReplyToCommand(client, "[SM] Usage: sm_drop <#userid|name> <slot to drop>");
		}
	}
	else if (args == 0)
	{
		DropActiveWeapon(client);
	}
	else if (args > 0)
	{
		if (GetAdminFlag(GetUserAdmin(client), Admin_Root))
		{
			static char target[MAX_TARGET_LENGTH], arg[8];
			GetCmdArg(1, target, sizeof(target));
			GetCmdArg(2, arg, sizeof(arg));
			int slot = StringToInt(arg);
			static char target_name[MAX_TARGET_LENGTH]; target_name[0] = '\0';
			int target_list[MAXPLAYERS], target_count; 
			bool tn_is_ml;
			if ((target_count = ProcessTargetString(
				target,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_ALIVE,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
			{
				ReplyToTargetError(client, target_count);
				return Plugin_Handled;
			}
			for (int i = 0; i < target_count; i++)
			{
				if (!IsValidClient(target_list[i])) 
				{
					continue;
				}
				
				if (slot > 0)
				{
					DropSlot(target_list[i], slot);
				}
				else
				{
					DropActiveWeapon(target_list[i]);
				}
			}
		}
	}
	return Plugin_Handled;
}

//#define tester_wep_slot 2
void DropSlot(int client, int slot)
{
	if (!IsValidClient(client) || !IsSurvivor(client) || !IsPlayerAlive(client) || IsplayerIncap(client) || GetInfectedAttacker(client) != -1) 
	{
		return;
	}
	//static char classname[64];
	//GetEntityClassname(GetPlayerWeaponSlot(client, tester_wep_slot), classname, sizeof(classname));
	//PrintToChatAll("slot: %s", classname);
	slot--;
	int weapon = GetPlayerWeaponSlot(client, slot);
	if (RealValidEntity(weapon) && DropBlocker(client, weapon))
	{
		DropWeapon(client, weapon);
	}
}

void DropActiveWeapon(int client)
{
	if (!IsValidClient(client) || !IsSurvivor(client) || !IsPlayerAlive(client) || IsplayerIncap(client) || GetInfectedAttacker(client) != -1) 
	{
		return;
	}
	//static char classname[64];
	//GetEntityClassname(GetPlayerWeaponSlot(client, tester_wep_slot), classname, sizeof(classname));
	//PrintToChatAll("slot: %s", classname);
	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	if (RealValidEntity(weapon) && DropBlocker(client, weapon))
	{
		DropWeapon(client, weapon);
	}
}

int DropBlocker(int client, int weapon)
{
	int wep_Secondary = GetPlayerWeaponSlot(client, 1);
	// Secondary check
	if (g_bBlockSecondaryDrop && wep_Secondary == weapon) 
	{
		return false;
	}
	static char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));
	// M60 check
	if (g_bLeft4Dead2 && g_bBlockM60Drop && StrEqual(classname, "weapon_rifle_m60", false))
	{
		return false;
	}
	return true;
}

void DropWeapon(int client, int weapon)
{
	if ((g_iBlockDropMidAction == 1 ||
	(g_iBlockDropMidAction > 1 && GetPlayerWeaponSlot(client, 2) == weapon)) && 
	GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon") == weapon && 
	GetEntPropFloat(weapon, Prop_Data, "m_flNextPrimaryAttack") >= GetGameTime()) 
	{
		return;
	}
	// slot 2 is throwable
	static char classname[32];
	GetEntityClassname(weapon, classname, sizeof(classname));
	if (strcmp(classname, "weapon_pistol") == 0 && GetEntProp(weapon, Prop_Send, "m_isDualWielding") > 0)
	{
		int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
		clip = clip / 2;
		RemovePlayerItem(client, weapon);
		RemoveEntity(weapon);
		int single_pistol = CreateEntityByName("weapon_pistol");
		if (single_pistol <= MaxClients) 
		{
			return;
		}
		DispatchSpawn(single_pistol);
		EquipPlayerWeapon(client, single_pistol);
		SDKHooks_DropWeapon(client, single_pistol);
		SetEntProp(single_pistol, Prop_Send, "m_iClip1", clip);
		single_pistol = CreateEntityByName("weapon_pistol");
		if (single_pistol <= MaxClients) 
		{
			return;
		}
		DispatchSpawn(single_pistol);
		EquipPlayerWeapon(client, single_pistol);
		SetEntProp(single_pistol, Prop_Send, "m_iClip1", clip);
		return;	
	}
	int ammo = GetPlayerReserveAmmo(client, weapon);
	SDKHooks_DropWeapon(client, weapon);
	SetPlayerReserveAmmo(client, weapon, 0);
	SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", ammo);
	if (!g_bLeft4Dead2) 
	{
		return;
	}
	if (strcmp(classname, "weapon_defibrillator") == 0)
	{
		int modelindex = GetEntProp(weapon, Prop_Data, "m_nModelIndex");
		SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", modelindex);
	}
}

//https://forums.alliedmods.net/showthread.php?t=260445
void SetPlayerReserveAmmo(int client, int weapon, int ammo)
{
	int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammotype >= 0 )
	{
		SetEntProp(client, Prop_Send, "m_iAmmo", ammo, _, ammotype);
		ChangeEdictState(client, FindDataMapInfo(client, "m_iAmmo"));
	}
}

int GetPlayerReserveAmmo(int client, int weapon)
{
	int ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammotype >= 0)
	{
		return GetEntProp(client, Prop_Send, "m_iAmmo", _, ammotype);
	}
	return 0;
}

bool IsSurvivor(int client)
{ 
	return GetClientTeam(client) == 2 || GetClientTeam(client) == 4; 
}

bool IsValidClient(int client, bool replaycheck = true)
{
	if (client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		if (replaycheck)
		{
			if (IsClientSourceTV(client) || IsClientReplay(client)) 
			{
				return false;
			}
		}
		return true;
	}
	return false;
}

bool RealValidEntity(int entity)
{ 
	return entity > 0 && IsValidEntity(entity); 
}

bool IsplayerIncap(int client)
{
	if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge") || GetEntProp(client, Prop_Send, "m_isIncapacitated"))
	{
		return true;
	}
	return false;
}

int GetInfectedAttacker(int client)
{
	int attacker;
	if (g_bLeft4Dead2)
	{
		/* Charger */
		attacker = GetEntPropEnt(client, Prop_Send, "m_pummelAttacker");
		if (attacker > 0)
		{
			return attacker;
		}

		attacker = GetEntPropEnt(client, Prop_Send, "m_carryAttacker");
		if (attacker > 0)
		{
			return attacker;
		}
		/* Jockey */
		attacker = GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker");
		if (attacker > 0)
		{
			return attacker;
		}
	}
	/* Hunter */
	attacker = GetEntPropEnt(client, Prop_Send, "m_pounceAttacker");
	if (attacker > 0)
	{
		return attacker;
	}
	/* Smoker */
	attacker = GetEntPropEnt(client, Prop_Send, "m_tongueOwner");
	if (attacker > 0)
	{
		return attacker;
	}
	return -1;
}