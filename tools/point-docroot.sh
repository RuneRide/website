#!/usr/bin/env bash
# SPDX-License-Identifier: EUPL-1.2
#
# Change la racine web d'un domaine (cPanel, o2switch), par exemple pour servir le site depuis ~/vitrine.
# Le jeton cPanel (AWS Secrets Manager : runeride/cpanel) ne passe jamais en argument ni à l'écran.
#
# Usage :
#   AWS_PROFILE=bike360 tools/point-docroot.sh                    # simulation : affiche la configuration du domaine
#   AWS_PROFILE=bike360 tools/point-docroot.sh --apply            # runeride.fr -> ~/vitrine
#   AWS_PROFILE=bike360 tools/point-docroot.sh --apply --dir runeride.fr   # retour arrière vers l'ancienne racine
#   options : --domain <domaine> (défaut runeride.fr), --dir <dossier relatif à ~> (défaut vitrine)
#
# L'ancienne racine n'est ni supprimée ni modifiée : seuls les fichiers servis changent.
set -euo pipefail

SECRET_ID="runeride/cpanel"; REGION="eu-north-1"
DOMAIN="runeride.fr"; DIR="vitrine"; APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --domain) DOMAIN="$2"; shift ;;
    --dir) DIR="$2"; shift ;;
    *) echo "Option inconnue : $1" >&2; exit 2 ;;
  esac
  shift
done

secret=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_ID" --query SecretString --output text)
pick() { jq -r --arg keys "$1" '[ ($keys | split(",")[]) as $k | .[$k]? | select(. != null and . != "") ] | first // empty' <<<"$secret"; }
host=$(pick host,hostname,server,url,cpanel_host)
user=$(pick user,username,login,cpanel_user)
token=$(pick token,api_token,apitoken,key,secret)
host=${host#*://}; host=${host%%/*}; host=${host%%:*}
[[ -n "$host" && -n "$user" && -n "$token" ]] || { echo "Secret inattendu (hôte, utilisateur ou jeton manquant)." >&2; exit 1; }
unset secret

# Appel cPanel ; le jeton et les valeurs passent par la configuration lue sur stdin.
# $1 = chemin après /execute/ ou /json-api/ (voir api2), puis des paires clé=valeur.
curl_call() {
  local url="$1"; shift
  {
    printf 'header = "Authorization: cpanel %s:%s"\n' "$user" "$token"
    printf 'url = "%s"\n' "$url"
    printf 'get\n'
    for kv in "$@"; do printf 'data-urlencode = "%s"\n' "$kv"; done
  } | curl -fsS -K -
}
uapi() { local fn="$1"; shift; curl_call "https://${host}:2083/execute/${fn}" "$@"; }
api2() { local mod="$1" fn="$2"; shift 2; curl_call "https://${host}:2083/json-api/cpanel" "cpanel_jsonapi_apiversion=2" "cpanel_jsonapi_module=${mod}" "cpanel_jsonapi_func=${fn}" "$@"; }

doms=$(uapi DomainInfo/domains_data "format=hash")
jq -e '.status == 1' >/dev/null <<<"$doms" || { echo "Échec cPanel :" >&2; jq -r '(.errors // ["réponse inattendue"]) | join(" ")' <<<"$doms" >&2; exit 1; }

kind=$(jq -r --arg d "$DOMAIN" '
  if .data.main_domain.domain == $d then "main"
  elif ([.data.sub_domains[]? | select(.domain == $d)] | length) > 0 then "sub"
  elif ([.data.addon_domains[]? | select(.domain == $d)] | length) > 0 then "addon"
  else "inconnu" end' <<<"$doms")
entry=$(jq -c --arg d "$DOMAIN" '[.data.main_domain, (.data.sub_domains[]?), (.data.addon_domains[]?)] | map(select(.domain == $d)) | first // {}' <<<"$doms")
main=$(jq -r '.data.main_domain.domain' <<<"$doms")
old=$(jq -r '.documentroot // ""' <<<"$entry")
servername=$(jq -r '.servername // ""' <<<"$entry")
homedir=$(jq -r '.homedir // ""' <<<"$entry")
home=${old%/*}

echo "== Configuration actuelle de $DOMAIN =="
echo "type        : $kind"
echo "racine web  : ${old:-?}"
echo "servername  : ${servername:-?}"
echo "domaine principal du compte : $main"
echo "nouvelle racine demandée    : ${home:-/home/…}/$DIR"
[[ "$kind" != "inconnu" ]] || { echo "Domaine introuvable dans ce compte cPanel." >&2; exit 1; }
[[ "$kind" != "main" ]] || { echo "C'est le domaine principal du compte : sa racine (public_html) n'est pas modifiable par cet outil." >&2; exit 1; }

# Pour un sous-domaine ou un domaine additionnel, cPanel gère la racine via un « sous-domaine » technique
sub=${servername%".$main"}
[[ -n "$servername" && "$sub" != "$servername" ]] || { echo "Impossible de déduire le sous-domaine technique à partir de '$servername'." >&2; exit 1; }
echo "sous-domaine technique : $sub (racine $main)"
echo "retour arrière : AWS_PROFILE=… tools/point-docroot.sh --apply --dir ${old#"$home"/}"

if [[ $APPLY -ne 1 ]]; then echo "(simulation : ajouter --apply pour exécuter)"; exit 0; fi
[[ "${old}" != "${home}/${DIR}" ]] || { echo "La racine pointe déjà vers ${home}/${DIR} : rien à faire."; exit 0; }

res=$(api2 SubDomain changedocroot "subdomain=$sub" "rootdomain=$main" "dir=$DIR")
if [[ "$(jq -r '.cpanelresult.data[0].result // 0' <<<"$res")" != "1" ]]; then
  echo "Échec du changement de racine :" >&2
  jq -r '.cpanelresult.data[0].reason // .cpanelresult.error // "réponse inattendue"' <<<"$res" >&2
  exit 1
fi

doms=$(uapi DomainInfo/domains_data "format=hash")
new=$(jq -r --arg d "$DOMAIN" '[.data.main_domain, (.data.sub_domains[]?), (.data.addon_domains[]?)] | map(select(.domain == $d)) | first | .documentroot' <<<"$doms")
echo "== Racine de $DOMAIN : $old  ->  $new =="
unset token
echo "== Réponse publique (peut mettre quelques secondes) =="
curl -sS -o /dev/null -w "https://$DOMAIN/ -> HTTP %{http_code}\n" "https://$DOMAIN/" || true
curl -sS "https://$DOMAIN/" | grep -o '<title>[^<]*</title>' | head -1 || true
