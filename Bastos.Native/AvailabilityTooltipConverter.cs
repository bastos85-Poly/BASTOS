using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace Bastos.Native;

public sealed class AvailabilityTooltipConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is string reason && !string.IsNullOrWhiteSpace(reason) ? reason : null;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => DependencyProperty.UnsetValue;
}
