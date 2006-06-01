var ESN = {};

DOM.addEventListener(window, "load", function (evt) {
  ESN.initCheckAllBtns();
  ESN.initEventCheckBtns();
});

// When page loads, set up "check all" checkboxes
ESN.initCheckAllBtns = function () {
  var ntids  = $("ntypeids");
  var catids = $("catids");

  if (!ntids || !catids)
    return;

  ntidList  = ntids.value;
  catidList = catids.value;

  if (!ntidList || !catidList)
    return;

  ntids  = ntidList.split(",");
  catids = catidList.split(",");

  catids.forEach( function (catid) {
    ntids.forEach( function (ntypeid) {
      var className = "SubscribeCheckbox-" + catid + "-" + ntypeid;

      var cab = new CheckallButton();
      cab.init({
        "class": className,
          "button": $("CheckAll-" + catid + "-" + ntypeid),
          "parent": $("CategoryRow-" + catid)
          });
    });
  });
}

// set up auto show/hiding of notification methods
ESN.initEventCheckBtns = function () {
  var viewObjects = document.getElementsByTagName("*");
  var boxes = DOM.filterElementsByClassName(viewObjects, "SubscriptionInboxCheck") || [];

  boxes.forEach( function (box) {
    DOM.addEventListener(box, "click", ESN.eventChecked.bindEventListener());
  });
}

ESN.eventChecked = function (evt) {
  var target = evt.target;
  if (!target)
    return;

  var parentRow = DOM.getFirstAncestorByTagName(target, "tr", false);

  var viewObjects = parentRow.getElementsByTagName("*");
  var boxes = DOM.filterElementsByClassName(viewObjects, "NotificationOptions") || [];

  boxes.forEach( function (box) {
    box.style.visibility = target.checked ? "visible" : "hidden";
  });
}
