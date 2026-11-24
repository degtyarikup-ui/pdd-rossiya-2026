const menu = document.querySelector("#nav-toggle");
menu?.addEventListener("click", () => {
  const open = document.querySelector("#sidebar").classList.toggle("open");
  menu.setAttribute("aria-expanded", String(open));
  menu.setAttribute("aria-label", open ? "Закрыть меню" : "Открыть меню");
});
document.querySelector("[data-switch]")?.addEventListener("change", event => event.target.form.requestSubmit());
document.addEventListener("click", async event => {
  const button = event.target.closest("button");
  if (!button) return;
  if (button.dataset.confirm && !window.confirm(button.dataset.confirm)) event.preventDefault();
  if (button.dataset.dialog) document.getElementById(button.dataset.dialog).showModal();
  if (button.hasAttribute("data-close")) button.closest("dialog").close();
  if (button.dataset.copy) {
    const toast = document.getElementById("toast");
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      toast.textContent = "Ссылка скопирована";
    } catch {
      const details = document.querySelector(".secondary");
      details.open = true;
      const input = details.querySelector("input");
      input.focus();
      input.select();
      toast.textContent = "Скопируйте выделенную ссылку";
    }
    toast.hidden = false;
    window.setTimeout(() => { toast.hidden = true; }, 3000);
  }
});


const providerRedirect = document.getElementById("provider-redirect");
if (providerRedirect) window.location.replace(providerRedirect.href);

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") document.getElementById("telegram-check")?.requestSubmit();
});
