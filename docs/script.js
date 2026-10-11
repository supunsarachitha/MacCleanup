// Product tour: one screenshot at a time. Without JavaScript the panels simply stack.
(function () {
  var tour = document.querySelector("[data-tour]");
  if (!tour) return;

  var tabs = Array.prototype.slice.call(tour.querySelectorAll('[role="tab"]'));
  var panels = Array.prototype.slice.call(tour.querySelectorAll('[role="tabpanel"]'));

  function select(index, focus) {
    tabs.forEach(function (tab, i) {
      var active = i === index;
      tab.setAttribute("aria-selected", active ? "true" : "false");
      tab.tabIndex = active ? 0 : -1;
      panels[i].classList.toggle("is-active", active);
    });
    if (focus) tabs[index].focus();
  }

  tabs.forEach(function (tab, i) {
    tab.addEventListener("click", function () { select(i, false); });
    tab.addEventListener("keydown", function (event) {
      var next = null;
      if (event.key === "ArrowDown" || event.key === "ArrowRight") next = (i + 1) % tabs.length;
      if (event.key === "ArrowUp" || event.key === "ArrowLeft") next = (i - 1 + tabs.length) % tabs.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = tabs.length - 1;
      if (next !== null) {
        event.preventDefault();
        select(next, true);
      }
    });
  });

  select(0, false);
})();
