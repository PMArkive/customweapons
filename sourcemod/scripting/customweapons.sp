#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <anymap>
#include <customweapons>

#pragma semicolon 1
#pragma newdecls required

// External file compilation protection.
#define COMPILING_FROM_MAIN
#include "customweapons/structs.sp"
#include "customweapons/api.sp"
#include "customweapons/modelsmgr.sp"
#include "customweapons/soundsmgr.sp"
#undef COMPILING_FROM_MAIN

// Whether the plugin loaded late.
// Used to call a lateload function in 'OnPluginStart()'
bool g_Lateload;

public Plugin myinfo = 
{
	name = "[CS:GO] Custom-Weapons", 
	author = "KoNLiG", 
	description = "Provides an API for custom weapons management.", 
	version = "1.0.0", 
	url = "https://github.com/KoNLiG/customweapons"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// Lock the use of this plugin for CS:GO only.
	if (GetEngineVersion() != Engine_CSGO)
	{
		strcopy(error, err_max, "This plugin was made for use with CS:GO only.");
		return APLRes_Failure;
	}
	
	// Initialzie API stuff.
	InitializeAPI();
	
	g_Lateload = late;
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	// Initialize all global variables.
	InitializeGlobalVariables();
	
	// Perform hooks that required for the models manager.
	ModelsManagerHooks();
	
	// Perform hooks that required for the sounds manager.
	SoundsManagerHooks();
	
	// Late late function for secure measures.
	if (g_Lateload)
	{
		LateLoad();
	}
}

public void OnPluginEnd()
{
	OnNotifyPluginUnloaded(GetMyHandle());
}

public void OnNotifyPluginUnloaded(Handle plugin)
{
	CustomWeaponData custom_weapon_data;
	
	AnyMapSnapshot custom_weapons_snapshot = g_CustomWeapons.Snapshot();
	
	for (int current_index, current_key; current_index < custom_weapons_snapshot.Length; current_index++)
	{
		current_key = custom_weapons_snapshot.GetKey(current_index);
		
		if (custom_weapon_data.GetMyselfByReference(current_key) && custom_weapon_data.plugin == plugin)
		{
			// Release the custom weapon data from the plugin.
			custom_weapon_data.RemoveMyself(current_key);
		}
	}
	
	delete custom_weapons_snapshot;
}

public void OnEntityDestroyed(int entity)
{
	// Validate the entity index. (for some reason an entity reference can by passed)
	if (entity <= 0)
	{
		return;
	}
	
	int entity_reference = EntIndexToEntRef(entity);
	
	CustomWeaponData custom_weapon_data;
	if (custom_weapon_data.GetMyselfByReference(entity_reference))
	{
		// Release the custom weapon data from the plugin.
		custom_weapon_data.RemoveMyself(entity_reference);
	}
}

public void OnClientPutInServer(int client)
{
	g_Players[client].Init(client);
	
	// Perform client hooks that required for the models manager.
	ModelsManagerClientHooks(client);
	
	// 'SDKHook_WeaponSwitchPost' SDKHook are used both in `soundsmgr.sp` and `modelsmgr.sp`,
	// theirfore we will hook it globaly and each subfile will use sepearated "callback".
	SDKHook(client, SDKHook_WeaponSwitchPost, Hook_OnWeaponSwitchPost);
}

void Hook_OnWeaponSwitchPost(int client, int weapon)
{
	ModelsMgr_OnWeaponSwitchPost(client, weapon);
	SoundsMgr_OnWeaponSwitchPost(client, weapon);
}

public void OnClientDisconnect(int client)
{
	// Frees the slot data.
	g_Players[client].Close();
}

bool IsEntityWeapon(int entity)
{
	// Retrieve the entity classname.
	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	
	// Validate the classname.
	return !StrContains(classname, "weapon_");
}

// Retrieves a model precache index.
// This is efficient since extra 'PrecacheModel()' function call isn't necessary here.
// Returns INVALID_STRING_INDEX if the model isn't precached.
stock int GetModelPrecacheIndex(const char[] filename)
{
	static int table = INVALID_STRING_TABLE;
	
	if (table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("modelprecache");
	}
	
	return FindStringIndex(table, filename);
}

void LateLoad()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientConnected(current_client))
		{
			OnClientPutInServer(current_client);
			
			// Late load initialization.
			g_Players[current_client].InitViewModel();
		}
	}
}

void ReEquipWeaponEntity(int weapon, int weapon_owner = -1)
{
	if (weapon_owner == -1 && (weapon_owner = GetEntPropEnt(weapon, Prop_Data, "m_hOwnerEntity")) == -1)
	{
		return;
	}
	
	// Remove the weapon.
	RemovePlayerItem(weapon_owner, weapon);
	
	// Equip the weapon back in a frame.
	DataPack dp = new DataPack();
	dp.WriteCell(GetClientUserId(weapon_owner));
	dp.WriteCell(EntIndexToEntRef(weapon));
	dp.Reset();
	
	RequestFrame(Frame_EquipWeapon, dp);
}

void Frame_EquipWeapon(DataPack dp)
{
	int client = GetClientOfUserId(dp.ReadCell());
	int weapon = EntRefToEntIndex(dp.ReadCell());
	
	if (client && weapon != -1)
	{
		EquipPlayerWeapon(client, weapon);
	}
	
	dp.Close();
} 