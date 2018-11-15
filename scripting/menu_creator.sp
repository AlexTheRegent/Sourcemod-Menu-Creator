#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required

#define PLUGIN_VERSION "3.0.0.2"
public Plugin myinfo =
{
	name 		= "[ Menu Creator ]",
	author 		= "AlexTheRegent",
	description = "Simple creating of menu and panels for Source Games",
	version 	= PLUGIN_VERSION,
	url 		= "http://hlmod.ru/forum/showthread.php?t=18977"
}

StringMap	g_hTrie_NameToHandle;
StringMap	g_hTrie_CommandToHandle;
StringMap	g_hTrie_HandleToHandleType;
StringMap	g_hTrie_HandleToBackHandle;
StringMap	g_hTrie_NameToShowTime;
StringMap	g_hTrie_HandleToShowTime;
KeyValues	g_hKeyValues_PanelCommands;
Handle		g_hCurrentHandle;
bool		g_bIsHandlePanel;

StringMap	g_hTrie_ClientCookies[MAXPLAYERS+1];
Handle		g_hCurrentPanel[MAXPLAYERS+1];
char 		g_szOnClientPostAdminCheck[256];

public void OnPluginStart()
{
	// инициализация переменных
	g_hTrie_NameToHandle 		= new StringMap();
	g_hTrie_CommandToHandle 	= new StringMap();
	g_hTrie_HandleToHandleType 	= new StringMap();
	g_hTrie_HandleToBackHandle 	= new StringMap();
	g_hTrie_NameToShowTime 		= new StringMap();
	g_hTrie_HandleToShowTime 	= new StringMap();
	g_hKeyValues_PanelCommands 	= new KeyValues("commands");
	
	// путь к конфиг файлу
	char szConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, szConfigFile, sizeof(szConfigFile), "configs/menu_creator.txt");
	
	// открытие конфиг файла
	File hFile = OpenFile(szConfigFile, "r");
	if ( hFile == null ) {
		LogError("File \"%s\" not found", szConfigFile);
		SetFailState("File \"%s\" not found", szConfigFile);
	}
	
	// построчное чтение файла
	char szLine[512], szBuffer[3][256];
	while ( !hFile.EndOfFile() && hFile.ReadLine(szLine, sizeof(szLine)) ) {
		// если строка не начинается с // (комментарий)
		if ( StrContains(szLine, "//", true) != 0 ) {
			// разделение строки на составные по |
			int iArgc = ExplodeString(szLine, "|", szBuffer, sizeof(szBuffer), sizeof(szBuffer[]));
			// удаление пробелов в строках
			for ( int i = 0; i < iArgc; ++i ) {
				TrimString(szBuffer[i]);
			}
			
			if ( !strcmp(szBuffer[0], "create", false) ) {
				if ( !InitHandle(szBuffer[1], szBuffer[2]) ) {
					LogError("error in line: \"%s\" ", szLine);
				}
			}
			else if ( !strcmp(szBuffer[0], "regcmd", false) ) {
				if ( !RegisterCommand(szBuffer[1], szBuffer[2]) ) {
					LogError("error in line: \"%s\" ", szLine);
				}
			}
			else if ( !strcmp(szBuffer[0], "title", false) ) {
				if ( !SetTitle(szBuffer[1]) ) {
					LogError("error in line: \"%s\" ", szLine);
				}
			}
			else if ( !strcmp(szBuffer[0], "item", false) ) {
				if ( !AddItem(szBuffer[1], szBuffer[2]) ) {
					LogError("error in line: \"%s\" ", szLine);
				}
			}
			else if ( !strcmp(szBuffer[0], "text", false) ) {
				if ( !AddText(szBuffer[1]) ) {
					LogError("error in line: \"%s\" ", szLine);
				}
			}
			else if ( !strcmp(szBuffer[0], "setback", false) ) {
				if ( !SetBack(szBuffer[1]) ) {
					LogError("error in line: \"%s\" ", szLine);
				}
			}
			else if ( !strcmp(szBuffer[0], "setpos", false) ) {
				if ( !SetPosition(szBuffer[1]) ) {
					LogError("error in line: \"%s\" ", szLine);
				}
			}
			else if ( !strcmp(szBuffer[0], "settime", false) ) {
				if ( !SetTime(szBuffer[1], szBuffer[2]) ) {
					LogError("error in line: \"%s\" ", szLine);
				}
			}
		}
	}
	
	RegServerCmd("sm_mc_om", 	Command_OpenMenu);
	RegServerCmd("sm_mc_ol", 	Command_OpenList);
	RegServerCmd("sm_mc_odl", 	Command_OpenDynamicList);
	RegServerCmd("sm_mc_ourl", 	Command_OpenUrl);
	RegServerCmd("sm_mc_fc", 	Command_FakeCommand);
	
	CreateConVar("sm_mc_onpostadmin", "", "команда, выполняемая от лица игрока после входа на сервер");
	AutoExecConfig(true, "menu_creator");
}

