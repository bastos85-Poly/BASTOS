using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Bastos.Native.Infrastructure;
using Bastos.Native.Models;

namespace Bastos.Native.ViewModels;

public sealed partial class MainViewModel
{
    private static int HardwareOrder(string category)
    {
        var text = category.ToLowerInvariant();
        if (text.Contains("chipset") || text.Contains("processeur") || text.Contains("processor")) return 2;
        if (text.Contains("carte mere") || text.Contains("carte mère") || text.Contains("motherboard")) return 1;
        if (text.Contains("graphique") || text.Contains("gpu")) return 3;
        if (text.Contains("ethernet")) return 4;
        if (text.Contains("audio") || text == "son") return 5;
        return 6;
    }

    private static string HardwareHeading(string category) => HardwareOrder(category) switch
    {
        1 => "01 · Carte mère",
        2 => "02 · Processeur / chipset",
        3 => "03 · Carte graphique",
        4 => "04 · Ethernet",
        5 => "05 · Son",
        _ => "06 · " + category
    };

    private void ShowHardwareResults(PageViewModel page, HardwareAnalysisResult result)
    {
        page.Cards.Clear();
        page.HardwareResults.Clear();
        page.Cards.Add(page.GraphicsStandardCard!);
        page.Cards.Add(page.GraphicsLiteCard!);
        page.Cards.Add(page.HardwareAnalysisCard!);
        var report = new StatusCard("Rapport complet de l’analyse",
            $"{result.DetectedDevices} périphériques détectés · {result.Recommendations.Count} liens officiels proposés · {result.ProblemCount} problème(s).",
            result.Operation?.State == OperationState.Partial ? "Analyse partielle — certaines informations sont indisponibles." : "Les liens de pilotes sont classés ci-dessous. Une proposition ne signifie pas qu’une mise à jour est disponible.",
            result.Operation?.State == OperationState.Partial ? StatusTone.Warning : StatusTone.Neutral,
            "Ouvrir le rapport complet", new AsyncRelayCommand(() =>
            {
                if (File.Exists(result.ReportPath)) operations.Open(result.ReportPath);
                return Task.CompletedTask;
            }, () => File.Exists(result.ReportPath), () => "Le fichier du rapport est indisponible."))
        { IsHardwareResult = true, HardwareRole = "RAPPORT · Inventaire et diagnostic" };
        page.Cards.Add(report);
        page.HardwareResults.Add(report);

        foreach (var recommendation in result.Recommendations.OrderBy(r => HardwareOrder(r.Category))
            .ThenBy(r => r.Category, StringComparer.CurrentCultureIgnoreCase).ThenBy(r => r.Hardware, StringComparer.CurrentCultureIgnoreCase))
        {
            StatusCard card = null;
            var version = string.IsNullOrWhiteSpace(recommendation.CurrentVersion) ? "Version installée non détectée" : "Version installée : " + recommendation.CurrentVersion;
            card = new StatusCard(HardwareHeading(recommendation.Category), recommendation.Hardware,
                version, StatusTone.Neutral, "Voir les téléchargements officiels",
                new AsyncRelayCommand(() => OpenDriver(card, recommendation)))
            {
                IsHardwareResult = true,
                HardwareRole = "PILOTES · Page officielle du fabricant",
                HardwareSource = recommendation.SourceName,
                HardwareDetails = $"{recommendation.Category}\n{recommendation.Manufacturer}\n{recommendation.Reason}\nCorrespondance : {recommendation.Confidence}\n{recommendation.OfficialUrl}"
            };
            page.Cards.Add(card);
            page.HardwareResults.Add(card);
        }
        var inventory = new StatusCard("Inventaire détaillé du PC", "Composants détectés et informations techniques, regroupés dans les détails.",
            $"{result.Inventory.Count} éléments principaux", StatusTone.Neutral)
        {
            IsHardwareResult = true, HardwareRole = "INVENTAIRE · Consultation",
            HardwareDetails = string.Join("\n\n", result.Inventory.OrderBy(i => HardwareOrder(i.Category))
                .ThenBy(i => i.Category).Select(i => $"{i.Category} — {i.Name}\n{i.Details}"))
        };
        page.Cards.Add(inventory);
        page.HardwareResults.Add(inventory);
    }
}
