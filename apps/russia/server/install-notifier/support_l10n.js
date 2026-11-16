// Only service-generated labels are translated. The operator's reply is verbatim.
const COPY = {
  ru: { title: '💬 Ответ поддержки', photo: '📷 Фото', message: 'Новое сообщение',
    sticker: '[Стикер]', voice: '[Голосовое сообщение]', document: '[Документ]', attachment: '[Вложение]' },
  en: { title: '💬 Support reply', photo: '📷 Photo', message: 'New message',
    sticker: '[Sticker]', voice: '[Voice message]', document: '[Document]', attachment: '[Attachment]' },
  kk: { title: '💬 Қолдау қызметінің жауабы', photo: '📷 Сурет', message: 'Жаңа хабарлама',
    sticker: '[Стикер]', voice: '[Дауыстық хабарлама]', document: '[Құжат]', attachment: '[Тіркеме]' },
};

export function supportLocale(value) {
  const lang = typeof value === 'string' ? value.toLowerCase().split(/[-_]/)[0] : '';
  return Object.hasOwn(COPY, lang) ? lang : 'ru';
}

export function supportPushCopy(message, locale) {
  const strings = COPY[supportLocale(locale)];
  let body = message.text || '';
  const type = typeof message.kind === 'string' ? message.kind.replace(/^attachment_/, '') : '';
  const known = ['sticker', 'voice', 'document', 'attachment'];
  if (known.includes(type) && body.endsWith(COPY.ru[type])) {
    body = body.slice(0, -COPY.ru[type].length) + strings[type];
  } else if (!message.kind) {
    // Older stored service placeholders did not carry a kind. Match whole
    // values only, so ordinary sentences are never rewritten.
    const legacyType = known.find(key => body === COPY.ru[key]);
    if (legacyType) body = strings[legacyType];
  }
  if (!body) body = message.imageUrl ? strings.photo : strings.message;
  return { title: strings.title, body: body.length > 150 ? body.slice(0, 147) + '…' : body };
}
