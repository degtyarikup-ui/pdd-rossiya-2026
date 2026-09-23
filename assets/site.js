// Общие интерактивы сайта: тень шапки при прокрутке, разделы-чипы на телефоне,
// плавное появление блоков. Без зависимостей; сайт работает и без этого файла.
(function () {
  var header = document.querySelector('.site-header');
  if (header) {
    var onScroll = function () { header.classList.toggle('scrolled', window.scrollY > 4); };
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });

    // На узких экранах ссылки шапки прячутся — дублируем их лентой чипов под шапкой.
    var links = header.querySelectorAll('.site-nav a:not(.nav-cta)');
    if (links.length && !document.querySelector('.mobile-nav')) {
      var bar = document.createElement('nav');
      bar.className = 'mobile-nav';
      bar.setAttribute('aria-label', 'Разделы сайта');
      links.forEach(function (a) { bar.appendChild(a.cloneNode(true)); });
      header.insertAdjacentElement('afterend', bar);
    }
  }

  var items = document.querySelectorAll('.reveal');
  if (!items.length) return;
  if (!('IntersectionObserver' in window)) {
    items.forEach(function (el) { el.classList.add('in'); });
    return;
  }
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
    });
  }, { rootMargin: '0px 0px -8% 0px' });
  items.forEach(function (el) { io.observe(el); });
})();
