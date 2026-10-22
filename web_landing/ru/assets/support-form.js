(function () {
  'use strict';
  var form = document.getElementById('support-form');
  if (!form) return;
  var button = form.querySelector('button[type="submit"]');
  var status = document.getElementById('support-status');
  var sending = false;
  // One random ID per page visit; no contact details are kept in browser storage.
  var clientId = 'website_' + crypto.randomUUID();

  form.addEventListener('submit', async function (event) {
    event.preventDefault();
    if (sending || !form.reportValidity() || form.elements.website.value) return;
    var name = form.elements.name.value.trim();
    var contact = form.elements.contact.value.trim();
    var message = form.elements.message.value.trim();
    if (!contact || message.length < 5) {
      status.textContent = 'Укажите контакт для ответа и напишите сообщение (не менее 5 символов).';
      status.dataset.error = 'true';
      return;
    }
    sending = true;
    button.disabled = true;
    button.textContent = 'Отправляем…';
    status.textContent = '';
    var controller = new AbortController();
    var timeout = setTimeout(function () { controller.abort(); }, 45000);
    try {
      var response = await fetch('https://pdd-install-notifier.sergei-pdd.workers.dev/api/support/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: controller.signal,
        body: JSON.stringify({
          clientId: clientId,
          userName: name || 'Посетитель сайта',
          platform: 'Сайт pdd-drive.ru',
          text: 'Обращение с сайта pdd-drive.ru\nКонтакт для ответа: ' + contact + '\n\n' + message
        })
      });
      var result = await response.json();
      if (!response.ok || result.ok !== true) throw new Error('send_failed');
      form.reset();
      status.dataset.error = 'false';
      status.textContent = 'Сообщение отправлено! Ответим по указанному контакту.';
    } catch (_) {
      status.dataset.error = 'true';
      status.textContent = 'Не удалось подтвердить отправку. Текст сохранён в форме — попробуйте ещё раз.';
    } finally {
      clearTimeout(timeout);
      sending = false;
      button.disabled = false;
      button.textContent = 'Отправить сообщение';
    }
  });
})();