public void OnMapStart()
{
	
}

public void OnConfigsExecuted()
{
	ConVar hConVar = FindConVar("sm_mc_onpostadmin");
	GetConVarString(hConVar, g_szOnClientPostAdminCheck, sizeof(g_szOnClientPostAdminCheck));
	CloseHandle(hConVar);
}

public void OnClientPutInServer(int client)
{
	g_hTrie_ClientCookies[client] = new StringMap();
}

public void OnClientPostAdminCheck(int iClient)
{
	if ( g_szOnClientPostAdminCheck[0] ) {
		FakeClientCommand(iClient, g_szOnClientPostAdminCheck);
	}
}

public void OnClientDisconnect(int client)
{
	delete g_hTrie_ClientCookies[client];
}

bool InitHandle(char[] szHandleName, char[] szType)
{
	if ( !strcmp(szType, "menu") ) {
		g_hCurrentHandle = new Menu(Handle_Menu);
		g_bIsHandlePanel = false;
	}
	else if ( !strcmp(szType, "panel") ) {
		g_hCurrentHandle = new Panel();
		g_bIsHandlePanel = true;
	}
	else if ( !strcmp(szType, "list") ) {
		g_hCurrentHandle = new Menu(Handle_List);
		g_bIsHandlePanel = false;
	}
	else {
		LogError("invalid handle type: %s", szType);
		return false;
	}
	
	g_hTrie_NameToHandle.SetValue(szHandleName, g_hCurrentHandle);
	char szHandle[16]; FormatEx(szHandle, sizeof(szHandle), "%d", g_hCurrentHandle);
	g_hTrie_HandleToHandleType.SetValue(szHandle, g_bIsHandlePanel);
	g_hTrie_NameToShowTime.SetValue(szHandleName, 0);
	g_hTrie_HandleToShowTime.SetValue(szHandle, 0);
	return true;
}

bool RegisterCommand(char[] szCommand, char[] szAccessFlag)
{
	if ( g_hCurrentHandle == null ) {
		LogError("current handle is null");
		return false;
	}
	
	g_hTrie_CommandToHandle.SetValue(szCommand, g_hCurrentHandle);
	if ( szAccessFlag[0] == 0 ) {
		RegConsoleCmd(szCommand, Command_DisplayHandle);
	}
	else {
		int iAccessFlags = ReadFlagString(szAccessFlag);
		RegAdminCmd(szCommand, Command_DisplayHandle, iAccessFlags);
	}
	
	return true;
}

bool SetTitle(char[] szTitle)
{
	if ( g_hCurrentHandle == null ) {
		LogError("current handle is null");
		return false;
	}
	
	ReplaceAliases(szTitle);
	if ( g_bIsHandlePanel ) {
		SetPanelTitle(g_hCurrentHandle, szTitle);
	}
	else { 
		SetMenuTitle(g_hCurrentHandle, szTitle);
	}
	
	return true;
}

