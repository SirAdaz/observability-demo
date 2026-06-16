const alertsGrid = document.getElementById("alerts-grid");
const terminal = document.getElementById("terminal");
const streamStatus = document.getElementById("stream-status");
const alertTemplate = document.getElementById("alert-card-template");

let paused = false;
let eventSource = null;

function showToast(message) {
  const existing = document.querySelector(".toast");
  if (existing) {
    existing.remove();
  }

  const toast = document.createElement("div");
  toast.className = "toast";
  toast.textContent = message;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 9000);
}

function formatLogLine(entry) {
  const meta = [
    entry.timestamp,
    entry.level,
    entry.event || entry.message,
    entry.route ? `route=${entry.route}` : null,
    entry.status ? `status=${entry.status}` : null,
    entry.scenario_id ? `scenario=${entry.scenario_id}` : null,
    entry.alert ? `alert=${entry.alert}` : null,
  ]
    .filter(Boolean)
    .join(" | ");

  return `<div class="log-line level-${entry.level}"><span class="meta">${meta}</span></div>`;
}

function appendLog(entry) {
  if (paused) {
    return;
  }
  terminal.insertAdjacentHTML("beforeend", formatLogLine(entry));
  terminal.scrollTop = terminal.scrollHeight;
}

async function loadAlerts() {
  const response = await fetch("/api/alerts");
  const alerts = await response.json();
  alertsGrid.innerHTML = "";

  for (const alert of alerts) {
    const node = alertTemplate.content.cloneNode(true);
    const card = node.querySelector(".alert-card");
    const severity = node.querySelector(".severity");
    const triggerBtn = node.querySelector(".trigger-btn");

    severity.textContent = alert.severity;
    severity.classList.add(alert.severity);
    node.querySelector(".prom-alert").textContent = alert.prometheus_alert;
    node.querySelector(".alert-name").textContent = alert.name;
    node.querySelector(".alert-description").textContent = alert.description;
    node.querySelector(".alert-hint").textContent = alert.trigger_hint;

    triggerBtn.addEventListener("click", async () => {
      triggerBtn.disabled = true;
      try {
        const result = await fetch(`/api/trigger/${alert.id}`, { method: "POST" });
        const payload = await result.json();
        if (!result.ok) {
          throw new Error(payload.error || "Echec du declenchement");
        }
        showToast(payload.message);
      } catch (error) {
        showToast(error.message);
      } finally {
        triggerBtn.disabled = false;
      }
    });

    alertsGrid.appendChild(node);
  }
}

function connectLogStream() {
  if (eventSource) {
    eventSource.close();
  }

  eventSource = new EventSource("/api/logs/stream");
  streamStatus.textContent = "Terminal: connecte";

  eventSource.onmessage = (event) => {
    appendLog(JSON.parse(event.data));
  };

  eventSource.onerror = () => {
    streamStatus.textContent = "Terminal: reconnexion...";
  };
}

document.getElementById("refresh-alerts").addEventListener("click", loadAlerts);
document.getElementById("clear-terminal").addEventListener("click", () => {
  terminal.innerHTML = "";
});
document.getElementById("pause-terminal").addEventListener("click", (event) => {
  paused = !paused;
  event.currentTarget.textContent = paused ? "Reprendre" : "Pause";
});

loadAlerts();
connectLogStream();
