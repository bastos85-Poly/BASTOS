using System;
using System.Globalization;
using System.Windows.Data;

namespace Bastos.Native;

public sealed class SoftwareColumnsConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is double width && double.IsFinite(width)
            ? Math.Clamp((int)(width / 280), 1, 3)
            : 1;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