bool AddItem(char[] szText, char[] szCommand)
{
	if ( g_hCurrentHandle == null ) {
		LogError("current handle is null");
		return false;
	}
	
	ReplaceAliases(szText);
	if ( g_bIsHandlePanel ) {
		int iPosition = DrawPanelItem(g_hCurrentHandle, szText);
		if ( iPosition != 0 )
		{
			g_hKeyValues_PanelCommands.Rewind();
			
			char szHandle[16]; FormatEx(szHandle, sizeof(szHandle), "%d", g_hCurrentHandle);
			if ( g_hKeyValues_PanelCommands.JumpToKey(szHandle, true) )
			{
				char szPosition[4];
				IntToString(iPosition, szPosition, sizeof(szPosition));
				g_hKeyValues_PanelCommands.SetString(szPosition, szCommand);
			}
			else {
				LogError("key with this number exists");
				return false;
			}
		}
		else {
			LogError("panel overflow (more than 9 items)");
			return false;
		}
	}
	else {
		AddMenuItem(g_hCurrentHandle, szCommand, szText);
	}
	
	return true;
}

bool AddText(char[] szText)
{
	if ( g_hCurrentHandle == null ) {
		LogError("current handle is null");
		return false;
	}
	
	ReplaceAliases(szText);
	if ( g_bIsHandlePanel ) {
		DrawPanelItem(g_hCurrentHandle, szText, ITEMDRAW_RAWLINE);
	}
	else {
		AddMenuItem(g_hCurrentHandle, NULL_STRING, szText, ITEMDRAW_DISABLED);
	}
	
	return true;
}

bool SetBack(char[] szBackHandleName)
{
	if ( g_hCurrentHandle == null ) {
		LogError("current handle is null");
		return false;
	}
	
	Handle hBackHandle;
	if ( g_hTrie_NameToHandle.GetValue(szBackHandleName, hBackHandle) ) {
		if ( g_bIsHandlePanel ) {
			char szCommand[64];
			FormatEx(szCommand, sizeof(szCommand), "sm_mc_om {cl} %s", szBackHandleName);
			AddItem("Назад", szCommand);
		}
		else {
			SetMenuExitBackButton(g_hCurrentHandle, true);
		}
	}
	else {
		LogError("backhandle not found");
		return false;
	}
	
	char szHandle[16]; FormatEx(szHandle, sizeof(szHandle), "%d", g_hCurrentHandle);
	g_hTrie_HandleToBackHandle.SetValue(szHandle, hBackHandle);
	return true;
}

bool SetPosition(char[] szPosition)
{
	if ( g_hCurrentHandle == null ) {
		LogError("current handle is null");
		return false;
	}
	
	if ( g_bIsHandlePanel ) {
		int iPosition = StringToInt(szPosition);
		if ( !SetPanelCurrentKey(g_hCurrentHandle, iPosition) ) {
			LogError("invalid key number: %s", szPosition);
			return false;
		}
	}
	else { 
		LogError("setpos only for panels");
		return false;
	}
	
	return true;
}

bool SetTime(char[] szHandleName, char[] szTime)
{
	if ( g_hCurrentHandle == null ) {
		LogError("current handle is null");
		return false;
	}
	
	char szHandle[16]; FormatEx(szHandle, sizeof(szHandle), "%d", g_hCurrentHandle);
	int iTime = StringToInt(szTime);
	g_hTrie_HandleToShowTime.SetValue(szHandle, iTime);
	g_hTrie_NameToShowTime.SetValue(szHandleName, iTime);
	return true;
}

void ReplaceAliases(char[] szString)
{
	ReplaceString(szString, strlen(szString), "{nl}", 	"\n", false);
	ReplaceString(szString, strlen(szString), "{s}", 	"|", false);
	ReplaceString(szString, strlen(szString), "{ }", 	" ", false);
}

