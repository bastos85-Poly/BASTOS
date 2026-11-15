using System.Windows;
namespace Bastos.Native;
// Keep the original buttons, default response and result. Only presentation changes.
internal static class LocalizedMessageBox
{
    internal static MessageBoxResult Show(string text, string title, MessageBoxButton buttons = MessageBoxButton.OK,
        MessageBoxImage image = MessageBoxImage.None, MessageBoxResult defaultResult = MessageBoxResult.None) =>
        MessageBox.Show(InterfaceLanguage.Instance.Translate(text), InterfaceLanguage.Instance.Translate(title), buttons, image, defaultResult);
    internal static MessageBoxResult Show(Window owner, string text, string title, MessageBoxButton buttons = MessageBoxButton.OK,
        MessageBoxImage image = MessageBoxImage.None, MessageBoxResult defaultResult = MessageBoxResult.None) =>
        MessageBox.Show(owner, InterfaceLanguage.Instance.Translate(text), InterfaceLanguage.Instance.Translate(title), buttons, image, defaultResult);
}
