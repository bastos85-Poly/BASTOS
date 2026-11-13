using System;
using System.Globalization;
using System.Windows.Data;

namespace Bastos.Native;

// Text spans the full card for ordinary actions; switch cards reserve a
// dedicated right column so neither the text nor the switch can overlap.
public sealed class SettingCardSpanConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value is true ? 1 : 2;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
