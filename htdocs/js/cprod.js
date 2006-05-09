// This library will provide handy functionality to a contextual prodding
// box on a page.

CProd = new Object;

// show the next tip
CProd.next = function (evt) {
  var prodClassElement = $("CProd_class");
  var prodClass;

  if (prodClassElement)
    prodClass = prodClassElement.innerHTML;

  var data = HTTPReq.formEncoded({
    "class": prodClass,
      "content": "framed",
      });

  var req = HTTPReq.getJSON({
      "url": "/tools/endpoints/cprod.bml?" + data,
      "method": "GET",
        "data": data,
      "onData": CProd.gotData
  });
}

// got the next tip
CProd.gotData = function (res) {
  if (!res || !res.content) return;

  var cprodbox = $("CProd_box");
  if (!cprodbox) return;

  cprodbox.innerHTML = res.content;

  CProd.attachNextClickListener();
}

// attach onclick listener to the "next" button
CProd.attachNextClickListener = function () {
  var nextBtn = $("CProd_nextbutton");
  if (!nextBtn) return;

  DOM.addEventListener(nextBtn, "click", CProd.next.bindEventListener());
}

DOM.addEventListener(window, "load", function () {
  CProd.attachNextClickListener();
});
