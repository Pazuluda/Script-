# VERIFIE L'ELEVATION ADMIN
IF (-NOT ([SECURITY.PRINCIPAL.WINDOWSPRINCIPAL][SECURITY.PRINCIPAL.WINDOWSIDENTITY]::GETCURRENT()).ISINROLE([SECURITY.PRINCIPAL.WINDOWSBUILTINROLE] "ADMINISTRATOR")) {
    WRITE-WARNING "CE SCRIPT DOIT ETRE LANCE EN TANT QU'ADMINISTRATEUR !"
    PAUSE
    EXIT
}

FUNCTION PAUSE-ECRAN {
    WRITE-HOST ""
    READ-HOST "APPUYE SUR ENTREE POUR CONTINUER..." -FOREGROUNDCOLOR DARKGRAY
}

FUNCTION SHOW-MENUCENTERED {
    PARAM (
        [STRING[]]$LINES,
        [CONSOLECOLOR]$COLOR = "WHITE"
    )
    $WINDOWWIDTH = $HOST.UI.RAWUI.WINDOWSIZE.WIDTH
    $WINDOWHEIGHT = $HOST.UI.RAWUI.WINDOWSIZE.HEIGHT
    $MENUHEIGHT = $LINES.COUNT
    $TOPPADDING = [MATH]::MAX(0, [MATH]::FLOOR(($WINDOWHEIGHT - $MENUHEIGHT) / 2))
    FOR ($I = 0; $I -LT $TOPPADDING; $I++) { WRITE-HOST "" }
    FOREACH ($LINE IN $LINES) {
        $PADDING = [MATH]::MAX(0, [MATH]::FLOOR(($WINDOWWIDTH - $LINE.LENGTH) / 2))
        $OUT = (" " * $PADDING) + $LINE
        WRITE-HOST $OUT -FOREGROUNDCOLOR $COLOR
    }
}

# NOUVELLE VERSION : INSTALL-HYPERV CHOIX MANUEL SERVER/NORMAL
FUNCTION INSTALL-HYPERV {
    WRITE-HOST "CHOISIS LE TYPE D'INSTALLATION HYPER-V :" -FOREGROUNDCOLOR CYAN
    WRITE-HOST "1. WINDOWS CLIENT (STANDARD)"
    WRITE-HOST "2. WINDOWS SERVER (AVEC INTERFACE GRAPHIQUE)"
    WRITE-HOST "3. WINDOWS SERVER CORE"
    $CHOIX = READ-HOST "TON CHOIX ? [1/2/3]"

    IF ($CHOIX -EQ "1") {
        IF (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
            IF ($feature.State -eq 'Enabled') {
                WRITE-HOST "HYPER-V EST DEJA INSTALLE SUR CE POSTE CLIENT !" -FOREGROUNDCOLOR GREEN
            } ELSE {
                WRITE-HOST "INSTALLATION DE HYPER-V POUR WINDOWS CLIENT..." -FOREGROUNDCOLOR YELLOW
                Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
                WRITE-HOST "INSTALLATION TERMINEE. REDMARREZ LA MACHINE." -FOREGROUNDCOLOR CYAN
            }
        } ELSE {
            WRITE-HOST "COMMANDE 'GET-WINDOWSOPTIONALFEATURE' INTROUVABLE !" -FOREGROUNDCOLOR RED
        }
    }
    ELSEIF ($CHOIX -EQ "2") {
        IF (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
            $feature = Get-WindowsFeature -Name Hyper-V
            IF ($feature -and $feature.InstallState -eq "Installed") {
                WRITE-HOST "HYPER-V EST DEJA INSTALLE SUR CE SERVEUR (GUI) !" -FOREGROUNDCOLOR GREEN
            } ELSE {
                WRITE-HOST "INSTALLATION DE HYPER-V POUR WINDOWS SERVER GUI..." -FOREGROUNDCOLOR YELLOW
                Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart:$false
                WRITE-HOST "INSTALLATION TERMINEE. REDMARREZ LA MACHINE." -FOREGROUNDCOLOR CYAN
            }
        } ELSE {
            WRITE-HOST "COMMANDE 'GET-WINDOWSFEATURE' INTROUVABLE !" -FOREGROUNDCOLOR RED
        }
    }
    ELSEIF ($CHOIX -EQ "3") {
        IF (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
            $feature = Get-WindowsFeature -Name Hyper-V
            IF ($feature -and $feature.InstallState -eq "Installed") {
                WRITE-HOST "HYPER-V EST DEJA INSTALLE SUR CE SERVEUR CORE !" -FOREGROUNDCOLOR GREEN
            } ELSE {
                WRITE-HOST "INSTALLATION DE HYPER-V POUR WINDOWS SERVER CORE..." -FOREGROUNDCOLOR YELLOW
                Install-WindowsFeature -Name Hyper-V -Restart:$false
                WRITE-HOST "INSTALLATION TERMINEE. REDMARREZ LA MACHINE." -FOREGROUNDCOLOR CYAN
            }
        } ELSE {
            WRITE-HOST "COMMANDE 'GET-WINDOWSFEATURE' INTROUVABLE !" -FOREGROUNDCOLOR RED
        }
    }
    ELSE {
        WRITE-HOST "CHOIX INVALIDE !" -FOREGROUNDCOLOR RED
    }
    PAUSE-ECRAN
}