public Action Command_DisplayHandle(int iClient, int iArgc)
{
	char szCommand[16]; GetCmdArg(0, szCommand, sizeof(szCommand));
	Handle hHandle; g_hTrie_CommandToHandle.GetValue(szCommand, hHandle);
	
	char szHandle[16]; FormatEx(szHandle, sizeof(szHandle), "%d", hHandle);
	bool bIsHandlePanel; g_hTrie_HandleToHandleType.GetValue(szHandle, bIsHandlePanel);
	int iShowTime; g_hTrie_HandleToShowTime.GetValue(szHandle, iShowTime);
	if ( bIsHandlePanel ) {
		g_hCurrentPanel[iClient] = hHandle;
		SendPanelToClient(hHandle, iClient, Handle_Panel, iShowTime);
	}
	else {
		DisplayMenu(hHandle, iClient, iShowTime);
	}
	
	return Plugin_Handled;
}

public int Handle_Menu(Menu hMenu, MenuAction action, int iClient, int iSlot)
{
	if ( action == MenuAction_Select ) {
		char szCommand[256];
		hMenu.GetItem(iSlot, szCommand, sizeof(szCommand));
		
		ReplaceAliases(szCommand);
		ReplaceUserAliases(iClient, szCommand, sizeof(szCommand));
		MyServerCommand(szCommand, sizeof(szCommand));
	}
	else if ( action == MenuAction_Cancel && iSlot == MenuCancel_ExitBack ) {
		char szHandle[16]; 
		FormatEx(szHandle, sizeof(szHandle), "%d", hMenu);
		
		Handle hBackHandle;
		if ( g_hTrie_HandleToBackHandle.GetValue(szHandle, hBackHandle) ) {
			char szBackHandle[16];
			FormatEx(szBackHandle, sizeof(szBackHandle), "%d", hBackHandle);
			
			bool bIsHandlePanel;
			g_hTrie_HandleToHandleType.GetValue(szBackHandle, bIsHandlePanel);
			if ( bIsHandlePanel ) {
				g_hCurrentPanel[iClient] = hBackHandle;
				SendPanelToClient(hBackHandle, iClient, Handle_Panel, MENU_TIME_FOREVER);
			}
			else {
				DisplayMenu(hBackHandle, iClient, MENU_TIME_FOREVER);
			}
		}
	}
}

public int Handle_Panel(Menu hMenu, MenuAction action, int iClient, int iSlot)
{
	if ( action == MenuAction_Select ) {
		char szHandle[16];
		FormatEx(szHandle, sizeof(szHandle) - 1, "%d", g_hCurrentPanel[iClient]);
		
		g_hKeyValues_PanelCommands.Rewind();
		g_hKeyValues_PanelCommands.JumpToKey(szHandle);
		
		char szPosition[4], szCommand[256];
		IntToString(iSlot, szPosition, sizeof(szPosition));
		g_hKeyValues_PanelCommands.GetString(szPosition, szCommand, sizeof(szCommand));
		
		ReplaceAliases(szCommand);
		ReplaceUserAliases(iClient, szCommand, sizeof(szCommand));
		MyServerCommand(szCommand, sizeof(szCommand));
	}
}

void ReplaceUserAliases(int iClient, char[] szString, int iMaxLen)
{
	if ( StrContains(szString, "{cl}") != -1 ) {
		char szClient[4]; IntToString(iClient, szClient, sizeof(szClient));
		ReplaceString(szString, iMaxLen, "{cl}", szClient);
	}
	if ( StrContains(szString, "{uid}") != -1 ) {
		char szUserId[4]; IntToString(GetClientUserId(iClient), szUserId, sizeof(szUserId));
		ReplaceString(szString, iMaxLen, "{uid}", szUserId);
	}
	if ( StrContains(szString, "{name}") != -1 ) {
		char szName[32]; GetClientName(iClient, szName, sizeof(szName));
		ReplaceString(szString, iMaxLen, "{name}", szName);
	}
}

