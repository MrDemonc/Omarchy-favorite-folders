// FoldersHelper.js - Helper utilities for Omarchy Favorite Folders

function trimPath(path) {
  if (!path) return ""
  var p = String(path).trim()
  // Remove trailing slashes unless it's root "/"
  while (p.length > 1 && p.endsWith("/")) {
    p = p.slice(0, -1)
  }
  return p
}

function expandHome(path, homeDir) {
  var p = trimPath(path)
  if (!p) return ""
  var home = homeDir || ""
  if (p === "~") {
    return home
  }
  if (p.indexOf("~/") === 0) {
    return home + p.slice(1)
  }
  return p
}

function displayPath(path, homeDir) {
  var p = trimPath(path)
  if (!p) return ""
  var home = homeDir || ""
  if (home && p === home) {
    return "~"
  }
  if (home && p.indexOf(home + "/") === 0) {
    return "~" + p.slice(home.length)
  }
  return p
}

function extractFolderName(path) {
  var p = trimPath(path)
  if (!p || p === "/") return "/"
  if (p === "~") return "Home"
  var segments = p.split("/")
  for (var i = segments.length - 1; i >= 0; i--) {
    if (segments[i].length > 0) {
      return segments[i]
    }
  }
  return "Folder"
}

function detectIcon(path, name) {
  var combined = (String(path || "") + " " + String(name || "")).toLowerCase()

  if (combined.indexOf("download") !== -1 || combined.indexOf("descarga") !== -1) {
    return "󰉏" // nf-md-folder_download
  }
  if (combined.indexOf("picture") !== -1 || combined.indexOf("imagen") !== -1 || combined.indexOf("foto") !== -1 || combined.indexOf("wallpaper") !== -1) {
    return "󰉐" // nf-md-folder_image
  }
  if (combined.indexOf("music") !== -1 || combined.indexOf("musica") !== -1 || combined.indexOf("audio") !== -1 || combined.indexOf("sound") !== -1) {
    return "󰉑" // nf-md-folder_music
  }
  if (combined.indexOf("video") !== -1 || combined.indexOf("movie") !== -1 || combined.indexOf("pelicula") !== -1 || combined.indexOf("serie") !== -1) {
    return "󰉓" // nf-md-folder_play
  }
  if (combined.indexOf("project") !== -1 || combined.indexOf("proyect") !== -1 || combined.indexOf("code") !== -1 || combined.indexOf("dev") !== -1 || combined.indexOf("git") !== -1 || combined.indexOf("repo") !== -1 || combined.indexOf("workspace") !== -1 || combined.indexOf("src") !== -1) {
    return "󰲋" // nf-md-folder_file
  }
  if (combined.indexOf("document") !== -1 || combined.indexOf("doc") !== -1 || combined.indexOf("texto") !== -1 || combined.indexOf("pdf") !== -1 || combined.indexOf("book") !== -1) {
    return "󰈙" // nf-md-file_document
  }
  if (combined.indexOf("game") !== -1 || combined.indexOf("juego") !== -1 || combined.indexOf("steam") !== -1 || combined.indexOf("rom") !== -1) {
    return "󰊖" // nf-md-gamepad_variant
  }
  if (combined.indexOf("config") !== -1 || combined.indexOf("setting") !== -1 || combined.indexOf("dotfile") !== -1 || combined.indexOf("etc") !== -1) {
    return "󱁿" // nf-md-folder_cog
  }
  if (combined.indexOf("desktop") !== -1 || combined.indexOf("escritorio") !== -1) {
    return "󰨇" // nf-md-desktop_mac
  }
  if (combined === "~" || combined.indexOf("home") !== -1) {
    return "󰋜" // nf-md-home
  }
  if (combined.indexOf("cloud") !== -1 || combined.indexOf("drive") !== -1 || combined.indexOf("dropbox") !== -1 || combined.indexOf("nextcloud") !== -1) {
    return "󰅟" // nf-md-cloud
  }

  return "󰉋" // nf-md-folder
}

function parseFolders(raw) {
  if (!raw || typeof raw !== "string" || raw.trim() === "") {
    return []
  }

  try {
    var data = JSON.parse(raw)
    if (!Array.isArray(data)) {
      if (data && Array.isArray(data.folders)) {
        data = data.folders
      } else {
        return []
      }
    }

    var validList = []
    for (var i = 0; i < data.length; i++) {
      var item = data[i]
      if (item && typeof item === "object" && item.path) {
        var cleanPath = trimPath(item.path)
        var name = item.name ? String(item.name).trim() : extractFolderName(cleanPath)
        var icon = item.icon || detectIcon(cleanPath, name)
        var id = item.id ? String(item.id) : generateId()

        validList.push({
          id: id,
          name: name,
          path: cleanPath,
          icon: icon
        })
      }
    }
    return validList
  } catch (e) {
    console.warn("FoldersHelper: failed to parse folders json:", e)
    return []
  }
}

function serializeFolders(folders) {
  var list = []
  if (Array.isArray(folders)) {
    for (var i = 0; i < folders.length; i++) {
      var item = folders[i]
      if (item && item.path) {
        list.push({
          id: item.id || generateId(),
          name: item.name || extractFolderName(item.path),
          path: trimPath(item.path),
          icon: item.icon || detectIcon(item.path, item.name)
        })
      }
    }
  }
  return JSON.stringify(list, null, 2) + "\n"
}

function generateId() {
  return "folder_" + Date.now().toString(36) + "_" + Math.random().toString(36).substring(2, 7)
}
