.pragma library

var providerIds = ["chatgpt", "claude"]

function validProvider(providerId) {
  return providerIds.indexOf(String(providerId || "")) !== -1
}

function blankStatus() {
  return {
    lastProvider: "chatgpt",
    providers: {
      chatgpt: { state: "closed", address: "" },
      claude: { state: "closed", address: "" }
    },
    error: ""
  }
}

function normalizeState(value) {
  var state = String(value || "").toLowerCase()
  return ["closed", "hidden", "visible"].indexOf(state) !== -1 ? state : "closed"
}

function normalizeStatus(value) {
  var result = blankStatus()
  if (!value || typeof value !== "object") return result

  if (validProvider(value.lastProvider)) result.lastProvider = value.lastProvider

  for (var i = 0; i < providerIds.length; i++) {
    var providerId = providerIds[i]
    var source = value.providers && value.providers[providerId]
      ? value.providers[providerId]
      : {}
    result.providers[providerId] = {
      state: normalizeState(source.state),
      address: typeof source.address === "string" ? source.address : ""
    }
  }

  result.error = typeof value.error === "string" ? value.error : ""
  return result
}

function providerName(providerId) {
  if (providerId === "chatgpt") return "ChatGPT"
  if (providerId === "claude") return "Claude"
  return ""
}

function stateLabel(status, providerId) {
  if (!status || !status.providers || !status.providers[providerId])
    return "Closed"
  var state = normalizeState(status.providers[providerId].state)
  return state.charAt(0).toUpperCase() + state.slice(1)
}

function providerButtonText(status, providerId) {
  var marker = status && status.lastProvider === providerId ? "  ·  Last used" : ""
  return providerName(providerId) + "  —  " + stateLabel(status, providerId) + marker
}
