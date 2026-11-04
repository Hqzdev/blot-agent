import Foundation

@main
struct VerifyMacPressActivation {
    @MainActor static func main() {
        let interaction = MacTeamPressState()
        var selections = 0
        // Capture before the hold, as AppKit can do when queuing a button action.
        let pendingClick = { interaction.activate { selections += 1 } }
        pendingClick()
        precondition(selections == 1, "A short click must select the chat")
        interaction.beginMenu()
        pendingClick()
        precondition(selections == 1, "Release after a hold must not select the chat")
        interaction.endMenu()
        pendingClick()
        precondition(selections == 2, "Closing the menu must restore activation")
        let anotherRow = MacTeamPressState()
        interaction.beginMenu()
        anotherRow.activate { selections += 1 }
        precondition(selections == 3, "Suppression must be local to its row")
        print("4 activation regression checks passed")
    }
}