public Action Command_OpenMenu(int iArgc)
{
	char szClient[4], szHandleName[32];
	GetCmdArg(1, szClient, sizeof(szClient));
	GetCmdArg(2, szHandleName, sizeof(szHandleName));
	
	Handle hHandle;
	if ( g_hTrie_NameToHandle.GetValue(szHandleName, hHandle) ) {
		int iClient = StringToInt(szClient);
		
		char szHandle[16]; 
		FormatEx(szHandle, sizeof(szHandle), "%d", hHandle);
		
		bool bIsHandlePanel; 
		int iShowTime; g_hTrie_NameToShowTime.GetValue(szHandleName, iShowTime);
		g_hTrie_HandleToHandleType.GetValue(szHandle, bIsHandlePanel);
		if ( bIsHandlePanel ) {
			g_hCurrentPanel[iClient] = hHandle;
			SendPanelToClient(hHandle, iClient, Handle_Panel, iShowTime);
		}
		else {
			DisplayMenu(hHandle, iClient, iShowTime);
		}
	}
	else {
		LogError("invalid handle name: %s", szHandleName);
	}
	
	return Plugin_Handled;
}

public Action Command_OpenUrl(int iArgc)
{
	char szClient[4], szURL[128];
	GetCmdArg(1, szClient, sizeof(szClient));
	GetCmdArg(2, szURL, sizeof(szURL));
	
	int iClient = StringToInt(szClient);
	ShowMOTDPanel(iClient, " ", szURL, MOTDPANEL_TYPE_URL);
	
	return Plugin_Handled;
}

public Action Command_FakeCommand(int iArgc)
{
	char szClient[4], szCommand[128];
	GetCmdArg(1, szClient, sizeof(szClient));
	GetCmdArg(2, szCommand, sizeof(szCommand));
	
	int iClient = StringToInt(szClient);
	FakeClientCommand(iClient, szCommand);
	
	return Plugin_Handled;
}

public Action Command_OpenList(int iArgc)
{
	char szClient[4], szHandleName[32], szCommand[256];
	GetCmdArg(1, szClient, sizeof(szClient));
	GetCmdArg(2, szHandleName, sizeof(szHandleName));
	GetCmdArgString(szCommand, sizeof(szCommand));
	
	// due to limitation of quotes get last part as string manually
	int iStartPos = strlen(szClient) + strlen(szHandleName) + 2;
	for ( int i = iStartPos; szCommand[i] != 0; ++i ) {
		szCommand[i - iStartPos] = szCommand[i];
	}
	szCommand[strlen(szCommand)-iStartPos] = 0;
	
	Handle hHandle;
	if ( g_hTrie_NameToHandle.GetValue(szHandleName, hHandle) ) {
		int iClient = StringToInt(szClient);
		SetTrieString(g_hTrie_ClientCookies[iClient], "OnListPress", szCommand);
		SetTrieString(g_hTrie_ClientCookies[iClient], "CurrentList", szHandleName);
		//g_hTrie_ClientCookies[iClient].SetString("OnListPress", szCommand);
		
		int iShowTime; g_hTrie_NameToShowTime.GetValue(szHandleName, iShowTime);
		DisplayMenu(hHandle, iClient, iShowTime);
	}
	else {
		LogError("invalid handle name: %s", szHandleName);
	}
	
	return Plugin_Handled;
}

