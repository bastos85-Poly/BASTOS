# BASTOS 7.120.134 — sources des logiciels

Correction de huit anomalies confirmées lors de l'audit des 127 logiciels.

AIMP : URL actuelle stable 5.40.2731 x64, SHA-256 publié par le site officiel et signature de l'éditeur exigés. HWiNFO : miroir SAC proposé par le site officiel, version 8.60, SHA-256 fixé après validation de la signature REALiX, s.r.o. CCleaner et LatencyMon : source officielle, signature de l'éditeur et nom de produit vérifiés avant lancement silencieux. La présence reste contrôlée par le gestionnaire après installation ; aucun code retour seul ne suffit.

Process Explorer : archive officielle Microsoft, liste d'entrées fermée et signatures Microsoft de ses trois exécutables ; installation et suppression portables gérées, présence détectée dans Bastos. Le programme n'est pas lancé automatiquement.

Equalizer APO et Peace : résolution du lien temporaire dans la page SourceForge, limitée au même projet et au fichier exact. Le SHA-256 attendu reste inchangé. Une page HTML, un autre projet ou un autre fichier est refusé.

RealVNC : le paquet public obsolète Viewer 7 est remplacé par RealVNC.VNCConnect.Viewer. Le nom et la description indiquent clairement le produit actuel et le besoin d'un compte RealVNC ; les fonctionnalités dépendent du forfait. L'archive actuelle est conforme au manifeste WinGet.

Les parcours spécifiques AIMP/HWiNFO/CCleaner/LatencyMon sont réservés à ces identifiants et au gestionnaire WinGet. Aucun contrôle WinGet d'empreinte n'est désactivé ; Chocolatey conserve son propre fonctionnement. Les signatures, produits et empreintes des sources spécifiques sont contrôlés indépendamment. Une modification du fichier entre vérification et lancement est bloquée par un verrou de lecture.

Validation : tests ciblés des sources et téléchargements réels, tests d'installation groupée avec gestionnaires simulés, compilation x64 autonome et smoke natif ; voir Verification pour les nombres et résultats exacts. Les huit installations réelles et la réinstallation Windows complète en VM ne sont pas validées. Aucun faux rapport général Passed=true n'est fourni.
