document.documentElement.classList.add("js");

const revealItems = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.18 }
  );

  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

const shotMap = {
  panel: {
    src: "assets/notchflow-panel.png",
    alt: "NotchFlow expanded panel screenshot"
  },
  modules: {
    src: "assets/notchflow-modules.png",
    alt: "NotchFlow modules screenshot"
  },
  settings: {
    src: "assets/notchflow-settings.png",
    alt: "NotchFlow settings screenshot"
  }
};

const shotImage = document.querySelector("[data-shot-image]");
const shotFrame = document.querySelector(".shot-frame");

document.querySelectorAll("[data-shot]").forEach((button) => {
  button.addEventListener("click", () => {
    const shot = shotMap[button.dataset.shot];
    if (!shot || !shotImage || button.classList.contains("is-active")) {
      return;
    }

    document.querySelectorAll("[data-shot]").forEach((item) => {
      item.classList.toggle("is-active", item === button);
      item.setAttribute("aria-selected", item === button ? "true" : "false");
    });

    shotFrame?.classList.add("is-switching");
    window.setTimeout(() => {
      shotImage.src = shot.src;
      shotImage.alt = shot.alt;
      shotFrame?.classList.remove("is-switching");
    }, 160);
  });
});
