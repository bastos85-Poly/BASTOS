# Validation avant livraison

Sous PowerShell 7 / Windows avec SDK .NET 8 : Build/Invoke-ReleaseValidation.ps1 prend CandidateRoot (paquet préparé), RuntimeRoot (application complète de base), DotNetPath (SDK), VmPlanPath (Lab.json privé) et OutputDirectory (nouveau dossier de résultats).

La VM doit être arrêtée. L'ID de la VM, la baseline connue, le témoin invité, l'absence de réseau et les disques virtuels locaux sont obligatoires. GuestCredential.clixml reste local au laboratoire et ne figure pas dans les sources livrées. Un point de retour est conservé puis restauré, même après échec. Les chaînes de points de contrôle locaux sont bornées à 16 liens. Ne pas utiliser simultanément le laboratoire. Hyper-V n'est pas activé par cette commande et l'hôte n'est jamais redémarré.

La configuration privée contient Lab.json, GuestCredential.clixml et LabAuthorization.json dans le même dossier de laboratoire protégé. L'autorisation épingle séparément LabId, VmId, Name, DiskPath et BaselineId ; ces valeurs doivent correspondre exactement à la VM et au plan. Les identifiants exemples sont refusés. Aucun identifiant réel ne doit être ajouté aux sources. L'étape Hyper-V est exécutée par Windows PowerShell 5.1 ; le pilote de validation et les suites C# utilisent PowerShell 7/.NET 8. Prévoir un chemin de résultats court pour les workers Windows PowerShell.

Les suites moteur ont besoin de preuves téléchargées depuis Microsoft, dans le dossier de fixtures : webview4-download.json, webview4-real-download/BASTOS/Tools/WebView2 et adk-reference-KB5101684.zip. Le dossier doit être choisi via BASTOS_RELEASE_FIXTURES (ou work dans le répertoire courant). Le harnais WebViewWorkerHarness.ps1 fourni simule les lectures système et le lancement de l'installateur ; il télécharge le bootstrapper officiel sans l'exécuter. Les rapports locaux et archives Microsoft de ces fixtures ne vont pas sur GitHub.

La réinstallation réelle vérifie Windows 11 Pro français, UEFI/EFI conservée, AZERTY, compte local, nom du PC, partition Windows recréée, D: et témoin conservés, Bureau, finalisation et binaire candidat. La sonde arrête uniquement cette VM après le résultat. Les délais sont bornés. Cela ne valide pas toutes les éditions ni tous les matériels.

-HostOnly exécute les tests locaux ; son rapport reste Passed=false et ne permet pas de livraison. Les tests de reprise ne tuent que leur propre lanceur fixture. Les nettoyages portent uniquement sur les fixtures. Les données WPF sont isolées dans le TEMP du passage ; BASTOS_TEST_DATA est accepté uniquement avec --smoke-test.

Les journaux et ReleaseValidation.json sont conservés après chaque passage. Toute modification des sources ou du candidat pendant les tests annule le succès. Assert-ReleaseValidation.ps1 exige 13 groupes positifs, un rapport de moins de 24 heures et les mêmes empreintes SHA-256 de l'exécutable, du manifeste et des sources archivées.

Dans l'espace actuel, work/Publish-BASTOS-Update.ps1 prépare le candidat, valide puis déploie. -StageOnly prépare sans installer ; le script de déploiement généré exige également le rapport. Les VHDX/AVHDX, identifiants privés et résultats détaillés du laboratoire ne sont pas inclus dans le paquet utilisateur.

La sonde est transmise par Guest Service Interface Hyper-V : aucun arret de controle pendant Setup. Cette integration de copie est activee dans la VM seulement et son etat initial revient avec le point de retour. Aucun mot de passe ou parametre de securite Windows n'est change.
