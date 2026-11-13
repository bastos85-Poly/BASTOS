using System;
using System.Globalization;
using System.Linq;
using System.Windows.Data;

namespace Bastos.Native;

// Presentation only: commands, enabled states and confirmations stay unchanged.
public sealed class ButtonRoleConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not string label) return "primary";
        label = label.Trim();
        if (new[] { "Supprimer", "Désinstaller", "Effacer", "Retirer", "Nettoyer", "Vider la corbeille" }
            .Any(prefix => label.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))) return "destructive";
        if (new[] { "Actualiser", "Recharger", "Fermer", "Retour", "Annuler", "Ouvrir le dossier", "Consulter", "Voir la rubrique", "Tout désélectionner", "Gérer" }
            .Any(prefix => label.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))) return "auxiliary";
        return "primary";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
