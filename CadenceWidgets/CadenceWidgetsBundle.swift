import WidgetKit
import SwiftUI

/// The extension's entry point: the Home Screen readiness widget plus the
/// rest-timer Live Activity.
@main
struct CadenceWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CadenceWidgets()
        CadenceWidgetsLiveActivity()
    }
}