public int Handle_List(Menu hMenu, MenuAction action, int iClient, int iSlot)
{
	if ( action == MenuAction_Select ) {
		char szInfo[128], szCommand[256], szBuffer[32];
		hMenu.GetItem(iSlot, szInfo, sizeof(szInfo));
		
		GetTrieString(g_hTrie_ClientCookies[iClient], "CurrentList", szBuffer, sizeof(szBuffer));
		SetTrieString(g_hTrie_ClientCookies[iClient], szBuffer, szInfo);
		
		GetTrieString(g_hTrie_ClientCookies[iClient], "OnListPress", szCommand, sizeof(szCommand));
		//g_hTrie_ClientCookies[iClient].GetString("OnListPress", szCommand, sizeof(szCommand));
		ReplaceAliases(szCommand);
		ReplaceUserAliases(iClient, szCommand, sizeof(szCommand));
		
		/*char szSubStr[32];
		int iOpenPos = StrContains(szCommand, "{"), iClosePos;
		while ( iOpenPos != -1 ) {
			iClosePos = StrContains(szCommand, "}");
			strcopy(szSubStr, iClosePos-iOpenPos, szCommand[iOpenPos+1]);
			
			if ( GetTrieString(g_hTrie_ClientCookies[iClient], szSubStr, szInfo, sizeof(szInfo)) ) {
				Format(szSubStr, sizeof(szSubStr), "{%s}", szSubStr);
				ReplaceString(szCommand, sizeof(szCommand), szSubStr, szInfo);
			}
			else {
				LogError("unexpected bracket in: %s", szCommand);
				break;
			}
			
			iOpenPos = StrContains(szCommand, "{");
		}*/
		Format(szBuffer, sizeof(szBuffer), "{%s}", szBuffer);
		ReplaceString(szCommand, sizeof(szCommand), szBuffer, szInfo);
		
		MyServerCommand(szCommand, sizeof(szCommand));
	}
	else if ( action == MenuAction_Cancel && iSlot == MenuCancel_ExitBack ) {
		char szHandle[16]; 
		FormatEx(szHandle, sizeof(szHandle), "%d", hMenu);
		
		Handle hBackHandle;
		if ( g_hTrie_HandleToBackHandle.GetValue(szHandle, hBackHandle) ) {
			char szBackHandle[16];
			FormatEx(szBackHandle, sizeof(szBackHandle), "%d", hBackHandle);
			
			bool bIsHandlePanel;
			g_hTrie_HandleToHandleType.GetValue(szBackHandle, bIsHandlePanel);
			if ( bIsHandlePanel ) {
				g_hCurrentPanel[iClient] = hBackHandle;
				SendPanelToClient(hBackHandle, iClient, Handle_Panel, MENU_TIME_FOREVER);
			}
			else {
				DisplayMenu(hBackHandle, iClient, MENU_TIME_FOREVER);
			}
		}
	}
}


