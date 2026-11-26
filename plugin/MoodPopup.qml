import QtQuick
import qs.Commons
import qs.Ui

// The popup's frame and keys. The shell's KeyboardPanel grows the card out of
// the bar item and gives it the keyboard as it opens; the surface's Popup.qml
// is loaded inside it and only draws.
//
//   Up, Down, Tab      move the focus (it wraps)
//   Left, Right        change a setting, or walk along the manual controls
//   Enter, Space       do what the focused entry does
//   Escape             close
//
// The bar widget loads this file through a Loader, so if a shell update renames
// a panel part only the popup fails; the bar item keeps working.
Item {
  id: host

  // The bar widget: anchor, bar, panelOpen, close(), context, model, surfaceId.
  property var widget: null
  readonly property var model: widget ? widget.model : null

  KeyboardPanel {
    id: panel
    anchorItem: host.widget ? host.widget.anchor : null
    bar: host.widget ? host.widget.bar : null
    // Closing goes through the widget, which owns panelOpen; the bar also
    // calls the owner's close() when another popup opens.
    owner: host.widget
    open: !!host.widget && host.widget.panelOpen
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(panel.loadedContent ? panel.loadedContent.wantedWidth : Style.space(300))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      implicitHeight: body.item ? body.item.implicitHeight : Style.space(120)
      readonly property real wantedWidth: body.item && body.item.implicitWidth > 0
        ? Math.max(Style.space(220), Math.min(Style.space(520), body.item.implicitWidth)) : Style.space(300)
      blocked: !!host.model && host.model.editing

      onCloseRequested: host.widget.close()
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) host.model.move(dy)
        else if (dx !== 0) host.model.adjust(dx)
      }
      onTabRequested: function(direction) { host.model.move(direction) }
      onActivateRequested: host.model.activate(host.model.focusId)

      // Taller than the screen allows (many moods, both sections open): it
      // scrolls, and the focused entry is kept in view.
      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.item ? body.item.implicitHeight : 0
        clip: contentHeight > height + 0.5
        interactive: contentHeight > height + 0.5
        boundsBehavior: Flickable.StopAtBounds

        Loader {
          id: body
          width: scroller.width
          readonly property string wanted: host.widget ? host.widget.surfaceId : "plain"
          onWantedChanged: load()
          Component.onCompleted: load()
          function load() {
            if (!host.widget || wanted === "") return
            setSource(Qt.resolvedUrl("surfaces/" + wanted + "/Popup.qml"), { mood: host.widget.context })
          }
          // A surface whose popup won't load falls back to the plain one.
          onStatusChanged: if (status === Loader.Error && wanted !== "plain")
            Qt.callLater(function() { body.setSource(Qt.resolvedUrl("surfaces/plain/Popup.qml"), { mood: host.widget.context }) })
        }
      }

      Connections {
        target: host.model
        function onReveal(item) {
          if (!item || !scroller.interactive) return
          var top = item.mapToItem(scroller.contentItem, 0, 0).y
          if (top < scroller.contentY) scroller.contentY = top
          else if (top + item.height > scroller.contentY + scroller.height)
            scroller.contentY = Math.min(scroller.contentHeight - scroller.height, top + item.height - scroller.height)
        }
        function onFocusBack() { keys.forceActiveFocus() }
      }
    }
  }
}
