# Agenda unifié CFE-CGC Orange FC : présentation détaillée du projet

> Document de briefing destiné à servir de base à une notice d'utilisation, à des pages d'aide en ligne et à des supports de présentation « façon offre ». Il décrit **ce que fait le site, comment on s'en sert, ce que chaque fonction apporte, et comment c'est construit**.

- **Adresse du site** : https://ccffeetest.github.io/agenda-cfecgc/
- **Nom affiché** : « Agenda unifié CFE-CGC Orange FC », sous-titre « événements publics »
- **Statut** : version de démonstration en cours de test (panneau « travaux » affiché dans l'en-tête)
- **Langue** : français
- **Supports** : ordinateur, tablette, smartphone (iPhone et Android), mode clair et mode nuit

---

## 1. En une phrase

Un agenda **unique, clair et toujours à jour** qui rassemble tous les rendez-vous publics de la CFE-CGC Orange (accueils café, conférences, webinaires, formations, élections, réunions d'information…), qu'ils soient publiés sur le site national ou annoncés par email, avec une vue par jour, une vue calendrier et une carte de France des lieux.

## 2. Le problème résolu

- Les événements sont **dispersés** : une partie est publiée sur le site cfecgc-orange.org (rubrique Événements, présentée en liste paginée), une autre circule **uniquement par email** (invitations transférées, webinaires de partenaires, salons…).
- Sur le site d'origine, il est difficile de voir **d'un coup d'œil** ce qui se passe un jour donné, **où** cela se passe, et **comment y participer** (sur place, Teams, hybride).
- Les informations pratiques (lieu, mode de participation, intervenants) sont souvent enfouies dans le texte de chaque événement.

**L'Agenda unifié** réunit tout au même endroit, extrait automatiquement les informations utiles et les présente de trois façons complémentaires, sur tous les écrans.

## 3. Les points forts (argumentaire)

| Point fort | Ce que ça apporte |
|---|---|
| **Un seul agenda pour toutes les sources** | Site national + communications email réunis, chaque événement indique clairement son origine. |
| **Toujours à jour, sans intervention** | Mise à jour automatique trois fois par jour (8h, 14h, 18h, heure de Paris). Les événements passés disparaissent seuls. |
| **Trois vues au choix** | Journée (frise horaire), mois (calendrier), France (carte). On choisit selon la question qu'on se pose : « quoi aujourd'hui ? », « quand ce mois-ci ? », « près de chez moi ? ». |
| **Informations pratiques extraites automatiquement** | Lieu (ville, département, site Orange), mode de participation (présentiel, Teams/distanciel, hybride), durée, événements sur plusieurs jours. |
| **Filtres et recherche instantanés** | Par origine, mode de participation, grande région ; recherche plein texte (titre, description, lieu, intervenants). |
| **Pensé mobile** | Interface tactile dédiée : barre fixe, onglets toujours accessibles, glisser du doigt pour changer de jour ou de mois, filtres en panneau qui monte du bas. |
| **Lisible de jour comme de nuit** | Mode nuit en un clic, choix mémorisé. |
| **Respect de la vie privée** | Aucun compte, aucun cookie, aucune donnée personnelle collectée. Les liens de suivi des emails ne sont jamais publiés. |
| **Gratuit à héberger, robuste** | Site statique hébergé sur GitHub Pages ; en cas de panne de la source, la version précédente reste en ligne. |

## 4. Prise en main rapide

1. Ouvrir l'adresse du site (aucune installation, aucun compte).
2. L'onglet **Prochains événements** s'affiche : choisir une date en haut, voir la journée sur la frise à gauche et le détail des rendez-vous à droite.
3. Passer à **Agenda (Calendrier)** pour une vue du mois, ou à **Carte des événements** pour voir où ils ont lieu.
4. Utiliser la **loupe** pour chercher un mot (ville, intervenant, thème) et **Filtres** pour n'afficher que ce qui vous intéresse.
5. Cliquer sur un événement pour le déplier, puis sur **« Voir le détail → »** pour ouvrir sa page sur le site d'origine.

## 5. L'écran en détail

### 5.1 En-tête

- **Titre** « Agenda unifié CFE-CGC Orange FC » et sous-titre « événements publics ».
- **Panneau « travaux »** : rappelle qu'il s'agit d'une version de démonstration. Au survol (ordinateur) ou au toucher (mobile), un message s'affiche : *« Version de démonstration en cours de test ! Certains événements peuvent être manquants (notamment ceux diffusés par mail) »*.
- **Recherche** (raccourci clavier Ctrl+K / ⌘K sur ordinateur, icône loupe sur mobile).
- **Filtres** : ouvre le panneau de filtres ; une **pastille rouge « − »** apparaît sur le bouton dès que des filtres masquent des événements, pour ne jamais oublier qu'on regarde une sélection.
- **Mode nuit** : interrupteur clair / sombre, mémorisé sur l'appareil (par défaut : réglage du système).
- **Ligne d'informations** : date et heure de la dernière mise à jour et nombre d'événements par origine, par exemple *« 20 événements (14 sur cfecgc-orange.org + 6 issus des emails) »*.

### 5.2 Les trois onglets

L'interface est organisée en **trois onglets exclusifs**. Sur ordinateur, la colonne de gauche (≈ 40 %) contient l'outil de navigation de l'onglet, la colonne de droite (≈ 60 %) les fiches des rendez-vous correspondants.

#### Onglet 1 : Prochains événements (vue par défaut)

- **Sélecteur de dates** : uniquement les jours ouvrés qui ont des rendez-vous (aujourd'hui toujours présent), avec le nombre de rendez-vous de chaque jour. Autant de dates que la largeur le permet ; flèches ‹ › pour avancer ou reculer ; sur écran tactile, **glisser vers la gauche ou la droite**.
- **Frise horaire 8h–20h** : chaque rendez-vous est un bloc coloré dont la position et la hauteur correspondent exactement à l'horaire ; la **durée** est écrite dans le bloc (« 1h30 », « 4h+ » pour un événement sur plusieurs jours). Les rendez-vous **simultanés sont placés côte à côte**, jusqu'à 7 en parallèle, sans jamais se chevaucher. Un trait rouge indique l'heure actuelle le jour même.
- **Fiches des rendez-vous** (à droite, ou à côté de la frise sur mobile) : même couleur que leur bloc dans la frise.
- **Lien frise ↔ fiches** : cliquer un bloc met en évidence et déplie la fiche correspondante et fait défiler jusqu'à elle ; survoler l'un éclaire l'autre.

**Le plus** : on voit immédiatement l'enchaînement de la journée, les créneaux qui se chevauchent et les moments libres.

#### Onglet 2 : Agenda (Calendrier)

- **Mois du lundi au vendredi**, avec une pastille indiquant le nombre de rendez-vous de chaque jour. Navigation de mois en mois (flèches ou glisser du doigt), du mois courant jusqu'au dernier mois où un événement est connu.
- Cliquer un jour affiche ses rendez-vous ; cliquer le **nom du mois** affiche **tous les rendez-vous du mois**, regroupés par jour.
- Les jours sans rendez-vous ne sont pas cliquables (sauf aujourd'hui, qui affiche « Aucun événement n'est encore prévu aujourd'hui »).

**Le plus** : la vision d'ensemble du mois pour planifier, et la liste complète du mois en un clic.

#### Onglet 3 : Carte des événements

- **Carte de France interactive** (OpenStreetMap) avec un repère par lieu et le **nombre de rendez-vous** ; les lieux proches se **regroupent** et se séparent en zoomant.
- Toucher / cliquer un repère affiche **tous les rendez-vous de ce lieu**, sans limite ; ouvrir une fiche **recentre la carte** sur son lieu.
- À droite : la **liste des lieux classés par grande région** (Île-de-France, Nord-Est, Nord-Ouest, Sud-Est, Sud-Ouest, Corse, Hors Métropole), avec leur nombre de rendez-vous et leurs dates.
- Interrupteur **« événements géolocalisés »** : en le coupant, on liste les rendez-vous **à distance ou non géolocalisés** (Teams, webinaires, en ligne…), qui ne sont jamais placés artificiellement sur la carte.

**Le plus** : trouver en un regard les rendez-vous près de chez soi ou d'un site Orange donné.

### 5.3 La fiche d'un rendez-vous

Chaque rendez-vous est présenté sous la même forme dans les trois onglets :

- **Horaire** de début et de fin (ou « Horaire non précisé »), événements sur plusieurs jours signalés « (+3 jours) ».
- **Origine** : pastille « Calendrier national » ou « Communication email » ; pastille grise **« événement terminé »** une fois l'heure de fin passée (le rendez-vous devient grisé).
- **Titre**.
- **Lieu** (avec le numéro de département quand c'est une ville, par exemple « Orléans (45) », ou le nom du site Orange).
- **Mode de participation** avec icône : Présentiel, Teams / Distanciel, Hybride (rien n'est affiché quand il n'est pas identifiable, pour ne jamais induire en erreur).
- **Lien « Voir le détail → »** vers la page de l'événement sur cfecgc-orange.org ; pour une communication email : **« → voir mail (s'inscrire) »**, qui renvoie vers la page d'inscription aux communications de la CFE-CGC Orange.
- **Description** : visible quand on déplie la fiche (clic ou toucher). Les fiches sont dépliées d'office quand la journée compte peu de rendez-vous ; un nouveau clic les replie.

### 5.4 Filtres

Le panneau **Filtres** s'ouvre à droite sur ordinateur, en panneau qui monte du bas sur mobile et tablette. Il propose, avec le nombre de rendez-vous pour chaque choix :

- **Origine des événements** : Calendrier national, Communications email.
- **Mode de participation** : Présentiel, Distanciel / Teams, Hybride, Non détecté (avec une explication : le mode n'a pas pu être identifié, par exemple quand il faut cliquer sur un bouton dans un mail pour l'obtenir).
- **Lieu (quand identifié)** : par grande région.

Ergonomie :
- seuls les **choix utiles** sont proposés : une catégorie sans rendez-vous est masquée, et un groupe entier disparaît s'il ne permet pas de distinguer au moins deux catégories ;
- les choix restent **provisoires** jusqu'à « **Appliquer les filtres (N éléments masqués)** », qui annonce combien de rendez-vous seront retirés de l'affichage ; « Sortir du menu » quand rien n'est masqué ;
- « **Réinitialiser (ne rien filtrer)** » remet tout à zéro ; fermer le panneau sans appliquer conserve les filtres précédents ;
- les filtres sont **mémorisés** sur l'appareil et s'appliquent aux trois onglets (frise, calendrier, carte, compteurs).

### 5.5 Recherche

- Recherche **instantanée** pendant la frappe, **sans tenir compte des accents ni des majuscules**.
- Porte sur le titre, la description, le lieu et **le texte complet de la page d'origine** (ce qui permet de retrouver un **intervenant** cité seulement dans le détail).
- S'applique aux trois vues, en plus des filtres ; bouton ✕ pour effacer.

## 6. Ergonomie et confort d'utilisation

- **Cohérence** : un seul orange de marque pour tout ce qui est sélectionné ou actif, même survol orange clair partout, même fiche dans tous les onglets.
- **Couleurs pastel par rendez-vous** : chaque rendez-vous garde la même couleur dans la frise et sur sa fiche, quelle que soit la vue.
- **Mémoire de la navigation** : l'onglet, la date, le lieu, la recherche sont conservés lors de la mise à jour automatique de la page (toutes les 15 minutes, uniquement si l'utilisateur est inactif, pour ne jamais l'interrompre).
- **Accessibilité** : navigation au clavier (onglets aux flèches, Entrée pour ouvrir une fiche, Échap pour fermer), libellés pour lecteurs d'écran, préférence « animations réduites » respectée.
- **Séparateurs et libellés soignés** : format d'heure lisible, pluriels justes, aucun libellé redondant.

## 7. Version mobile et tablette

Interface dédiée **jusqu'à 900 px de large** (smartphones et tablettes), avec les mêmes fonctions que sur ordinateur :

- **Barre du haut fixe** : titre, panneau travaux, loupe, filtres, mode nuit sous forme d'icônes ; **onglets toujours visibles** ; toucher un onglet **remonte en haut** de la page.
- **Prochains événements** : dates et frise **restent fixes**, seules les fiches défilent à côté de la frise ; fiches compactes (lieu affiché quand on déplie), horaire au format court « 16:00-17:00 », pastilles courtes « national » / « mail ».
- **Glisser du doigt** pour changer de jours (frise) ou de mois (calendrier).
- **Carte carrée** (16:10 sur tablette) pour garder la liste visible ; toucher un lieu fait défiler jusqu'à ses rendez-vous.
- **Filtres** dans un panneau qui monte du bas, boutons toujours visibles, fermeture en touchant à côté.
- Adapté aux **iPhone** (encoche, barre du bas, pas de zoom intempestif) et **Android** ; tablettes avec un peu plus de marges.

## 8. D'où viennent les informations (fonctionnement)

1. **Collecte automatique** : un script lit la rubrique Événements du site cfecgc-orange.org (jusqu'à 5 pages), puis la **page de chaque événement** pour en récupérer le texte complet et les liens.
2. **Communications email** : les événements annoncés par email et encore à venir sont ajoutés depuis un fichier dédié (alimentation prévue à terme par un automate de traitement des mails).
3. **Enrichissement automatique** :
   - **Lieu** déduit du texte (sites Orange connus, adresse postale, ville entre crochets ou en début de titre, département), puis **géolocalisé** via le service public api-adresse.data.gouv.fr, et rattaché à une **grande région** ;
   - **Mode de participation** : indices du texte (présentiel, salle, étage, accueil café… / Teams, webinaire, visio, en ligne…), **liens** (réunion Teams, fichier d'agenda .ics, outils de visio ou de réservation, y compris derrière des liens raccourcis), numéro de téléphone avec code de conférence ; « hybride » quand les deux sont présents ; jamais « présentiel » par défaut ;
   - **Événements sur plusieurs jours** repérés dans le texte (« du 7 au 10 décembre »…).
4. **Publication** : la page est régénérée et publiée automatiquement **trois fois par jour** ; si la source est indisponible, **la version précédente reste en ligne**.

## 9. Techniques utilisées

| Élément | Technique |
|---|---|
| Hébergement | GitHub Pages (site statique, gratuit, HTTPS) |
| Mise à jour automatique | GitHub Actions, trois créneaux par jour, robuste aux retards de planification |
| Collecte et enrichissement | Script Windows PowerShell 5.1 (lecture HTML, extraction, géocodage, détection du mode de participation) |
| Interface | HTML + CSS + JavaScript « vanilla » (sans framework), une seule page |
| Carte | Leaflet 1.9 + regroupement des repères (Leaflet.markercluster), fonds OpenStreetMap |
| Géocodage | API Adresse (data.gouv.fr), service public gratuit |
| Style | Feuille de style unique organisée en sections, toutes les couleurs et tailles en variables ; mode sombre ; mise en page responsive (ordinateur / tablette / mobile) |
| Statistiques de visite | GoatCounter : compteur anonyme, sans cookie ni donnée personnelle |
| Versions | Historique Git, versions de référence étiquetées pour revenir en arrière à tout moment |

## 10. Confidentialité et sécurité

- **Aucun compte, aucun cookie**, aucune donnée personnelle des visiteurs.
- Statistiques de fréquentation **anonymes** (nombre de visites, type d'appareil, pays), sans adresse IP conservée côté site.
- Les **emails sources ne sont jamais publiés** : ni expéditeurs, ni destinataires, ni liens de suivi ou d'inscription personnels ; seule l'information de l'événement est reprise.
- Seuls les rendez-vous **publics et à venir** sont affichés.

## 11. Limites actuelles (à mentionner dans l'aide)

- Version de démonstration : certains événements, notamment ceux diffusés par email, peuvent manquer.
- Les informations déduites automatiquement (lieu, mode de participation) peuvent être absentes quand le texte ne les précise pas ; le détail fait toujours foi sur le site d'origine.
- Un événement sur plusieurs jours disparaît une fois son premier jour passé.
- Le calendrier et la frise n'affichent que les jours ouvrés (lundi–vendredi).

## 12. Idées de rubriques pour l'aide en ligne

- Démarrer en 1 minute
- Lire la frise horaire
- Trouver les rendez-vous d'un mois
- Trouver un rendez-vous près de chez moi (carte)
- Filtrer : origine, mode de participation, région
- Rechercher un intervenant ou un thème
- Utiliser l'agenda sur smartphone et tablette (gestes, barre fixe)
- Mode nuit
- Comprendre les pastilles (national, mail, terminé) et les icônes (présentiel, Teams, hybride)
- D'où viennent les informations ? Fréquence de mise à jour
- Confidentialité
- Questions fréquentes (événement manquant, lieu absent, différence avec le site national…)
