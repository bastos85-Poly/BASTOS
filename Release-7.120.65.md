# 7.120.65 — correction de la restauration des métadonnées WIM

Échec réel constaté le 19 octobre 2026, opération 8d67305a871f4c688604d113a2b47e17 : « Restauration des metadonnees WIM non conforme. », à 69 % après commit du nettoyage. Aucun redémarrage demandé. Cet incident est distinct du réglage OOBE grisé.

La routine envoyait le XML global à WIMSetImageInformation avec le handle du conteneur WIM. Sur une copie de boot.wim, l’appel accepte l’écriture mais ne modifie pas les champs WINDOWS de l’index ciblé. La routine charge maintenant cet index par WIMLoadImage, fournit son élément IMAGE et ferme le handle de l’image avant celui du fichier. Le bloc WINDOWS original est restauré, les autres champs actuels de l’image sont conservés. Le contrôle par relecture reste obligatoire ; aucun contournement de la vérification d’édition/langues.

Référence : https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/wim/dd834951(v=msdn.10)?view=windows-11

Validation : 14 contrôles WIMGAPI réels sous Windows PowerShell 5.1 sur copie jetable multi-index de boot.wim (persistance, restauration de WINDOWS absent, autres champs et second index conservés, index invalide refusé, empreinte source inchangée), 36 contrôles cache PowerShell, 51 contrôles C# du bilan et du vérificateur indépendant, compilation/publication x64.

Pas de relance de Provision/BootOnce, de montage DISM, de modification de partitions ni de redémarrage pendant le correctif. La tentative initiale de créer une petite WIM via DISM a été refusée faute d’élévation (740) ; les tests réels ont ensuite utilisé exclusivement une copie locale. La préparation complète et la réinstallation restent à retester après relance de BASTOS.

Le journal indique un arrêt du worker après échec ; il ne prouve pas un retour arrière complet de tous les effets de préparation. L’export de pilotes a pu être effectué avant le blocage. La nouvelle préparation doit relire et vérifier les caches et la disposition, sans réutiliser un résultat échoué comme preuve de conformité.
