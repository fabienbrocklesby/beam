import BeamCore
import Testing

/// Action strings as Ghostty 1.4.0 writes them in a config's `keybind`.
struct BindingActionTests {
    @Test func splits() {
        #expect(BindingAction("new_split:right") == .newSplit(.right))
        #expect(BindingAction("new_split:down") == .newSplit(.down))
        #expect(BindingAction("new_split:left") == .newSplit(.left))
        #expect(BindingAction("new_split:up") == .newSplit(.up))
        #expect(BindingAction("new_split:auto") == .newSplit(nil))
        #expect(BindingAction("new_split") == .newSplit(nil))
        #expect(BindingAction("toggle_split_zoom") == .toggleSplitZoom)
        #expect(BindingAction("equalize_splits") == .equalizeSplits)
        #expect(BindingAction("close_surface") == .closeSurface)
    }

    @Test func goingToASplit() {
        #expect(BindingAction("goto_split:previous") == .gotoSplit(.previous))
        #expect(BindingAction("goto_split:next") == .gotoSplit(.next))
        #expect(BindingAction("goto_split:left") == .gotoSplit(.neighbour(.left)))
        #expect(BindingAction("goto_split:right") == .gotoSplit(.neighbour(.right)))
        #expect(BindingAction("goto_split:up") == .gotoSplit(.neighbour(.up)))
        #expect(BindingAction("goto_split:down") == .gotoSplit(.neighbour(.down)))
        // Ghostty still reads the names it used before up and down.
        #expect(BindingAction("goto_split:top") == .gotoSplit(.neighbour(.up)))
        #expect(BindingAction("goto_split:bottom") == .gotoSplit(.neighbour(.down)))
    }

    @Test func resizingASplit() {
        #expect(BindingAction("resize_split:up,10") == .resizeSplit(.up, 10))
        #expect(BindingAction("resize_split:left,25") == .resizeSplit(.left, 25))
        #expect(BindingAction("resize_split:up") == nil)
        #expect(BindingAction("resize_split:sideways,10") == nil)
    }

    @Test func tabsAndWindows() {
        #expect(BindingAction("new_tab") == .newTab)
        #expect(BindingAction("new_window") == .newWindow)
        #expect(BindingAction("close_tab") == .closeTab)
        #expect(BindingAction("close_tab:this") == .closeTab)
        #expect(BindingAction("close_tab:other") == nil)
        #expect(BindingAction("goto_tab:1") == .gotoTab(.position(0)))
        #expect(BindingAction("goto_tab:9") == .gotoTab(.position(8)))
        #expect(BindingAction("goto_tab:0") == nil)
        #expect(BindingAction("next_tab") == .gotoTab(.next))
        #expect(BindingAction("previous_tab") == .gotoTab(.previous))
        #expect(BindingAction("last_tab") == .gotoTab(.last))
        #expect(BindingAction("close_window") == .closeWindow)
    }

    @Test func editing() {
        #expect(BindingAction("copy_to_clipboard") == .copyToClipboard)
        #expect(BindingAction("copy_to_clipboard:mixed") == .copyToClipboard)
        #expect(BindingAction("paste_from_clipboard") == .pasteFromClipboard)
        #expect(BindingAction("select_all") == .selectAll)
        #expect(BindingAction("start_search") == .startSearch)
    }

    /// The Edit menu sends copy, paste, select all and find to the focused
    /// view itself, so a document listens only for pane and workspace keys.
    @Test func aDocumentListensForPaneAndWorkspaceKeys() {
        let keys = BindingAction.documentKeys
        #expect(keys.count == Set(keys).count)
        for key in keys {
            let action = BindingAction(key)
            #expect(action != nil, "\(key)")
            #expect(![.copyToClipboard, .pasteFromClipboard, .selectAll, .startSearch].contains(action), "\(key)")
        }
        // As Ghostty's macOS defaults write them, parameters included.
        for key in ["new_split:right", "goto_split:left", "resize_split:up,10", "goto_tab:1", "close_tab:this"] {
            #expect(keys.contains(key), "\(key)")
        }
    }

    @Test func actionsBeamDoesNotHandleParseToNothing() {
        #expect(BindingAction("increase_font_size:1") == nil)
        #expect(BindingAction("") == nil)
        #expect(BindingAction("new_split:sideways") == nil)
    }
}
