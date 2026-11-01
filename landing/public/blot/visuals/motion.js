(() => {
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  let active = false;
  let step = 0;
  const groups = [...document.querySelectorAll(".feature-swap, .feature-recording__bar")];
  const change = () => {
    if (!active || document.hidden || reduced.matches) return;
    step += 1;
    groups.forEach(group => [...group.children].forEach((element, index) => {
      element.dataset.hidden = String(index !== step % group.children.length);
    }));
    document.querySelectorAll(".blot-bot-entry-enter").forEach((element, index) => {
      element.animate([{ opacity: 0, transform: "translateY(5px)" }, { opacity: 1, transform: "translateY(0)" }], { duration: 400, delay: index * 160, fill: "both" });
    });
    document.querySelectorAll(".avatar-row__pill").forEach((element, index) => {
      element.animate([{ transform: "translateY(0)" }, { transform: "translateY(-3px)" }, { transform: "translateY(0)" }], { duration: 650, delay: index * 160 });
    });
  };
  addEventListener("message", event => {
    if (event.origin === location.origin && event.data?.type === "blot-visual") active = Boolean(event.data.active);
  });
  const timer = setInterval(change, 4200);
  addEventListener("pagehide", () => clearInterval(timer), { once: true });
})();