FUNCTION ENSURE-FIREWALLRUNNING {
    $FW = GET-SERVICE MPSSVC -ERRORACTION SILENTLYCONTINUE
    IF ($NULL -EQ $FW) {
        WRITE-HOST "LE SERVICE DE PARE-FEU WINDOWS (MPSSVC) EST INTROUVABLE ! (CORE SYSTEME ENDOMMAGE ?)" -FOREGROUNDCOLOR RED
        PAUSE-ECRAN
        RETURN $FALSE
    }
    IF ($FW.STATUS -NE 'RUNNING') {
        WRITE-HOST "LE SERVICE DE PARE-FEU WINDOWS N'EST PAS ACTIF, DEMARRAGE..." -FOREGROUNDCOLOR YELLOW
        TRY {
            START-SERVICE MPSSVC -ERRORACTION STOP
            SET-SERVICE MPSSVC -STARTUPTYPE AUTOMATIC
            START-SLEEP 1
        } CATCH {
            WRITE-HOST "IMPOSSIBLE DE DEMARRER LE SERVICE PARE-FEU ! (DROITS ?)" -FOREGROUNDCOLOR RED
            PAUSE-ECRAN
            RETURN $FALSE
        }
    }
    RETURN $TRUE
}

FUNCTION ENSURE-WINRMREADY {
    $WINRM = GET-SERVICE WINRM -ERRORACTION SILENTLYCONTINUE
    IF ($NULL -EQ $WINRM -OR $WINRM.STATUS -NE "RUNNING") {
        TRY {
            START-SERVICE WINRM -ERRORACTION STOP
            SET-SERVICE WINRM -STARTUPTYPE AUTOMATIC
        } CATCH {
            WRITE-HOST "IMPOSSIBLE DE DEMARRER WINRM (DROITS OU BLOQUAGE SYSTEME) !" -FOREGROUNDCOLOR RED
            RETURN $FALSE
        }
    }
    TRY {
        $RULES = @(
            "WINRM-HTTP-IN-TCP",
            "WINRM-HTTP-IN-TCP-DOMAIN",
            "WINRM-HTTP-IN-TCP-PRIVATE",
            "WINRM-HTTP-IN-TCP-PUBLIC",
            "WINRM-HTTPS-IN-TCP",
            "WINRM-HTTPS-IN-TCP-DOMAIN",
            "WINRM-HTTPS-IN-TCP-PRIVATE",
            "WINRM-HTTPS-IN-TCP-PUBLIC"
        )
        FOREACH ($R IN $RULES) {
            TRY { ENABLE-NETFIREWALLRULE -NAME $R } CATCH {}
        }
    } CATCH {}
    TRY {
        TEST-WSMAN LOCALHOST | OUT-NULL
        WRITE-HOST "WINRM OK, GESTION DISTANTE POSSIBLE !" -FOREGROUNDCOLOR GREEN
        RETURN $TRUE
    } CATCH {
        WRITE-HOST "WINRM SEMBLE NE PAS REPONDRE, VERIFIE LES ERREURS !" -FOREGROUNDCOLOR RED
        RETURN $FALSE
    }
}

FUNCTION GET-GROUPNAME {
    PARAM (
        [STRING[]]$CANDIDATES
    )
    FOREACH ($NAME IN $CANDIDATES) {
        IF (GET-LOCALGROUP -NAME $NAME -ERRORACTION SILENTLYCONTINUE) {
            RETURN $NAME
        }
    }
    RETURN $null  # AUCUN GROUPE TROUVE
}

