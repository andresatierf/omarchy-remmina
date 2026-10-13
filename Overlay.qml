import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Remmina connection profile picker.
//
// The list and every action come from `omarchy-remmina`, which runs as its own
// short-lived process. The rows carry a profile's name, address and group, and
// the path of its file — never anything else stored in it, which for a saved
// connection includes the password. Acting on a row hands that path back to the
// helper, which only accepts files inside Remmina's own profiles folder.
//
// Profiles you connected to last are listed first, so Enter on an empty filter
// reconnects to the one you most likely want.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // The helper ships in this plugin's own bin/, which is not on PATH. The shell
  // stamps __sourceDir onto every manifest it loads, so ask the manifest where
  // we were installed rather than guessing at a path. A bare name is the
  // fallback: someone who put the helper on PATH themselves still gets a
  // working picker.
  readonly property string pluginDir: (root.manifest && root.manifest.__sourceDir) || ""
  readonly property string helper: root.pluginDir === ""
    ? "omarchy-remmina"
    : root.pluginDir + "/bin/omarchy-remmina"

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var rows: []
  property bool missing: false
  property bool loading: false

  // Shares the [menu] surface tokens, so any theme that styles the Omarchy
  // menu styles this the same way.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(22), Style.font.caption + Style.spacing.controlPaddingY)
  property int contentSpacing: Style.spacing.md
  property int rowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int cardWidth: Math.min(Style.space(620), panel.width - Style.gapsOut * 2)

  readonly property int rowSpacing: Style.space(2)
  readonly property int rowPitch: rowHeight + rowSpacing
  // What the card spends on chrome: borders, padding, header, footer, and the
  // two gaps around the list.
  readonly property int chromeHeight: card.contentTopInset + card.contentBottomInset
    + headerHeight + footerHeight + contentSpacing * 2
  readonly property int maxCardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  readonly property int maxListHeight: Math.max(rowPitch, maxCardHeight - chromeHeight)
  // Whole rows, and no more of them than there are results: the card shrinks to
  // its content rather than leaving dead space under the hints, and never slices
  // a row in half against the footer.
  readonly property int fittedListHeight: Math.floor((maxListHeight + rowSpacing) / rowPitch) * rowPitch - rowSpacing
  readonly property int listHeight: displayModel.count === 0
    ? Math.min(maxListHeight, rowPitch * 3)
    : Math.max(rowHeight, Math.min(displayModel.count * rowPitch - rowSpacing, fittedListHeight))
  property int cardHeight: chromeHeight + listHeight

  readonly property string hints: "Enter connect   Alt+e edit   Alt+n new   Alt+f forget   Alt+o Remmina   Alt+r reload"

  readonly property string recentGlyph: ""

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.andresatierf.remmina")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Re-read on every summon: a profile saved or deleted in Remmina since the
  // last time should show up without a restart.
  function reload() {
    if (listProc.running) return
    root.loading = true
    listProc.collected = ""
    listProc.running = true
  }

  function loadRows(raw) {
    var parsed = Model.parseList(raw)
    root.rows = parsed.rows
    root.missing = parsed.missing
    root.loading = false
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    // Rows about to be replaced under the pointer must not be allowed to claim
    // the cursor on their way in.
    root.disarmPointer()

    var rows = Model.displayRows(root.rows, root.filterText)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        name: row.name,
        sub: row.sub,
        glyph: row.glyph,
        file: row.file,
        recent: row.recent
      })
    }

    root.selectedIndex = Model.clampIndex(root.selectedIndex, displayModel.count)
    root.cursorActive = displayModel.count > 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectPage(delta) {
    if (displayModel.count === 0) return
    var visibleRows = Math.max(1, Math.floor(resultList.height / root.rowHeight))
    var next = root.selectedIndex + delta * visibleRows
    if (next < 0) next = 0
    if (next >= displayModel.count) next = displayModel.count - 1
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = next
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectEdge(toEnd) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = toEnd ? displayModel.count - 1 : 0
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  // Called wherever the list is rebuilt or the cursor is placed by anything
  // other than the pointer, so the next hover event has to prove real movement
  // before it may take the selection.
  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function currentRow() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return null
    return displayModel.get(root.selectedIndex) || null
  }

  // Actions are argv, never a shell string: a profile named `; rm -rf ~` is
  // just an awkward name.
  function act(action) {
    var row = root.currentRow()
    if (!row) return
    root.dismiss()
    Quickshell.execDetached([root.helper, action, row.file])
  }

  // A new profile. Whatever was typed is most likely the host you meant to
  // find, so it seeds the server field.
  function newProfile() {
    var server = root.filterText.trim()
    root.dismiss()
    Quickshell.execDetached(server ? [root.helper, "new", server] : [root.helper, "new"])
  }

  function openRemmina() {
    root.dismiss()
    Quickshell.execDetached([root.helper, "open"])
  }

  function forget() {
    var row = root.currentRow()
    if (!row || !row.recent) return
    Quickshell.execDetached([root.helper, "forget", row.file])
    Qt.callLater(function() { root.reload() })
  }

  ListModel { id: displayModel }

  // The card is drawn wherever the pointer already happens to be, and a row
  // arriving under a stationary pointer raises hover events as if the user had
  // moved onto it. Without this gate the picker opens with whatever row landed
  // under the mouse selected instead of the most recent profile.
  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Process {
    id: listProc
    command: [root.helper, "list"]
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { listProc.collected += data }
    }
    onExited: function(exitCode, exitStatus) {
      root.loadRows(listProc.collected)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "andresatierf-remmina"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var alt = (event.modifiers & Qt.AltModifier) !== 0

          if (event.key === Qt.Key_Escape) {
            // Escape unwinds one step at a time: the filter, then the picker.
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
            return
          }

          if (alt) {
            switch (event.key) {
              case Qt.Key_E: root.act("edit"); event.accepted = true; return
              case Qt.Key_N: root.newProfile(); event.accepted = true; return
              case Qt.Key_F: root.forget(); event.accepted = true; return
              case Qt.Key_O: root.openRemmina(); event.accepted = true; return
              case Qt.Key_R: root.reload(); event.accepted = true; return
            }
          }

          if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectPage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectPage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectEdge(false)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectEdge(true)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.act("connect")
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: countText.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.loading ? "Loading profiles…" : "Connect to…")
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: countText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: displayModel.count > 0 ? String(displayModel.count) : ""
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Item {
          width: parent.width
          height: root.listHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: root.rowHeight * 8

            delegate: Rectangle {
              required property int index
              required property string name
              required property string sub
              required property string glyph
              required property bool recent

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: resultList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Text {
                id: glyphText
                text: parent.glyph
                color: parent.hasCursor ? root.selectedText : root.foreground
                opacity: parent.hasCursor ? 1 : 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: markerText
                text: root.recentGlyph
                visible: parent.recent
                color: parent.hasCursor ? root.selectedText : root.foreground
                opacity: parent.hasCursor ? 0.9 : 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.left: glyphText.right
                anchors.leftMargin: Style.space(6)
                anchors.right: parent.recent ? markerText.left : parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  width: parent.width
                  text: name
                  color: hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: sub
                  visible: sub.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                id: rowPointer
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(index, rowPointer, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = index
                  root.act("connect")
                }
              }
            }
          }

          Column {
            // An explicit width, because the children below size themselves
            // from it: a Column that took its width from them instead would
            // resolve the loop to zero and draw nothing at all.
            width: parent.width - Style.space(24)
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && !root.loading

            Text {
              // Written as escapes: a literal private-use glyph does not
              // survive every editor and tool that touches this file.
              text: root.rows.length === 0 ? "" : ""
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.missing
                ? "No Remmina profiles folder — is Remmina set up?"
                : root.rows.length === 0
                  ? "No profiles yet — Alt+n to create one"
                  : "No matches for “" + root.filterText + "” — Alt+n to add it"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              width: parent.width
            }
          }
        }

        Text {
          width: parent.width
          height: root.footerHeight
          text: root.hints
          color: root.foreground
          opacity: 0.42
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
