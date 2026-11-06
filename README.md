# Agenda CFE-CGC Orange

Page qui affiche les prochains événements de https://www.cfecgc-orange.org/evenements/ :
timeline, planning du jour et calendrier mensuel. Chaque événement renvoie vers le site d'origine.

La page est régénérée **3 fois par jour (7h, 14h et 19h, heure de Paris)** par GitHub Actions et publiée sur GitHub Pages.

## Mise en ligne (une seule fois)

1. Sur github.com, crée un **nouveau dépôt public** (par exemple `agenda-cfecgc`), sans README.
2. Envoie les fichiers du projet dans le dépôt : **Add file → Upload files**, puis glisse-dépose
   `fetch-agenda.ps1`, `README.md`, `.gitignore` et le dossier `.github` (il contient `workflows/update.yml`),
   et clique sur **Commit changes**.
   Si le dossier `.github` ne passe pas : **Add file → Create new file**, nom `.github/workflows/update.yml`,
   colle le contenu du fichier, puis **Commit changes**.
3. **Settings → Pages** : dans *Build and deployment*, choisis la source **GitHub Actions**.
4. Onglet **Actions** → *Mise a jour de l'agenda* → **Run workflow**.
   Après 2 à 3 minutes, l'adresse du site apparaît dans le résultat de l'étape *deploy*,
   et dans **Settings → Pages** (du type `https://ton-pseudo.github.io/agenda-cfecgc/`).

Ensuite, tout est automatique.

## Bon à savoir

- Si le site d'origine est inaccessible ou si aucun événement n'est trouvé, l'exécution échoue
  (croix rouge dans l'onglet *Actions*) et **la version précédente reste en ligne**.
- Les heures de déclenchement de GitHub peuvent avoir quelques minutes de retard.
- Si le dépôt ne reçoit aucune modification pendant 60 jours, GitHub met en pause les tâches
  programmées (il prévient par e-mail). Un clic sur **Enable workflow** dans l'onglet *Actions* les relance.

## En local (Windows)

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\fetch-agenda.ps1
```

génère `index.html` et ajoute une ligne dans `fetch.log`.
