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
| `.htaccess` | Configuration Apache pour o2switch : HTTPS, sans `www`, en-têtes de sécurité (CSP stricte), cache |

Les pages sont du HTML écrit à la main : aucun style ni script en ligne (la CSP les interdit). Pour modifier un texte, éditer le fichier concerné, dans les deux langues.

## Prévisualiser

```sh
python3 -m http.server 8000   # puis http://localhost:8000/
```

## Déployer sur o2switch

Copier le contenu de ce dépôt (hors `.git`) à la racine web de `runeride.fr`. Le `.htaccess` fourni remplace celui de la racine : ne pas le déployer sur une racine qui porte aussi l'API PHP.

## Licences et usage de l'IA

Code (`.htaccess`, `assets/site.css`) : **EUPL-1.2**. Textes, logos, images et le reste : **CC BY-SA 4.0**. Polices tierces : SIL OFL 1.1. Voir `NOTICE.md` et `LICENSES/`.