FUNCTION GET-GROUPSHYPERV {
    $HVADMINNAMES = @("ADMINISTRATEURS HYPER-V", "HYPER-V ADMINISTRATORS")
    RETURN @{
        HVADMIN     = GET-GROUPNAME $HVADMINNAMES
    }
}

# -------- AJOUT GROUPE GESTION A DISTANCE PAR SID ----------
FUNCTION AJOUT-UTILISATEUR-GESTION-A-DISTANCE {
    $SID = "S-1-5-32-580"
    TRY {
        $groupe = Get-LocalGroup -SID $SID -ErrorAction Stop
        $nomGroupe = $groupe.Name
        $utilisateur = READ-HOST "NOM DE L UTILISATEUR LOCAL A AJOUTER"
        TRY {
            Add-LocalGroupMember -Group $nomGroupe -Member $utilisateur -ErrorAction Stop
            Write-Host "UTILISATEUR $utilisateur AJOUTE AU GROUPE $nomGroupe (SID $SID)" -ForegroundColor Green
        } CATCH {
            Write-Host "ECHEC DE L'AJOUT : $_" -ForegroundColor Red
        }
    } CATCH {
        Write-Host "LE GROUPE GESTION A DISTANCE (SID $SID) EST INTROUVABLE SUR CETTE MACHINE !" -ForegroundColor Red
    }
    PAUSE-ECRAN
}
# -----------------------------------------------------------

