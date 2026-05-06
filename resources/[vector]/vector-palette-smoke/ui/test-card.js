// Smoke test card. Subscribes to the FiveM NUI message bus and renders one chip
// per palette entry. Hex strings come from the Lua side via vector-palette
// (which itself was generated from src/tokens.json) — this file does not embed
// any hex literal, by design.

(function () {
  "use strict";

  const card = document.getElementById("card");
  const grid = document.getElementById("grid");

  function render(swatches) {
    grid.innerHTML = "";
    swatches.sort(function (a, b) {
      if (a.group === b.group) return a.token.localeCompare(b.token);
      return a.group.localeCompare(b.group);
    });
    for (const s of swatches) {
      const cell = document.createElement("div");
      cell.className = "swatch";

      const chip = document.createElement("div");
      chip.className = "chip";
      chip.style.background =
        "rgba(" + s.r + "," + s.g + "," + s.b + "," + s.a + ")";

      const name = document.createElement("div");
      name.className = "name";
      name.textContent = s.name;

      const hex = document.createElement("div");
      hex.className = "hex";
      hex.textContent = s.hex;

      const alpha = document.createElement("div");
      alpha.className = "alpha";
      alpha.textContent = "α " + s.a.toFixed(2);

      cell.appendChild(chip);
      cell.appendChild(name);
      cell.appendChild(hex);
      cell.appendChild(alpha);
      grid.appendChild(cell);
    }
  }

  window.addEventListener("message", function (event) {
    const msg = event.data || {};
    if (msg.type !== "vector-palette/show") return;
    if (msg.visible) {
      render(msg.swatches || []);
      card.classList.add("visible");
    } else {
      card.classList.remove("visible");
    }
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") {
      fetch("https://vector-palette-smoke/close", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      }).catch(function () {});
    }
  });
})();
