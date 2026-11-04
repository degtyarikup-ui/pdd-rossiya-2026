// Навигация по разделам сайта на узких экранах.
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

})();