# --------- GENERATEUR .REG CREDSSP AVEC IMPORT ----------
FUNCTION GENERER-REG-MULTI {
    CLEAR-HOST
    WRITE-HOST "+------------------------------------------------------------------+" -ForegroundColor Cyan
    WRITE-HOST "|   GENERATEUR DE FICHIER .REG (IMPORTATION MASSIVE CREDSSP)       |" -ForegroundColor Cyan
    WRITE-HOST "+------------------------------------------------------------------+" -ForegroundColor Cyan
    WRITE-HOST "|   EXEMPLE DE CONTENU .REG POUR CREDSSP (A EDITER MANUELLEMENT)   |" -ForegroundColor Yellow
    WRITE-HOST "|                                                                  |" -ForegroundColor Yellow
    WRITE-HOST "|   Windows Registry Editor Version 5.00                           |" -ForegroundColor Yellow
    WRITE-HOST "|                                                                  |" -ForegroundColor Yellow
    WRITE-HOST "|   [HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows\\CredentialsDelegation\\AllowFreshCredentials]" -ForegroundColor Yellow
    WRITE-HOST '|   "1"="wsman/SERV1"' -ForegroundColor Yellow
    WRITE-HOST '|   "2"="wsman/SERV2"' -ForegroundColor Yellow
    WRITE-HOST "|                                                                  |" -ForegroundColor Yellow
    WRITE-HOST "|   [HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows\\CredentialsDelegation\\AllowFreshCredentialsWhenNTLMOnly]" -ForegroundColor Yellow
    WRITE-HOST '|   "1"="wsman/SERV1"' -ForegroundColor Yellow
    WRITE-HOST '|   "2"="wsman/SERV2"' -ForegroundColor Yellow
    WRITE-HOST "|                                                                  |" -ForegroundColor Yellow
    WRITE-HOST "+------------------------------------------------------------------+" -ForegroundColor Cyan
    WRITE-HOST ""
    WRITE-HOST "LE FICHIER EXEMPLE VA S'OUVRIR DANS NOTEPAD." -ForegroundColor White
    WRITE-HOST "EDITE-LE AVEC TES VALEURS REELLES, ENREGISTRE PUIS FERME LE FICHIER." -ForegroundColor White

    $exemple = @'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentials]
"1"="wsman/SERV1"
"2"="wsman/SERV2"

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly]
"1"="wsman/SERV1"
"2"="wsman/SERV2"
'@
    $regPath = "$env:USERPROFILE\Desktop\import-credssp.reg"
    $exemple | Out-File -Encoding ASCII -FilePath $regPath

    # Ouvre Notepad et attend qu'il soit fermé
    $notepad = Start-Process notepad $regPath -PassThru
    $notepad.WaitForExit()

    # Propose d'importer après fermeture du notepad
    $rep = Read-Host "VOULEZ-VOUS IMPORTER CE FICHIER DANS LE REGISTRE ? (O/N)"
    if ($rep -match '^[oOyY]') {
        try {
            Start-Process regedit.exe "/s `"$regPath`"" -Verb RunAs
            Write-Host "IMPORTATION LANCEE !" -ForegroundColor Green
        } catch {
            Write-Host "ECHEC DE  L'IMPORTATION (DROIT ADMIN ?) !" -ForegroundColor Red
        }
    } else {
        Write-Host "IMPORTATION ANNULEE." -ForegroundColor Yellow
    }
    PAUSE-ECRAN
}
# --------------------------------------------------------

FUNCTION MENU-SERVEUR {
    $GROUPS = GET-GROUPSHYPERV
    $INFOSHOWN = $TRUE
    WHILE ($TRUE) {
        CLEAR-HOST
        $SERVMENU = @(
            "+--------------------------------------------------------------------------+",
            "|                       MENU SERVEUR HYPER-V                               |",
            "+--------------------------------------------------------------------------+",
            "| I. INSTALLER OU VERIFIER HYPER-V SUR CE SERVEUR                          |",
            "| 1. ACTIVER POWERSHELL REMOTING                                           |",
            "| 2. ACTIVER CREDSSP (SERVEUR)                                             |",
            "| 3. AJOUTER UN UTILISATEUR AUX GROUPES HYPER-V ET GESTION A DISTANCE      |",
            "| 4. AFFICHER LES PROFILS RESEAU                                           |",
            "| 5. CHANGER UN PROFIL RESEAU EN PRIVE                                     |",
            "| 6. AFFICHER TOUTES LES COMMANDES A COPIER COLLER                         |",
            "| R. RAFRAICHIR LE MENU                                                    |",
            "| 0. RETOUR MENU PRINCIPAL                                                 |",
            "+--------------------------------------------------------------------------+"
        )
        SHOW-MENUCENTERED $SERVMENU GREEN
        IF ($INFOSHOWN) {
            WRITE-HOST "`nSI LE MENU N EST PLUS CENTRE, REDIMENSIONNE LA FENETRE ET TAPE 'R' POUR RAFRAICHIR LE MENU." -FOREGROUNDCOLOR DARKGRAY
            $INFOSHOWN = $FALSE
        }
        WRITE-HOST ""
        $SERVOPT = READ-HOST "CHOISIS UNE OPTION"
        SWITCH ($SERVOPT) {
            "I" { INSTALL-HYPERV }
            "i" { INSTALL-HYPERV }
            "1" {
                IF (ENSURE-FIREWALLRUNNING) {
                    IF (ENSURE-WINRMREADY) {
                        ENABLE-PSREMOTING -FORCE
                        WRITE-HOST "POWERSHELL REMOTING ACTIVE !" -FOREGROUNDCOLOR GREEN
                    }
                }
                PAUSE-ECRAN
            }
            "2" {
                IF (ENSURE-FIREWALLRUNNING) {
                    IF (ENSURE-WINRMREADY) {
                        ENABLE-WSMANCREDSSP -ROLE SERVER -FORCE
                        WRITE-HOST "CREDSSP ACTIVE SUR LE SERVEUR !" -FOREGROUNDCOLOR GREEN
                    }
                }
                PAUSE-ECRAN
            }
            "3" {
                # Ajout dans Admin Hyper-V
                IF ($GROUPS.HVADMIN) {
                    $USER = READ-HOST "NOM DE L UTILISATEUR LOCAL A AJOUTER"
                    TRY {
                        ADD-LOCALGROUPMEMBER -GROUP $GROUPS.HVADMIN -MEMBER $USER -ErrorAction Stop
                        Write-Host "UTILISATEUR AJOUTE AU GROUPE $($GROUPS.HVADMIN)." -ForegroundColor Green
                    } CATCH {
                        Write-Host "ERREUR AJOUT $($GROUPS.HVADMIN) : $_" -ForegroundColor Red
                    }
                } ELSE {
                    Write-Host "GROUPE ADMINISTRATEURS HYPER-V  INTROUVABLE !" -FOREGROUNDCOLOR RED
                }
                # Ajout dans Gestion à distance (toujours par SID)
                AJOUT-UTILISATEUR-GESTION-A-DISTANCE
            }
            "4" { WRITE-HOST "PROFILS RESEAU ACTUELS :" -FOREGROUNDCOLOR GREEN; GET-NETCONNECTIONPROFILE; PAUSE-ECRAN }
            "5" {
                WRITE-HOST "PROFILS RESEAU ACTUELS :" -FOREGROUNDCOLOR GREEN
                GET-NETCONNECTIONPROFILE
                $ID = READ-HOST "INDIQUE L INTERFACEINDEX A METTRE EN PRIVE"
                SET-NETCONNECTIONPROFILE -INTERFACEINDEX $ID -NETWORKCATEGORY PRIVATE
                WRITE-HOST "INTERFACE $ID PASSE EN PRIVE." -FOREGROUNDCOLOR GREEN
                PAUSE-ECRAN
            }
            "6" {
                WRITE-HOST "COMMANDES A COPIER COLLER COTE SERVEUR :" -FOREGROUNDCOLOR GREEN
                WRITE-HOST ""
                WRITE-HOST 'GET-NETCONNECTIONPROFILE'
                WRITE-HOST 'SET-NETCONNECTIONPROFILE -INTERFACEINDEX <ID_INTERFACE> -NETWORKCATEGORY PRIVATE'
                WRITE-HOST 'ENABLE-PSREMOTING -FORCE'
                WRITE-HOST 'ENABLE-WSMANCREDSSP -ROLE SERVER -FORCE'
                WRITE-HOST 'ADD-LOCALGROUPMEMBER -GROUP \"ADMINISTRATEURS HYPER-V\" -MEMBER \"<NOM_UTILISATEUR>\"'
                WRITE-HOST 'ADD-LOCALGROUPMEMBER -GROUP \"HYPER-V ADMINISTRATORS\" -MEMBER \"<NOM_UTILISATEUR>\"'
                WRITE-HOST 'ADD-LOCALGROUPMEMBER -GROUP \"UTILISATEURS DE GESTION A DISTANCE\" -MEMBER \"<NOM_UTILISATEUR>\"'
                WRITE-HOST 'ADD-LOCALGROUPMEMBER -GROUP \"REMOTE MANAGEMENT USERS\" -MEMBER \"<NOM_UTILISATEUR>\"'
                PAUSE-ECRAN
            }
            "R" { $INFOSHOWN = $TRUE; CONTINUE }
            "r" { $INFOSHOWN = $TRUE; CONTINUE }
            "0" { RETURN }
            DEFAULT { $INFOSHOWN = $TRUE; WRITE-HOST \"CHOIX INCONNU !\" -FOREGROUNDCOLOR RED; PAUSE-ECRAN }
        }
    }
}

