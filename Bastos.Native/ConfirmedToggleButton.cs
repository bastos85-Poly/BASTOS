using System.Windows.Controls.Primitives;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;

namespace Bastos.Native;

// Preserve the inherited click, command, keyboard and automation behavior.
// The verified model, not an optimistic click, controls the visual state.
public sealed class ConfirmedToggleButton : ToggleButton
{
    protected override void OnToggle() { }
    protected override AutomationPeer OnCreateAutomationPeer() => new ConfirmedTogglePeer(this);
    private sealed class ConfirmedTogglePeer(ConfirmedToggleButton owner) : ToggleButtonAutomationPeer(owner), IToggleProvider
    {
        public override object GetPattern(PatternInterface patternInterface) =>
            patternInterface == PatternInterface.Toggle ? this : base.GetPattern(patternInterface);
        ToggleState IToggleProvider.ToggleState => owner.IsChecked == true ? ToggleState.On :
            owner.IsChecked == false ? ToggleState.Off : ToggleState.Indeterminate;
        void IToggleProvider.Toggle()
        {
            if (!owner.IsEnabled) throw new ElementNotEnabledException();
            if (owner.Command?.CanExecute(owner.CommandParameter) == true)
                owner.Command.Execute(owner.CommandParameter);
        }
    }
}
