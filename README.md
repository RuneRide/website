# Site vitrine de RuneRide

Site statique bilingue (français, anglais) de [runeride.fr](https://runeride.fr), sans build, sans JavaScript, sans traceur. L'application elle-même vit sur `app.runeride.fr`.

## Structure

| Chemin | Contenu |
| :-- | :-- |
| `/`, `/fonctions/`, `/univers/`, `/tarifs/` | Pages en français |
| `/en/`, `/en/features/`, `/en/universe/`, `/en/pricing/` | Pages en anglais |
| `/mentions-legales/`, `/confidentialite/`, `/cgv/` | Documents légaux (français uniquement, **brouillons**, `noindex`) |
| `/en/legal/` | Page d'orientation vers les documents légaux français |
| `assets/` | CSS (tokens de la charte), polices locales, logos, motifs, icônes, image de partage |
| `.github/workflows/deploy.yml`, `tools/ftp-setup.sh` | Déploiement continu par FTPS vers o2switch et création du compte FTP |
| `.htaccess` | Configuration Apache pour o2switch : HTTPS, sans `www`, en-têtes de sécurité (CSP stricte), cache |

Les pages sont du HTML écrit à la main : aucun style ni script en ligne (la CSP les interdit). Pour modifier un texte, éditer le fichier concerné, dans les deux langues.

## Prévisualiser

```sh
python3 -m http.server 8000   # puis http://localhost:8000/
```

## Déployer sur o2switch (intégration continue)

Chaque push sur `main` synchronise le site vers o2switch par FTPS (workflow `.github/workflows/deploy.yml`, action `FTP-Deploy-Action`). Le compte FTP, nommé `deploy-vitrine@runeride.fr`, est enfermé dans le dossier `~/vitrine` de l'espace cPanel et **pas** dans la racine web de `runeride.fr` : le déploiement ne remplace rien tant que le domaine ne pointe pas vers ce dossier (cPanel, « Domaines »).

Mise en place, une seule fois (le jeton cPanel et le mot de passe FTP ne sont jamais affichés) :

```sh
AWS_PROFILE=bike360 tools/ftp-setup.sh           # simulation
AWS_PROFILE=bike360 tools/ftp-setup.sh --apply   # crée le compte, teste la connexion, pose les secrets GitHub
gh workflow run deploy.yml --repo RuneRide/website
```

Sans les secrets `FTP_SERVER`, `FTP_USERNAME` et `FTP_PASSWORD`, le workflow ne déploie rien et le signale par un avertissement. Le `.htaccess` fourni n'est à utiliser que sur une racine qui ne porte pas aussi l'API PHP.

## Licences et usage de l'IA

Code (`.htaccess`, `assets/site.css`) : **EUPL-1.2**. Textes, logos, images et le reste : **CC BY-SA 4.0**. Polices tierces : SIL OFL 1.1. Voir `NOTICE.md` et `LICENSES/`.
