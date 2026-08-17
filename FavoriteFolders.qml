import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "FoldersHelper.js" as FoldersHelper

BarWidget {
  id: root
  moduleName: "omarchy-favorite-folders"

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color bg: root.bar ? root.bar.background : Color.background
  readonly property color dim: Qt.darker(root.fg, 1.4)
  readonly property color subdim: Qt.darker(root.fg, 1.8)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property string homeDir: Quickshell.env("HOME") || ("/home/" + (Quickshell.env("USER") || "user"))

  property bool popupOpen: false
  property var foldersList: []
  property string viewState: "list" // "list" | "form" | "confirmDelete"

  // Form state (Add / Edit)
  property string editingId: ""
  property string inputPath: ""
  property string inputName: ""
  property string formError: ""
  property bool isBrowsing: false
  property string lastPickedPath: ""

  // Missing folders map
  property var missingMap: ({})

  onPopupOpenChanged: {
    if (popupOpen) {
      checkMissingFolders()
    }
  }

  onFoldersListChanged: {
    checkMissingFolders()
  }

  function checkMissingFolders() {
    if (!root.foldersList || root.foldersList.length === 0) {
      root.missingMap = ({})
      return
    }

    var rawPaths = []
    for (var i = 0; i < root.foldersList.length; i++) {
      if (root.foldersList[i] && root.foldersList[i].path) {
        rawPaths.push(root.foldersList[i].path)
      }
    }
    if (rawPaths.length === 0) return

    var cmd = ["bash", "-c", 'for p in "$@"; do expanded="${p/#\\~/$HOME}"; if [ -d "$expanded" ]; then echo "OK:$p"; else echo "MISSING:$p"; fi; done', "--"].concat(rawPaths)
    checkMissingProc.command = cmd
    checkMissingProc.running = true
  }

  Process {
    id: checkMissingProc
    property var tempMap: ({})
    onStarted: { tempMap = ({}) }
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line).trim()
        if (str.indexOf("MISSING:") === 0) {
          var pMiss = str.substring(8)
          checkMissingProc.tempMap[pMiss] = true
        } else if (str.indexOf("OK:") === 0) {
          var pOk = str.substring(3)
          checkMissingProc.tempMap[pOk] = false
        }
      }
    }
    onExited: {
      var copy = {}
      for (var k in checkMissingProc.tempMap) {
        copy[k] = checkMissingProc.tempMap[k]
      }
      root.missingMap = copy
    }
  }

  // Delete confirmation target
  property var deleteTarget: null

  // Config file path
  readonly property string configFilePath: root.homeDir + "/.config/omarchy/favorite-folders.json"

  // File persistence handler
  FileView {
    id: configFile
    path: root.configFilePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadFolders(text())
    onLoadFailed: root.loadFolders("[]")
  }

  function loadFolders(rawText) {
    var parsed = FoldersHelper.parseFolders(rawText)
    root.foldersList = parsed
  }

  function persistFolders() {
    var serialized = FoldersHelper.serializeFolders(root.foldersList)
    configFile.setText(serialized)
  }

  // File picker via Zenity
  Process {
    id: zenityPickerProc
    command: ["zenity", "--file-selection", "--directory", "--title=Select Favorite Folder"]
    stdout: SplitParser {
      onRead: function(data) {
        var picked = String(data).trim()
        if (picked) {
          root.lastPickedPath = picked
        }
      }
    }
    onExited: {
      var picked = root.lastPickedPath.trim()
      root.lastPickedPath = ""
      root.isBrowsing = false

      if (picked) {
        if (root.editingId !== "") {
          // Editing mode: update form inputs and reopen form view
          root.inputPath = picked
          if (pathInputField) pathInputField.text = picked
          if (root.inputName.trim() === "") {
            root.inputName = FoldersHelper.extractFolderName(picked)
            if (nameInputField) nameInputField.text = root.inputName
          }
          root.viewState = "form"
          Qt.callLater(function() { root.popupOpen = true })
        } else {
          // Add mode: auto-add folder and reopen popup in list view with the new item!
          var nameVal = root.inputName.trim() || FoldersHelper.extractFolderName(picked)
          var iconVal = FoldersHelper.detectIcon(picked, nameVal)
          var newFolder = {
            id: FoldersHelper.generateId(),
            name: nameVal,
            path: picked,
            icon: iconVal
          }
          var updatedList = root.foldersList.slice()
          updatedList.push(newFolder)
          root.foldersList = updatedList
          root.persistFolders()

          // Reset form state & reopen popup
          root.editingId = ""
          root.inputPath = ""
          root.inputName = ""
          if (pathInputField) pathInputField.text = ""
          if (nameInputField) nameInputField.text = ""
          root.formError = ""
          root.viewState = "list"
          Qt.callLater(function() { root.popupOpen = true })
        }
      } else {
        // User closed or cancelled zenity: reopen popup
        Qt.callLater(function() { root.popupOpen = true })
      }
    }
  }

  function setFormValues(path, name) {
    var p = path || ""
    var n = name || ""
    root.inputPath = p
    root.inputName = n
    if (pathInputField) pathInputField.text = p
    if (nameInputField) nameInputField.text = n
    root.formError = ""
  }

  function close() {
    if (root.isBrowsing) {
      root.popupOpen = false
      return
    }
    root.popupOpen = false
    root.viewState = "list"
    root.formError = ""
    root.deleteTarget = null
    root.editingId = ""
    root.setFormValues("", "")
  }

  function openFolder(path) {
    var isMissing = !!root.missingMap[path]
    var targetPath = FoldersHelper.expandHome(path, root.homeDir)
    if (!targetPath) return

    if (isMissing) {
      Quickshell.execDetached(["omarchy-notification-send", "Folder Missing", "The directory \"" + FoldersHelper.displayPath(path, root.homeDir) + "\" was deleted or does not exist."])
      return
    }

    Quickshell.execDetached(["xdg-open", targetPath])
    root.close()
  }

  function openAddForm() {
    root.editingId = ""
    root.setFormValues("", "")
    root.viewState = "form"
    Qt.callLater(function() {
      if (pathInputField) pathInputField.forceActiveFocus()
    })
  }

  function openEditForm(folder) {
    if (!folder) return
    root.editingId = folder.id
    root.setFormValues(folder.path, folder.name)
    root.viewState = "form"
    Qt.callLater(function() {
      if (pathInputField) pathInputField.forceActiveFocus()
    })
  }

  function saveForm() {
    var pathVal = (pathInputField ? pathInputField.text : root.inputPath).trim()
    if (!pathVal) {
      root.formError = "Please specify a folder path"
      return
    }

    var nameVal = (nameInputField ? nameInputField.text : root.inputName).trim()
    if (!nameVal) {
      nameVal = FoldersHelper.extractFolderName(pathVal)
    }

    var iconVal = FoldersHelper.detectIcon(pathVal, nameVal)
    var updatedList = []

    if (root.editingId !== "") {
      // Update existing item
      for (var i = 0; i < root.foldersList.length; i++) {
        var item = root.foldersList[i]
        if (item.id === root.editingId) {
          updatedList.push({
            id: item.id,
            name: nameVal,
            path: pathVal,
            icon: iconVal
          })
        } else {
          updatedList.push(item)
        }
      }
    } else {
      // Add new item
      var newFolder = {
        id: FoldersHelper.generateId(),
        name: nameVal,
        path: pathVal,
        icon: iconVal
      }
      updatedList = root.foldersList.slice()
      updatedList.push(newFolder)
    }

    root.foldersList = updatedList
    root.persistFolders()
    root.viewState = "list"
    root.formError = ""
    root.editingId = ""
    root.setFormValues("", "")
  }

  function promptDelete(folder) {
    if (!folder) return
    root.deleteTarget = folder
    root.viewState = "confirmDelete"
  }

  function executeDelete() {
    if (!root.deleteTarget) return
    var updatedList = []
    for (var i = 0; i < root.foldersList.length; i++) {
      if (root.foldersList[i].id !== root.deleteTarget.id) {
        updatedList.push(root.foldersList[i])
      }
    }
    root.foldersList = updatedList
    root.persistFolders()
    root.deleteTarget = null
    root.viewState = "list"
  }

  function cancelForm() {
    root.viewState = "list"
    root.formError = ""
    root.editingId = ""
    root.deleteTarget = null
    root.setFormValues("", "")
  }

  // Sizing on the bar
  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  // Waybar Icon Button
  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: "󰉋"
    active: root.popupOpen
    useActiveColor: root.popupOpen
    tooltipText: root.foldersList.length > 0
      ? ("Favorite Folders (" + root.foldersList.length + ")")
      : "Favorite Folders"

    onPressed: function(button) {
      root.popupOpen = !root.popupOpen
    }
  }

  // Keyboard Panel Popup
  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(popupLayout.implicitHeight, Style.space(500))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Keys.onEscapePressed: function(event) {
        if (root.viewState !== "list") {
          root.cancelForm()
        } else {
          root.close()
        }
        event.accepted = true
      }

      Column {
        id: popupLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // Header
        Item {
          width: parent.width
          height: Math.max(headerLeft.implicitHeight, headerActions.implicitHeight)

          // Header Title & Badge
          Row {
            id: headerLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              text: root.viewState === "list" ? "󰉋" : (root.viewState === "form" ? (root.editingId ? "󰏫" : "󰐕") : "󰩹")
              color: root.viewState === "confirmDelete" ? Color.urgent : Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.viewState === "list"
                ? "Favorite Folders"
                : (root.viewState === "form"
                  ? (root.editingId ? "Edit Folder" : "Add Folder")
                  : "Delete Folder")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            // Count Badge Pill (in list view)
            BorderSurface {
              visible: root.viewState === "list" && root.foldersList.length > 0
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.fg, Color.accent)
              borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
              width: countText.implicitWidth + Style.space(12)
              height: countText.implicitHeight + Style.space(4)

              Text {
                id: countText
                anchors.centerIn: parent
                text: String(root.foldersList.length)
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          // Header Right Action Buttons
          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            // Add (+) Button in List View
            Button {
              visible: root.viewState === "list"
              iconText: "󰐕"
              text: "Add"
              tooltipText: "Add favorite folder"
              bordered: true
              foreground: Color.accent
              onClicked: root.openAddForm()
            }

            // Back/Cancel Button in Form or Confirm View
            Button {
              visible: root.viewState !== "list"
              iconText: "󰁍"
              text: "Back"
              tooltipText: "Return to list"
              bordered: true
              onClicked: root.cancelForm()
            }
          }
        }

        // Divider
        PanelSeparator {
          foreground: root.fg
        }

        // ==========================================
        // VIEW 1: LIST VIEW
        // ==========================================
        Item {
          visible: root.viewState === "list"
          width: parent.width
          implicitHeight: root.foldersList.length === 0 ? emptyCard.implicitHeight : listContainer.implicitHeight

          // Empty State Card
          BorderSurface {
            id: emptyCard
            visible: root.foldersList.length === 0
            width: parent.width
            implicitHeight: emptyColumn.implicitHeight + Style.space(32)
            color: Style.normalFillFor(root.fg, Color.accent)
            borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
            radius: Style.cornerRadius

            Column {
              id: emptyColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(32)
              spacing: Style.space(10)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󱞪"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.space(42)
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No favorite folders configured"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Add your frequently used folders for instant one-click access."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                width: parent.width
              }

              Item { width: 1; height: Style.space(4) }

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                iconText: "󰐕"
                text: "Add Folder Shortcut"
                bordered: true
                foreground: Color.accent
                onClicked: root.openAddForm()
              }
            }
          }

          // Folders List View
          Column {
            id: listContainer
            visible: root.foldersList.length > 0
            width: parent.width
            spacing: Style.space(8)

            // Scrollable list when items exceed display limit
            Flickable {
              id: flickable
              width: parent.width
              implicitHeight: Math.min(Style.space(320), listColumn.implicitHeight)
              contentWidth: width
              contentHeight: listColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: listColumn
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.foldersList

                  delegate: BorderSurface {
                    id: folderItemRow
                    required property var modelData
                    required property int index

                    readonly property bool isMissing: !!root.missingMap[modelData.path]

                    width: listColumn.width
                    implicitHeight: rowContent.implicitHeight + Style.space(12)
                    radius: Style.cornerRadius

                    readonly property bool isHovered: itemMouseArea.containsMouse

                    color: itemMouseArea.pressed
                      ? Style.pressedFillFor(root.fg, isMissing ? Color.urgent : Color.accent)
                      : (isHovered ? Style.hoverFillFor(root.fg, isMissing ? Color.urgent : Color.accent) : "transparent")

                    borderSpec: isHovered
                      ? Border.controlSpec("hover-cursor", root.fg, isMissing ? Color.urgent : Color.accent)
                      : Border.controlSpec("normal", root.fg, isMissing ? Color.urgent : Color.accent)

                    MouseArea {
                      id: itemMouseArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openFolder(modelData.path)
                    }

                    Row {
                      id: rowContent
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(10)

                      // Folder Icon Badge (Ghost icon if missing)
                      BorderSurface {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(32)
                        height: Style.space(32)
                        radius: Style.cornerRadius
                        color: isMissing
                          ? Style.normalFillFor(Color.urgent, Color.urgent)
                          : Style.normalFillFor(root.fg, Color.accent)
                        borderSpec: isMissing
                          ? Border.controlSpec("normal", Color.urgent, Color.urgent)
                          : Border.controlSpec("normal", root.fg, Color.accent)

                        Text {
                          anchors.centerIn: parent
                          text: isMissing ? "󰊠" : (modelData.icon || "󰉋")
                          color: isMissing ? Color.urgent : Color.accent
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.icon
                        }
                      }

                      // Folder Name & Path
                      Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: rowContent.width - Style.space(32 + 10 + 64 + 10)
                        spacing: Style.space(2)

                        Row {
                          width: parent.width
                          spacing: Style.space(6)

                          Text {
                            text: modelData.name || FoldersHelper.extractFolderName(modelData.path)
                            color: isMissing ? Color.urgent : root.fg
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, parent.width - (isMissing ? (missingBadge.implicitWidth + Style.space(6)) : 0))
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          // Ghost / Missing Badge
                          BorderSurface {
                            id: missingBadge
                            visible: isMissing
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Style.cornerRadius
                            color: Style.normalFillFor(Color.urgent, Color.urgent)
                            borderSpec: Border.controlSpec("normal", Color.urgent, Color.urgent)
                            width: missingBadgeRow.implicitWidth + Style.space(8)
                            height: missingBadgeRow.implicitHeight + Style.space(2)

                            Row {
                              id: missingBadgeRow
                              anchors.centerIn: parent
                              spacing: Style.space(3)

                              Text {
                                text: "󰊠"
                                color: Color.urgent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "missing"
                                color: Color.urgent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }
                            }
                          }
                        }

                        Text {
                          width: parent.width
                          text: FoldersHelper.displayPath(modelData.path, root.homeDir)
                          color: isMissing ? Qt.darker(Color.urgent, 1.3) : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideMiddle
                        }
                      }

                      // Action Buttons (Edit / Delete)
                      Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(4)

                        // Edit Button
                        Button {
                          iconText: "󰏫"
                          tooltipText: "Edit shortcut"
                          bordered: false
                          foreground: root.dim
                          onClicked: root.openEditForm(modelData)
                        }

                        // Delete Button
                        Button {
                          iconText: "󰩹"
                          tooltipText: "Delete shortcut"
                          bordered: false
                          foreground: Color.urgent
                          onClicked: root.promptDelete(modelData)
                        }
                      }
                    }
                  }
                }
              }
            }

            // List Footer Helper Info
            Row {
              width: parent.width
              spacing: Style.space(4)

              Text {
                text: "󰌌 Click to open in default file manager"
                color: root.subdim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        // ==========================================
        // VIEW 2: ADD / EDIT FORM
        // ==========================================
        Column {
          visible: root.viewState === "form"
          width: parent.width
          spacing: Style.space(10)

          // Folder Path Field Label & Input
          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "Folder Path"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: pathInputField
                width: parent.width - browseButton.implicitWidth - Style.space(6)
                text: root.inputPath
                placeholderText: "e.g. ~/Documents/Projects or /var/log"
                onTextChanged: {
                  if (root.inputPath !== text) {
                    root.inputPath = text
                    if (root.inputName.trim() === "" && text.trim() !== "") {
                      var autoName = FoldersHelper.extractFolderName(text)
                      root.inputName = autoName
                      if (nameInputField) nameInputField.text = autoName
                    }
                    root.formError = ""
                  }
                }
                onAccepted: root.saveForm()
              }

              Button {
                id: browseButton
                iconText: "󰉓"
                text: "Browse..."
                tooltipText: "Select folder visually"
                bordered: true
                foreground: Color.accent
                onClicked: {
                  root.isBrowsing = true
                  zenityPickerProc.running = true
                }
              }
            }
          }

          // Folder Name Field Label & Input
          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "Display Name (Optional)"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            TextField {
              id: nameInputField
              width: parent.width
              text: root.inputName
              placeholderText: "Leave blank to auto-detect from path"
              onTextChanged: {
                if (root.inputName !== text) {
                  root.inputName = text
                  root.formError = ""
                }
              }
              onAccepted: root.saveForm()
            }
          }

          // Quick Preset Suggestions
          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "Quick Shortcuts"
              color: root.subdim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [
                  { name: "Home", path: "~", icon: "󰋜" },
                  { name: "Documents", path: "~/Documents", icon: "󰈙" },
                  { name: "Downloads", path: "~/Downloads", icon: "󰉏" },
                  { name: "Projects", path: "~/Documents/Proyects", icon: "󰲋" },
                  { name: "Pictures", path: "~/Pictures", icon: "󰉐" },
                  { name: "Videos", path: "~/Videos", icon: "󰉓" },
                  { name: "Music", path: "~/Music", icon: "󰉑" }
                ]

                delegate: Button {
                  required property var modelData
                  iconText: modelData.icon || "󰉋"
                  text: modelData.name
                  bordered: true
                  fontSize: Style.font.caption
                  onClicked: {
                    root.setFormValues(modelData.path, modelData.name)
                  }
                }
              }
            }
          }

          // Error Message Display
          Text {
            visible: root.formError !== ""
            text: root.formError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Item { width: 1; height: Style.space(4) }

          // Form Action Buttons
          Row {
            anchors.right: parent.right
            spacing: Style.space(8)

            Button {
              text: "Cancel"
              bordered: true
              onClicked: root.cancelForm()
            }

            Button {
              iconText: root.editingId ? "󰄬" : "󰐕"
              text: root.editingId ? "Save Changes" : "Add Shortcut"
              bordered: true
              foreground: Color.accent
              onClicked: root.saveForm()
            }
          }
        }

        // ==========================================
        // VIEW 3: CONFIRM DELETE
        // ==========================================
        Column {
          visible: root.viewState === "confirmDelete"
          width: parent.width
          spacing: Style.space(12)

          BorderSurface {
            width: parent.width
            implicitHeight: deleteConfirmCol.implicitHeight + Style.space(24)
            color: Style.normalFillFor(Color.urgent, Color.urgent)
            borderSpec: Border.controlSpec("normal", Color.urgent, Color.urgent)
            radius: Style.cornerRadius

            Column {
              id: deleteConfirmCol
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              spacing: Style.space(8)

              Row {
                spacing: Style.space(8)
                Text {
                  text: "󰩹"
                  color: Color.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: "Remove Favorite Folder?"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Text {
                text: root.deleteTarget
                  ? ("Are you sure you want to remove \"" + root.deleteTarget.name + "\" (" + root.deleteTarget.path + ") from your favorites?")
                  : "Remove this folder shortcut?"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                width: parent.width
              }
            }
          }

          Row {
            anchors.right: parent.right
            spacing: Style.space(8)

            Button {
              text: "Cancel"
              bordered: true
              onClicked: root.cancelForm()
            }

            Button {
              iconText: "󰩹"
              text: "Delete"
              bordered: true
              foreground: Color.urgent
              onClicked: root.executeDelete()
            }
          }
        }
      }
    }
  }
}
