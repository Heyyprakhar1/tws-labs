(function () {
  var buttons = Array.prototype.slice.call(document.querySelectorAll('.filters button'));
  var topics = Array.prototype.slice.call(document.querySelectorAll('.topic'));
  var domains = Array.prototype.slice.call(document.querySelectorAll('[data-domain]'));
  function apply(f) {
    buttons.forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-f') === f)); });
    topics.forEach(function (t) { t.hidden = !(f === 'all' || t.getAttribute('data-filter') === f); });
    domains.forEach(function (d) { d.hidden = !d.querySelector('.topic:not([hidden])'); });
  }
  buttons.forEach(function (b) { b.addEventListener('click', function () { apply(b.getAttribute('data-f')); }); });
  // opening a section from a link (#cloud) expands nothing; the list is already compact
})();