FUNCTION MENU-CLIENT {
    $INFOSHOWN = $TRUE
    WHILE ($TRUE) {
        CLEAR-HOST
        $CLIMENU = @(
            "+--------------------------------------------------------------------------+",
            "|                         MENU CLIENT HYPER-V & CREDSSP                   |",
            "+--------------------------------------------------------------------------+",
            "| I. INSTALLER OU VERIFIER HYPER-V SUR CE POSTE CLIENT                     |",
            "| 1. DEMARRER WINRM                                                        |",
            "| 2. AJOUTER LE SERVEUR AUX TRUSTEDHOSTS                                   |",
            "| 3. ACTIVER CREDSSP (CLIENT)                                              |",
            "| 4. AFFICHER LES PROFILS RESEAU                                           |",
            "| 5. CHANGER UN PROFIL RESEAU EN PRIVE                                     |",
            "| 6. AJOUTER ENTREE DANS HOSTS (OUVERTURE NOTEPAD)                         |",
            "| 7. GENERATEUR FICHIER .REG CREDSSP                                       |",
            "| R. RAFRAICHIR LE MENU                                                    |",
            "| 0. RETOUR MENU PRINCIPAL                                                 |",
            "+--------------------------------------------------------------------------+"
        )
        SHOW-MENUCENTERED $CLIMENU YELLOW
        IF ($INFOSHOWN) {
            WRITE-HOST "`nPOUR GENERER UN FICHIER .REG POUR CREDSSP (OPTION 7), REDIMENSIONNER LA FENETRE AVEC R." -FOREGROUNDCOLOR DARKGRAY
            $INFOSHOWN = $FALSE
        }
        $CLIOPT = READ-HOST "CHOISIS UNE OPTION"
        SWITCH ($CLIOPT) {
            "I" { INSTALL-HYPERV }
            "i" { INSTALL-HYPERV }
            "1" { ENSURE-WINRMREADY | OUT-NULL; WRITE-HOST "WINRM DEMARRE." -FOREGROUNDCOLOR GREEN; PAUSE-ECRAN }
            "2" {
                $SERV = READ-HOST "NOM DU SERVEUR HYPER-V (POUR PLUSIEURS, SEPARE PAR UNE VIRGULE)"
                IF ($SERV -IS [SYSTEM.ARRAY]) { $SERV = $SERV -JOIN "," }
                SET-ITEM WSMAN:\LOCALHOST\CLIENT\TRUSTEDHOSTS -VALUE "$SERV"
                WRITE-HOST "$SERV AJOUTE AUX TRUSTEDHOSTS." -FOREGROUNDCOLOR GREEN
                PAUSE-ECRAN
            }
            "3" {
                $SERV = READ-HOST "NOM DU SERVEUR HYPER-V"
                ENABLE-WSMANCREDSSP -ROLE CLIENT -DELEGATECOMPUTER $SERV -FORCE
                WRITE-HOST "CREDSSP ACTIVE POUR $SERV." -FOREGROUNDCOLOR GREEN
                PAUSE-ECRAN
            }
            "4" { WRITE-HOST "PROFILS RESEAU ACTUELS :" -FOREGROUNDCOLOR YELLOW; GET-NETCONNECTIONPROFILE; PAUSE-ECRAN }
            "5" {
                WRITE-HOST "PROFILS RESEAU ACTUELS :" -FOREGROUNDCOLOR YELLOW
                GET-NETCONNECTIONPROFILE
                $ID = READ-HOST "INDIQUE L INTERFACEINDEX A METTRE EN PRIVE"
                SET-NETCONNECTIONPROFILE -INTERFACEINDEX $ID -NETWORKCATEGORY PRIVATE
                WRITE-HOST "INTERFACE $ID PASSE EN PRIVE." -FOREGROUNDCOLOR GREEN
                PAUSE-ECRAN
            }
            "6" {
                WRITE-HOST "OUVERTURE DU FICHIER HOSTS AVEC NOTEPAD..." -FOREGROUNDCOLOR YELLOW
                START-PROCESS NOTEPAD "C:\\WINDOWS\\SYSTEM32\\DRIVERS\\ETC\\HOSTS"
                PAUSE-ECRAN
            }
            "7" { GENERER-REG-MULTI }
            "R" { $INFOSHOWN = $TRUE; CONTINUE }
            "r" { $INFOSHOWN = $TRUE; CONTINUE }
            "0" { RETURN }
            DEFAULT { $INFOSHOWN = $TRUE; WRITE-HOST "CHOIX INCONNU !" -FOREGROUNDCOLOR RED; PAUSE-ECRAN }
        }
    }
}

