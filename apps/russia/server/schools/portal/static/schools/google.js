const mount = document.getElementById("google-button");
const statusText = document.getElementById("google-status");
const library = document.createElement("script");
library.src = "https://accounts.google.com/gsi/client";
library.onload = () => {
  google.accounts.id.initialize({
    client_id: mount.dataset.client,
    nonce: mount.dataset.nonce,
    callback: ({credential}) => {
      const form = document.getElementById("google-result");
      form.elements.credential.value = credential;
      form.requestSubmit();
    },
  });
  google.accounts.id.renderButton(mount, {type:"standard", theme:"outline", size:"large", locale:"ru"});
  statusText.hidden = true;
};
library.onerror = () => { statusText.textContent = "Google не загрузился. Обновите страницу или выберите другой способ входа."; };
document.head.appendChild(library);
