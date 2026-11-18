# 🕺 Danse Réveil

Une alarme du matin qui **ne s'arrête que si tu danses**.

## Fonctionnement

1. Choisis l'heure du réveil, la sonnerie (5 sons intégrés ou ta propre musique via
   **➕ Choisir ma musique**, à écouter avec **▶️ Écouter**), la durée de danse (15 s, 30 s ou 1 min) et le mode de détection.
2. Appuie sur **Activer l'alarme**, laisse la page ouverte et le téléphone branché (l'écran reste allumé).
3. À l'heure dite, l'alarme sonne et vibre. Pour l'arrêter, il faut danser :
   - **📷 Caméra** : pose le téléphone face à toi. La détection de posture (MediaPipe) suit
     bras, jambes, bassin et tête. Il faut bouger plusieurs parties du corps à la fois :
     agiter une main ne suffit pas.
   - **📱 Téléphone en main** : l'accéléromètre mesure tes secousses.
4. La barre se remplit tant que tu danses et redescend si tu t'arrêtes. Le son baisse un peu
   quand tu bouges bien, mais il ne se coupe qu'une fois la barre pleine.

Le bouton **Tester maintenant** déclenche l'alarme tout de suite.

## Installer sur le téléphone

Il s'agit d'une application web installable (PWA). La caméra et les capteurs demandent HTTPS :

1. Active GitHub Pages sur ce dépôt (Settings → Pages → branche, dossier `/`).
2. Ouvre l'adresse sur ton téléphone :
   - Android (Chrome) : menu ⋮ → *Ajouter à l'écran d'accueil* ;
   - iPhone (Safari) : bouton Partager → *Sur l'écran d'accueil*.

Pour tester sur ordinateur : `python3 -m http.server` puis ouvre http://localhost:8000.

## Limites

Une page web ne peut pas réveiller un téléphone en veille. L'app doit rester **ouverte et au
premier plan** jusqu'au réveil (l'écran reste allumé grâce au *Wake Lock*). Branche ton
téléphone et baisse la luminosité. Sur iPhone, coupe le mode silencieux pour entendre le son.
