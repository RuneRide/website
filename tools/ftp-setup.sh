#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
#
# Crée le compte FTP de déploiement du site sur o2switch (cPanel) et enregistre ses identifiants
# comme secrets GitHub Actions du dépôt RuneRide/website (FTP_SERVER, FTP_USERNAME, FTP_PASSWORD).
#
# Le jeton cPanel (AWS Secrets Manager : runeride/cpanel) et le mot de passe FTP généré ne sont jamais
# affichés, jamais écrits sur disque et jamais passés en argument de commande (ils transitent par stdin).
#
# Le compte FTP est enfermé dans le dossier « vitrine » de l'espace cPanel, PAS dans la racine web de
# runeride.fr : le déploiement ne remplace rien tant que le domaine ne pointe pas vers ce dossier.
#
# Usage :
#   AWS_PROFILE=bike360 tools/ftp-setup.sh            # simulation : liste les racines web et les comptes FTP
#   AWS_PROFILE=bike360 tools/ftp-setup.sh --apply    # crée le compte, teste la connexion, pose les secrets
#   AWS_PROFILE=bike360 tools/ftp-setup.sh --apply --rotate   # change le mot de passe d'un compte existant
#
# Prérequis : aws (profil avec accès à Secrets Manager), gh (connecté, droit d'écrire les secrets), curl, jq, openssl.
set -euo pipefail

SECRET_ID="runeride/cpanel"; REGION="eu-north-1"; DOMAIN="runeride.fr"
FTP_USER="deploy-vitrine"; HOMEDIR="vitrine"; REPO="RuneRide/website"
LOGIN="${FTP_USER}@${DOMAIN}"

APPLY=0; ROTATE=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --rotate) ROTATE=1 ;;
    *) echo "Option inconnue : $arg" >&2; exit 2 ;;
  esac
done

secret=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_ID" --query SecretString --output text)
pick() { jq -r --arg keys "$1" '[ ($keys | split(",")[]) as $k | .[$k]? | select(. != null and . != "") ] | first // empty' <<<"$secret"; }
host=$(pick host,hostname,server,url,cpanel_host)
user=$(pick user,username,login,cpanel_user)
token=$(pick token,api_token,apitoken,key,secret)
host=${host#*://}; host=${host%%/*}; host=${host%%:*}
if [[ -z "$host" || -z "$user" || -z "$token" ]]; then
  echo "Secret inattendu : il faut un hôte, un utilisateur et un jeton. Clés présentes :" >&2
  jq -r 'if type=="object" then keys | join(", ") else "(pas un objet JSON)" end' <<<"$secret" >&2
  exit 1
fi
unset secret

# Appel UAPI cPanel. Le jeton et les valeurs passent par la configuration lue sur stdin (pas dans argv).
cp_call() {
  local fn="$1"; shift
  {
    printf 'header = "Authorization: cpanel %s:%s"\n' "$user" "$token"
    printf 'url = "https://%s:2083/execute/%s"\n' "$host" "$fn"
    printf 'get\n'
    for kv in "$@"; do printf 'data-urlencode = "%s"\n' "$kv"; done
  } | curl -fsS -K -
}
ok() { jq -e '.status == 1' >/dev/null 2>&1 <<<"$1"; }
fail() { echo "Échec cPanel :" >&2; jq -r '(.errors // ["réponse inattendue"]) | join(" ")' <<<"$1" 2>/dev/null >&2 || true; exit 1; }

echo "== Racines web des domaines (cPanel : $host) =="
doms=$(cp_call DomainInfo/domains_data "format=hash")
ok "$doms" || fail "$doms"
jq -r '.data | ([.main_domain] + (.sub_domains // []) + (.addon_domains // []))[]? | [.domain, .documentroot] | @tsv' <<<"$doms"

echo "== Comptes FTP existants =="
ftps=$(cp_call Ftp/list_ftp)
ok "$ftps" || fail "$ftps"
jq -r '.data[]? | [(.user // .serverlogin // ""), (.homedir // "")] | @tsv' <<<"$ftps"
exists=$(jq -r --arg l "$LOGIN" '[.data[]? | select((.user // .serverlogin // "") == $l)] | length' <<<"$ftps")

echo "== Plan =="
if [[ "$exists" -gt 0 && $ROTATE -eq 0 ]]; then
  echo "= Le compte $LOGIN existe déjà : rien à créer (ajouter --rotate pour changer son mot de passe et remettre les secrets)."
  exit 0
fi
if [[ "$exists" -gt 0 ]]; then echo "+ rotation du mot de passe de $LOGIN"; else echo "+ création de $LOGIN, dossier ~/$HOMEDIR, quota illimité"; fi
echo "+ secrets GitHub FTP_SERVER, FTP_USERNAME, FTP_PASSWORD sur $REPO"
if [[ $APPLY -ne 1 ]]; then echo "(simulation : ajouter --apply pour exécuter)"; exit 0; fi

pass=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-32)
if [[ "$exists" -gt 0 ]]; then
  res=$(cp_call Ftp/passwd "user=$FTP_USER" "pass=$pass" "domain=$DOMAIN")
else
  res=$(cp_call Ftp/add_ftp "user=$FTP_USER" "pass=$pass" "homedir=$HOMEDIR" "quota=0" "domain=$DOMAIN")
fi
ok "$res" || fail "$res"
echo "compte FTP prêt : $LOGIN"

# Test de connexion FTPS explicite (identifiants via stdin)
if printf 'user = "%s:%s"\nssl-reqd\nlist-only\nurl = "ftp://%s/"\n' "$LOGIN" "$pass" "$host" | curl -fsS -K - >/dev/null 2>&1; then
  echo "connexion FTPS réussie sur $host"
else
  echo "! connexion FTPS impossible sur $host (certificat, pare-feu ou délai de création) : secrets posés quand même, à vérifier" >&2
fi

printf '%s' "$host"  | gh secret set FTP_SERVER   --repo "$REPO" >/dev/null
printf '%s' "$LOGIN" | gh secret set FTP_USERNAME --repo "$REPO" >/dev/null
printf '%s' "$pass"  | gh secret set FTP_PASSWORD --repo "$REPO" >/dev/null
unset pass token
echo "secrets GitHub posés sur $REPO"
echo "Lancer le déploiement : gh workflow run deploy.yml --repo $REPO"