public Action Command_OpenDynamicList(int iArgc)
{
	char szClient[4], szHandleName[32], szFilterState[2], szFilterCommand[2], szCommand[256];
	GetCmdArg(1, szClient, sizeof(szClient));
	GetCmdArg(2, szHandleName, sizeof(szHandleName));
	GetCmdArg(3, szFilterState, sizeof(szFilterState));
	GetCmdArg(4, szFilterCommand, sizeof(szFilterCommand));
	GetCmdArgString(szCommand, sizeof(szCommand));
	
	// due to limitation of quotes get last part as string manually
	int iStartPos = strlen(szClient) + strlen(szHandleName) + strlen(szFilterState) + strlen(szFilterCommand) + 4;
	for ( int i = iStartPos; szCommand[i] != 0; ++i ) {
		szCommand[i - iStartPos] = szCommand[i];
	}
	szCommand[strlen(szCommand)-iStartPos] = 0;
	
	Handle hMenu = CreateMenu(Handle_DynamicList);
	SetMenuTitle(hMenu, "Выберите игрока:\n ");
	
	char szInfo[32], szName[32];
	if ( !strcmp(szHandleName, "clients1") || !strcmp(szHandleName, "clients2") ||
		 !strcmp(szHandleName, "userids1") || !strcmp(szHandleName, "userids2") ) {
		for ( int i = 1; i <= MaxClients; ++i ) {
			if ( IsClientInGame(i) && CheckFilter(i, StringToInt(szFilterState), StringToInt(szFilterCommand)) ) {
				GetClientName(i, szName, sizeof(szName));
				IntToString(GetClientUserId(i), szInfo, sizeof(szInfo));
				AddMenuItem(hMenu, szInfo, szName);
			}
		}
	}
	else if ( !strcmp(szHandleName, "name1") || !strcmp(szHandleName, "name2") ) {
		for ( int i = 1; i <= MaxClients; ++i ) {
			if ( IsClientInGame(i) && CheckFilter(i, StringToInt(szFilterState), StringToInt(szFilterCommand)) ) {
				GetClientName(i, szName, sizeof(szName));
				strcopy(szInfo, sizeof(szInfo), szName);
				AddMenuItem(hMenu, szInfo, szName);
			}
		}
	}
	else {
		LogError("invalid dlist handle name: %s", szHandleName);
	}
	
	int iClient = StringToInt(szClient);
	SetTrieString(g_hTrie_ClientCookies[iClient], "OnListPress", szCommand);
	SetTrieString(g_hTrie_ClientCookies[iClient], "CurrentList", szHandleName);
	DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

bool CheckFilter(int iClient, int iState, int iCommand)
{
	if ( iState == 2 || (IsPlayerAlive(iClient) == ((iState==0)?false:true)) ) {
		int iTeam = GetClientTeam(iClient);
		if ( !iCommand || (iTeam == iCommand) || (iCommand == 4 && iTeam > 1) ) {
			return true;
		}
	}
	return false;
}

public int Handle_DynamicList(Menu hMenu, MenuAction action, int iClient, int iSlot)
{
	if ( action == MenuAction_Select ) {
		char szInfo[128], szCommand[256], szBuffer[32];
		hMenu.GetItem(iSlot, szInfo, sizeof(szInfo));
		
		GetTrieString(g_hTrie_ClientCookies[iClient], "CurrentList", szBuffer, sizeof(szBuffer));
		SetTrieString(g_hTrie_ClientCookies[iClient], szBuffer, szInfo);
		
		GetTrieString(g_hTrie_ClientCookies[iClient], "OnListPress", szCommand, sizeof(szCommand));
		ReplaceAliases(szCommand);
		ReplaceUserAliases(iClient, szCommand, sizeof(szCommand));
		
		if ( !strcmp(szBuffer, "clients1") || !strcmp(szBuffer, "clients2") ) {
			Format(szInfo, sizeof(szInfo), "%d", GetClientOfUserId(StringToInt(szInfo)));
		}
		
		Format(szBuffer, sizeof(szBuffer), "{%s}", szBuffer);
		ReplaceString(szCommand, sizeof(szCommand), szBuffer, szInfo);
		
		MyServerCommand(szCommand, sizeof(szCommand));
	}
	else if ( action == MenuAction_Cancel && iSlot == MenuCancel_ExitBack ) {
		char szHandle[16]; 
		FormatEx(szHandle, sizeof(szHandle), "%d", hMenu);
		
		Handle hBackHandle;
		if ( g_hTrie_HandleToBackHandle.GetValue(szHandle, hBackHandle) ) {
			char szBackHandle[16];
			FormatEx(szBackHandle, sizeof(szBackHandle), "%d", hBackHandle);
			
			bool bIsHandlePanel;
			g_hTrie_HandleToHandleType.GetValue(szBackHandle, bIsHandlePanel);
			if ( bIsHandlePanel ) {
				g_hCurrentPanel[iClient] = hBackHandle;
				SendPanelToClient(hBackHandle, iClient, Handle_Panel, MENU_TIME_FOREVER);
			}
			else {
				DisplayMenu(hBackHandle, iClient, MENU_TIME_FOREVER);
			}
		}
	}
	else if ( action == MenuAction_End ) {
		CloseHandle(hMenu);
	}
}

void MyServerCommand(char[] szCommand, int iLen)
{
	if ( StrContains(szCommand, "{q1}") == 0 ) {
		ReplaceString(szCommand, iLen, "{q1}", ";");
	}
	else if ( StrContains(szCommand, "{q2}") == 0 ) {
		ReplaceString(szCommand, iLen, "{q2}", ";");
	}
	ServerCommand(szCommand);
}