# ----------- MENU PRINCIPAL -----------
$AFFICHEINFOMENU = $TRUE
WHILE ($TRUE) {
    CLEAR-HOST
    $MAINMENU = @(
        "+------------------------------------------------------------+",
        "|      MENU DE CONFIGURATION HYPER-V DISTANT + CREDSSP       |",
        "+------------------------------------------------------------+",
        "| 1. MODE SERVEUR                                            |",
        "| 2. MODE CLIENT                                             |",
        "| 0. QUITTER                                                 |",
        "| R. RAFRAICHIR LE MENU                                      |",
        "+------------------------------------------------------------+"
    )
    SHOW-MENUCENTERED $MAINMENU CYAN
    IF ($AFFICHEINFOMENU) {
        WRITE-HOST "`nSI LE MENU N EST PLUS CENTRE, REDIMENSIONNE LA FENETRE ET TAPE 'R' POUR RAFRAICHIR LE MENU." -FOREGROUNDCOLOR DARKGRAY
        $AFFICHEINFOMENU = $FALSE
    }
    $CHOIX = READ-HOST "CHOISIS TON MODE"
    SWITCH ($CHOIX) {
        "1" { MENU-SERVEUR }
        "2" { MENU-CLIENT }
        "0" { RETURN }
        "R" { $AFFICHEINFOMENU = $TRUE; CONTINUE }
        "r" { $AFFICHEINFOMENU = $TRUE; CONTINUE }
        DEFAULT { WRITE-HOST "CHOIX INCONNU !" -FOREGROUNDCOLOR RED; PAUSE-ECRAN }
    }
}
